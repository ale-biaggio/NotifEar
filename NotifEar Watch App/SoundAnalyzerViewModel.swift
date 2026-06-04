//
//  SoundAnalyzerViewModel.swift
//  NotifEar Watch App
//
//  Created by NotifEar Team on 26/03/2026.
//

import Foundation
import SwiftUI
import Combine
import SoundAnalysis
import AVFoundation
import WatchKit
import UserNotifications

struct SoundInfo: Equatable, Identifiable {
    let label: String
    let iconName: String
    let isSystemIcon: Bool
    let category: SoundCategory

    /// Per i suoni di SISTEMA è nil: il target del tracking si risolve via `soundMap`
    /// (più identifier possono mappare alla stessa SoundInfo, es. "door_bell"+"doorbell").
    /// Per i suoni PERSONALIZZATI contiene la label grezza della classe del modello custom
    /// (es. "campanello_di_casa"). Serve al tracking/sonar per il gating della confidence,
    /// perché i risultati del modello custom arrivano da una richiesta separata e non
    /// passano da `soundMap`.
    var customIdentifier: String? = nil

    /// Colore proporzionale alla gravità della categoria (verde → rosso). Derivato dalla
    /// categoria: suoni di sistema e personalizzati restano così sempre coerenti.
    var color: Color { category.color }

    /// Identità per `.sheet(item:)`. `label` è la chiave logica di un suono nella UI
    /// (più identifier del classificatore possono mappare alla stessa SoundInfo, es. "door_bell" e "doorbell").
    var id: String { label }
}

enum SoundCategory: String, CaseIterable {
    case emergency, danger, home, attention

    /// Colore proporzionale alla gravità: verde (lieve) → rosso (massima).
    /// Unica fonte di verità per il colore, condivisa da suoni di sistema e personalizzati.
    var color: Color {
        switch self {
        case .attention: return .green   // suono generico
        case .home:      return .yellow  // suono domestico
        case .danger:    return .orange  // suono urgente
        case .emergency: return .red     // emergenza
        }
    }
}

/// VINCOLO CRITICO: SNAudioStreamAnalyzer e SFSpeechRecognizer NON possono avere due tap simultanei
/// sullo stesso inputNode di AVAudioEngine. Tutte le feature audio (classificazione, voice command,
/// sonar, captioning) DEVONO passare da uno SWITCH di pipeline. Questo enum traccia la pipeline attiva
/// e va aggiornato attraverso `switchPipeline(to:)` per garantire teardown -> setup atomico.
enum AudioPipeline {
    case idle
    case classification
    case voiceCommand
    case sonar
    case captioning
}

class SoundAnalyzerViewModel: NSObject, ObservableObject, SNResultsObserving {
    @Published var statusMessage: String = "Inizializzazione..."
    @Published var isListening: Bool = false
    @Published var detectedSound: SoundInfo?
    /// Vero quando il sistema ha chiuso la sessione di ascolto e il rinnovo non è andato
    /// a buon fine: la UI mostra "scaduta" e un tocco sull'orecchio fa ripartire tutto.
    @Published var sessionExpired: Bool = false

    /// Pipeline audio attualmente collegata all'inputNode. Cambiarla solo tramite `switchPipeline(to:)`.
    @Published var activePipeline: AudioPipeline = .idle

    /// RMS audio corrente (0...~1), calcolato sul tap di classificazione.
    /// Usato dalla modalità Tracking come proxy d'intensità acustica per modulare
    /// l'haptic continuo istante per istante. Aggiornato su main thread.
    @Published var currentRMS: Float = 0

    /// Confidence corrente (0...1) della classe target attualmente tracciata.
    /// È il **massimo** tra le confidence degli identifier target, aggiornato a ogni
    /// risultato di SNClassifySoundRequest. Per un target di SISTEMA si calcola sul ramo
    /// di sistema (`trackingTargetIdentifiers`); per un target PERSONALIZZATO sul ramo
    /// custom (`trackingCustomLabels`, in `updateCustomTargetConfidence`). Zero se nessun
    /// target è impostato o se nessuno degli identifier target compare nelle classifications
    /// del frame corrente. Il TrackingService la usa per zittire la vibrazione quando il
    /// suono target non è più nell'aria, anche se il volume ambientale resta alto.
    @Published var currentTargetConfidence: Float = 0

