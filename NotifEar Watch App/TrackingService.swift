
import Foundation
import SwiftUI
import Combine
import WatchKit

final class TrackingService: ObservableObject {

    // MARK: - State

    enum State: Equatable {
        case idle
        case tracking(target: SoundInfo)
    }

    @Published var state: State = .idle

    @Published var liveLevel: Float = 0

    @Published var pulseCounter: UInt32 = 0

    // MARK: - Sound Level

    private static let rmsReference: Float = 0.015
    private static let dBFloor: Float = -28
    private static let dBCeiling: Float = 0

    // MARK: - Haptics

    private static let hapticPeriod: TimeInterval = 0.45

    private static let silenceThreshold: Float = 0.06

    private static let hapticLadder: [WKHapticType] = [.click, .start, .notification, .failure]

    private static func haptic(forIntensity intensity: Float) -> WKHapticType? {
        guard intensity >= silenceThreshold else { return nil }
        let clamped = min(max(intensity, 0), 1)
        let count = hapticLadder.count
        let index = min(Int(clamped * Float(count)), count - 1)
        return hapticLadder[index]
    }

    // MARK: - Gating

    private static let confidenceThreshold: Float = 0.4
    private static let confidenceDecay: Float = 0.96

    private static let monitorPeriod: TimeInterval = 0.1

    private static let silenceTimeout: TimeInterval = 5

    // MARK: - Dependencies

    private weak var viewModel: SoundAnalyzerViewModel?

    // MARK: - Private State

    private var monitorTimer: Timer?
    private var smoothedConfidence: Float = 0
    private var lastPresentAt: Date = .distantPast
    private var executionGeneration: UInt64 = 0

    // MARK: - Init

    init(viewModel: SoundAnalyzerViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - API

    func startTracking(target: SoundInfo) {
        guard let vm = viewModel else { return }
        if case .tracking(let current) = state, current == target { return }

        vm.setTrackingTarget(for: target)

        smoothedConfidence = 0
        liveLevel = 0
        pulseCounter = 0
        lastPresentAt = Date()

        state = .tracking(target: target)
        WKInterfaceDevice.current().play(.start)

        executionGeneration &+= 1
        let myGen = executionGeneration

        startMonitorLoop()
        DispatchQueue.main.async { [weak self] in
            self?.runTrackingHaptics(generation: myGen)
        }
    }

    func stopTracking() {
        viewModel?.clearTrackingTarget()
        executionGeneration &+= 1
        stopMonitorLoop()
        state = .idle
        liveLevel = 0
        smoothedConfidence = 0
    }

    // MARK: - Monitor Loop

    private func startMonitorLoop() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: Self.monitorPeriod, repeats: true) { [weak self] _ in
            self?.monitorTick()
        }
    }

    private func stopMonitorLoop() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func monitorTick() {
        guard case .tracking = state, let vm = viewModel else { return }

        smoothedConfidence = max(vm.currentTargetConfidence, smoothedConfidence * Self.confidenceDecay)
        let isPresent = smoothedConfidence >= Self.confidenceThreshold

        if isPresent {
            lastPresentAt = Date()
        } else if Date().timeIntervalSince(lastPresentAt) > Self.silenceTimeout {
            stopTracking()
            return
        }

        liveLevel = isPresent ? Self.intensity(forRMS: vm.currentRMS) : 0
    }

    // MARK: - Haptic Loop

    private func runTrackingHaptics(generation: UInt64) {
        guard case .tracking = state, generation == executionGeneration else { return }

        emitHaptic(forLevel: liveLevel)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hapticPeriod) { [weak self] in
            self?.runTrackingHaptics(generation: generation)
        }
    }

    private func emitHaptic(forLevel level: Float) {
        guard let type = Self.haptic(forIntensity: level) else { return }
        WKInterfaceDevice.current().play(type)
        pulseCounter &+= 1
    }

    // MARK: - Level Mapping

    private static func intensity(forRMS rms: Float) -> Float {
        let safe = max(rms, 1e-5)
        let db = 20 * log10f(safe / rmsReference)
        let normalized = (db - dBFloor) / (dBCeiling - dBFloor)
        return min(max(normalized, 0), 1)
    }

    // MARK: - Cleanup

    deinit {
        executionGeneration &+= 1
        monitorTimer?.invalidate()
    }
}
