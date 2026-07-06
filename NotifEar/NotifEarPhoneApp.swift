
import SwiftUI

@main
struct NotifEarPhoneApp: App {
    @StateObject private var store = CustomSoundStore()
    @StateObject private var connectivity = PhoneConnectivityManager.shared
    @StateObject private var history = DetectionHistoryStore()

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView {
                    PhoneRootView()
                        .tabItem { Label("Suoni", systemImage: "waveform") }
                    HistoryView()
                        .tabItem { Label("Storico", systemImage: "clock") }
                }

                if let target = connectivity.pendingSonarTarget {
                    PhoneSonarView(target: target)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: connectivity.pendingSonarTarget)
            .environment(\.locale, Locale(identifier: "it_IT"))
            .environmentObject(store)
            .environmentObject(connectivity)
            .environmentObject(history)
            .onAppear {
                connectivity.configureNotifications()
                connectivity.onDetectionReceived = { event in
                    history.add(event)
                }
            }
        }
    }
}
