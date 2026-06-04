//
//  PhoneSoundRecognizer.swift
//  NotifEar (iPhone companion)
//
//  Motore di riconoscimento per la modalità Sonar dell'iPhone. È la versione iOS,
//  SNELLITA, del riconoscitore del Watch ([SoundAnalyzerViewModel] lato Watch): usa
//  la STESSA sorgente — classificatore di sistema Apple (`.version1`, ~300 suoni) +
//  modello custom locale ([PhoneCustomModelStore]) — ma NON fa alert né notifiche.
//  Il suo unico compito è, dato un bersaglio (`SonarTarget`), produrre due numeri che
//  il sonar legge istante per istante:
//    - `currentRMS`            → volume corrente (intensità della vibrazione)
//    - `currentTargetConfidence` → quanto il suono target è presente ORA (gating:
//                                  zittisce la vibrazione quando il suono sparisce)
//
//  L'iPhone NON ascolta in continuo: questo motore parte solo quando si apre la
//  schermata Sonar e si ferma quando si chiude. Il ruolo di "sentinella sempre attiva"
//  resta del Watch.
//
//  AUDIO SESSION: categoria `.playAndRecord` (NON `.record`). Documentato da Apple:
//  con la sola `.record` Core Haptics non emette vibrazioni. Serve quindi la categoria
//  che ammette anche output, così il microfono e la vibrazione continua convivono.
//

import Foundation
import Combine
import SoundAnalysis
import AVFoundation

final class PhoneSoundRecognizer: NSObject, ObservableObject, SNResultsObserving {

    /// RMS audio corrente (0...~1) calcolato sul tap. Proxy di volume per il sonar.
    @Published var currentRMS: Float = 0
    /// Confidence corrente (0...1) della classe target: massimo sugli identifier target
    /// nel frame corrente, 0 quando il suono non è presente. Pilota il gating.
    @Published var currentTargetConfidence: Float = 0
    @Published var isRunning: Bool = false

    /// Invocato (su main) quando l'engine audio è effettivamente partito. Il controller lo
    /// usa per avviare la vibrazione SOLO dopo che la sessione audio è attiva, evitando il
    /// conflitto Core Haptics ↔ AVAudioEngine che può far crashare l'avvio.
    var onReady: (() -> Void)?

    /// Identifier del modello di sistema che contano come "target presente".
    private var trackingTargetIdentifiers: Set<String> = []
    /// Label grezze del modello custom che contano come "target presente".
    private var trackingCustomLabels: Set<String> = []

    private let audioEngine = AVAudioEngine()
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.notifear.phone.AnalysisQueue")
    /// Richiesta del modello custom (nil se nessun modello installato), affiancata a
    /// quella di sistema sullo stesso analyzer: un solo tap, due classificatori.
    private var customSoundRequest: SNClassifySoundRequest?

    // MARK: - Target

    /// Imposta il bersaglio del gating. Per i suoni di SISTEMA passare gli `identifiers`
    /// (es. ["door_bell", "doorbell"]); per i suoni CUSTOM passare `customLabel`.
    func setTarget(identifiers: [String], customLabel: String?) {
        DispatchQueue.main.async {
            self.trackingTargetIdentifiers = Set(identifiers)
            self.trackingCustomLabels = customLabel.map { [$0] } ?? []
            self.currentTargetConfidence = 0
        }
    }

    // MARK: - Avvio / stop

    func start() {
        guard !isRunning else { return }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard granted else { return }
                self?.setupAndStart()
            }
        }
    }

    private func setupAndStart() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playAndRecord + mode .default per far convivere microfono e haptic.
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            // LA CHIAVE: di default iOS SILENZIA le vibrazioni mentre il microfono registra
            // (per non far entrare il ronzio del Taptic Engine nell'audio). Senza questo il
            // sonar non vibrava affatto. Questo metodo le riabilita durante la registrazione.
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)
        } catch {
            print("⚠️ [iPhone] Errore audio session: \(error)")
            return
        }

        // ORDINE CRITICO (causa del crash 'inputNode != nullptr || outputNode != nullptr'):
        // accedere a `inputNode` PER PRIMO lo istanzia e dà all'engine un nodo di I/O.
        // Chiamare prima `reset()`/`prepare()` (senza nessun nodo) faceva crashare su iOS.
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("⚠️ [iPhone] Formato hardware non valido")
            return
        }

        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        do {
            let systemRequest = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try streamAnalyzer?.add(systemRequest, withObserver: self)

            if let custom = PhoneCustomModelStore.shared.makeRequest() {
                customSoundRequest = custom
                try? streamAnalyzer?.add(custom, withObserver: self)
            } else {
                customSoundRequest = nil
            }
        } catch {
            print("⚠️ [iPhone] Errore creazione richieste: \(error)")
            return
        }

        // Rimuove un eventuale tap residuo: reinstallarne uno senza rimuovere il precedente
        // fa sollevare un'eccezione Obj-C non catturabile (crash).
        inputNode.removeTap(onBus: 0)
        // Buffer più piccolo (4096): l'RMS si aggiorna più spesso → la vibrazione segue il
        // volume con meno ritardo. L'analyzer accumula da sé fino alla sua finestra.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self else { return }
            let rms = PhoneSoundRecognizer.computeRMS(buffer: buffer)
            DispatchQueue.main.async { self.currentRMS = rms }
            self.analysisQueue.async { self.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime) }
        }

        // prepare()/start() solo ORA, a grafo valido (input → tap).
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRunning = true
            // Audio attivo: ora è sicuro avviare la vibrazione (Core Haptics).
            onReady?()
        } catch {
            print("⚠️ [iPhone] Avvio engine fallito: \(error)")
        }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        streamAnalyzer?.removeAllRequests()
        streamAnalyzer = nil
        customSoundRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isRunning = false
        currentRMS = 0
        currentTargetConfidence = 0
    }

    // MARK: - SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }

        // Ramo CUSTOM: i risultati del modello personalizzato arrivano dallo stesso
        // observer, distinti per identità della richiesta.
        if let custom = customSoundRequest, request === custom {
            guard !trackingCustomLabels.isEmpty else { return }
            let conf = classification.classifications
                .filter { trackingCustomLabels.contains($0.identifier) }
                .map { Float($0.confidence) }
                .max() ?? 0
            DispatchQueue.main.async { self.currentTargetConfidence = conf }
            return
        }

        // Ramo SISTEMA: confidence target = max sugli identifier di sistema. Calcolata a
        // ogni frame (anche quando il target non è la classe vincente) così il sonar sa
        // quando il suono "scompare" e zittisce la vibrazione.
        guard !trackingTargetIdentifiers.isEmpty else { return }
        let conf = classification.classifications
            .filter { trackingTargetIdentifiers.contains($0.identifier) }
            .map { Float($0.confidence) }
            .max() ?? 0
        DispatchQueue.main.async { self.currentTargetConfidence = conf }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("⚠️ [iPhone] Errore analisi: \(error)")
    }

    // MARK: - RMS helper

    /// RMS (Root Mean Square) di un buffer PCM float. 0 se il buffer non è valido.
    static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let s = channelData[i]
            sum += s * s
        }
        return (sum / Float(frameLength)).squareRoot()
    }

    deinit {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}
