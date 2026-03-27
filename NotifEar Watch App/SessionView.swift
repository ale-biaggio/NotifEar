//
//  SessionView.swift
//  NotifEar Watch App
//
//  Created by NotifEar Team on 27/03/2026.
//

import SwiftUI

struct SessionView: View {
    @ObservedObject var viewModel: SoundAnalyzerViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 12) {
                Spacer()
                
                if viewModel.isListening {
                    // Timer circolare
                    ZStack {
                        // Track di sfondo
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 8)
                            .frame(width: 110, height: 110)
                        
                        // Progress ring
                        Circle()
                            .trim(from: 0, to: viewModel.sessionProgress)
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [.blue, .cyan, .blue]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 110, height: 110)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: viewModel.sessionProgress)
                        
                        // Tempo rimanente
                        VStack(spacing: 2) {
                            Text(viewModel.formattedTimeRemaining)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .monospacedDigit()
                            
                            Text("rimanenti")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Pulsante Stop
                    Button(action: {
                        viewModel.stopListening()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12))
                            Text("Ferma")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    
                } else if viewModel.sessionExpired {
                    // Sessione scaduta
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange.gradient)
                        
                        Text("Tempo scaduto")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Button(action: {
                            viewModel.restartSession()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12))
                                Text("Riavvia")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    
                } else {
                    // Non attivo
                    VStack(spacing: 12) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.gray.gradient)
                        
                        Text("Ascolto fermo")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            viewModel.restartSession()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12))
                                Text("Avvia")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    SessionView(viewModel: SoundAnalyzerViewModel())
}
