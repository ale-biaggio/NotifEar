
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

    var customIdentifier: String? = nil

    var color: Color { category.color }

    var id: String { label }
}

enum SoundCategory: String, CaseIterable {
    case emergency, danger, home, attention

    var color: Color {
        switch self {
        case .attention: return .green
        case .home:      return .yellow
        case .danger:    return .orange
        case .emergency: return .red
        }
    }
}

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
    @Published var sessionExpired: Bool = false

    @Published var activePipeline: AudioPipeline = .idle

    @Published var currentRMS: Float = 0

    @Published var currentTargetConfidence: Float = 0

    private var trackingTargetIdentifiers: Set<String> = []

    private var trackingCustomLabels: Set<String> = []

    private var sonarSuppressedIdentifiers: Set<String> = []
    private var sonarSuppressedCustomLabels: Set<String> = []
    private var sonarSuppressionTimer: Timer?

    private var suppressedSystemIdentifiers: Set<String> { trackingTargetIdentifiers.union(sonarSuppressedIdentifiers) }
    private var suppressedCustomLabels: Set<String> { trackingCustomLabels.union(sonarSuppressedCustomLabels) }

    let audioEngine = AVAudioEngine()
    var streamAnalyzer: SNAudioStreamAnalyzer?
    let analysisQueue = DispatchQueue(label: "com.notifear.AnalysisQueue")

    private var customSoundRequest: SNClassifySoundRequest?

    // MARK: - Custom Sound Filtering

    private static let customConfidenceThreshold: Float = 0.85
    private static let customMarginThreshold: Float = 0.30
    private static let customRequiredHits: Int = 3
    private static let customCooldown: TimeInterval = 8

    private var customHitLabel: String?
    private var customHitCount: Int = 0
    private var customLastAlertAt: Date?

    private var extendedSession: WKExtendedRuntimeSession?
    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - State
    var mutedCategories: [SoundCategory: Date] = [:]
    var lastDetectedSound: SoundInfo?
    var lastDetectedAt: Date?
    
    private let soundMap: [String: SoundInfo] = [
        "ambulance_siren": SoundInfo(label: "AMBULANZA", iconName: "🚑", isSystemIcon: false, category: .emergency),
        "siren": SoundInfo(label: "SIRENA", iconName: "🚨", isSystemIcon: false, category: .emergency),
        "fire_alarm": SoundInfo(label: "ALLARME INCENDIO", iconName: "flame.fill", isSystemIcon: true, category: .emergency),
        "smoke_detector": SoundInfo(label: "ALLARME FUMO", iconName: "🔥", isSystemIcon: false, category: .emergency),

        "scream": SoundInfo(label: "URLO RILEVATO", iconName: "exclamationmark.triangle.fill", isSystemIcon: true, category: .danger),
        "shout": SoundInfo(label: "GRIDO RILEVATO", iconName: "speaker.wave.3.fill", isSystemIcon: true, category: .danger),
        "car_horn": SoundInfo(label: "CLACSON", iconName: "🚗", isSystemIcon: false, category: .danger),

        "door_bell": SoundInfo(label: "CAMPANELLO", iconName: "bell.fill", isSystemIcon: true, category: .home),
        "doorbell": SoundInfo(label: "CAMPANELLO", iconName: "bell.fill", isSystemIcon: true, category: .home),
        "knock": SoundInfo(label: "BUSSANO", iconName: "🚪", isSystemIcon: false, category: .home),
        "telephone_bell": SoundInfo(label: "TELEFONO", iconName: "phone.fill", isSystemIcon: true, category: .home),
        "ringtone": SoundInfo(label: "TELEFONO", iconName: "phone.fill", isSystemIcon: true, category: .home),

        "baby_crying": SoundInfo(label: "PIANTO NEONATO", iconName: "👶", isSystemIcon: false, category: .attention),
        "baby_cry": SoundInfo(label: "PIANTO NEONATO", iconName: "👶", isSystemIcon: false, category: .attention),
        "crying": SoundInfo(label: "PIANTO", iconName: "😢", isSystemIcon: false, category: .attention),
        "dog": SoundInfo(label: "CANE", iconName: "🐕", isSystemIcon: false, category: .attention),
        "bark": SoundInfo(label: "ABBAIO", iconName: "🐕", isSystemIcon: false, category: .attention)
    ]

    // MARK: - Init

    override init() {
        super.init()
        WatchModelReceiver.shared.onModelInstalled = { [weak self] in
            guard let self = self, self.isListening, self.activePipeline == .classification else { return }
            self.switchPipeline(to: .classification)
        }
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
                            self.isListening = false
                        }
                    }
                }
            }
        }
    }

    @discardableResult
    func prepareAudioSession() -> Bool {
        audioEngine.inputNode.removeTap(onBus: 0)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true)
            Thread.sleep(forTimeInterval: 0.2)
        } catch {
            DispatchQueue.main.async { self.statusMessage = "Errore Audio" }
            return false
        }

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

    func removeCurrentTap() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        streamAnalyzer?.removeAllRequests()
        streamAnalyzer = nil
    }

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

    func switchPipeline(to pipeline: AudioPipeline) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.removeCurrentTap()
            self.activePipeline = pipeline
            switch pipeline {
            case .classification:
                self.installClassificationTap()
            case .voiceCommand, .sonar, .captioning, .idle:
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

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func dismissAlert() {
        if detectedSound != nil {
            detectedSound = nil
            statusMessage = isListening ? "In ascolto..." : "Fermo"
        }
    }

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
        guard WKApplication.shared().applicationState != .active else { return }
        
        let content = UNMutableNotificationContent()
        content.title = info.label
        content.body = "NotifEar ha rilevato il suono di un \(info.label.lowercased())!"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "NotifEar_\(info.label)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - Extended Runtime Session
    
    private func startExtendedSession() {
        extendedSession?.invalidate()
        startSession()
    }

    private func startSession() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        extendedSession = session
    }

    private func renewExtendedSession() {
        guard isListening else { return }
        startSession()
    }

    private func stopExtendedSession() {
        extendedSession?.invalidate()
        extendedSession = nil
    }

    private func onSessionExpired() {
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

    // MARK: - Tracking Target

    func identifiers(matching info: SoundInfo) -> Set<String> {
        Set(soundMap.compactMap { (key, value) in value.label == info.label ? key : nil })
    }

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

    func setTrackingTarget(for info: SoundInfo) {
        let builtIn = identifiers(matching: info)
        let custom: Set<String> = info.customIdentifier.map { [$0] } ?? []
        let update = {
            self.trackingTargetIdentifiers = builtIn
            self.trackingCustomLabels = custom
            self.currentTargetConfidence = 0
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    func clearTrackingTarget() {
        let update = {
            self.trackingTargetIdentifiers = []
            self.trackingCustomLabels = []
            self.currentTargetConfidence = 0
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    // MARK: - Sonar Suppression

    func setSonarSuppression(identifiers: [String], customLabel: String?) {
        let update = {
            self.sonarSuppressedIdentifiers = Set(identifiers)
            self.sonarSuppressedCustomLabels = customLabel.map { [$0] } ?? []
            self.sonarSuppressionTimer?.invalidate()
            self.sonarSuppressionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                self?.clearSonarSuppression()
            }
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    func clearSonarSuppression() {
        let update = {
            self.sonarSuppressedIdentifiers = []
            self.sonarSuppressedCustomLabels = []
            self.sonarSuppressionTimer?.invalidate()
            self.sonarSuppressionTimer = nil
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    func isCategoryMuted(_ category: SoundCategory) -> Bool {
        guard let until = mutedCategories[category] else { return false }
        if Date() >= until {
            mutedCategories[category] = nil
            return false
        }
        return true
    }
    
    // MARK: - Haptic Feedback
    
    private func playHaptic(for category: SoundCategory) {
        let device = WKInterfaceDevice.current()
        
        switch category {
        case .emergency:
            device.play(.directionUp)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { device.play(.directionUp) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { device.play(.directionUp) }
            
        case .danger:
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

        if let custom = customSoundRequest, request === custom {
            updateCustomTargetConfidence(classificationResult)
            handleCustomClassification(classificationResult)
            return
        }

        let topClassifications = classificationResult.classifications.filter { $0.confidence > 0.4 }
        if !topClassifications.isEmpty {
            let descriptions = topClassifications.map { "\($0.identifier): \(Int($0.confidence * 100))%" }.joined(separator: ", ")
            print("🔍 Udito: \(descriptions)")
        }

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
                if self.isCategoryMuted(info.category) { return }
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

    // MARK: - Custom Sounds

    private func updateCustomTargetConfidence(_ result: SNClassificationResult) {
        guard !trackingCustomLabels.isEmpty else { return }
        let targetConf = result.classifications
            .filter { trackingCustomLabels.contains($0.identifier) }
            .map { Float($0.confidence) }
            .max() ?? 0
        DispatchQueue.main.async { self.currentTargetConfidence = targetConf }
    }

    private func handleCustomClassification(_ result: SNClassificationResult) {
        let sorted = result.classifications
        guard let top = sorted.first else { resetCustomHits(); return }

        let label = top.identifier

        if suppressedCustomLabels.contains(label) { return }

        let conf = Float(top.confidence)
        let second = Float(sorted.dropFirst().first?.confidence ?? 0)
        let margin = conf - second

        let qualifies = CustomSoundConfigStore.shared.isEnabled(label)
            && conf >= Self.customConfidenceThreshold
            && margin >= Self.customMarginThreshold

        guard qualifies else { resetCustomHits(); return }

        if label == customHitLabel {
            customHitCount += 1
        } else {
            customHitLabel = label
            customHitCount = 1
        }
        guard customHitCount >= Self.customRequiredHits else { return }

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

    private func resetCustomHits() {
        customHitLabel = nil
        customHitCount = 0
    }

    private static func customSoundInfo(label: String, category: String) -> SoundInfo {
        let cat = SoundCategory(rawValue: category) ?? .attention
        return SoundInfo(label: label.uppercased(),
                         iconName: "waveform.badge.mic",
                         isSystemIcon: true,
                         category: cat,
                         customIdentifier: label)
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
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension SoundAnalyzerViewModel: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("✅ Extended session avviata")
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("⚠️ Extended session in scadenza → rinnovo trasparente")
        DispatchQueue.main.async {
            self.renewExtendedSession()
        }
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {
        print("❌ Extended session invalidata: \(reason) (rawValue: \(reason.rawValue)) - Error: \(String(describing: error))")

        DispatchQueue.main.async {
            guard extendedRuntimeSession === self.extendedSession else {
                print("ℹ️ Invalidazione di una sessione già sostituita: ignoro.")
                return
            }
            guard self.isListening else { return }

            switch reason {
            case .expired, .suppressedBySystem:
                self.onSessionExpired()
            case .error:
                print("⚠️ Sessione persa ma audio in foreground attivo. Retry tra 5s...")
                self.extendedSession = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if self.isListening && self.extendedSession == nil {
                        print("🔄 Tentativo di riavvio sessione estesa...")
                        self.startSession()
                    }
                }
            default:
                print("⚠️ Motivo invalidazione non gestito: \(reason.rawValue)")
            }
        }
    }
}