    /// Identifier (chiavi del modello Apple, es. "ambulance_siren") che, quando classificati,
    /// contano come "il target è ancora presente". Impostato da `setTrackingTarget(for:)`.
    private var trackingTargetIdentifiers: Set<String> = []

    /// Come `trackingTargetIdentifiers` ma per il modello CUSTOM: label grezze della classe
    /// custom che contano come "target presente". I risultati custom arrivano da una richiesta
    /// separata (`handleCustomClassification`), quindi il gating del sonar per i suoni
    /// personalizzati si calcola lì, non nel ramo di sistema. Impostato da `setTrackingTarget(for:)`.
    private var trackingCustomLabels: Set<String> = []

    /// Soppressione del re-trigger mentre l'iPhone sta localizzando un suono (handoff): il
    /// Watch non lo ri-annuncia finché l'iPhone non segnala la fine (o scatta il timeout).
    /// Per il sonar SUL WATCH la soppressione usa già `trackingTargetIdentifiers`/`...CustomLabels`.
    private var sonarSuppressedIdentifiers: Set<String> = []
    private var sonarSuppressedCustomLabels: Set<String> = []
    private var sonarSuppressionTimer: Timer?

    /// Identifier di sistema da NON ri-annunciare: bersaglio del sonar sul Watch + sull'iPhone.
    private var suppressedSystemIdentifiers: Set<String> { trackingTargetIdentifiers.union(sonarSuppressedIdentifiers) }
    /// Label custom da NON ri-annunciare.
    private var suppressedCustomLabels: Set<String> { trackingCustomLabels.union(sonarSuppressedCustomLabels) }

    let audioEngine = AVAudioEngine()
    var streamAnalyzer: SNAudioStreamAnalyzer?
    let analysisQueue = DispatchQueue(label: "com.notifear.AnalysisQueue")

    /// Richiesta di classificazione del modello PERSONALIZZATO (suoni custom addestrati
    /// dall'utente sull'iPhone), affiancata a quella di sistema SULLO STESSO analyzer.
    /// Nil quando nessun modello custom è installato.
    private var customSoundRequest: SNClassifySoundRequest?

    // MARK: - Calibrazione riconoscimento suoni custom (anti-falsi-positivi)

    /// Confidenza minima della classe top per considerare valida una finestra.
    private static let customConfidenceThreshold: Float = 0.85
    /// Distacco minimo fra la classe top e la seconda: se il modello è "indeciso"
    /// (es. applauso 0.55 vs fondo 0.45) NON scattiamo.
    private static let customMarginThreshold: Float = 0.30
    /// Numero di finestre CONSECUTIVE che devono confermare lo stesso suono prima di
    /// avvisare. Con windowDuration ~1.5 s e overlap 0.5 equivale a ~1.5–2 s di suono
    /// realmente presente: i picchi isolati (rumori brevi) non bastano più a far scattare.
    private static let customRequiredHits: Int = 3
    /// Intervallo minimo fra due avvisi dello stesso suono custom.
    private static let customCooldown: TimeInterval = 8

    /// Etichetta custom attualmente in corso di conferma.
    private var customHitLabel: String?
    /// Finestre consecutive che hanno confermato `customHitLabel`.
    private var customHitCount: Int = 0
    /// Istante dell'ultimo avviso custom emesso (per il cooldown).
    private var customLastAlertAt: Date?

    private var extendedSession: WKExtendedRuntimeSession?
    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Stato per intent vocali
    /// Categorie temporaneamente silenziate da "ignora [categoria] per un'ora".
    /// Mappa categoria -> data fino alla quale ignorare gli alert.
    var mutedCategories: [SoundCategory: Date] = [:]
    /// Ultimo suono effettivamente rilevato (per intent "cosa hai sentito" / "ripeti").
    var lastDetectedSound: SoundInfo?
    var lastDetectedAt: Date?
    
