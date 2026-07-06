
import Foundation
import AVFoundation
import Combine

@MainActor
final class SamplePlayer: NSObject, ObservableObject {
    @Published var playingURL: URL?

    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playingURL == url { stop() } else { play(url) }
    }

    func play(_ url: URL) {
        do {
            stop()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            playingURL = url
        } catch {
            deactivateSession()
            playingURL = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
        deactivateSession()
    }

    private func finishPlayback() {
        player = nil
        playingURL = nil
        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

extension SamplePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finishPlayback() }
    }
}
