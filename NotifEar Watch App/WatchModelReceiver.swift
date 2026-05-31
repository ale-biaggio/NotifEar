//
//  WatchModelReceiver.swift
//  NotifEar Watch App
//
//  Lato Watch di WatchConnectivity: riceve il pacchetto del modello dall'iPhone,
//  lo ricostruisce in `.mlmodelc` e lo installa. Espone `hasCustomModel` e un
//  callback `onModelInstalled` così il ViewModel può ri-creare la pipeline audio
//  per includere il classificatore custom.
//

import Foundation
import WatchConnectivity
import Combine
import WatchKit

final class WatchModelReceiver: NSObject, ObservableObject {
    static let shared = WatchModelReceiver()

    @Published var hasCustomModel: Bool = CustomModelStore.shared.hasModel

    /// Aggiornata ad ogni installazione riuscita: la UI la osserva per mostrare
    /// un banner "nuovo suono ricevuto".
    @Published var lastInstall: Date?

    /// Messaggio dell'ultimo errore di ricezione/installazione (nil se tutto ok).
    @Published var lastErrorMessage: String?

    /// Invocato (su main thread) quando un nuovo modello è stato installato.
    var onModelInstalled: (() -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// Da chiamare all'avvio per attivare la sessione anche se nessuno osserva ancora.
    func activate() { _ = WCSession.isSupported() }

    /// Invia all'iPhone un evento di rilevamento, per lo storico. Usa `transferUserInfo`:
    /// piccolo, in coda, consegnato in background (anche se l'iPhone non è raggiungibile
    /// in quel momento).
    func reportDetection(label: String, category: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.transferUserInfo([
            "kind": "detection",
            "label": label,
            "category": category,
            "ts": Date().timeIntervalSince1970
        ])
    }
}

extension WatchModelReceiver: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    /// Aggiornamento immediato delle preferenze (interruttori) senza riaddestrare.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard (applicationContext["type"] as? String) == "customSoundConfig",
              let config = applicationContext["config"] as? [String: Any] else { return }
        CustomSoundConfigStore.shared.update(from: config)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard (file.metadata?["type"] as? String) == "customSoundModel" else { return }

        // Preferenze inviate insieme al modello.
        if let config = file.metadata?["config"] as? [String: Any] {
            CustomSoundConfigStore.shared.update(from: config)
        }

        // Il file ricevuto viene cancellato dal sistema al ritorno: lavoriamo subito.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("incoming_model.mlmodelc", isDirectory: true)
        do {
            try ModelPackaging.unpack(file: file.fileURL, to: tmpDir)
            try CustomModelStore.shared.install(from: tmpDir)
            try? FileManager.default.removeItem(at: tmpDir)
            DispatchQueue.main.async {
                self.hasCustomModel = true
                self.lastInstall = Date()
                self.lastErrorMessage = nil
                // Feedback aptico: l'utente sente che è arrivato un nuovo suono.
                WKInterfaceDevice.current().play(.success)
                self.onModelInstalled?()
            }
        } catch {
            print("⚠️ Installazione modello custom fallita: \(error)")
            DispatchQueue.main.async {
                self.lastErrorMessage = error.localizedDescription
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }
}
