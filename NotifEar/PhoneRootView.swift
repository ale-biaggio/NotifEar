
import SwiftUI

enum SoundCategory: String, CaseIterable, Identifiable {
    case attention, home, danger, emergency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: return "Suono generico"
        case .home:      return "Suono domestico"
        case .danger:    return "Suono urgente"
        case .emergency: return "Emergenza"
        }
    }

    var color: Color {
        switch self {
        case .attention: return .green
        case .home:      return .yellow
        case .danger:    return .orange
        case .emergency: return .red
        }
    }

    static func title(for raw: String) -> String { SoundCategory(rawValue: raw)?.title ?? raw.capitalized }
    static func color(for raw: String) -> Color { SoundCategory(rawValue: raw)?.color ?? .gray }
}

struct PhoneRootView: View {
    @EnvironmentObject var store: CustomSoundStore
    @EnvironmentObject var connectivity: PhoneConnectivityManager
    @StateObject private var recorder = SampleRecorder()

    @State private var showAddSheet = false
    @State private var trainingState: TrainingState = .idle

    enum TrainingState: Equatable {
        case idle, training, done(String), failed(String)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.sounds.isEmpty {
                        Text("Nessun suono. Tocca + per aggiungerne uno e registrare qualche campione.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.sounds) { sound in
                        HStack {
                            NavigationLink(value: sound) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sound.label).font(.headline)
                                    HStack(spacing: 4) {
                                        Text("\(sound.sampleFileNames.count) campioni · \(SoundCategory.title(for: sound.category))")
                                        Circle()
                                            .fill(SoundCategory.color(for: sound.category))
                                            .frame(width: 8, height: 8)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            Toggle("Avvisa", isOn: Binding(
                                get: { sound.isEnabled },
                                set: { newValue in
                                    store.setEnabled(sound, newValue)
                                    connectivity.sendConfig(store.configPayload())
                                }
                            ))
                            .labelsHidden()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.deleteSound(sound)
                                connectivity.sendConfig(store.configPayload())
                            } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Suoni personalizzati")
                } footer: {
                    Text("L'interruttore decide se quel suono ti avvisa sul Watch. Tieni SPENTO il \"rumore di fondo\": serve solo ad addestrare, non deve allarmarti. Le modifiche arrivano al Watch subito, senza riaddestrare.")
                }

                Section("Watch") {
                    LabeledContent("Abbinato", value: connectivity.isPaired ? "Sì" : "No")
                    LabeledContent("App installata", value: connectivity.isWatchAppInstalled ? "Sì" : "No")
                    LabeledContent("Raggiungibile", value: connectivity.isReachable ? "Sì" : "No")
                    LabeledContent("Ultimo invio", value: connectivity.lastTransferState)
                }

                Section {
                    Button {
                        Task { await trainAndSend() }
                    } label: {
                        HStack {
                            Text("Addestra e invia al Watch")
                            Spacer()
                            if trainingState == .training { ProgressView() }
                        }
                    }
                    .disabled(trainingState == .training || !store.canTrain)

                    switch trainingState {
                    case .done(let msg):   Text(msg).font(.caption).foregroundStyle(.green)
                    case .failed(let msg): Text(msg).font(.caption).foregroundStyle(.red)
                    default:               EmptyView()
                    }
                } footer: {
                    Text(store.trainingStatusText)
                }
            }
            .navigationTitle("NotifEar")
            .navigationDestination(for: CustomSound.self) { sound in
                RecordSampleView(sound: sound, recorder: recorder)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddSoundView().environmentObject(store)
            }
            .onAppear { recorder.requestPermission() }
        }
    }

    private func trainAndSend() async {
        trainingState = .training
        guard store.canTrain else {
            trainingState = .failed(store.trainingStatusText)
            return
        }
        guard #available(iOS 16.0, *) else {
            trainingState = .failed("Richiede iOS 16 o successivo."); return
        }
        let pairs = store.trainingPairs()
        do {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("training", isDirectory: true)
            let compiled = try await CustomSoundTrainer.train(pairs: pairs, workDirectory: work)
            try? PhoneCustomModelStore.shared.install(from: compiled)
            connectivity.sendModel(compiledModelURL: compiled, config: store.configPayload())
            trainingState = .done("Modello addestrato e messo in invio al Watch.")
        } catch {
            trainingState = .failed("Addestramento fallito: \(error.localizedDescription)")
        }
    }
}

struct AddSoundView: View {
    @EnvironmentObject var store: CustomSoundStore
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var category = SoundCategory.attention.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome del suono (es. Citofono)", text: $label)
                } footer: {
                    if store.containsLabel(trimmedLabel) {
                        Text("Esiste già un suono con questo nome.")
                            .foregroundStyle(.red)
                    }
                }

                Picker("Categoria", selection: $category) {
                    ForEach(SoundCategory.allCases) { cat in
                        HStack {
                            Circle().fill(cat.color).frame(width: 10, height: 10)
                            Text(cat.title)
                        }
                        .tag(cat.rawValue)
                    }
                }
            }
            .navigationTitle("Nuovo suono")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let trimmed = trimmedLabel
                        guard !trimmed.isEmpty else { return }
                        if store.addSound(label: trimmed, category: category) {
                            dismiss()
                        }
                    }
                    .disabled(trimmedLabel.isEmpty || store.containsLabel(trimmedLabel))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
