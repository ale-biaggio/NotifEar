
import Foundation
import Combine

final class PhoneSonarController: ObservableObject {

    @Published var liveLevel: Float = 0
    @Published var isActive: Bool = false

    // MARK: - Configuration

    private static let rmsReference: Float = 0.015
    private static let dBFloor: Float = -28
    private static let dBCeiling: Float = 0
    private static let confidenceThreshold: Float = 0.4
    private static let confidenceDecay: Float = 0.82
    private static let monitorPeriod: TimeInterval = 0.1
    private static let silenceTimeout: TimeInterval = 5

    // MARK: - Dependencies

    private let recognizer = PhoneSoundRecognizer()
    private let haptics = SonarHapticEngine()
    private var monitorTimer: Timer?
    private var smoothedConfidence: Float = 0
    private var smoothedLevel: Float = 0
    private static let attackFactor: Float = 0.5
    private static let releaseFactor: Float = 0.18
    private var lastPresentAt: Date = .distantPast

    // MARK: - API

    func start(target: SonarTarget) {
        recognizer.setTarget(identifiers: target.identifiers, customLabel: target.customLabel)
        smoothedConfidence = 0
        smoothedLevel = 0
        liveLevel = 0
        lastPresentAt = Date()
        isActive = true

        haptics.start()
        startMonitor()
        recognizer.start()
    }

    func stop() {
        stopMonitor()
        haptics.stop()
        recognizer.stop()
        isActive = false
        liveLevel = 0
        smoothedConfidence = 0
        smoothedLevel = 0
    }

    // MARK: - Monitor Loop

    private func startMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: Self.monitorPeriod, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func tick() {
        guard isActive else { return }

        smoothedConfidence = max(recognizer.currentTargetConfidence, smoothedConfidence * Self.confidenceDecay)
        let isPresent = smoothedConfidence >= Self.confidenceThreshold

        if isPresent {
            lastPresentAt = Date()
        } else if Date().timeIntervalSince(lastPresentAt) > Self.silenceTimeout {
            stop()
            return
        }

        let target = isPresent ? Self.intensity(forRMS: recognizer.currentRMS) : 0
        let factor = target > smoothedLevel ? Self.attackFactor : Self.releaseFactor
        smoothedLevel += (target - smoothedLevel) * factor

        liveLevel = smoothedLevel
        haptics.setLevel(smoothedLevel)
    }

    // MARK: - Level Mapping

    private static func intensity(forRMS rms: Float) -> Float {
        let safe = max(rms, 1e-5)
        let db = 20 * log10f(safe / rmsReference)
        let normalized = (db - dBFloor) / (dBCeiling - dBFloor)
        return min(max(normalized, 0), 1)
    }

    deinit {
        monitorTimer?.invalidate()
    }
}
