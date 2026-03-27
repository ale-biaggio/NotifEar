import SoundAnalysis

if #available(macOS 12.0, *) {
    do {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let labels = request.knownClassifications.sorted()
        for label in labels {
            print(label)
        }
    } catch {
        print("Errore: \(error)")
    }
}
