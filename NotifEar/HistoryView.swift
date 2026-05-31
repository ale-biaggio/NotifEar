//
//  HistoryView.swift
//  NotifEar (iPhone companion)
//
//  Scheda "Storico": i suoni rilevati dal Watch, raggruppati in "run" (una voce per
//  sequenza consecutiva dello stesso suono). Le voci con più rilevamenti mostrano un
//  contatore e si espandono al tocco.
//
//  Eliminazione (swipe verso sinistra):
//   - sulla VOCE PRINCIPALE (gruppo) → "Elimina tutto" (rimuove tutti i rilevamenti);
//   - su una SOTTOVOCE → "Elimina" (rimuove solo quel rilevamento).
//
//  NB: niente DisclosureGroup — l'espansione è gestita a mano per evitare che lo swipe
//  del gruppo "tracimi" sulle sottovoci.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var history: DetectionHistoryStore
    @State private var confirmClearAll = false
    @State private var expanded: Set<UUID> = []

    private static let itLocale = Locale(identifier: "it_IT")

    var body: some View {
        NavigationStack {
            Group {
                if history.events.isEmpty {
                    ContentUnavailableView(
                        "Nessun suono ancora",
                        systemImage: "clock",
                        description: Text("Qui compaiono i suoni rilevati dal Watch mentre NotifEar è in ascolto.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(history.runs) { run in
                                headerRow(run)

                                if run.count > 1 && expanded.contains(run.id) {
                                    ForEach(run.items) { event in
                                        subRow(event, category: run.category)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    history.deleteEvent(event)
                                                } label: {
                                                    Label("Elimina", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                            }
                        }

                        Section {
                            Button(role: .destructive) {
                                confirmClearAll = true
                            } label: {
                                Text("Cancella tutto")
                                    .frame(maxWidth: .infinity)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Storico")
            .confirmationDialog("Cancellare tutto lo storico?",
                                isPresented: $confirmClearAll, titleVisibility: .visible) {
                Button("Cancella tutto", role: .destructive) { history.clear() }
                Button("Annulla", role: .cancel) {}
            }
        }
    }

    // MARK: - Righe

    @ViewBuilder
    private func headerRow(_ run: DetectionRun) -> some View {
        if run.count > 1 {
            // Niente Button qui: con la riga avvolta in un Button SwiftUI allinea in
            // alto l'etichetta dello swipe. Riga "normale" + onTapGesture per espandere.
            headerContent(run)
                .onTapGesture {
                    toggle(run.id)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        history.deleteRun(run)
                    } label: {
                        Label("Elimina tutto", systemImage: "trash")
                    }
                }
        } else {
            headerContent(run)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        if let only = run.items.first { history.deleteEvent(only) }
                    } label: {
                        Label("Elimina", systemImage: "trash")
                    }
                }
        }
    }

    private func headerContent(_ run: DetectionRun) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: run.category))
                .foregroundStyle(color(for: run.category))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.label).foregroundStyle(.primary)
                Text(subtitle(run)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if run.count > 1 {
                Text("×\(run.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color(for: run.category).opacity(0.2), in: Capsule())
                    .foregroundStyle(color(for: run.category))
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded.contains(run.id) ? 90 : 0))
            }
        }
        .contentShape(Rectangle())
    }

    private func subRow(_ event: DetectedEvent, category: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path")
                .font(.caption)
                .foregroundStyle(color(for: category))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.date, format: .dateTime.weekday().hour().minute().second())
                    .font(.callout)
                Text(event.date, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.leading, 8)
    }

    // MARK: - Helper

    private func toggle(_ id: UUID) {
        withAnimation {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    private func subtitle(_ run: DetectionRun) -> String {
        if run.count > 1 {
            let style = Date.FormatStyle(date: .omitted, time: .shortened).locale(Self.itLocale)
            return "\(run.start.formatted(style)) – \(run.end.formatted(style))"
        } else {
            let style = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Self.itLocale)
            return run.end.formatted(style)
        }
    }

    private func color(for category: String) -> Color {
        // Stessa scala di gravità (verde → rosso) usata in tutta l'app.
        SoundCategory.color(for: category)
    }

    private func icon(for category: String) -> String {
        switch category {
        case "emergency": return "exclamationmark.triangle.fill"
        case "danger":    return "exclamationmark.octagon.fill"
        case "home":      return "house.fill"
        default:          return "waveform"
        }
    }
}
