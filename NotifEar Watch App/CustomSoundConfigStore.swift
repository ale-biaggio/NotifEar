
import Foundation
import Combine

final class CustomSoundConfigStore: ObservableObject {
    static let shared = CustomSoundConfigStore()

    struct Entry: Codable, Equatable {
        var enabled: Bool
        var category: String
    }

    @Published private(set) var entries: [String: Entry] = [:]

    private let fm = FileManager.default
    private var url: URL {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("custom_config.json")
    }

    init() { load() }

    func isEnabled(_ label: String) -> Bool { entries[label]?.enabled ?? true }

    func category(for label: String) -> String { entries[label]?.category ?? "attention" }

    func update(from raw: [String: Any]) {
        var newEntries: [String: Entry] = [:]
        for (label, value) in raw {
            guard let dict = value as? [String: Any] else { continue }
            let enabled = (dict["enabled"] as? Bool) ?? ((dict["enabled"] as? NSNumber)?.boolValue ?? true)
            let category = (dict["category"] as? String) ?? "attention"
            newEntries[label] = Entry(enabled: enabled, category: category)
        }
        DispatchQueue.main.async {
            self.entries = newEntries
            self.save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
