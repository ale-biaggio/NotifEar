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

struct SoundInfo: Equatable {
    let label: String
    let iconName: String
    let isSystemIcon: Bool
    let color: Color
    let category: SoundCategory
}

enum SoundCategory {
    case emergency, danger, home, attention
}

class SoundAnalyzerViewModel: NSObject, ObservableObject, SNResultsObserving {
    @Published var statusMessage: String = "Inizializzazione..."
    @Published var isListening: Bool = false
    @Published var detectedSound: SoundInfo?
    @Published var timeRemaining: TimeInterval = 0
    @Published var sessionExpired: Bool = false
    
    static let sessionDuration: TimeInterval = 30 * 60 // 30 minuti
    
    private let audioEngine = AVAudioEngine()
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.notifear.AnalysisQueue")
    
    private var extendedSession: WKExtendedRuntimeSession?
    private var countdownTimer: Timer?
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // Mappa con le chiavi esatte del modello Apple e icone SF Symbols
    private let soundMap: [String: SoundInfo] = [
        // EMERGENZE
        "ambulance_siren": SoundInfo(label: "AMBULANZA", iconName: "🚑", isSystemIcon: false, color: .red, category: .emergency),
        "siren": SoundInfo(label: "SIRENA", iconName: "🚨", isSystemIcon: false, color: .red, category: .emergency),
        "fire_alarm": SoundInfo(label: "ALLARME INCENDIO", iconName: "flame.fill", isSystemIcon: true, color: .red, category: .emergency),
        "smoke_detector": SoundInfo(label: "ALLARME FUMO", iconName: "🔥", isSystemIcon: false, color: .red, category: .emergency),
        
        // PERICOLI / GRIDA
        "scream": SoundInfo(label: "URLO RILEVATO", iconName: "exclamationmark.triangle.fill", isSystemIcon: true, color: .orange, category: .danger),
        "shout": SoundInfo(label: "GRIDO RILEVATO", iconName: "speaker.wave.3.fill", isSystemIcon: true, color: .orange, category: .danger),
        "car_horn": SoundInfo(label: "CLACSON", iconName: "🚗", isSystemIcon: false, color: .orange, category: .danger),
        
        // CASA
        "door_bell": SoundInfo(label: "CAMPANELLO", iconName: "bell.fill", isSystemIcon: true, color: .blue, category: .home),
        "doorbell": SoundInfo(label: "CAMPANELLO", iconName: "bell.fill", isSystemIcon: true, color: .blue, category: .home),
        "knock": SoundInfo(label: "BUSSANO", iconName: "🚪", isSystemIcon: false, color: .blue, category: .home),
        "telephone_bell": SoundInfo(label: "TELEFONO", iconName: "phone.fill", isSystemIcon: true, color: .green, category: .home),
        "ringtone": SoundInfo(label: "TELEFONO", iconName: "phone.fill", isSystemIcon: true, color: .green, category: .home),
        
        // ATTENZIONE
        "baby_crying": SoundInfo(label: "PIANTO NEONATO", iconName: "👶", isSystemIcon: false, color: .yellow, category: .attention),
        "baby_cry": SoundInfo(label: "PIANTO NEONATO", iconName: "👶", isSystemIcon: false, color: .yellow, category: .attention),
        "crying": SoundInfo(label: "PIANTO", iconName: "😢", isSystemIcon: false, color: .yellow, category: .attention),
        "dog": SoundInfo(label: "CANE", iconName: "🐕", isSystemIcon: false, color: .orange, category: .attention),
        "bark": SoundInfo(label: "ABBAIO", iconName: "🐕", isSystemIcon: false, color: .orange, category: .attention)
    ]
    
    // MARK: - Formatted time
    
    var formattedTimeRemaining: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var sessionProgress: Double {
        guard Self.sessionDuration > 0 else { return 0 }
        return timeRemaining / Self.sessionDuration
    }
    
    // MARK: - Listening
    
