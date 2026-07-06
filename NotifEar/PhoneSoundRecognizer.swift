
import Foundation
import Combine
import SoundAnalysis
import AVFoundation

final class PhoneSoundRecognizer: NSObject, ObservableObject, SNResultsObserving {

    @Published var currentRMS: Float = 0
    @Published var currentTargetConfidence: Float = 0
    @Published var isRunning: Bool = false

    var onReady: (() -> Void)?

    private var trackingTargetIdentifiers: Set<String> = []
    private var trackingCustomLabels: Set<String> = []

    private let audioEngine = AVAudioEngine()
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.notifear.phone.AnalysisQueue")
    private var customSoundRequest: SNClassifySoundRequest?

    // MARK: - Target

    func setTarget(identifiers: [String], customLabel: String?) {
        DispatchQueue.main.async {
            self.trackingTargetIdentifiers = Set(identifiers)
            self.trackingCustomLabels = customLabel.map { [$0] } ?? []
            self.currentTargetConfidence = 0
        }
    }

    // MARK: - Start / Stop

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
            try session.setCategory(.playAndRecord, mode: .measurement, options: [])
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)
        } catch {
            print("⚠️ [iPhone] Errore audio session: \(error)")
            return
        }

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

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self else { return }
            let rms = PhoneSoundRecognizer.computeRMS(buffer: buffer)
            DispatchQueue.main.async { self.currentRMS = rms }
            self.analysisQueue.async { self.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime) }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRunning = true
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

        if let custom = customSoundRequest, request === custom {
            guard !trackingCustomLabels.isEmpty else { return }
            let conf = classification.classifications
                .filter { trackingCustomLabels.contains($0.identifier) }
                .map { Float($0.confidence) }
                .max() ?? 0
            DispatchQueue.main.async { self.currentTargetConfidence = conf }
            return
        }

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

    // MARK: - RMS

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
