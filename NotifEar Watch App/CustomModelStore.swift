//
//  CustomModelStore.swift
//  NotifEar Watch App
//
//  Conserva sul Watch il modello dei suoni personalizzati ricevuto dall'iPhone
//  e ne crea la `SNClassifySoundRequest` da affiancare a quella di sistema
//  (~300 suoni) SULLO STESSO `SNAudioStreamAnalyzer`: un solo tap audio, due
//  classificatori in parallelo.
//
//  Su watchOS NON si può compilare un modello: per questo riceviamo dall'iPhone
//  un `.mlmodelc` GIÀ compilato e qui lo carichiamo soltanto.
//

import Foundation
import CoreML
import SoundAnalysis
import CoreMedia

final class CustomModelStore {
    static let shared = CustomModelStore()

    private let fm = FileManager.default

    /// Cartella stabile dove vive il `.mlmodelc` installato.
    private var installedModelURL: URL {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("CustomSounds.mlmodelc", isDirectory: true)
    }

    var hasModel: Bool { fm.fileExists(atPath: installedModelURL.path) }

    /// Installa un `.mlmodelc` ricostruito, sovrascrivendo il precedente.
    func install(from compiledModelURL: URL) throws {
        if fm.fileExists(atPath: installedModelURL.path) {
            try fm.removeItem(at: installedModelURL)
        }
        try fm.copyItem(at: compiledModelURL, to: installedModelURL)
    }

    /// Crea la richiesta di classificazione per il modello custom, se installato.
    /// Va AGGIUNTA allo stesso analyzer della richiesta di sistema.
    func makeRequest() -> SNClassifySoundRequest? {
        guard hasModel else { return nil }
        do {
            let model = try MLModel(contentsOf: installedModelURL)
            let request = try SNClassifySoundRequest(mlModel: model)
            // CALIBRAZIONE 1 — finestra d'inferenza più lunga: il modello classifica su
            // ~1.5 s di audio invece che su frammenti brevi, producendo predizioni più
            // stabili e meno "nervose". Se la durata non è supportata dal modello, il
            // framework la arrotonda al valore valido più vicino.
            request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
            request.overlapFactor = 0.5
            return request
        } catch {
            print("⚠️ Modello custom non caricabile: \(error)")
            return nil
        }
    }
}