    func startListening() {
        guard !isListening else { return }
        sessionExpired = false
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.requestNotificationPermission()
                    self?.startExtendedSession()
                    self?.setupAudioAndStart()
                } else {
                    self?.statusMessage = "Permesso negato"
                }
            }
        }
    }
    
    private func setupAudioAndStart() {
        audioEngine.inputNode.removeTap(onBus: 0)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true)
            // Piccolo delay per permettere all'hardware di stabilizzarsi
            Thread.sleep(forTimeInterval: 0.2)
        } catch {
            self.statusMessage = "Errore Audio"; return
        }
        
        // Reset dell'engine per evitare stati sporchi
        audioEngine.stop()
        audioEngine.reset()
        
        // Preparo l'audio engine prima di chiedere il formato (risolve crash in certi simulatori e device)
        audioEngine.prepare()
        
        let recordingFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        
        // Controllo di sicurezza: se il formato è invalido (può succedere su simulatore) evito il crash
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            self.statusMessage = "Errore Hardware"; return
        }
        
        streamAnalyzer = SNAudioStreamAnalyzer(format: recordingFormat)
        
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try streamAnalyzer?.add(request, withObserver: self)
        } catch {
            self.statusMessage = "Errore Sistema"; return
        }
        
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 8192, format: recordingFormat) { [weak self] buffer, time in
            self?.analysisQueue.async { self?.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime) }
        }
        
        do {
            try audioEngine.start()
            self.isListening = true
            self.statusMessage = "In ascolto..."
        } catch { self.statusMessage = "Errore Avvio" }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false)
        self.isListening = false
        self.statusMessage = "Fermo"
        self.detectedSound = nil
        stopExtendedSession()
    }
    
    func restartSession() {
        stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startListening()
        }
    }
    
    /// Dismiss dell'alert corrente (usato da Double Tap e tap su schermo)
    func dismissAlert() {
        if detectedSound != nil {
            detectedSound = nil
            statusMessage = isListening ? "In ascolto..." : "Fermo"
        }
    }
    
    /// Azione primaria Double Tap: dismiss alert se attivo, restart se scaduta
    func handlePrimaryAction() {
        if detectedSound != nil {
            dismissAlert()
        } else if sessionExpired {
            restartSession()
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
        extendedSession = nil
        
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        extendedSession = session
        
        // Avvia il timer di countdown
        timeRemaining = Self.sessionDuration
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.onSessionExpired()
            }
        }
    }
    
    private func stopExtendedSession() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        timeRemaining = 0
        extendedSession?.invalidate()
        extendedSession = nil
    }
    
    private func onSessionExpired() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        
        // Haptic per avvisare l'utente
        WKInterfaceDevice.current().play(.stop)
        
        self.isListening = false
        self.sessionExpired = true
        self.statusMessage = "Sessione scaduta"
        self.detectedSound = nil
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false)
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
        
        let topClassifications = classificationResult.classifications.filter { $0.confidence > 0.4 }
        if !topClassifications.isEmpty {
            let descriptions = topClassifications.map { "\($0.identifier): \(Int($0.confidence * 100))%" }.joined(separator: ", ")
            print("🔍 Udito: \(descriptions)")
        }
        
        if let topMatch = classificationResult.classifications.first(where: { soundMap.keys.contains($0.identifier) && $0.confidence > 0.55 }),
           let info = soundMap[topMatch.identifier] {
            
            DispatchQueue.main.async {
                if self.detectedSound != info {
                    self.detectedSound = info
                    self.statusMessage = info.label
                    self.playHaptic(for: info.category)
                    self.sendLocalNotification(for: info)
                    
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
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension SoundAnalyzerViewModel: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("✅ Extended session avviata")
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("⚠️ Extended session in scadenza")
        DispatchQueue.main.async {
            self.onSessionExpired()
        }
    }
    
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {
        print("❌ Extended session invalidata: \(reason) (rawValue: \(reason.rawValue)) - Error: \(String(describing: error))")
        
        DispatchQueue.main.async {
            switch reason {
            case .expired, .suppressedBySystem:
                // La sessione è scaduta naturalmente o il sistema l'ha soppressa → ferma tutto
                if self.isListening {
                    self.onSessionExpired()
                }
            case .error:
                // Errore esterno (es. debugger collegato, conflitto sessioni).
                // L'audio continua a funzionare in foreground, ma il background non è garantito.
                // Non fermiamo l'ascolto, proviamo a ricreare la sessione dopo un delay.
                print("⚠️ Sessione persa ma audio in foreground attivo. Retry tra 5s...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if self.isListening && self.extendedSession == nil {
                        print("🔄 Tentativo di riavvio sessione estesa...")
                        let newSession = WKExtendedRuntimeSession()
                        newSession.delegate = self
                        newSession.start()
                        self.extendedSession = newSession
                    }
                }
            @unknown default:
                print("⚠️ Motivo invalidazione sconosciuto: \(reason.rawValue)")
            }
        }
    }
}
