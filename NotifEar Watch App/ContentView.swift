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
            // Sfondo dinamico FISSO dietro tutto: resta fermo mentre lo storico scorre.
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

            // Schermata principale: strato FISSO sotto, sempre interattivo (orecchio,
            // tocco, freccia). Non scorre mai.
            mainScreen

            // Storico in stile Smart Stack: a riposo nascosto (sotto resta SOLO l'orecchio
            // + freccia). Trascinando su col dito o con la Corona le card salgono UNA A UNA
            // dal basso, sopra l'orecchio che resta fermo. Il tocco sulla pagina vuota in
            // cima accende/spegne l'ascolto (trascinamento e tocco convivono).
            HistoryStackView(store: WatchHistoryStore.shared) {
                viewModel.toggleListening()
            }

            // Suono riconosciuto: emoji SOPRA A TUTTO (anche sopra lo storico se è stato
            // tirato su), con sfondo pieno che lo copre. Tap sull'icona → Sonar sul Watch;
            // pulsante → delega la localizzazione all'iPhone.
            if let detected = viewModel.detectedSound {
                detectedOverlay(detected)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.detectedSound?.label)
        // Double Tap (pizzico pollice-indice): chiude l'avviso oppure accende/spegne l'ascolto
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

    /// La schermata principale (stato dell'ascolto): occupa esattamente una "pagina",
    /// così sotto resta lo storico da rivelare scorrendo. In fondo, una piccola freccia
    /// suggerisce che c'è altro sotto (come la Smart Stack).
    private var mainScreen: some View {
        VStack(spacing: 12) {
            Spacer()

            if viewModel.sessionExpired {
                // Sessione scaduta — tocca l'orecchio per riprendere.
                earControl(
                    icon: "ear.trianglebadge.exclamationmark",
                    iconSize: 54,
                    tint: .orange,
                    title: "Sessione scaduta",
                    hint: "Tocca per riprendere"
                )

            } else if viewModel.isListening {
                // In ascolto — tocca l'orecchio per fermare.
                earControl(
                    icon: "ear.and.waveform",
                    iconSize: 54,
                    tint: .blue,
                    title: "In ascolto...",
                    hint: "Tocca per fermare",
                    animated: true
                )

            } else {
                // Fermo — tocca l'orecchio per avviare.
                earControl(
                    icon: "ear",
                    iconSize: 54,
                    tint: .gray,
                    title: "Non attivo",
                    hint: "Tocca per ascoltare"
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .overlay(alignment: .bottom) {
            // Affordance "c'è lo storico sotto": gira la Corona per rivelarlo.
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        // Tap su area vuota → chiude l'avviso del suono (i tocchi su orecchio/icona
        // hanno la precedenza coi loro gesti).
        .contentShape(Rectangle())
        .onTapGesture { viewModel.dismissAlert() }
    }

    /// Schermata d'allarme del suono riconosciuto: compare SOPRA tutto il resto (anche
    /// sopra lo storico se era tirato su) grazie a uno sfondo pieno che lo copre. Tap
    /// sull'icona → Sonar sul Watch; pulsante → delega la localizzazione all'iPhone.
    private func detectedOverlay(_ detected: SoundInfo) -> some View {
        ZStack {
            // Base SOLIDA: copre del tutto schermata principale e storico sotto.
            Color.black.ignoresSafeArea()
            LinearGradient(
                gradient: Gradient(colors: [detected.color.opacity(0.7), Color.black]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                VStack(spacing: 8) {
                    if detected.isSystemIcon {
                        Image(systemName: detected.iconName)
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(detected.color)
                    } else {
                        Text(detected.iconName)
                            .font(.system(size: 64))
                    }

                    Text(detected.label)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .contentShape(Rectangle())
                .onTapGesture { trackingTarget = detected }

                Button {
                    // Delego all'iPhone → fermo l'eventuale sonar sul Watch (un solo
                    // dispositivo alla volta deve fare il sonar).
                    tracker.stopTracking()
                    trackingTarget = nil
                    let ids = Array(viewModel.identifiers(matching: detected))
                    WatchModelReceiver.shared.requestSonarOnPhone(
                        label: detected.label,
                        category: detected.category.rawValue,
                        iconName: detected.iconName,
                        isSystemIcon: detected.isSystemIcon,
                        identifiers: ids,
                        customLabel: detected.customIdentifier
                    )
                    // Mentre l'iPhone localizza questo suono, il Watch non lo ri-annuncia.
                    viewModel.setSonarSuppression(identifiers: ids, customLabel: detected.customIdentifier)
                    showBanner("Inviato all'iPhone 📱")
                } label: {
                    Label("Localizza su iPhone", systemImage: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .tint(detected.color)
            }
            .padding(.horizontal)
        }
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
        .id(detected.label)
    }

    /// Orecchio interruttore: mostra stato (ascolto / fermo / scaduto) e, al tocco,
    /// accende o spegne l'ascolto. Un solo gesto per tutto, anche eyes-free col Double Tap
    /// (vedi `handlePrimaryAction`).
    @ViewBuilder
    private func earControl(
        icon: String,
        iconSize: CGFloat,
        tint: Color,
        title: String,
        hint: String,
        animated: Bool = false
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(tint.gradient)
                .symbolEffect(.variableColor.iterative, isActive: animated)
                // Altezza fissa: avviato e fermo restano della stessa grandezza e nella
                // stessa posizione, così al tocco non c'è "salto" di dimensione.
                .frame(height: 70)

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Text(hint)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggleListening() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
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
