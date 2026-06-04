//
//  HistoryStackView.swift
//  NotifEar Watch App
//
//  Storico "a colpo d'occhio" in stile Smart Stack: a riposo NON si vede nulla (sotto
//  resta l'orecchio + la freccia). Trascinando su col dito o con la Digital Crown, le
//  card salgono UNA A UNA dal basso — ingrandendosi e comparendo — come i widget della
//  Smart Stack del quadrante. Non c'è un pannello unico che copre: sono card singole.
//
//  Volutamente NON interattivo: niente apertura di dettagli o sottovoci (quella
//  granularità vive nell'app iPhone). Il Watch continua a inviare gli eventi all'iPhone
//  via `WatchModelReceiver.reportDetection`.
//

import SwiftUI

struct HistoryStackView: View {
    @ObservedObject var store: WatchHistoryStore

    /// Tocco sulla "pagina" vuota in cima (= l'orecchio sotto): accende/spegne l'ascolto.
    /// Il trascinamento sullo stesso punto fa invece scorrere (gesti distinti, convivono).
    var onTapEar: () -> Void

    /// Avanzamento dello scroll: 0 a riposo, 1 quando lo storico è salito di una schermata.
    /// Pilota l'intensità della velatura sfocata dietro le card.
    @State private var reveal: CGFloat = 0

    var body: some View {
        ZStack {
            // Velatura DIETRO le card: a riposo invisibile (si vede nitido l'orecchio
            // sotto). Salendo, sfoca E scurisce lo sfondo finché — entro la seconda card —
            // non si vede più nulla sotto. Sempre graduale (segue lo scroll).
            ZStack {
                Rectangle().fill(.ultraThinMaterial)         // sfocatura
                Rectangle().fill(Color.black).opacity(0.9)   // oscurità: nasconde lo sfondo
            }
            .ignoresSafeArea()
            .opacity(Double(reveal))
            .allowsHitTesting(false)

            ScrollView {
                LazyVStack(spacing: 12) {
                    // Pagina vuota alta come lo schermo: a riposo si vede SOLO l'orecchio +
                    // freccia sotto. Tocco = on/off ascolto; trascina su (o Corona) = card su.
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
                    }

                    Spacer(minLength: 10)
                }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                let h = max(geo.containerSize.height, 1)
                // Pieno entro ~mezza schermata di scroll (≈ la seconda card), ma graduale.
                return min(max(geo.contentOffset.y / (h * 0.5), 0), 1)
            } action: { _, newValue in
                reveal = newValue
            }
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
}

private extension View {
    /// Effetto Smart Stack: ogni card entra dal basso salendo, ingrandendosi e comparendo;
    /// scivola via in alto allo stesso modo. L'animazione è guidata dallo scroll (Corona o
    /// dito), quindi le card salgono "una a una" mentre scorri.
    func riseLikeSmartStack() -> some View {
        scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .scaleEffect(phase.isIdentity ? 1 : 0.85)
                .offset(y: phase.value * 30)   // value>0 = card sotto (entra dal basso)
        }
    }
}

/// Singola card-widget di un tipo di suono nello storico.
private struct HistoryCard: View {
    let group: WatchHistoryGroup

    var body: some View {
        HStack(spacing: 10) {
            // "Icona app" del widget: quadratino colorato come la gravità del suono.
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
            // Card scura e opaca: un vero "widget" che si stacca dallo sfondo (niente
            // pannello unico che copre tutto — ogni card è a sé).
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.16))
        )
    }

    /// Colore proporzionale alla gravità (verde → rosso), coerente con tutta l'app.
    private var color: Color {
        (SoundCategory(rawValue: group.category) ?? .attention).color
    }

    /// Icona derivata dalla categoria, come nello storico iPhone.
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
