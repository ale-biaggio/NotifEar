//
//  ContentView.swift
//  NotifEar Watch App
//
//  Created by NotifEar Team on 26/03/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SoundAnalyzerViewModel
    
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
                    // Suono rilevato
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
            
            // Double Tap: dismiss alert o restart sessione
            Button(action: { viewModel.handlePrimaryAction() }) {}
                .handGestureShortcut(.primaryAction)
                .hidden()
        }
        // Tap per dismiss dell'alert
        .onTapGesture {
            viewModel.dismissAlert()
        }
        .onAppear {
            viewModel.startListening()
        }
    }
}

#Preview {
    ContentView(viewModel: SoundAnalyzerViewModel())
}
