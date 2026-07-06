
import Foundation
import Combine

struct WatchDetectionEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    let label: String
    let category: String
    let date: Date
}

struct WatchHistoryGroup: Identifiable {
    let id: String
    let label: String
    let category: String
    let count: Int
    let lastDate: Date
}

final class WatchHistoryStore: ObservableObject {
    static let shared = WatchHistoryStore()

    @Published private(set) var events: [WatchDetectionEvent] = []

    private let maxEvents = 200
    private let key = "watch_detection_history"
    private let defaults = UserDefaults.standard

    private init() { load() }

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

    // MARK: - Persistence

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
