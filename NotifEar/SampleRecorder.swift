//
//  SampleRecorder.swift
//  NotifEar (iPhone companion)
//
//  Registra brevi campioni audio dal microfono dell'iPhone in PCM lineare a
//  16 kHz mono (WAV) — la stessa fascia a cui lavora l'estrattore di feature
//  di Apple (AudioFeaturePrint), così i campioni sono già nel formato giusto.
//
//  NOTA SUL DOMINIO MICROFONO: il riconoscimento finale avviene col microfono
//  del Watch. Registrare i campioni dall'iPhone introduce un piccolo mismatch.
//  In una fase successiva conviene poter registrare i campioni DAL Watch e
//  trasferirli qui per l'addestramento.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class SampleRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var permissionDenied = false

    private var recorder: AVAudioRecorder?

    func requestPermission() {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor [weak self] in
                self?.permissionDenied = !granted
            }
        }
    }

    func startRecording(to url: URL) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.record()
            recorder = r
            isRecording = true
        } catch {
            isRecording = false
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
