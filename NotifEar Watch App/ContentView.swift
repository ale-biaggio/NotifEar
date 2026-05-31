//
//  ContentView.swift
//  NotifEar Watch App
//
//  Created by NotifEar Team on 26/03/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SoundAnalyzerViewModel
    @ObservedObject var tracker: TrackingService

    /// Riceve i modelli di suoni personalizzati dall'iPhone.
    @ObservedObject private var modelReceiver = WatchModelReceiver.shared

    /// Suono target selezionato dal tap sul tile. Quando non-nil presenta lo sheet TrackingView.
    @State private var trackingTarget: SoundInfo?

    /// Testo del banner transitorio (es. "Nuovo suono ricevuto").
    @State private var bannerText: String?

    var body: some View {
        ZStack {
            // Sfondo dinamico con gradiente
            LinearGradient(
                gradient: Gradient(colors: [
                    (viewModel.detectedSound != nil ? viewModel.detectedSound!.color.opacity(0.6) : Color.black),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: viewModel.detectedSound?.label)
            
            VStack(spacing: 12) {
                Spacer()
                
                if let detected = viewModel.detectedSound {
                    // Suono rilevato — tappabile per entrare in modalità Tracking su questa classe.
                    VStack(spacing: 8) {
                        if detected.isSystemIcon {
                            Image(systemName: detected.iconName)
                                .font(.system(size: 60, weight: .bold))
                                .foregroundColor(detected.color)
                        } else {
                            Text(detected.iconName)
                                .font(.system(size: 70))
                        }

                        Text(detected.label)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    .id(detected.label)
                    .contentShape(Rectangle())
                    .onTapGesture { trackingTarget = detected }

                } else if viewModel.sessionExpired {
                    // Sessione scaduta
                    VStack(spacing: 8) {
                        Image(systemName: "ear.trianglebadge.exclamationmark")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange.gradient)
                        
                        Text("Sessione scaduta")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                } else if viewModel.isListening {
                    // In ascolto – animazione
                    VStack(spacing: 8) {
                        Image(systemName: "ear.and.waveform")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue.gradient)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                        
                        Text("In ascolto...")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                } else {
                    // Non attivo
                    VStack(spacing: 8) {
                        Image(systemName: "ear")
                            .font(.system(size: 44))
                            .foregroundStyle(.gray.gradient)
                        
                        Text("Non attivo")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
        }
        // Tap per dismiss dell'alert
        .onTapGesture {
            viewModel.dismissAlert()
        }
        // Double Tap (pizzico pollice-indice): dismiss alert o restart sessione
        .overlay {
            Button(action: { viewModel.handlePrimaryAction() }) {
                Color.clear
                    .frame(width: 0, height: 0)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(false)
            .handGestureShortcut(.primaryAction)
        }
        .onAppear {
            viewModel.startListening()
        }
        .sheet(item: $trackingTarget) { target in
            TrackingView(target: target, tracker: tracker, viewModel: viewModel)
        }
        // Banner transitorio quando arriva un nuovo modello dall'iPhone.
        .overlay(alignment: .top) {
            if let bannerText {
                Text(bannerText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.purple.opacity(0.9), in: Capsule())
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: modelReceiver.lastInstall) { _, _ in
            showBanner("Nuovo suono ricevuto ✓")
        }
        .onChange(of: modelReceiver.lastErrorMessage) { _, newValue in
            if newValue != nil { showBanner("Errore ricezione suono") }
        }
    }

    /// Mostra un banner per qualche secondo, poi lo nasconde.
    private func showBanner(_ text: String) {
        withAnimation { bannerText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { if bannerText == text { bannerText = nil } }
        }
    }
}

#Preview {
    let vm = SoundAnalyzerViewModel()
    return ContentView(viewModel: vm, tracker: TrackingService(viewModel: vm))
}
