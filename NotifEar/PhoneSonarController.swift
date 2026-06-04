//
//  PhoneSonarController.swift
//  NotifEar (iPhone companion)
//
//  Gemello iOS di [TrackingService] (lato Watch): orchestra la modalità Sonar
//  sull'iPhone. Possiede il [PhoneSoundRecognizer] (microfono + classificatori) e il
//  [SonarHapticEngine] (vibrazione continua), e a 10 Hz ricava da loro un `liveLevel`
//  0...1 che pilota SIA la UI SIA la forza della vibrazione.
//
//  ORDINE DI AVVIO (importante): la vibrazione (Core Haptics) parte SOLO quando la
//  sessione audio del microfono è già attiva (callback `recognizer.onReady`). Avviarla
//  prima creava un conflitto di sessione audio che poteva far crashare l'apertura.
//
//  Le costanti di taratura sono le STESSE del Watch, per coerenza percepita.
//

import Foundation
import Combine

final class PhoneSonarController: ObservableObject {

    /// Intensità 0...1 dell'ultimo campione (con il target presente). Pilota la UI e,
    /// gated dalla soglia di silenzio, la forza della vibrazione.
    @Published var liveLevel: Float = 0
    @Published var isActive: Bool = false

    // MARK: - Config (allineata a TrackingService del Watch)

    private static let rmsReference: Float = 0.015
    private static let dBFloor: Float = -28
    private static let dBCeiling: Float = 0
    private static let confidenceThreshold: Float = 0.4
    /// Envelope follower sulla confidence. Più BASSO del Watch (0.96) per ridurre il lag:
    /// 0.82 a 10 Hz → mezza-vita ~0.35 s, così la vibrazione si ferma prontamente quando
    /// il suono cessa, senza trascinarsi dietro.
    private static let confidenceDecay: Float = 0.82
    private static let monitorPeriod: TimeInterval = 0.1
    /// Dopo questo tempo senza il suono target presente, il sonar si ferma da solo.
    private static let silenceTimeout: TimeInterval = 5

    // MARK: - Dipendenze (possedute)

    private let recognizer = PhoneSoundRecognizer()
    private let haptics = SonarHapticEngine()
    private var monitorTimer: Timer?
    private var smoothedConfidence: Float = 0
    /// Ultimo istante in cui il target era presente: per l'auto-stop dopo silenzio.
    private var lastPresentAt: Date = .distantPast

    // MARK: - API

    /// Avvia il sonar sul bersaglio: arma il riconoscitore, avvia il monitor e — appena
    /// l'audio è pronto — la vibrazione continua.
    func start(target: SonarTarget) {
        recognizer.setTarget(identifiers: target.identifiers, customLabel: target.customLabel)
        smoothedConfidence = 0
        liveLevel = 0
        lastPresentAt = Date()   // grace: 5 s dall'avvio per "agganciare" il suono
        isActive = true

        // Vibrazione UIKit: indipendente dalla sessione audio → si avvia subito (colpetto
        // di conferma immediato), senza aspettare il microfono.
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
    }

    // MARK: - Monitor loop

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

    /// Aggiorna l'envelope sulla confidence, ricalcola `liveLevel` e modula la vibrazione.
    private func tick() {
        guard isActive else { return }

        smoothedConfidence = max(recognizer.currentTargetConfidence, smoothedConfidence * Self.confidenceDecay)
        let isPresent = smoothedConfidence >= Self.confidenceThreshold

        // Auto-stop: se il suono non si sente da più di `silenceTimeout`, ferma il sonar
        // (la view osserva `isActive` e chiude l'overlay).
        if isPresent {
            lastPresentAt = Date()
        } else if Date().timeIntervalSince(lastPresentAt) > Self.silenceTimeout {
            stop()
            return
        }

        // `liveLevel` (0...1) pilota SIA la UI SIA la vibrazione. Il motore haptic gestisce
        // soglia di silenzio, intensità e frequenza degli impulsi in base a questo livello.
        let raw = isPresent ? Self.intensity(forRMS: recognizer.currentRMS) : 0
        liveLevel = raw
        haptics.setLevel(raw)
    }

    // MARK: - Mapping volume → intensità

    private static func intensity(forRMS rms: Float) -> Float {
        let safe = max(rms, 1e-5)  // evita log(0)
        let db = 20 * log10f(safe / rmsReference)
        let normalized = (db - dBFloor) / (dBCeiling - dBFloor)
        return min(max(normalized, 0), 1)
    }

    deinit {
        monitorTimer?.invalidate()
    }
}