    // Mappa con le chiavi esatte del modello Apple e icone SF Symbols
    private let soundMap: [String: SoundInfo] = [
        // EMERGENZA (rosso)
        "ambulance_siren": SoundInfo(label: "AMBULANZA", iconName: "🚑", isSystemIcon: false, category: .emergency),
        "siren": SoundInfo(label: "SIRENA", iconName: "🚨", isSystemIcon: false, category: .emergency),
        "fire_alarm": SoundInfo(label: "ALLARME INCENDIO", iconName: "flame.fill", isSystemIcon: true, category: .emergency),
        "smoke_detector": SoundInfo(label: "ALLARME FUMO", iconName: "🔥", isSystemIcon: false, category: .emergency),

        // SUONO URGENTE (arancione)
        "scream": SoundInfo(label: "URLO RILEVATO", iconName: "exclamationmark.triangle.fill", isSystemIcon: true, category: .danger),
        "shout": SoundInfo(label: "GRIDO RILEVATO", iconName: "speaker.wave.3.fill", isSystemIcon: true, category: .danger),
        "car_horn": SoundInfo(label: "CLACSON", iconName: "🚗", isSystemIcon: false, category: .danger),

        // SUONO DOMESTICO (giallo)
        "door_bell": SoundInfo(label: "CAMPANELLO", iconName: "bell.fill", isSystemIcon: true, category: .home),
        "doorbell": SoundInfo(label: "CAMPANELLO", iconName: "bell.fill", isSystemIcon: true, category: .home),
        "knock": SoundInfo(label: "BUSSANO", iconName: "🚪", isSystemIcon: false, category: .home),
        "telephone_bell": SoundInfo(label: "TELEFONO", iconName: "phone.fill", isSystemIcon: true, category: .home),
        "ringtone": SoundInfo(label: "TELEFONO", iconName: "phone.fill", isSystemIcon: true, category: .home),

        // SUONO GENERICO (verde)
        "baby_crying": SoundInfo(label: "PIANTO NEONATO", iconName: "👶", isSystemIcon: false, category: .attention),
        "baby_cry": SoundInfo(label: "PIANTO NEONATO", iconName: "👶", isSystemIcon: false, category: .attention),
        "crying": SoundInfo(label: "PIANTO", iconName: "😢", isSystemIcon: false, category: .attention),
        "dog": SoundInfo(label: "CANE", iconName: "🐕", isSystemIcon: false, category: .attention),
        "bark": SoundInfo(label: "ABBAIO", iconName: "🐕", isSystemIcon: false, category: .attention)
    ]

    // MARK: - Init

    override init() {
        super.init()
        // Quando l'iPhone consegna (o aggiorna) il modello dei suoni personalizzati,
        // ricostruiamo la pipeline di classificazione per includerlo. Accedere al
        // singleton qui attiva anche la WCSession lato Watch, pronta a ricevere.
        WatchModelReceiver.shared.onModelInstalled = { [weak self] in
            guard let self = self, self.isListening, self.activePipeline == .classification else { return }
            self.switchPipeline(to: .classification)
        }
        // L'iPhone ha finito di localizzare un suono → riprendi ad avvisare per quel suono.
        WatchModelReceiver.shared.onSonarEnded = { [weak self] in
            self?.clearSonarSuppression()
        }
    }

    // MARK: - Listening
    
