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
    /// Intensità dell'impulso al livello minimo udibile (poi sale LINEARE fino a 1.0).
    private static let minIntensity: CGFloat = 0.25
    /// Frequenza degli impulsi (in Hz) — stile "metal detector": al minimo MOLTO rada
    /// (~0,6 Hz = uno ogni ~1,7 s), poi si infittisce fino a ~13 Hz (quasi continuo).
    private static let minFrequency: Double = 0.6
    private static let maxFrequency: Double = 13.0
    /// Curva sulla frequenza (esponente > 1): più è alto, più a lungo gli impulsi restano
    /// RADI salendo di volume — la raffica arriva solo vicino al massimo. 2.8 → la fascia
    /// lenta si estende fin verso metà corsa. L'intensità resta lineare (cresce subito).
    private static let frequencyCurve: Double = 2.8
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
            // Frequenza con curva (lvl^frequencyCurve): ai volumi bassi gli impulsi sono
            // ben distanziati, poi si infittiscono salendo. L'intensità resta lineare.
            let freq = Self.minFrequency + (Self.maxFrequency - Self.minFrequency) * pow(Double(lvl), Self.frequencyCurve)
            interval = 1.0 / freq
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.scheduleNextPulse(gen)
        }
    }

    deinit { stop() }
}
