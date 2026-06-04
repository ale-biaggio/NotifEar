//
//  WatchHistoryStore.swift
//  NotifEar Watch App
//
//  Storico LOCALE dei suoni rilevati, sul Watch. È volutamente minimale rispetto a
//  quello dell'iPhone (`DetectionHistoryStore`): qui serve solo una lista veloce,
//  raggruppata per tipo di suono, da rivelare con la Corona sotto la schermata
//  principale (stile Smart Stack). Niente run consecutive, niente apertura di
//  sottovoci, niente eliminazione per singolo evento.
//
//  Il Watch continua comunque a inviare gli eventi all'iPhone (vedi
//  `WatchModelReceiver.reportDetection`), dove c'è lo storico completo e ricco.
//

import Foundation
import Combine

/// Un suono rilevato in un certo istante (versione Watch, minimale).
struct WatchDetectionEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    let label: String
    let category: String   // rawValue di SoundCategory: "emergency"|"danger"|"home"|"attention"
    let date: Date
}

/// Una voce dello storico raggruppata per tipo di suono (stesso `label`): quante volte
/// è stato sentito e quando, l'ultima volta.
struct WatchHistoryGroup: Identifiable {
    let id: String          // = label (chiave del gruppo)
    let label: String
    let category: String
    let count: Int
    let lastDate: Date
}

final class WatchHistoryStore: ObservableObject {
    static let shared = WatchHistoryStore()

    /// Eventi dal più recente al più vecchio.
    @Published private(set) var events: [WatchDetectionEvent] = []

    /// Tetto agli eventi memorizzati: lo storico Watch è "a colpo d'occhio", non un archivio.
    private let maxEvents = 200
    private let key = "watch_detection_history"
    private let defaults = UserDefaults.standard

    private init() { load() }

    /// Registra un rilevamento. Sicuro da chiamare da qualsiasi thread (riallinea al main).
    func add(label: String, category: String, date: Date = Date()) {
        let event = WatchDetectionEvent(label: label, category: category, date: date)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.events.insert(event, at: 0)
            if self.events.count > self.maxEvents {
                self.events = Array(self.events.prefix(self.maxEvents))
            }
            self.save()
        }
    }

    func clear() {
        events = []
        save()
    }

    /// Eventi raggruppati PER TIPO di suono (label), dal gruppo più recente al più vecchio.
    /// Ogni gruppo riporta quante volte è stato sentito e l'ultima volta.
    var groups: [WatchHistoryGroup] {
        Dictionary(grouping: events, by: { $0.label })
            .values
            .compactMap { items -> WatchHistoryGroup? in
                guard let mostRecent = items.max(by: { $0.date < $1.date }) else { return nil }
                return WatchHistoryGroup(
                    id: mostRecent.label,
                    label: mostRecent.label,
                    category: mostRecent.category,
                    count: items.count,
                    lastDate: mostRecent.date
                )
            }
            .sorted { $0.lastDate > $1.lastDate }
    }

    // MARK: - Persistenza (UserDefaults: piccola e sufficiente per questo storico)

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WatchDetectionEvent].self, from: data) else { return }
        events = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: key)
    }
}
