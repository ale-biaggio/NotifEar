
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

    static func train(pairs: [(url: URL, label: String)],
                      workDirectory: URL) async throws -> URL {

        let labels = Set(pairs.map { $0.label })
        guard labels.count >= 2, pairs.count >= labels.count * 2 else {
            throw TrainingError.notEnoughData
        }

        let annotatedFiles = pairs.map { AnnotatedFeature(feature: $0.url, annotation: $0.label) }
        let trainingData = try AudioReader.read(annotatedFiles)

        let estimator = AudioFeaturePrint(windowDuration: 0.975, overlapFactor: 0.5)
            .appending(FullyConnectedNetworkClassifier<Float, String>(labels: labels))

        let model = try await estimator.fitted(to: trainingData)

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
