
import SwiftUI

struct TrackingView: View {
    let target: SoundInfo
    @ObservedObject var tracker: TrackingService
    @ObservedObject var viewModel: SoundAnalyzerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var activePulses: [UUID] = []

    @State private var backgroundDismissEnabled = false

    var body: some View {
        ZStack {
            backgroundPulse
                .contentShape(Rectangle())
                .onTapGesture {
                    if backgroundDismissEnabled { dismiss() }
                }

            VStack(spacing: 7) {
                Spacer(minLength: 0)

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
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                }
                .frame(width: 100, height: 100)

                Text(target.label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                phoneHandoffButton
                    .padding(.top, 2)

                Spacer(minLength: 8)
            }
            .padding(.vertical, 6)
        }
        .persistentSystemOverlays(.hidden)
        .onAppear {
            backgroundDismissEnabled = false
            tracker.startTracking(target: target)
            scheduleBackgroundDismissEnable()
        }
        .onDisappear { tracker.stopTracking() }
        .onChange(of: tracker.state) { _, newState in
            if case .idle = newState { dismiss() }
        }
        .onChange(of: tracker.pulseCounter) { _, _ in
            activePulses.append(UUID())
        }
    }


    private func scheduleBackgroundDismissEnable() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            backgroundDismissEnabled = true
        }
    }

    // MARK: - Handoff iPhone

    private var phoneHandoffButton: some View {
        Button {
            requestPhoneSonar()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text("Passa a iPhone")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(width: 154, height: 34)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .glassEffect(.regular.tint(.cyan.opacity(0.18)).interactive(), in: .rect(cornerRadius: 12))
            .shadow(color: .cyan.opacity(0.20), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Passa a iPhone")
    }

    private func requestPhoneSonar() {
        let ids = Array(viewModel.identifiers(matching: target))
        viewModel.setSonarSuppression(identifiers: ids, customLabel: target.customIdentifier)
        tracker.stopTracking()
        WatchModelReceiver.shared.requestSonarOnPhone(
            label: target.label,
            category: target.category.rawValue,
            iconName: target.iconName,
            isSystemIcon: target.isSystemIcon,
            identifiers: ids,
            customLabel: target.customIdentifier
        )
        dismiss()
    }

    // MARK: - Background

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
