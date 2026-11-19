import Foundation
import AVFoundation
import PlayLogic

/**
 * The demo's audio player: a thin AVAudioPlayer wrapper implementing PlayLogic's PlaybackEngine.
 * No navigation or resume logic here, that all lives in the PlayLogic library.
 *
 * AVAudioPlayer.currentTime reflects a seek immediately, which is what PlaybackEngine requires.
 */
final class DemoAudioEngine: NSObject, PlaybackEngine, AVAudioPlayerDelegate {
    var onTrackEnded: (@MainActor () -> Void)?
    private var player: AVAudioPlayer?

    var position: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }

    func load(_ track: PlayTrack, at position: TimeInterval, autoplay: Bool) {
        player?.delegate = nil
        player?.stop()

        let newPlayer = try? AVAudioPlayer(contentsOf: track.url)
        newPlayer?.delegate = self
        newPlayer?.prepareToPlay()
        newPlayer?.currentTime = position
        player = newPlayer
        if autoplay {
            newPlayer?.play()
        }
    }

    func seek(to position: TimeInterval) {
        player?.currentTime = position
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    // Called by AVAudioPlayer when a track plays to its end.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedID = ObjectIdentifier(player)
        Task { @MainActor in
            self.finished(finishedID)
        }
    }

    // Reports the end only for the track that is still the current one.
    private func finished(_ finishedID: ObjectIdentifier) {
        guard let player, ObjectIdentifier(player) == finishedID else { return }
        onTrackEnded?()
    }
}
