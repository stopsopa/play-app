//
//  AVPlayerEngine.swift
//  sanemp3
//

import Foundation
import AVFoundation
import Combine
import PlayLogic

// MARK: - PlaybackProgress

/**
 * Position and length of the current track, published on their own small object.
 * Only the scrubber observes it, so the 4-times-a-second progress update
 * does not redraw every list in the app (SUGGESTED_CHANGES.md D4).
 *
 * Usage:
 *   ScrubberView(progress: state.progress)
 */
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}

// MARK: - AVPlayerEngine

/**
 * The only place in the app that touches AVPlayer. Implements the `PlaybackEngine`
 * protocol of the PlayLogic library, so the library decides WHAT to play and this class
 * only does the playing.
 *
 * Nobody except PlayLogicController should call load / seek / play / pause on it.
 *
 * Usage:
 *   let engine = AVPlayerEngine()
 *   let logic = PlayLogicController(engine: engine, store: UserDefaultsResumeStore())
 *   engine.onTrackFailed = { track, reason in ... }   // file missing / unreadable
 *   engine.onStoppedBySystem = { logic.pause() }      // call, headphones unplugged
 *   engine.rate = 1.5                                 // applies from the next play()
 */
final class AVPlayerEngine: PlaybackEngine {
    let progress = PlaybackProgress()

    // Called by the engine, set by the library: the CURRENT track played to its end.
    var onTrackEnded: (@MainActor () -> Void)?
    // A new track was handed to the player (before it starts playing).
    var onTrackLoaded: (() -> Void)?
    // The current track turned out to be playable.
    var onTrackReady: (() -> Void)?
    // The current track cannot be played. Second argument is a human readable reason.
    var onTrackFailed: ((PlayTrack, String) -> Void)?
    // Playback stopped without us asking: interruption, route change, audio session refused.
    var onStoppedBySystem: (() -> Void)?
    // Anything the lock screen shows may have changed (play, pause, seek landed, new track).
    var onStateChanged: (() -> Void)?
    // Fires 4 times a second while a track is loaded.
    var onTick: (() -> Void)?
    // Length of a track known before the player has read the file (from the folder scan).
    var durationHint: ((PlayTrack) -> TimeInterval)?

    var rate: Float = 1.0

    // A direct seek never lands closer to the end than this, so the track still ends naturally.
    private static let endGuard: TimeInterval = 0.5

