
import Foundation
import WatchConnectivity
import Combine
import WatchKit

final class WatchModelReceiver: NSObject, ObservableObject {
    static let shared = WatchModelReceiver()

    @Published var hasCustomModel: Bool = CustomModelStore.shared.hasModel

    @Published var lastInstall: Date?

    @Published var lastErrorMessage: String?

    var onModelInstalled: (() -> Void)?

    var onSonarEnded: (() -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    func activate() { _ = WCSession.isSupported() }

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

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if (message["kind"] as? String) == "sonarEnded" {
            DispatchQueue.main.async { self.onSonarEnded?() }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if (userInfo["kind"] as? String) == "sonarEnded" {
            DispatchQueue.main.async { self.onSonarEnded?() }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard (applicationContext["type"] as? String) == "customSoundConfig",
              let config = applicationContext["config"] as? [String: Any] else { return }
        CustomSoundConfigStore.shared.update(from: config)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard (file.metadata?["type"] as? String) == "customSoundModel" else { return }

        if let config = file.metadata?["config"] as? [String: Any] {
            CustomSoundConfigStore.shared.update(from: config)
        }

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
