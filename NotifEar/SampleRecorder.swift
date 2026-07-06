
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
        if isRecording { stopRecording() }
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
            guard r.record() else { throw RecorderError.couldNotStart }
            recorder = r
            isRecording = true
        } catch {
            recorder = nil
            isRecording = false
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

private enum RecorderError: Error {
    case couldNotStart
}
