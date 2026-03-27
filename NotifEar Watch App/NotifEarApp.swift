//
//  NotifEarApp.swift
//  NotifEar Watch App
//
//  Created by Alessandro Biaggioli on 26/03/2026.
//

import SwiftUI

@main
struct NotifEar_Watch_AppApp: App {
    @StateObject private var viewModel = SoundAnalyzerViewModel()
    
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(viewModel: viewModel)
                SessionView(viewModel: viewModel)
            }
            .tabViewStyle(.page)
        }
    }
}