    private let player = AVPlayer()
    private var currentTrack: PlayTrack?
    // What the app asked for. Differs from the real player state when the system paused us.
    private var wantsToPlay = false
    // Target of a seek that AVPlayer has not finished yet.
    private var pendingSeek: TimeInterval?
    private var seekInFlight = false
    private var seekGeneration = 0
    private var failureReported = false
    private var itemObservers: [any NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var timeObserverToken: Any?

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        /**
         * Do not let AVPlayer pause itself at the end of a track. The library decides what
         * happens next, and a self-made pause would look like "the system paused us".
         */
        player.actionAtItemEnd = .none
        configureAudioSession()

        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            Task { @MainActor [weak self] in
                self?.tick(seconds)
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.timeControlChanged()
            }
        }
    }

    // MARK: - PlaybackEngine

    /**
     * While a seek is in flight this is the seek target, not the stale player time,
     * so several quick seeking presses add up (SUGGESTED_CHANGES.md A4).
     */
    var position: TimeInterval {
        if let pendingSeek {
            return pendingSeek
        }
        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? max(0, seconds) : progress.currentTime
    }

    var duration: TimeInterval { progress.duration }

    func load(_ track: PlayTrack, at position: TimeInterval, autoplay: Bool) {
        stopWatchingItem()
        currentTrack = track
        failureReported = false
        wantsToPlay = false
        seekGeneration += 1
        seekInFlight = false
        pendingSeek = nil

        let item = AVPlayerItem(url: track.url)
        watch(item)
        player.pause()
        player.replaceCurrentItem(with: item)

        progress.duration = durationHint?(track) ?? 0
        progress.currentTime = position
        if position > 0 {
            startSeek(to: position)
        }
        onTrackLoaded?()
        if autoplay {
            startPlaying()
        }
        onStateChanged?()
    }

    /**
     * Every seek is kept a little before the end of the track. Seeking to the exact end
     * does not reliably produce the end-of-track event (SUGGESTED_CHANGES.md A5).
     */
    func seek(to position: TimeInterval) {
        var target = max(0, position)
        if duration > 0 {
            target = min(target, max(0, duration - Self.endGuard))
        }
        startSeek(to: target)
    }

    func play() {
        // A track that failed earlier gets one fresh attempt instead of silence.
        if let track = currentTrack, player.currentItem?.status == .failed {
            load(track, at: progress.currentTime, autoplay: true)
            return
        }
        startPlaying()
        onStateChanged?()
    }

    func pause() {
        wantsToPlay = false
        player.pause()
        onStateChanged?()
    }

    // MARK: - Audio session

    // Runs once at app start (SUGGESTED_CHANGES.md D2). Errors are logged, not swallowed.
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("sanemp3: audio session setup failed: \(error)")
        }
    }

    // Starts playback only when the system lets us have the audio session (SUGGESTED_CHANGES.md A6).
    private func startPlaying() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("sanemp3: audio session refused: \(error)")
            wantsToPlay = false
            onStoppedBySystem?()
            return
        }
        wantsToPlay = true
        player.playImmediately(atRate: rate)
    }

    // MARK: - Seeking

    private func startSeek(to target: TimeInterval) {
        pendingSeek = target
        seekInFlight = true
        seekGeneration += 1
        let generation = seekGeneration
        progress.currentTime = target
        let time = CMTime(seconds: target, preferredTimescale: 44100)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                // A newer seek or a new track took over: this result is of no interest.
                guard let self, self.seekGeneration == generation else { return }
                self.seekInFlight = false
                if finished || self.player.currentItem?.status == .readyToPlay {
                    self.pendingSeek = nil
                }
                self.onStateChanged?()
            }
        }
    }

    // MARK: - Watching the player

    private func tick(_ seconds: TimeInterval) {
        // While a seek is in flight the player still reports the old time: ignore it.
        if pendingSeek == nil && seconds.isFinite && progress.currentTime != seconds {
            progress.currentTime = max(0, seconds)
        }
        if let item = player.currentItem {
            let length = CMTimeGetSeconds(item.duration)
            if length.isFinite && length > 0 && progress.duration != length {
                progress.duration = length
            }
        }
        onTick?()
    }

    /**
     * The player is paused although we asked it to play and the track is fine:
     * the system did it (phone call, headphones unplugged). Tell the host so its
     * play/pause state matches reality (SUGGESTED_CHANGES.md A6).
     */
    private func timeControlChanged() {
        guard wantsToPlay,
              player.timeControlStatus == .paused,
              player.currentItem?.status == .readyToPlay
        else { return }
        wantsToPlay = false
        onStoppedBySystem?()
    }

    private func isCurrent(_ id: ObjectIdentifier) -> Bool {
        guard let item = player.currentItem else { return false }
        return ObjectIdentifier(item) == id
    }

    /**
     * Watches ONE player item: ready, failed, played to end, stalled.
     * Every event is checked against the item that is current when it is handled,
     * so a track that was already replaced can never report anything
     * (SUGGESTED_CHANGES.md A1 and A3).
     */
    private func watch(_ item: AVPlayerItem) {
        let id = ObjectIdentifier(item)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription ?? "the file cannot be opened"
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(id) else { return }
                if status == .failed {
                    self.reportFailure(message)
                } else if status == .readyToPlay {
                    self.itemBecameReady()
                }
            }
        }
        observe(.AVPlayerItemDidPlayToEndTime, of: item) { engine in
            engine.onTrackEnded?()
        }
        observe(.AVPlayerItemFailedToPlayToEndTime, of: item) { engine in
            engine.reportFailure(engine.player.currentItem?.error?.localizedDescription ?? "playback broke before the end")
        }
        observe(.AVPlayerItemPlaybackStalled, of: item) { engine in
            // A stall is not a failure: keep going if we are supposed to play.
            if engine.wantsToPlay {
                engine.player.playImmediately(atRate: engine.rate)
            }
        }
    }

    private func observe(
        _ name: Notification.Name,
        of item: AVPlayerItem,
        _ action: @escaping @MainActor (AVPlayerEngine) -> Void
    ) {
        let id = ObjectIdentifier(item)
        let token = NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(id) else { return }
                action(self)
            }
        }
        itemObservers.append(token)
    }

    private func stopWatchingItem() {
        statusObservation?.invalidate()
        statusObservation = nil
        for token in itemObservers {
            NotificationCenter.default.removeObserver(token)
        }
        itemObservers = []
    }

    private func itemBecameReady() {
        // A start position requested before the file was readable may have been dropped: ask again.
        if let target = pendingSeek, !seekInFlight {
            startSeek(to: target)
        }
        onTrackReady?()
    }

    // Reports a broken track once, however many signals arrive for it.
    private func reportFailure(_ message: String) {
        guard !failureReported, let track = currentTrack else { return }
        failureReported = true
        onTrackFailed?(track, message)
    }
}
