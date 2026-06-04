//
//  PhoneCustomModelStore.swift
//  NotifEar (iPhone companion)
//
//  Gemello iOS di `CustomModelStore` (lato Watch): conserva sull'iPhone una copia
//  STABILE del modello dei suoni personalizzati — lo stesso `.mlmodelc` che l'app
//  addestra/compila e spedisce al Watch — così la modalità Sonar dell'iPhone può
//  riconoscere i suoni custom con lo STESSO modello del Watch.
//
//  Oggi il compilato finisce in una cartella temporanea e, dopo l'invio, viene
//  buttato; qui ne salviamo una copia in Application Support al momento del training
//  (vedi PhoneRootView.trainAndSend).
//

import Foundation
import CoreML
import SoundAnalysis
import CoreMedia

final class PhoneCustomModelStore {
    static let shared = PhoneCustomModelStore()

    private let fm = FileManager.default

    /// Cartella stabile dove vive il `.mlmodelc` installato localmente sull'iPhone.
    private var installedModelURL: URL {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("CustomSounds.mlmodelc", isDirectory: true)
    }

    var hasModel: Bool { fm.fileExists(atPath: installedModelURL.path) }

    /// Installa un `.mlmodelc` compilato, sovrascrivendo il precedente. Chiamato dopo
    /// l'addestramento, con lo stesso compilato che si spedisce al Watch.
    func install(from compiledModelURL: URL) throws {
        if fm.fileExists(atPath: installedModelURL.path) {
            try fm.removeItem(at: installedModelURL)
        }
        try fm.copyItem(at: compiledModelURL, to: installedModelURL)
    }

    /// Crea la richiesta di classificazione per il modello custom, se installato.
    /// Va AGGIUNTA allo stesso analyzer della richiesta di sistema (stessa calibrazione
    /// del Watch: finestra ~1.5 s, overlap 0.5, per predizioni stabili).
    func makeRequest() -> SNClassifySoundRequest? {
        guard hasModel else { return nil }
        do {
            let model = try MLModel(contentsOf: installedModelURL)
            let request = try SNClassifySoundRequest(mlModel: model)
            request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
            request.overlapFactor = 0.5
            return request
        } catch {
            print("⚠️ [iPhone] Modello custom non caricabile: \(error)")
            return nil
        }
    }
}
