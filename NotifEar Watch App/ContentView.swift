//
//  ContentView.swift
//  NotifEar Watch App
//
//  Created by NotifEar Team on 26/03/2026.
//

import SwiftUI

struct ContentView: View {
    private enum PresentedSheet: Identifiable {
        case detected(SoundInfo)
        case tracking(SoundInfo)

        var id: String {
            switch self {
            case .detected(let sound), .tracking(let sound):
                return "sound-\(sound.id)"
            }
        }
    }

    @ObservedObject var viewModel: SoundAnalyzerViewModel
    @ObservedObject var tracker: TrackingService

    /// Riceve i modelli di suoni personalizzati dall'iPhone.
    @ObservedObject private var modelReceiver = WatchModelReceiver.shared

    /// Sheet attualmente presentato: avviso del suono oppure Sonar/Tracking sul Watch.
    @State private var presentedSheet: PresentedSheet?

    /// Target in transizione dall'avviso al Sonar. Durante questo passaggio ignoriamo
    /// eventuali re-trigger dello stesso suono finché la sheet di tracking non è pronta.
    @State private var pendingTrackingTarget: SoundInfo?

    /// Testo del banner transitorio (es. "Nuovo suono ricevuto").
    @State private var bannerText: String?

    /// Binding unico di presentazione: usando `.sheet` watchOS disegna la stessa X
    /// nativa sia sull'avviso sia nella schermata Sonar/Tracking.
    private var presentedSheetBinding: Binding<PresentedSheet?> {
        Binding(
            get: { presentedSheet },
            set: { newValue in
                if newValue == nil {
                    pendingTrackingTarget = nil
                    viewModel.dismissAlert()
                }
                presentedSheet = newValue
            }
        )
    }

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

            // L'avviso del suono è presentato come sheet sotto: così la X è quella
            // nativa di watchOS, identica a quella del Sonar avviato.
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
            syncDetectedAlert(with: viewModel.detectedSound)
        }
        .sheet(item: presentedSheetBinding) { fallbackSheet in
            switch presentedSheet ?? fallbackSheet {
            case .detected(let detected):
                detectedAlertSheet(detected)
            case .tracking(let target):
                TrackingView(target: target, tracker: tracker, viewModel: viewModel)
            }
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
        .onChange(of: viewModel.detectedSound) { _, newValue in
            syncDetectedAlert(with: newValue)
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

    /// Schermata d'allarme del suono riconosciuto: il tap fuori dai controlli
    /// chiude l'avviso, il bottone principale apre il Sonar sul Watch.
    private func detectedAlertSheet(_ detected: SoundInfo) -> some View {
        ZStack {
            // Base SOLIDA: copre del tutto schermata principale e storico sotto.
            Color.black.ignoresSafeArea()
            LinearGradient(
                gradient: Gradient(colors: [detected.color.opacity(0.7), Color.black]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Spacer(minLength: 8)

                    VStack(spacing: 4) {
                        Group {
                            if detected.isSystemIcon {
                                Image(systemName: detected.iconName)
                                    .font(.system(size: 70, weight: .bold))
                                    .foregroundColor(detected.color)
                            } else {
                                Text(detected.iconName)
                                    .font(.system(size: 80))
                            }
                        }
                        .frame(width: 100, height: 100)

                        Text(detected.label)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Suono rilevato: \(detected.label)")

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissDetectedAlert()
                }
                .accessibilityAddTraits(.isButton)

                sonarActionBar(for: detected)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .padding(.top, 2)
            }
        }
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

    private func dismissDetectedAlert() {
        viewModel.dismissAlert()
        if case .detected = presentedSheet {
            presentedSheet = nil
        }
    }

    private func presentWatchSonar(for detected: SoundInfo) {
        // Arma subito il target e cambia contenuto della stessa sheet: nessun intervallo
        // "vuoto" in cui il suono continuo possa riaprire l'avviso sotto al Sonar.
        pendingTrackingTarget = detected
        viewModel.setTrackingTarget(for: detected)
        presentedSheet = .tracking(detected)
        viewModel.dismissAlert()

        DispatchQueue.main.async {
            guard pendingTrackingTarget == detected else { return }
            pendingTrackingTarget = nil
        }
    }

    private func syncDetectedAlert(with detected: SoundInfo?) {
        if pendingTrackingTarget != nil { return }
        if case .tracking = presentedSheet {
            if detected != nil { viewModel.dismissAlert() }
            return
        }
        if let detected {
            presentedSheet = .detected(detected)
        } else if case .detected = presentedSheet {
            presentedSheet = nil
        }
    }

    private func sonarActionBar(for detected: SoundInfo) -> some View {
        Button {
            presentWatchSonar(for: detected)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .bold))
                    .symbolEffect(.pulse, options: .repeating)
                    .frame(width: 31, height: 31)
                    .background(.white.opacity(0.10), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                    }

                Text("Sonar")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.leading, 8)
            .padding(.trailing, 15)
            .frame(height: 44)
            .background {
                Capsule()
                    .fill(.white.opacity(0.08))
                    .overlay {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.20),
                                        detected.color.opacity(0.18),
                                        .white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.9)
                    }
            }
            .glassEffect(.regular.tint(detected.color.opacity(0.18)).interactive(), in: .capsule)
            .shadow(color: detected.color.opacity(0.30), radius: 9, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apri Sonar sul Watch")
    }
}

#Preview {
    let vm = SoundAnalyzerViewModel()
    return ContentView(viewModel: vm, tracker: TrackingService(viewModel: vm))
}
