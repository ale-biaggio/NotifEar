//
//  DetectionHistoryStore.swift
//  NotifEar (iPhone companion)
//
//  Storico dei suoni rilevati dal Watch. Il Watch invia un evento per ogni
//  rilevamento (via WatchConnectivity `transferUserInfo`, consegna in background);
//  qui li accumuliamo, li persistiamo e li esponiamo raggruppati per giorno.
//

import Foundation
import Combine

/// Un suono rilevato dal Watch in un certo istante.
struct DetectedEvent: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var category: String   // "emergency" | "danger" | "home" | "attention" | custom
    var date: Date
}

/// Una "voce" dello storico: una sequenza CONSECUTIVA di rilevamenti dello stesso
/// suono. Una nuova voce nasce solo quando il suono rilevato cambia.
struct DetectionRun: Identifiable {
    let id: UUID
    let label: String
    let category: String
    let items: [DetectedEvent]   // dal più recente al più vecchio
    var count: Int { items.count }
    var start: Date { items.last?.date ?? .distantPast }  // più vecchio della run
    var end: Date { items.first?.date ?? .distantPast }   // più recente della run
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
        events.insert(event, at: 0) // più recente in cima
        if events.count > maxEvents { events = Array(events.prefix(maxEvents)) }
        save()
    }

    func clear() {
        events = []
        save()
    }

    /// Elimina una singola voce (run) dello storico.
    func deleteRun(_ run: DetectionRun) {
        let ids = Set(run.items.map { $0.id })
        events.removeAll { ids.contains($0.id) }
        save()
    }

    /// Elimina un singolo rilevamento (una sottovoce dentro una run).
    func deleteEvent(_ event: DetectedEvent) {
        events.removeAll { $0.id == event.id }
        save()
    }

    /// Lo storico raggruppato in run: una voce per ogni sequenza consecutiva dello
    /// stesso suono. Una nuova voce nasce solo quando il suono cambia.
    var runs: [DetectionRun] {
        var result: [DetectionRun] = []
        var current: [DetectedEvent] = []
        for event in events { // events è dal più recente al più vecchio
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
            id: items.last?.id ?? UUID(), // id dell'evento più vecchio: stabile mentre la run cresce
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
