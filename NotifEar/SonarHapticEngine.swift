//
//  SonarHapticEngine.swift
//  NotifEar (iPhone companion)
//
//  Vibrazione del sonar, in stile "sensore di parcheggio". A differenza del Watch (che
//  ha solo 4 preset di forza fissi), su iPhone abbiamo controllo GRANULARE: ogni impulso
//  ha un'intensità continua 0...1 (`UIImpactFeedbackGenerator.impactOccurred(intensity:)`)
//  e noi controlliamo anche la CADENZA degli impulsi. Così sia l'intensità sia la
//  frequenza crescono col volume:
//    - volume minimo → impulsi DEBOLI e LENTI;
//    - volume massimo → impulsi FORTI e RAPIDISSIMI (quasi un buzz continuo).
//
//  Usiamo UIKit feedback (non Core Haptics) perché è indipendente dalla sessione audio
//  del microfono. NB: iOS silenzia comunque gli haptic durante la registrazione finché
//  non si chiama `setAllowHapticsAndSystemSoundsDuringRecording(true)` (vedi
//  PhoneSoundRecognizer).
//

import Foundation
import UIKit

final class SonarHapticEngine {

    private var generator: UIImpactFeedbackGenerator?
    /// Livello corrente 0...1 (volume gated), aggiornato dal controller a ~10 Hz.
    private var level: Float = 0
    private var running = false
    /// Invalida i cicli pending del loop di impulsi su stop/restart.
    private var generation = 0

    // MARK: - Taratura

    /// Sotto questo livello: nessun impulso (silenzio).
    private static let silence: Float = 0.06
    /// Intensità dell'impulso al livello minimo udibile (poi sale fino a 1.0).
    private static let minIntensity: CGFloat = 0.2
    /// Frequenza degli impulsi (in Hz) interpolata LINEARMENTE col volume, così sale in
    /// proporzione esattamente come l'intensità: lenta al minimo → rapida al massimo.
    private static let minFrequency: Double = 1.5
    private static let maxFrequency: Double = 12.0
    /// Ogni quanto ricontrollare quando si è sotto la soglia di silenzio.
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

    /// Aggiorna il livello (0...1) che pilota intensità e frequenza degli impulsi.
    func setLevel(_ value: Float) {
        level = max(0, min(1, value))
    }

    func stop() {
        running = false
        generation &+= 1   // invalida le closure pending
        generator = nil
        level = 0
    }

    // MARK: - Loop di impulsi (auto-schedulante)

    /// Emette un impulso (se sopra silenzio) e programma il successivo dopo un intervallo
    /// che dipende dal livello corrente: più forte il suono, più ravvicinati gli impulsi.
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
            // Frequenza LINEARE col volume (come l'intensità): le due salgono insieme e in
            // proporzione su tutta la scala, niente saturazione precoce della cadenza.
            let freq = Self.minFrequency + (Self.maxFrequency - Self.minFrequency) * Double(lvl)
            interval = 1.0 / freq
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.scheduleNextPulse(gen)
        }
    }

    deinit { stop() }
}
