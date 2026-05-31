//
//  PatternDebugView.swift
//  NotifEar Watch App
//
//  Schermata TEMPORANEA di debug delle firme aptiche. Mostra una griglia di tile,
//  uno per ogni suono del catalogo: toccando un tile parte la firma aptica associata
//  per qualche secondo, indipendentemente dal classificatore — così l'utente può
//  testare e confrontare i pattern senza dover riprodurre il suono reale.
//
//  RIMUOVERE prima del rilascio: questa view, la sua tab in `NotifEarApp.swift` e
//  le API `playDebugPattern`/`stopDebugPattern`/`isPlayingDebugPattern` su
//  `TrackingService`.
//

import SwiftUI

/// Le quattro intensità provabili dal menù. Il `value` è un'intensità (0...1) che in
/// `TrackingService` sceglie il PRESET haptic della fascia (`hapticLadder`): a cadenza
/// fissa, a cambiare è la forza del colpo. Debole = colpo leggero (`.click`); Max = colpo
/// pieno (`.failure`). Così dal menù si sente esattamente come vibrerebbe quel volume in
/// modalità sonar reale.
private enum DebugIntensity: String, CaseIterable, Identifiable {
    case far = "Lontano"
    case medium = "Medio"
    case near = "Vicino"
    case veryNear = "Max"

    var id: String { rawValue }

    /// Intensità rappresentativa del volume (più alta = colpetti più fitti).
    /// I quattro valori sono distribuiti sull'intervallo 0...1.
    var value: Float {
        switch self {
        case .far:      return 0.15
        case .medium:   return 0.42
        case .near:     return 0.67
        case .veryNear: return 0.92
        }
    }

    /// Numero di barrette piene nell'icona (1...4), come indicatore di vicinanza.
    var bars: Int {
        switch self {
        case .far:      return 1
        case .medium:   return 2
        case .near:     return 3
        case .veryNear: return 4
        }
    }
}

struct PatternDebugView: View {
    @ObservedObject var viewModel: SoundAnalyzerViewModel
    @ObservedObject var tracker: TrackingService

    /// Ultimo suono di cui è stato avviato il test. Usato per evidenziare il tile
    /// corrispondente finché il debug è in corso (poi torna a nil).
    @State private var activeLabel: String?

    /// Intensità selezionata: simula il volume del suono. Riavvia il test attivo (se
    /// presente) quando cambia, così si sente subito la differenza di densità.
    @State private var intensity: DebugIntensity = .medium

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Test firme aptiche")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.top, 4)

                Text("Tocca per provare")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                intensitySelector

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(viewModel.distinctSounds) { info in
                        tile(for: info)
                    }
                }
                .padding(.horizontal, 2)

                Button(action: stopAndClear) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Stop")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
                .buttonStyle(.bordered)
                .tint(.gray)
                .padding(.top, 4)
                .disabled(activeLabel == nil)
            }
            .padding(.vertical, 6)
        }
        .onDisappear {
            // Se l'utente lascia la tab a metà debug, fermiamo la vibrazione.
            tracker.stopDebugPattern()
            activeLabel = nil
        }
        .onChange(of: tracker.isPlayingDebugPattern) { _, playing in
            // Se il debug timer scade da solo, svuotiamo l'highlight del tile.
            if !playing { activeLabel = nil }
        }
    }

    // MARK: - Selettore intensità

    /// Riga di quattro pulsanti (debole → Max) che simulano il volume del suono.
    /// Cambiarlo riavvia il test attivo così la differenza di densità dei colpetti si
    /// sente subito sullo stesso suono.
    private var intensitySelector: some View {
        VStack(spacing: 3) {
            Text("Intensità (distanza)")
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 4) {
                ForEach(DebugIntensity.allCases) { level in
                    intensityButton(level)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func intensityButton(_ level: DebugIntensity) -> some View {
        let isSelected = intensity == level

        return Button(action: { select(level) }) {
            VStack(spacing: 2) {
                barsIcon(filled: level.bars)
                Text(level.rawValue)
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(isSelected ? 0.95 : 0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Quattro barrette di altezza crescente; le prime `filled` sono piene.
    private func barsIcon(filled: Int) -> some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.white.opacity(i < filled ? 0.9 : 0.2))
                    .frame(width: 2.5, height: 4 + CGFloat(i) * 2)
            }
        }
        .frame(height: 10, alignment: .bottom)
    }

    // MARK: - Tile

    private func tile(for info: SoundInfo) -> some View {
        let isActive = activeLabel == info.label

        return Button(action: { play(info) }) {
            VStack(spacing: 3) {
                Group {
                    if info.isSystemIcon {
                        Image(systemName: info.iconName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(info.color)
                    } else {
                        Text(info.iconName)
                            .font(.system(size: 26))
                    }
                }
                .frame(height: 28)

                Text(info.label)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? info.color.opacity(0.45) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? info.color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Azioni

    private func play(_ info: SoundInfo) {
        tracker.playDebugPattern(for: info.label, intensity: intensity.value)
        activeLabel = info.label
    }

    /// Cambia l'intensità. Se un test è in corso, lo rilancia subito alla nuova
    /// intensità così la differenza di densità si percepisce sullo stesso suono.
    private func select(_ level: DebugIntensity) {
        intensity = level
        if let label = activeLabel {
            tracker.playDebugPattern(for: label, intensity: level.value)
        }
    }

    private func stopAndClear() {
        tracker.stopDebugPattern()
        activeLabel = nil
    }
}

#Preview {
    let vm = SoundAnalyzerViewModel()
    return PatternDebugView(viewModel: vm, tracker: TrackingService(viewModel: vm))
}
