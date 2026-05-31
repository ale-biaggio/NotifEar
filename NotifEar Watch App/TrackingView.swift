//
//  TrackingView.swift
//  NotifEar Watch App
//
//  UI della modalità Tracking. Presentata come `.sheet` da ContentView quando l'utente
//  tocca il tile di un suono riconosciuto. Mostra:
//   - emoji/icona grande del suono che ha innescato il tracking (scala col volume) +
//     sfondo e cerchi concentrici che pulsano in sincrono con l'intensità haptic
//   - nome del suono
//
//  Per uscire si usa la chiusura nativa del foglio (X in alto a sinistra): alla
//  dismissione `onDisappear` ferma il tracking. Si chiude da sola anche se il
//  tracking torna idle.
//
//  L'haptic è gestito dal `TrackingService` (vibrazione continua modulata dal volume
//  audio istante per istante). La view si limita a:
//   - chiamare `startTracking` in onAppear / `stopTracking` in onDisappear
//   - leggere `tracker.liveLevel` (lo stesso valore che pilota l'intensità haptic) per
//     dare un feedback visivo coerente con la vibrazione percepita.
//

import SwiftUI

struct TrackingView: View {
    let target: SoundInfo
    @ObservedObject var tracker: TrackingService
    @ObservedObject var viewModel: SoundAnalyzerViewModel
    @Environment(\.dismiss) private var dismiss

    /// Pulsazioni visive in volo. Ogni elemento è un cerchio che si espande dall'emoji
    /// e svanisce; quando l'animazione finisce viene rimosso. Sincronizzato con l'haptic
    /// via `tracker.pulseCounter`: spawnato esattamente quando esce un colpetto.
    @State private var activePulses: [UUID] = []

    var body: some View {
        ZStack {
            backgroundPulse

            VStack(spacing: 10) {
                Spacer(minLength: 4)

                ZStack {
                    ForEach(activePulses, id: \.self) { id in
                        ExpandingRing(color: target.color) {
                            activePulses.removeAll { $0 == id }
                        }
                    }

                    Group {
                        if target.isSystemIcon {
                            Image(systemName: target.iconName)
                                .font(.system(size: 70, weight: .bold))
                                .foregroundColor(target.color)
                        } else {
                            Text(target.iconName)
                                .font(.system(size: 80))
                        }
                    }
                    .scaleEffect(1.0 + 0.15 * CGFloat(tracker.liveLevel))
                    .animation(.easeOut(duration: 0.08), value: tracker.liveLevel)
                }
                .frame(width: 100, height: 100)

                Text(target.label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4)
            }
            .padding(.vertical, 6)
        }
        .onAppear { tracker.startTracking(target: target) }
        .onDisappear { tracker.stopTracking() }
        .onChange(of: tracker.state) { _, newState in
            if case .idle = newState { dismiss() }
        }
        .onChange(of: tracker.pulseCounter) { _, _ in
            // Ogni colpetto emesso dal service → un cerchio che si espande dall'emoji.
            activePulses.append(UUID())
        }
    }

    // Nessun pulsante Stop: si esce dal foglio con la chiusura nativa (X in alto a
    // sinistra) e `onDisappear` ferma il tracking.

    // MARK: - Sfondo che pulsa col livello

    private var backgroundPulse: some View {
        let level = Double(tracker.liveLevel)
        return LinearGradient(
            colors: [
                target.color.opacity(0.25 + 0.55 * level),
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

// MARK: - ExpandingRing

/// Singolo cerchio di pulsazione: parte poco più grande dell'emoji, si espande e
/// svanisce in ~0.8 s. Al termine chiama `onComplete` per essere rimosso dalla lista
/// del parent. Più cerchi possono coesistere: ai volumi alti il sonar emette fino a
/// 10 colpetti al secondo, e il cerchio si dissolve in ~800 ms → fino a ~8 cerchi
/// sovrapposti contemporaneamente.
private struct ExpandingRing: View {
    let color: Color
    let onComplete: () -> Void

    @State private var scale: CGFloat = 0.7
    @State private var opacity: Double = 0.75

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: 90, height: 90)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    scale = 1.9
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    onComplete()
                }
            }
    }
}

#Preview {
    let vm = SoundAnalyzerViewModel()
    let info = SoundInfo(
        label: "SIRENA",
        iconName: "🚨",
        isSystemIcon: false,
        category: .emergency
    )
    return TrackingView(target: info, tracker: TrackingService(viewModel: vm), viewModel: vm)
}
