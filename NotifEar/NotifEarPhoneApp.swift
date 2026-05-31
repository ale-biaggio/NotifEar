//
//  NotifEarPhoneApp.swift
//  NotifEar (iPhone companion)
//
//  App iPhone companion di NotifEar. Scopo: registrare campioni di suoni
//  PERSONALIZZATI, addestrare on-device un classificatore Core ML (Create ML
//  Components, iOS 16+) e spedirlo al Watch via WatchConnectivity, dove gira
//  ACCANTO al classificatore di sistema (~300 suoni) di SoundAnalysis.
//

import SwiftUI

@main
struct NotifEarPhoneApp: App {
    @StateObject private var store = CustomSoundStore()
    @StateObject private var connectivity = PhoneConnectivityManager.shared
    @StateObject private var history = DetectionHistoryStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                PhoneRootView()
                    .tabItem { Label("Suoni", systemImage: "waveform") }
                HistoryView()
                    .tabItem { Label("Storico", systemImage: "clock") }
            }
            .environment(\.locale, Locale(identifier: "it_IT"))
            .environmentObject(store)
            .environmentObject(connectivity)
            .environmentObject(history)
            .onAppear {
                // Gli eventi rilevati dal Watch confluiscono nello storico.
                connectivity.onDetectionReceived = { event in
                    history.add(event)
                }
            }
        }
    }
}
