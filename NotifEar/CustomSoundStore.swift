//
//  CustomSoundStore.swift
//  NotifEar (iPhone companion)
//
//  Modello + persistenza dei suoni personalizzati che l'utente vuole insegnare.
//  Ogni suono ha un'etichetta, una categoria (che mappa alle SoundCategory del
//  Watch) e una lista di file audio campione registrati dal microfono.
//

import Foundation
import Combine

/// Un suono personalizzato definito dall'utente.
struct CustomSound: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var label: String                  // es. "Citofono di casa"
    var category: String               // "emergency" | "danger" | "home" | "attention"
    var sampleFileNames: [String] = [] // file .wav nella cartella campioni
    /// Se false, il Watch riconosce comunque il suono ma NON avvisa. Utile per la
    /// classe "rumore di fondo": serve ad addestrare, ma non deve generare allarmi.
    var isEnabled: Bool = true

    enum CodingKeys: String, CodingKey { case id, label, category, sampleFileNames, isEnabled }

    init(id: UUID = UUID(), label: String, category: String,
         sampleFileNames: [String] = [], isEnabled: Bool = true) {
        self.id = id
        self.label = label
        self.category = category
        self.sampleFileNames = sampleFileNames
        self.isEnabled = isEnabled
    }

    // Decodifica tollerante: i cataloghi salvati prima dell'aggiunta di `isEnabled`
    // restano validi (default = true).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decode(String.self, forKey: .label)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "attention"
        sampleFileNames = try c.decodeIfPresent([String].self, forKey: .sampleFileNames) ?? []
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

@MainActor
final class CustomSoundStore: ObservableObject {
    @Published private(set) var sounds: [CustomSound] = []

    private let fm = FileManager.default

    init() { load() }

    // MARK: - Percorsi

    private var documents: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var catalogURL: URL { documents.appendingPathComponent("custom_sounds.json") }

    /// Cartella che contiene tutti i file audio campione.
    var samplesDirectory: URL {
        let url = documents.appendingPathComponent("samples", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - CRUD

    var canTrain: Bool {
        trainingReadinessMessage == nil
    }

    var trainingStatusText: String {
        trainingReadinessMessage ?? "Pronto per addestrare: almeno 2 campioni per ciascun suono."
    }

    func addSound(label: String, category: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !containsLabel(trimmed) else { return false }
        sounds.append(CustomSound(label: trimmed, category: category))
        save()
        return true
    }

    func containsLabel(_ label: String) -> Bool {
        let normalized = Self.normalizedLabel(label)
        guard !normalized.isEmpty else { return false }
        return sounds.contains { Self.normalizedLabel($0.label) == normalized }
    }

    func deleteSound(_ sound: CustomSound) {
        for name in sound.sampleFileNames {
            try? fm.removeItem(at: samplesDirectory.appendingPathComponent(name))
        }
        sounds.removeAll { $0.id == sound.id }
        save()
    }

    func registerSample(fileName: String, for soundID: UUID) {
        guard let idx = sounds.firstIndex(where: { $0.id == soundID }) else { return }
        sounds[idx].sampleFileNames.append(fileName)
        save()
    }

    /// Attiva/disattiva l'avviso per un suono (resta nel modello, ma non allarma).
    func setEnabled(_ sound: CustomSound, _ enabled: Bool) {
        guard let idx = sounds.firstIndex(where: { $0.id == sound.id }) else { return }
        sounds[idx].isEnabled = enabled
        save()
    }

    /// Configurazione da inviare al Watch: per ogni etichetta, se avvisare e con quale categoria.
    func configPayload() -> [String: [String: Any]] {
        var dict: [String: [String: Any]] = [:]
        for s in sounds {
            dict[s.label] = ["enabled": s.isEnabled, "category": s.category]
        }
        return dict
    }

    /// URL per un nuovo file campione del suono indicato.
    func newSampleURL(for sound: CustomSound) -> URL {
        let name = "\(sound.id.uuidString)_\(UUID().uuidString).wav"
        return samplesDirectory.appendingPathComponent(name)
    }

    /// URL su disco di un campione dato il suo nome file.
    func sampleURL(named name: String) -> URL {
        samplesDirectory.appendingPathComponent(name)
    }

    /// Versione aggiornata di un suono (lo store è la fonte di verità).
    func sound(for id: UUID) -> CustomSound? { sounds.first { $0.id == id } }

    /// Elimina un singolo campione: il file su disco e il suo riferimento.
    func deleteSample(named name: String, from soundID: UUID) {
        guard let idx = sounds.firstIndex(where: { $0.id == soundID }) else { return }
        try? fm.removeItem(at: samplesDirectory.appendingPathComponent(name))
        sounds[idx].sampleFileNames.removeAll { $0 == name }
        save()
    }

    /// Tutte le coppie (file audio, etichetta), pronte per l'addestramento.
    func trainingPairs() -> [(url: URL, label: String)] {
        sounds.flatMap { sound in
            sound.sampleFileNames.compactMap { name in
                let url = samplesDirectory.appendingPathComponent(name)
                guard fm.fileExists(atPath: url.path) else { return nil }
                return (url, sound.label)
            }
        }
    }

    private var trainingReadinessMessage: String? {
        guard sounds.count >= 2 else {
            return "Servono almeno 2 categorie di suono. Aggiungi anche un rumore di fondo per ridurre i falsi allarmi."
        }

        let normalizedLabels = sounds.map { Self.normalizedLabel($0.label) }
        guard Set(normalizedLabels).count == normalizedLabels.count else {
            return "Ci sono suoni con lo stesso nome. Elimina il duplicato prima di addestrare."
        }

        let missingSamples = sounds.filter { sound in
            validSampleCount(for: sound) < 2
        }
        guard missingSamples.isEmpty else {
            let label = missingSamples.first?.label ?? "un suono"
            return "Registra almeno 2 campioni per ogni suono. Mancano campioni per \"\(label)\"."
        }

        return nil
    }

    private func validSampleCount(for sound: CustomSound) -> Int {
        sound.sampleFileNames.filter { name in
            fm.fileExists(atPath: samplesDirectory.appendingPathComponent(name).path)
        }.count
    }

    private static func normalizedLabel(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    // MARK: - Persistenza

    private func load() {
        guard let data = try? Data(contentsOf: catalogURL),
              let decoded = try? JSONDecoder().decode([CustomSound].self, from: data) else { return }
        sounds = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sounds) else { return }
        try? data.write(to: catalogURL, options: .atomic)
    }
}
