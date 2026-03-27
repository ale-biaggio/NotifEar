import SoundAnalysis

if #available(macOS 12.0, *) {
    do {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let labels = request.knownClassifications
        let sirenLabels = labels.filter { $0.lowercased().contains("siren") || $0.lowercased().contains("ambulance") }
        print("Trovate etichette: \(sirenLabels)")
    } catch {
        print("Errore: \(error)")
    }
}
