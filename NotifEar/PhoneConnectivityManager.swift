
import Foundation
import WatchConnectivity
import Combine
import UserNotifications

final class PhoneConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneConnectivityManager()

    static let sonarNotificationCategory = "NotifEarSonar"

    @Published var isPaired = false
    @Published var isReachable = false
    @Published var isWatchAppInstalled = false
    @Published var lastTransferState = "—"

    @Published var pendingSonarTarget: SonarTarget?

    var onDetectionReceived: ((DetectedEvent) -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Sonar Handoff

    private func handleSonarHandoff(_ payload: [String: Any]) {
        guard let target = SonarTarget(payload: payload) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Localizza: \(target.label)"
        content.body = "Tocca per attivare il sonar e trovare la sorgente."
        content.sound = .default
        content.categoryIdentifier = Self.sonarNotificationCategory
        content.userInfo = target.payload
        let request = UNNotificationRequest(
            identifier: "sonar_\(target.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func routeIncoming(_ dict: [String: Any]) {
        if (dict["kind"] as? String) == SonarTarget.messageKind {
            handleSonarHandoff(dict)
        }
    }

    private func sonarTarget(fromUserInfo userInfo: [AnyHashable: Any]) -> SonarTarget? {
        var dict: [String: Any] = [:]
        for (key, value) in userInfo {
            if let k = key as? String { dict[k] = value }
        }
        return SonarTarget(payload: dict)
    }

    // MARK: - Sonar Presentation

    private func presentSonar(_ target: SonarTarget) {
        DispatchQueue.main.async { self.pendingSonarTarget = target }
    }

    func dismissSonar() {
        pendingSonarTarget = nil
        sendSonarEnded()
    }

    private func sendSonarEnded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let msg: [String: Any] = ["kind": "sonarEnded"]
        if session.isReachable {
            session.sendMessage(msg, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(msg)
            })
        } else {
            session.transferUserInfo(msg)
        }
    }

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

    func sendModel(compiledModelURL: URL, config: [String: [String: Any]]) {
        guard WCSession.isSupported() else {
            setState("WatchConnectivity non disponibile su questo dispositivo")
            return
        }
        let session = WCSession.default

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

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        routeIncoming(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        routeIncoming(message)
        replyHandler(["ok": true])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let kind = userInfo["kind"] as? String
        if kind == SonarTarget.messageKind {
            handleSonarHandoff(userInfo)
            return
        }
        guard kind == "detection" else { return }
        let label = userInfo["label"] as? String ?? "—"
        let category = userInfo["category"] as? String ?? "attention"
        let ts = userInfo["ts"] as? Double ?? Date().timeIntervalSince1970
        let event = DetectedEvent(label: label, category: category, date: Date(timeIntervalSince1970: ts))
        DispatchQueue.main.async { self.onDetectionReceived?(event) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
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

// MARK: - UNUserNotificationCenterDelegate

extension PhoneConnectivityManager: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if let target = sonarTarget(fromUserInfo: notification.request.content.userInfo) {
            presentSonar(target)
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let target = sonarTarget(fromUserInfo: response.notification.request.content.userInfo) {
            presentSonar(target)
        }
        completionHandler()
    }
}