    func startListening() {
        guard !isListening else { return }
        sessionExpired = false
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard granted else {
                    self.statusMessage = "Permesso negato"
                    return
                }
                // Feedback IMMEDIATO: l'orecchio passa subito a "in ascolto", così il tocco
                // non sembra in ritardo. L'avvio audio vero e proprio (che include una breve
                // pausa di stabilizzazione dell'hardware) gira FUORI dal main thread, così
                // non blocca né fa "scattare" l'interfaccia.
                self.isListening = true
                self.statusMessage = "In ascolto..."
                self.requestNotificationPermission()
                self.startExtendedSession()
                self.analysisQueue.async {
                    let ready = self.prepareAudioSession()
                    DispatchQueue.main.async {
                        if ready {
                            self.switchPipeline(to: .classification)
                        } else {
                            // Avvio fallito: torna allo stato "fermo".
                            self.isListening = false
                        }
                    }
                }
            }
        }
    }

    /// Configura `AVAudioSession` e fa partire l'engine "pulito". Ritorna false in caso di errore.
    @discardableResult
    func prepareAudioSession() -> Bool {
        audioEngine.inputNode.removeTap(onBus: 0)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true)
            // Piccolo delay per permettere all'hardware di stabilizzarsi
            Thread.sleep(forTimeInterval: 0.2)
        } catch {
            DispatchQueue.main.async { self.statusMessage = "Errore Audio" }
            return false
        }

        // Reset dell'engine per evitare stati sporchi
        audioEngine.stop()
        audioEngine.reset()
        audioEngine.prepare()

        let recordingFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            DispatchQueue.main.async { self.statusMessage = "Errore Hardware" }
            return false
        }
        return true
    }

    /// Rimuove l'eventuale tap audio installato e ferma l'engine. Non tocca l'audio session.
    func removeCurrentTap() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        streamAnalyzer?.removeAllRequests()
        streamAnalyzer = nil
    }

    /// Installa il tap di classificazione suoni e avvia l'engine. Idempotente: chiama prima `removeCurrentTap`.
    func installClassificationTap() {
        removeCurrentTap()
        let recordingFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            self.isListening = false; self.statusMessage = "Errore Hardware"; return
        }

        streamAnalyzer = SNAudioStreamAnalyzer(format: recordingFormat)
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try streamAnalyzer?.add(request, withObserver: self)

            // Suoni personalizzati: se l'utente ne ha addestrati (modello arrivato
            // dall'iPhone), affianchiamo una SECONDA richiesta sullo stesso analyzer.
            // Un solo tap audio, due classificatori in parallelo.
            if let custom = CustomModelStore.shared.makeRequest() {
                customSoundRequest = custom
                try? streamAnalyzer?.add(custom, withObserver: self)
            } else {
                customSoundRequest = nil
            }
        } catch {
            self.isListening = false; self.statusMessage = "Errore Sistema"; return
        }

        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 8192, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            // RMS aggregato sull'intero buffer (~500 ms a 16 kHz). Usato dal sonar
            // per decidere la "forza" del prossimo tap del pattern aptico in corso —
            // non serve risoluzione più fine perché il sonar non insegue le micro-
            // modulazioni del suono, esegue un pattern fisso e legge il volume solo
            // a istanti specifici (ai tap del pattern).
            let rms = SoundAnalyzerViewModel.computeRMS(buffer: buffer)
            DispatchQueue.main.async { self.currentRMS = rms }
            self.analysisQueue.async { self.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime) }
        }

        do {
            try audioEngine.start()
            self.isListening = true
            self.statusMessage = "In ascolto..."
        } catch {
            self.isListening = false
            self.statusMessage = "Errore Avvio"
        }
    }

    /// Switch atomico di pipeline audio: garantisce teardown -> setup serializzato sul main per evitare
    /// race condition fra classification e voice command sullo stesso inputNode.
    func switchPipeline(to pipeline: AudioPipeline) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.removeCurrentTap()
            self.activePipeline = pipeline
            switch pipeline {
            case .classification:
                self.installClassificationTap()
            case .voiceCommand, .sonar, .captioning, .idle:
                // L'installazione del tap per queste pipeline è responsabilità del rispettivo modulo
                // (es. startVoiceCommand). `activePipeline` aggiornato preventivamente come lock.
                break
            }
        }
    }

    func stopListening() {
        removeCurrentTap()
        try? AVAudioSession.sharedInstance().setActive(false)
        self.isListening = false
        self.statusMessage = "Fermo"
        self.detectedSound = nil
        self.activePipeline = .idle
        stopExtendedSession()
    }
    
    func restartSession() {
        stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startListening()
        }
    }

    /// Interruttore dell'ascolto: l'orecchio nella schermata principale lo chiama a ogni
    /// tocco. Se sta ascoltando lo ferma; altrimenti (fermo o sessione scaduta) lo riavvia.
    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    /// Dismiss dell'alert corrente (usato da Double Tap e tap su schermo)
    func dismissAlert() {
        if detectedSound != nil {
            detectedSound = nil
            statusMessage = isListening ? "In ascolto..." : "Fermo"
        }
    }

    /// Azione primaria Double Tap: se c'è un alert lo chiude, altrimenti accende/spegne
    /// l'ascolto (incluso il riavvio quando la sessione è scaduta).
    func handlePrimaryAction() {
        if detectedSound != nil {
            dismissAlert()
        } else {
            toggleListening()
        }
    }
    
    // MARK: - Notifications
    
    private func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("❌ Errore permessi notifiche: \(error)")
            }
        }
    }
    
    private func sendLocalNotification(for info: SoundInfo) {
        // Inviamo la notifica solo se l'app NON è attiva in primo piano.
        // Se è attiva, l'utente vede già l'alert grafico della UI.
        guard WKApplication.shared().applicationState != .active else { return }
        
        let content = UNMutableNotificationContent()
        content.title = info.label
        content.body = "NotifEar ha rilevato il suono di un \(info.label.lowercased())!"
        content.sound = .default
        
        // Identificatore unico per evitare duplicati troppi ravvicinati dello stesso suono
        let request = UNNotificationRequest(
            identifier: "NotifEar_\(info.label)",
            content: content,
            trigger: nil // Invio immediato
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - Extended Runtime Session
    
    private func startExtendedSession() {
        extendedSession?.invalidate()
        startSession()
    }

    /// Crea e avvia una nuova sessione di sistema, sostituendo l'eventuale precedente nel
    /// riferimento. Usata sia all'avvio dell'ascolto sia per il rinnovo "al volo".
    private func startSession() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        extendedSession = session
    }

    /// Rinnovo trasparente: quando la sessione corrente sta per scadere ne apriamo subito
    /// una nuova, così l'ascolto non si interrompe. La vecchia sessione invaliderà da sola
    /// poco dopo: il suo `didInvalidate` viene ignorato perché non è più quella corrente.
    /// È questo concatenamento a dare la "durata massima" restando invisibili (nessun
    /// allenamento, nessun anello attività). Se il sistema NON concede il rinnovo, la
    /// nuova sessione invalida subito e cade il fallback "scaduta → ritocca l'orecchio".
    private func renewExtendedSession() {
        guard isListening else { return }
        startSession()
    }

    private func stopExtendedSession() {
        extendedSession?.invalidate()
        extendedSession = nil
    }

    private func onSessionExpired() {
        // Haptic per avvisare l'utente
        WKInterfaceDevice.current().play(.stop)

        self.isListening = false
        self.sessionExpired = true
        self.statusMessage = "Sessione scaduta"
        self.detectedSound = nil
        self.activePipeline = .idle
        self.extendedSession = nil

        removeCurrentTap()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Tracking target (modalità Tracking)

    /// Tutti gli identifier del modello che mappano alla stessa `SoundInfo` (per label).
    /// Esempio: "door_bell" e "doorbell" mappano entrambi a SoundInfo "CAMPANELLO".
    func identifiers(matching info: SoundInfo) -> Set<String> {
        Set(soundMap.compactMap { (key, value) in value.label == info.label ? key : nil })
    }

    /// Lista degli `SoundInfo` distinti per `label` (deduplicati: "door_bell" + "doorbell"
    /// → una sola voce CAMPANELLO), ordinati per categoria + label. Usato dalla schermata
    /// di debug dei pattern aptici per popolare la griglia dei tile.
    var distinctSounds: [SoundInfo] {
        var seen = Set<String>()
        let unique = soundMap.values.compactMap { info -> SoundInfo? in
            if seen.contains(info.label) { return nil }
            seen.insert(info.label)
            return info
        }
        return unique.sorted { (a, b) in
            if a.category.rawValue != b.category.rawValue {
                return a.category.rawValue < b.category.rawValue
            }
            return a.label < b.label
        }
    }

    /// Imposta il target della modalità Tracking a partire da un `SoundInfo`, gestendo
    /// SIA i suoni di sistema SIA quelli personalizzati. Per i suoni di sistema risolve gli
    /// identifier via `soundMap`; per i suoni custom usa `customIdentifier` (la label grezza
    /// del modello custom). Il VM, a ogni risultato, aggiornerà `currentTargetConfidence`
    /// come massimo delle confidence sugli identifier target — sul ramo giusto a seconda
    /// che il target sia di sistema o custom.
    func setTrackingTarget(for info: SoundInfo) {
        let builtIn = identifiers(matching: info)
        let custom: Set<String> = info.customIdentifier.map { [$0] } ?? []
        DispatchQueue.main.async {
            self.trackingTargetIdentifiers = builtIn
            self.trackingCustomLabels = custom
            self.currentTargetConfidence = 0
        }
    }

    /// Termina il tracking: nessun identifier target (di sistema o custom) →
    /// `currentTargetConfidence` resta a 0.
    func clearTrackingTarget() {
        DispatchQueue.main.async {
            self.trackingTargetIdentifiers = []
            self.trackingCustomLabels = []
            self.currentTargetConfidence = 0
        }
    }

    // MARK: - Muting categorie (usato da intent vocali)

    // MARK: - Soppressione re-trigger durante il sonar sull'iPhone

    /// L'iPhone ha iniziato a localizzare un suono (handoff): finché dura, il Watch non lo
    /// ri-annuncia. Timeout di sicurezza nel caso il messaggio di fine non arrivi.
    func setSonarSuppression(identifiers: [String], customLabel: String?) {
        DispatchQueue.main.async {
            self.sonarSuppressedIdentifiers = Set(identifiers)
            self.sonarSuppressedCustomLabels = customLabel.map { [$0] } ?? []
            self.sonarSuppressionTimer?.invalidate()
            self.sonarSuppressionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                self?.clearSonarSuppression()
            }
        }
    }

    /// L'iPhone ha terminato il sonar (o timeout): il Watch torna ad avvisare per quel suono.
    func clearSonarSuppression() {
        DispatchQueue.main.async {
            self.sonarSuppressedIdentifiers = []
            self.sonarSuppressedCustomLabels = []
            self.sonarSuppressionTimer?.invalidate()
            self.sonarSuppressionTimer = nil
        }
    }

    /// Vero se la categoria è attualmente silenziata da un intent "ignora ... per un'ora".
    func isCategoryMuted(_ category: SoundCategory) -> Bool {
        guard let until = mutedCategories[category] else { return false }
        if Date() >= until {
            mutedCategories[category] = nil
            return false
        }
        return true
    }
    
    // MARK: - Haptic Feedback
    
    /// Pattern aptici differenziati per categoria:
    /// - Emergency: 3 vibrazioni rapide (urgenza massima)
    /// - Danger: 2 vibrazioni (attenzione alta)
    /// - Home/Attention: vibrazione singola
    private func playHaptic(for category: SoundCategory) {
        let device = WKInterfaceDevice.current()
        
        switch category {
        case .emergency:
            // 3 vibrazioni ravvicinate per massima urgenza
            device.play(.directionUp)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { device.play(.directionUp) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { device.play(.directionUp) }
            
        case .danger:
            // 2 vibrazioni per pericolo
            device.play(.notification)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { device.play(.notification) }
            
        case .home:
            device.play(.click)
            
        case .attention:
            device.play(.retry)
        }
    }
    
    // MARK: - SNResultsObserving
    
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }

        // I risultati del modello PERSONALIZZATO arrivano dallo stesso observer:
        // li distinguiamo per identità della richiesta e li gestiamo a parte.
        if let custom = customSoundRequest, request === custom {
            // Gating del sonar per i suoni custom (indipendente dalla logica anti-falsi-
            // positivi degli alert: qui conta la confidence grezza del target).
            updateCustomTargetConfidence(classificationResult)
            handleCustomClassification(classificationResult)
            return
        }

        let topClassifications = classificationResult.classifications.filter { $0.confidence > 0.4 }
        if !topClassifications.isEmpty {
            let descriptions = topClassifications.map { "\($0.identifier): \(Int($0.confidence * 100))%" }.joined(separator: ", ")
            print("🔍 Udito: \(descriptions)")
        }

        // Confidence target per la modalità Tracking: max delle confidence sugli identifier
        // target. Calcolata a ogni frame anche quando il target NON è tra le top-classifications,
        // perché il tracker ha bisogno di sapere quando il suono "scompare" (conf → 0) per
        // zittire la vibrazione.
        if !trackingTargetIdentifiers.isEmpty {
            let targetConf = classificationResult.classifications
                .filter { trackingTargetIdentifiers.contains($0.identifier) }
                .map { Float($0.confidence) }
                .max() ?? 0
            DispatchQueue.main.async { self.currentTargetConfidence = targetConf }
        }

        if let topMatch = classificationResult.classifications.first(where: { soundMap.keys.contains($0.identifier) && $0.confidence > 0.55 }),
           let info = soundMap[topMatch.identifier] {

            DispatchQueue.main.async {
                // Filtro muting: se la categoria è silenziata da un comando vocale, ignoro l'alert.
                if self.isCategoryMuted(info.category) { return }
                // Soppressione: se questo suono è il bersaglio del sonar attivo (Watch o
                // iPhone), non ri-annunciarlo — lo stai già localizzando.
                if self.suppressedSystemIdentifiers.contains(topMatch.identifier) { return }

                if self.detectedSound != info {
                    self.detectedSound = info
                    self.statusMessage = info.label
                    self.lastDetectedSound = info
                    self.lastDetectedAt = Date()
                    self.playHaptic(for: info.category)
                    self.sendLocalNotification(for: info)
                    WatchModelReceiver.shared.reportDetection(label: info.label, category: info.category.rawValue)
                    WatchHistoryStore.shared.add(label: info.label, category: info.category.rawValue)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if self.isListening && self.detectedSound == info {
                            self.statusMessage = "In ascolto..."
                            self.detectedSound = nil
                        }
                    }
                }
            }
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) { print("Errore: \(error)") }

    // MARK: - Suoni personalizzati

    /// Aggiorna `currentTargetConfidence` quando il target del tracking è un suono
    /// PERSONALIZZATO: massimo delle confidence sugli identifier custom target presenti nel
    /// frame (0 se assenti). Calcolato a ogni risultato custom anche quando il target non è
    /// la classe vincente, così il sonar sa quando il suono "scompare" e zittisce la
    /// vibrazione. È volutamente separato dalla logica anti-falsi-positivi degli alert
    /// (soglie/conferma sostenuta): per inseguire l'intensità serve la confidence grezza.
    private func updateCustomTargetConfidence(_ result: SNClassificationResult) {
        guard !trackingCustomLabels.isEmpty else { return }
        let targetConf = result.classifications
            .filter { trackingCustomLabels.contains($0.identifier) }
            .map { Float($0.confidence) }
            .max() ?? 0
        DispatchQueue.main.async { self.currentTargetConfidence = targetConf }
    }

    /// Gestisce un risultato del modello CUSTOM con una calibrazione realistica e
    /// conservativa per evitare falsi positivi (il problema dell'"applauso" che scatta
    /// sempre). Tre filtri in cascata:
    ///   1. confidenza alta sulla classe top (≥ `customConfidenceThreshold`);
    ///   2. distacco netto dalla seconda classe (≥ `customMarginThreshold`): se il
    ///      modello è indeciso non si scatta;
    ///   3. conferma SOSTENUTA: stessa etichetta vincente per `customRequiredHits`
    ///      finestre consecutive (il suono dev'essere davvero presente, non un picco);
    /// più un cooldown per non ripetere l'avviso ad ogni finestra.
    private func handleCustomClassification(_ result: SNClassificationResult) {
        let sorted = result.classifications // ordinate per confidenza decrescente
        guard let top = sorted.first else { resetCustomHits(); return }

        let label = top.identifier

        // Soppressione: se questo suono custom è il bersaglio del sonar attivo (Watch o
        // iPhone), non ri-annunciarlo. Il gating del sonar è gestito a parte
        // (`updateCustomTargetConfidence`), quindi qui salta solo l'avviso.
        if suppressedCustomLabels.contains(label) { return }

        let conf = Float(top.confidence)
        let second = Float(sorted.dropFirst().first?.confidence ?? 0)
        let margin = conf - second

        let qualifies = CustomSoundConfigStore.shared.isEnabled(label)
            && conf >= Self.customConfidenceThreshold
            && margin >= Self.customMarginThreshold

        guard qualifies else { resetCustomHits(); return }

        // Conferma sostenuta su finestre consecutive.
        if label == customHitLabel {
            customHitCount += 1
        } else {
            customHitLabel = label
            customHitCount = 1
        }
        guard customHitCount >= Self.customRequiredHits else { return }

        // Cooldown: evita avvisi a raffica mentre il suono persiste.
        if let last = customLastAlertAt, Date().timeIntervalSince(last) < Self.customCooldown { return }
        customLastAlertAt = Date()

        let category = CustomSoundConfigStore.shared.category(for: label)
        let info = Self.customSoundInfo(label: label, category: category)
        DispatchQueue.main.async {
            if self.isCategoryMuted(info.category) { return }
            self.detectedSound = info
            self.statusMessage = info.label
            self.lastDetectedSound = info
            self.lastDetectedAt = Date()
            self.playHaptic(for: info.category)
            self.sendLocalNotification(for: info)
            WatchModelReceiver.shared.reportDetection(label: info.label, category: info.category.rawValue)
            WatchHistoryStore.shared.add(label: info.label, category: info.category.rawValue)

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if self.isListening && self.detectedSound == info {
                    self.statusMessage = "In ascolto..."
                    self.detectedSound = nil
                }
            }
        }
    }

    /// Azzera il contatore di conferma quando una finestra non qualifica.
    private func resetCustomHits() {
        customHitLabel = nil
        customHitCount = 0
    }

    /// `SoundInfo` per un'etichetta personalizzata, con la categoria scelta sull'iPhone
    /// (determina colore e pattern aptico). Default `.attention` se categoria ignota.
    private static func customSoundInfo(label: String, category: String) -> SoundInfo {
        let cat = SoundCategory(rawValue: category) ?? .attention
        // Colore e pattern aptico derivano dalla categoria (vedi SoundCategory.color e
        // playHaptic): un suono custom è quindi indistinguibile da uno di sistema della
        // stessa gravità.
        return SoundInfo(label: label.uppercased(),
                         iconName: "waveform.badge.mic",
                         isSystemIcon: true,
                         category: cat,
                         customIdentifier: label)
    }

    // MARK: - RMS helper

    /// RMS (Root Mean Square) di un buffer PCM float. Restituisce 0 se il buffer non è valido.
    /// Calcolato sull'intero buffer (~500 ms a 16 kHz). Usato dal sonar come proxy
    /// di volume per scegliere la "forza" del singolo tap del pattern aptico.
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
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension SoundAnalyzerViewModel: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("✅ Extended session avviata")
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("⚠️ Extended session in scadenza → rinnovo trasparente")
        DispatchQueue.main.async {
            // Apri subito una nuova sessione così l'ascolto non si interrompe. L'audio
            // resta attivo nel frattempo. La vecchia sessione invaliderà da sola.
            self.renewExtendedSession()
        }
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {
        print("❌ Extended session invalidata: \(reason) (rawValue: \(reason.rawValue)) - Error: \(String(describing: error))")

        DispatchQueue.main.async {
            // Ignora le sessioni "vecchie" già sostituite da un rinnovo: solo quella
            // corrente conta. (Su rinnovo, la precedente invalida poco dopo.)
            guard extendedRuntimeSession === self.extendedSession else {
                print("ℹ️ Invalidazione di una sessione già sostituita: ignoro.")
                return
            }
            guard self.isListening else { return }

            switch reason {
            case .expired, .suppressedBySystem:
                // Il rinnovo non è andato a buon fine (il sistema non concede altra
                // sessione): fermiamo l'ascolto e mostriamo "scaduta". Un tocco
                // sull'orecchio lo fa ripartire.
                self.onSessionExpired()
            case .error:
                // Errore esterno (es. debugger collegato, conflitto sessioni).
                // L'audio continua a funzionare in foreground, ma il background non è garantito.
                // Non fermiamo l'ascolto, proviamo a ricreare la sessione dopo un delay.
                print("⚠️ Sessione persa ma audio in foreground attivo. Retry tra 5s...")
                self.extendedSession = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if self.isListening && self.extendedSession == nil {
                        print("🔄 Tentativo di riavvio sessione estesa...")
                        self.startSession()
                    }
                }
            default:
                // .none, .sessionInProgress, .resignedFrontmost o @unknown default
                print("⚠️ Motivo invalidazione non gestito: \(reason.rawValue)")
            }
        }
    }
}
