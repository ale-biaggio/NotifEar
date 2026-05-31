//
//  PhoneConnectivityManager.swift
//  NotifEar (iPhone companion)
//
//  Lato iPhone di WatchConnectivity: impacchetta il modello compilato e lo
//  spedisce al Watch con `transferFile` (consegna in background, in coda).
//

import Foundation
import WatchConnectivity
import Combine

final class PhoneConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneConnectivityManager()

    @Published var isPaired = false
    @Published var isReachable = false
    @Published var isWatchAppInstalled = false
    @Published var lastTransferState = "—"

    /// Invocato (su main) per ogni suono rilevato dal Watch. Lo collega lo storico.
    var onDetectionReceived: ((DetectedEvent) -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// Invia SOLO le preferenze (quali suoni avvisano) al volo, senza riaddestrare.
    /// Usa l'application context: l'ultimo stato sovrascrive il precedente e arriva al
    /// Watch appena raggiungibile.
    func sendConfig(_ config: [String: [String: Any]]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext(["type": "customSoundConfig", "config": config])
            setState("Preferenze suoni aggiornate")
        } catch {
            setState("Errore preferenze: \(error.localizedDescription)")
        }
    }

    /// Impacchetta la directory `.mlmodelc` e la invia al Watch, insieme alle preferenze.
    func sendModel(compiledModelURL: URL, config: [String: [String: Any]]) {
        guard WCSession.isSupported() else {
            setState("WatchConnectivity non disponibile su questo dispositivo")
            return
        }
        let session = WCSession.default

        // Pre-controlli: senza questi, transferFile fallisce con errori poco chiari.
        guard session.activationState == .activated else {
            setState("Sessione Watch non ancora attiva — riprova tra un istante")
            session.activate()
            return
        }
        guard session.isWatchAppInstalled else {
            setState("L'app Watch non risulta companion di questa app iPhone. Reinstalla partendo dall'iPhone.")
            return
        }

        do {
            let packaged = FileManager.default.temporaryDirectory
                .appendingPathComponent("CustomSounds_\(UUID().uuidString).model")
            try ModelPackaging.pack(directory: compiledModelURL, to: packaged)
            session.transferFile(packaged, metadata: ["type": "customSoundModel", "config": config])
            setState("In invio… (consegna in background)")
        } catch {
            setState("Errore impacchettamento: \(error.localizedDescription)")
        }
    }

    private func setState(_ message: String) {
        DispatchQueue.main.async { self.lastTransferState = message }
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        refreshState(session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        refreshState(session)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        refreshState(session)
    }

    private func refreshState(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isReachable = session.isReachable
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    /// Riceve gli eventi di rilevamento inviati dal Watch (consegna in background).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard (userInfo["kind"] as? String) == "detection" else { return }
        let label = userInfo["label"] as? String ?? "—"
        let category = userInfo["category"] as? String ?? "attention"
        let ts = userInfo["ts"] as? Double ?? Date().timeIntervalSince1970
        let event = DetectedEvent(label: label, category: category, date: Date(timeIntervalSince1970: ts))
        DispatchQueue.main.async { self.onDetectionReceived?(event) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Riattiva per supportare il cambio di Watch abbinato.
        session.activate()
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error as NSError? {
            print("❌ Errore trasferimento file: \(error.domain) code \(error.code) — \(error)")
            setState("Errore invio [\(error.code)]: \(error.localizedDescription)")
        } else {
            setState("Inviato ✓")
        }
    }
}
