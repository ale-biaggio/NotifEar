//
//  RecordSampleView.swift
//  NotifEar (iPhone companion)
//
//  Schermata di un suono: registrazione di nuovi campioni + elenco dei campioni già
//  registrati, con riascolto ed eliminazione. Usa solo i dati già presenti
//  (nomi file in `sampleFileNames` + i WAV su disco): nessun dato aggiuntivo salvato.
//

import SwiftUI
import AVFoundation

struct RecordSampleView: View {
    let sound: CustomSound
    @ObservedObject var recorder: SampleRecorder
    @EnvironmentObject var store: CustomSoundStore
    @StateObject private var player = SamplePlayer()

    @State private var currentURL: URL?

    // Lo store è la fonte di verità: leggo sempre la versione aggiornata del suono.
    private var currentSound: CustomSound { store.sound(for: sound.id) ?? sound }
    private var samples: [String] { currentSound.sampleFileNames }

    var body: some View {
        List {
            // MARK: Registrazione
            Section {
                VStack(spacing: 16) {
                    Text("\(samples.count) campioni registrati")
                        .foregroundStyle(.secondary)

                    Button {
                        if recorder.isRecording { stop() } else { start() }
                    } label: {
                        Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                            .resizable()
                            .frame(width: 72, height: 72)
                            .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                    }
                    .buttonStyle(.plain)

                    if recorder.permissionDenied {
                        Text("Permesso microfono negato. Abilitalo in Impostazioni.")
                            .font(.caption).foregroundStyle(.red)
                    }

                    Text("Registra più campioni dello stesso suono, da distanze e volumi diversi. Più esempi vari = riconoscimento migliore.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // MARK: Campioni registrati (riascolto / elimina)
            if !samples.isEmpty {
                Section("Campioni registrati") {
                    ForEach(Array(samples.enumerated()), id: \.element) { index, name in
                        let url = store.sampleURL(named: name)
                        HStack(spacing: 12) {
                            Button {
                                player.toggle(url)
                            } label: {
                                Image(systemName: player.playingURL == url ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Campione \(index + 1)")
                                Text(detailText(url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if player.playingURL == url { player.stop() }
                                store.deleteSample(named: name, from: sound.id)
                            } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(sound.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { recorder.requestPermission() }
        .onDisappear { cleanupOnDisappear() }
    }

    private static let itLocale = Locale(identifier: "it_IT")

    /// Durata di un campione, letta dal file audio (nessun dato aggiuntivo salvato).
    private func sampleDuration(_ url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sr = file.processingFormat.sampleRate
        guard sr > 0 else { return nil }
        return Double(file.length) / sr
    }

    /// Riga di dettaglio del campione: "10,2 s · 12 nov 14:30".
    private func detailText(_ url: URL) -> String {
        var parts: [String] = []
        if let dur = sampleDuration(url) {
            let n = dur.formatted(.number.precision(.fractionLength(1)).locale(Self.itLocale))
            parts.append("\(n) s")
        }
        if let date = fileDate(url) {
            let style = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Self.itLocale)
            parts.append(date.formatted(style))
        }
        return parts.joined(separator: " · ")
    }

    private func fileDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
    }

    private func start() {
        let url = store.newSampleURL(for: sound)
        currentURL = url
        recorder.startRecording(to: url)
    }

    private func stop() {
        recorder.stopRecording()
        if let url = currentURL {
            store.registerSample(fileName: url.lastPathComponent, for: sound.id)
        }
        currentURL = nil
    }

    private func cleanupOnDisappear() {
        player.stop()
        guard recorder.isRecording else { return }
        stop()
    }
}
