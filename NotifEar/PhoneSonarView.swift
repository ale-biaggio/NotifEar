
import SwiftUI

struct PhoneSonarView: View {
    let target: SonarTarget

    @StateObject private var controller = PhoneSonarController()

    @State private var showMovePrompt = true
    private static let movePromptDuration: TimeInterval = 4

    init(target: SonarTarget) {
        self.target = target
    }

    private var tint: Color { SoundCategory.color(for: target.category) }
    private var level: CGFloat { CGFloat(controller.liveLevel) }

    var body: some View {
        ZStack {
            backgroundPulse

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        ZStack {
                            ForEach(0..<3, id: \.self) { i in
                                let loop = t.truncatingRemainder(dividingBy: 1.8) / 1.8
                                let phase = (loop + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0)
                                Circle()
                                    .stroke(tint, lineWidth: 3)
                                    .frame(width: 150, height: 150)
                                    .scaleEffect(0.7 + phase * 1.5)
                                    .opacity((1.0 - phase) * Double(level))
                            }
                        }
                    }

                    icon
                        .scaleEffect(1.0 + 0.15 * level)
                        .animation(.easeOut(duration: 0.1), value: level)
                        .contentShape(Rectangle())
                        .onTapGesture { PhoneConnectivityManager.shared.dismissSonar() }
                }
                .frame(width: 220, height: 220)

                Text(target.label)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal)

                Spacer()
            }

            if showMovePrompt {
                VStack {
                    Spacer()
                    movePrompt.padding(.bottom, 40)
                }
            }
        }
        .contentShape(Rectangle())
        .overlay(alignment: .topLeading) {
            Button { PhoneConnectivityManager.shared.dismissSonar() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
        .statusBarHidden()
        .onAppear {
            controller.start(target: target)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.movePromptDuration) {
                withAnimation(.easeOut(duration: 0.4)) { showMovePrompt = false }
            }
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: controller.isActive) { _, active in
            if !active { PhoneConnectivityManager.shared.dismissSonar() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var icon: some View {
        if target.isSystemIcon {
            Image(systemName: target.iconName)
                .font(.system(size: 100, weight: .bold))
                .foregroundColor(tint)
        } else {
            Text(target.iconName)
                .font(.system(size: 120))
        }
    }

    private var backgroundPulse: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [tint.opacity(0.25 + 0.55 * Double(level)), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.15), value: level)
    }

    private var movePrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.system(size: 16, weight: .semibold))
                .symbolEffect(.wiggle, options: .repeating)
            Text("Muoviti per localizzare")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    PhoneSonarView(target: SonarTarget(
        label: "SIRENA",
        category: "emergency",
        iconName: "🚨",
        isSystemIcon: false,
        identifiers: ["siren", "ambulance_siren"],
        customLabel: nil
    ))
}
