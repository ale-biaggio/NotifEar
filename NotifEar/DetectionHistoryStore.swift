
import Foundation
import Combine

struct DetectedEvent: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var category: String
    var date: Date
}

struct DetectionRun: Identifiable {
    let id: UUID
    let label: String
    let category: String
    let items: [DetectedEvent]
    var count: Int { items.count }
    var start: Date { items.last?.date ?? .distantPast }
    var end: Date { items.first?.date ?? .distantPast }
}

@MainActor
final class DetectionHistoryStore: ObservableObject {
    @Published private(set) var events: [DetectedEvent] = []

    private let fm = FileManager.default
    private let maxEvents = 1000

    init() { load() }

    private var url: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("detection_history.json")
    }

    func add(_ event: DetectedEvent) {
        events.insert(event, at: 0)
        if events.count > maxEvents { events = Array(events.prefix(maxEvents)) }
        save()
    }

    func clear() {
        events = []
        save()
    }

    func deleteRun(_ run: DetectionRun) {
        let ids = Set(run.items.map { $0.id })
        events.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteEvent(_ event: DetectedEvent) {
        events.removeAll { $0.id == event.id }
        save()
    }

    var runs: [DetectionRun] {
        var result: [DetectionRun] = []
        var current: [DetectedEvent] = []
        for event in events {
            if let head = current.first, head.label == event.label {
                current.append(event)
            } else {
                if !current.isEmpty { result.append(Self.makeRun(current)) }
                current = [event]
            }
        }
        if !current.isEmpty { result.append(Self.makeRun(current)) }
        return result
    }

    private static func makeRun(_ items: [DetectedEvent]) -> DetectionRun {
        DetectionRun(
            id: items.last?.id ?? UUID(),
            label: items.first?.label ?? "",
            category: items.first?.category ?? "attention",
            items: items
        )
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([DetectedEvent].self, from: data) else { return }
        events = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
