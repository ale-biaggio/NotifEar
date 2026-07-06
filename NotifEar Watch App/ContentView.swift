
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

    @ObservedObject private var modelReceiver = WatchModelReceiver.shared

    @State private var presentedSheet: PresentedSheet?

    @State private var pendingTrackingTarget: SoundInfo?

    @State private var bannerText: String?

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

            mainScreen

            HistoryStackView(store: WatchHistoryStore.shared) {
                viewModel.toggleListening()
            }

        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.detectedSound?.label)
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

    private var mainScreen: some View {
        VStack(spacing: 12) {
            Spacer()

            if viewModel.sessionExpired {
                earControl(
                    icon: "ear.trianglebadge.exclamationmark",
                    iconSize: 54,
                    tint: .orange,
                    title: "Sessione scaduta",
                    hint: "Tocca per riprendere"
                )

            } else if viewModel.isListening {
                earControl(
                    icon: "ear.and.waveform",
                    iconSize: 54,
                    tint: .blue,
                    title: "In ascolto...",
                    hint: "Tocca per fermare",
                    animated: true
                )

            } else {
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
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.dismissAlert() }
    }

    private func detectedAlertSheet(_ detected: SoundInfo) -> some View {
        ZStack {
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
