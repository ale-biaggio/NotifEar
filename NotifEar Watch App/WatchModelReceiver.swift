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

    /// Invocato (su main thread) quando l'iPhone segnala che il sonar è terminato.
    var onSonarEnded: (() -> Void)?

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

    /// Chiede all'iPhone di attivare la modalità Sonar su un suono già riconosciuto qui.
    /// Manda il "bersaglio" (etichetta, icona, categoria e le chiavi di gating: identifier
    /// di sistema OPPURE `customLabel`); l'iPhone ne fa una notifica locale che, al tap,
    /// apre la schermata Sonar pre-armata.
    ///
    /// Se l'iPhone è raggiungibile usa `sendMessage` (lo sveglia in background subito);
    /// altrimenti, o in caso d'errore, ripiega su `transferUserInfo` (consegna in coda).
    ///
    /// NOTA: le chiavi del payload e il valore "sonarHandoff" devono restare allineati a
    /// `SonarTarget` lato iPhone (NON condividono codice tra i due target).
    func requestSonarOnPhone(label: String, category: String, iconName: String,
                             isSystemIcon: Bool, identifiers: [String], customLabel: String?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        var payload: [String: Any] = [
            "kind": "sonarHandoff",
            "label": label,
            "category": category,
            "iconName": iconName,
            "isSystemIcon": isSystemIcon,
            "identifiers": identifiers
        ]
        if let customLabel { payload["customLabel"] = customLabel }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                // Il messaggio immediato è fallito: ripieghiamo sulla consegna in coda.
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }
}

extension WatchModelReceiver: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    /// Messaggio "fine sonar" dall'iPhone (immediato, se raggiungibile).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if (message["kind"] as? String) == "sonarEnded" {
            DispatchQueue.main.async { self.onSonarEnded?() }
        }
    }

    /// Fallback in coda per il "fine sonar" (se l'iPhone non era raggiungibile via sendMessage).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if (userInfo["kind"] as? String) == "sonarEnded" {
            DispatchQueue.main.async { self.onSonarEnded?() }
        }
    }

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
