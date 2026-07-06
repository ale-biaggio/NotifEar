
import Foundation
import CoreML
import SoundAnalysis
import CoreMedia

final class CustomModelStore {
    static let shared = CustomModelStore()

    private let fm = FileManager.default

    private var installedModelURL: URL {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("CustomSounds.mlmodelc", isDirectory: true)
    }

    var hasModel: Bool { fm.fileExists(atPath: installedModelURL.path) }

    func install(from compiledModelURL: URL) throws {
        if fm.fileExists(atPath: installedModelURL.path) {
            try fm.removeItem(at: installedModelURL)
        }
        try fm.copyItem(at: compiledModelURL, to: installedModelURL)
    }

    func makeRequest() -> SNClassifySoundRequest? {
        guard hasModel else { return nil }
        do {
            let model = try MLModel(contentsOf: installedModelURL)
            let request = try SNClassifySoundRequest(mlModel: model)
            request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
            request.overlapFactor = 0.5
            return request
        } catch {
            print("⚠️ Modello custom non caricabile: \(error)")
            return nil
        }
    }
}
