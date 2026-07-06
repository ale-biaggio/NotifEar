
import SwiftUI

struct HistoryStackView: View {
    @ObservedObject var store: WatchHistoryStore

    var onTapEar: () -> Void

    @State private var reveal: CGFloat = 0
    @State private var confirmClearAll = false

    var body: some View {
        ZStack {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.black).opacity(0.9)
            }
            .ignoresSafeArea()
            .opacity(Double(reveal))
            .allowsHitTesting(false)

            ScrollView {
                LazyVStack(spacing: 12) {
                    Color.clear
                        .containerRelativeFrame(.vertical)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapEar() }

                    if store.groups.isEmpty {
                        emptyCard
                            .padding(.horizontal, 6)
                            .riseLikeSmartStack()
                    } else {
                        ForEach(store.groups) { group in
                            HistoryCard(group: group)
                                .padding(.horizontal, 6)
                                .riseLikeSmartStack()
                        }

                        clearHistoryButton
                            .padding(.top, 2)
                            .riseLikeSmartStack()
                    }

                    Spacer(minLength: 10)
                }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                let h = max(geo.containerSize.height, 1)
                return min(max(geo.contentOffset.y / (h * 0.5), 0), 1)
            } action: { _, newValue in
                reveal = newValue
            }
        }
        .confirmationDialog("Cancellare tutto lo storico?",
                            isPresented: $confirmClearAll,
                            titleVisibility: .visible) {
            Button("Cancella tutto", role: .destructive) {
                store.clear()
            }
            Button("Annulla", role: .cancel) {}
        }
    }

    private var emptyCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("Nessun suono ancora")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.16))
        )
    }

    private var clearHistoryButton: some View {
        Button {
            confirmClearAll = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
                .glassEffect(.regular.tint(.red.opacity(0.18)).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Cancella storico")
    }
}

private extension View {
    func riseLikeSmartStack() -> some View {
        scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .scaleEffect(phase.isIdentity ? 1 : 0.85)
                .offset(y: phase.value * 30)
        }
    }
}

private struct HistoryCard: View {
    let group: WatchHistoryGroup

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(0.3))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(group.lastDate, format: .dateTime.hour().minute())
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if group.count > 1 {
                Text("×\(group.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.3), in: Capsule())
                    .foregroundStyle(color)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.16))
        )
    }

    private var color: Color {
        (SoundCategory(rawValue: group.category) ?? .attention).color
    }

    private var icon: String {
        switch group.category {
        case "emergency": return "exclamationmark.triangle.fill"
        case "danger":    return "exclamationmark.octagon.fill"
        case "home":      return "house.fill"
        default:          return "waveform"
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        HistoryStackView(store: .shared, onTapEar: {})
    }
}
