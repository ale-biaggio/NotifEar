//
//  NotifEarApp.swift
//  NotifEar Watch App
//
//  Created by NotifEar Team on 26/03/2026.
//

import SwiftUI

@main
struct NotifEar_Watch_AppApp: App {
    @StateObject private var viewModel: SoundAnalyzerViewModel
    @StateObject private var tracker: TrackingService

    init() {
        let vm = SoundAnalyzerViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _tracker = StateObject(wrappedValue: TrackingService(viewModel: vm))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(viewModel: viewModel, tracker: tracker)
                SessionView(viewModel: viewModel)
                // TEMPORANEA — schermata di test delle firme aptiche.
                // Rimuovere insieme a PatternDebugView e alle API debug di
                // TrackingService prima del rilascio.
                PatternDebugView(viewModel: viewModel, tracker: tracker)
            }
            .tabViewStyle(.page)
        }
    }
}
