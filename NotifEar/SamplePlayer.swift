//
//  SamplePlayer.swift
//  NotifEar (iPhone companion)
//
//  Riproduce i file WAV dei campioni registrati, per riascoltarli prima di
//  addestrare. Usa i file già su disco: nessun dato aggiuntivo da salvare.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class SamplePlayer: NSObject, ObservableObject {
    /// URL del campione attualmente in riproduzione (nil se fermo).
    @Published var playingURL: URL?

    private var player: AVAudioPlayer?

    /// Avvia il campione, o lo ferma se è già quello in riproduzione.
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
