
import Foundation
import UIKit

final class SonarHapticEngine {

    private var generator: UIImpactFeedbackGenerator?
    private var level: Float = 0
    private var running = false
    private var generation = 0

    // MARK: - Configuration

    private static let silence: Float = 0.06
    private static let minIntensity: CGFloat = 0.25
    private static let minFrequency: Double = 0.6
    private static let maxFrequency: Double = 13.0
    private static let frequencyCurve: Double = 2.8
    private static let idleInterval: TimeInterval = 0.12

    // MARK: - API

    func start() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        generator = gen
        running = true
        generation &+= 1
        scheduleNextPulse(generation)
    }

    func setLevel(_ value: Float) {
        level = max(0, min(1, value))
    }

    func stop() {
        running = false
        generation &+= 1
        generator = nil
        level = 0
    }

    // MARK: - Pulse Loop

    private func scheduleNextPulse(_ gen: Int) {
        guard running, gen == generation else { return }

        let lvl = level
        let interval: TimeInterval
        if lvl < Self.silence {
            interval = Self.idleInterval
        } else {
            let intensity = Self.minIntensity + (1 - Self.minIntensity) * CGFloat(lvl)
            generator?.impactOccurred(intensity: intensity)
            generator?.prepare()
            let freq = Self.minFrequency + (Self.maxFrequency - Self.minFrequency) * pow(Double(lvl), Self.frequencyCurve)
            interval = 1.0 / freq
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.scheduleNextPulse(gen)
        }
    }

    deinit { stop() }
}
