//
//  CustomSoundTrainer.swift
//  NotifEar (iPhone companion)
//
//  Addestra ON-DEVICE sull'iPhone (NESSUN Mac richiesto) un classificatore di
//  suoni personalizzati con Create ML Components (iOS 16+) e lo esporta come
//  modello Core ML compilato (.mlmodelc), pronto per essere spedito al Watch.
//
//  Pipeline:
//    AudioReader  ->  AudioFeaturePrint  ->  FullyConnectedNetworkClassifier
//
//  IMPORTANTE: il framework "CreateML" di alto livello (MLSoundClassifier) NON
//  esiste su iOS — solo su macOS. Su iPhone si usa "CreateMLComponents", che è
//  esattamente ciò che facciamo qui.
//
//  CONSIGLIO QUALITÀ: per evitare falsi positivi, aggiungere sempre una classe
//  "rumore di fondo" con campioni di ambiente generico: senza una classe
//  negativa il classificatore sceglie comunque sempre una delle etichette note.
//

import Foundation
import CoreML
import CreateMLComponents

@available(iOS 16.0, *)
enum CustomSoundTrainer {

    enum TrainingError: LocalizedError {
        case notEnoughData
        var errorDescription: String? {
            "Servono almeno 2 categorie di suono e qualche campione per ciascuna."
        }
    }

    /// Addestra e compila il modello.
    /// - Parameters:
    ///   - pairs: coppie (file audio, etichetta).
    ///   - workDirectory: cartella di lavoro per i file intermedi e l'output.
    /// - Returns: URL della directory `.mlmodelc` compilata, pronta per il transfer.
    static func train(pairs: [(url: URL, label: String)],
                      workDirectory: URL) async throws -> URL {

        let labels = Set(pairs.map { $0.label })
        guard labels.count >= 2, pairs.count >= labels.count * 2 else {
            throw TrainingError.notEnoughData
        }

        // 1. Dati etichettati -> sequenze temporali di buffer audio.
        let annotatedFiles = pairs.map { AnnotatedFeature(feature: $0.url, annotation: $0.label) }
        let trainingData = try AudioReader.read(annotatedFiles)

        // 2. Estrattore di feature di Apple + classificatore addestrabile on-device.
        let estimator = AudioFeaturePrint(windowDuration: 0.975, overlapFactor: 0.5)
            .appending(FullyConnectedNetworkClassifier<Float, String>(labels: labels))

        // 3. Addestramento (asincrono, on-device).
        let model = try await estimator.fitted(to: trainingData)

        // 4. Esporta in .mlmodel, poi compila in .mlmodelc.
        //    La compilazione NON è disponibile su watchOS: va fatta QUI sull'iPhone.
        let fm = FileManager.default
        try? fm.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let mlmodelURL = workDirectory.appendingPathComponent("CustomSounds.mlmodel")
        try model.export(to: mlmodelURL)

        let tempCompiled = try await MLModel.compileModel(at: mlmodelURL)
        let compiledURL = workDirectory.appendingPathComponent("CustomSounds.mlmodelc")
        if fm.fileExists(atPath: compiledURL.path) { try fm.removeItem(at: compiledURL) }
        try fm.copyItem(at: tempCompiled, to: compiledURL)
        return compiledURL
    }
}
