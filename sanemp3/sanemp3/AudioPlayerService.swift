//
//  AudioPlayerService.swift
//  sanemp3
//

import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI
import Combine
import UIKit

public enum RepeatMode: String, CaseIterable, Identifiable, Codable {
    case off = "Off"
    case all = "Repeat All"
    case one = "Repeat One"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

public struct SavedPlaybackState: Codable {
    public var track: AudioTrack
    public var queue: [AudioTrack]
    public var currentIndex: Int
    public var currentTime: TimeInterval
    public var duration: TimeInterval
    public var isShuffle: Bool
    public var repeatMode: RepeatMode
}

@MainActor
public final class AudioPlayerService: ObservableObject {
    public static let shared = AudioPlayerService()
    
    // Playback state
    @Published public var currentTrack: AudioTrack?
    @Published public var queue: [AudioTrack] = []
    @Published public var currentIndex: Int = 0
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var currentArtwork: UIImage?
    @Published public var repeatMode: RepeatMode = .all
    @Published public var isShuffle: Bool = false
    @Published public var playbackRate: Float = 1.0
    
    // Screen awake setting (Defaults to true: prevent screen locking while app is running)
    @Published public var preventScreenLock: Bool = true {
        didSet {
            UserDefaults.standard.set(preventScreenLock, forKey: "sanemp3_prevent_screen_lock")
            applyScreenLockSetting()
        }
    }
    
    // Car physical button remote behavior mode
    // When enabled: Car Next/Prev single click will skip 3s, long press / seek triggers Next/Prev song
    @Published public var carRemoteQuickPressSkips3s: Bool = false {
        didSet {
            UserDefaults.standard.set(carRemoteQuickPressSkips3s, forKey: "sanemp3_car_remote_mode")
            setupRemoteCommands()
        }
    }
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var originalQueue: [AudioTrack] = []
    private var lastSavedTime: TimeInterval = 0
    private let playbackStateKey = "sanemp3_saved_playback_state"
    
    public init() {
        if UserDefaults.standard.object(forKey: "sanemp3_prevent_screen_lock") != nil {
            self.preventScreenLock = UserDefaults.standard.bool(forKey: "sanemp3_prevent_screen_lock")
        } else {
            self.preventScreenLock = true
        }
        self.carRemoteQuickPressSkips3s = UserDefaults.standard.bool(forKey: "sanemp3_car_remote_mode")
        
        applyScreenLockSetting()
        configureAudioSession()
        setupRemoteCommands()
        setupNotificationObservers()
        restorePlaybackState()
    }
    
    deinit {
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Screen Lock Prevention
    
    public func applyScreenLockSetting() {
        UIApplication.shared.isIdleTimerDisabled = preventScreenLock
    }
    
    // MARK: - Audio Session
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }
    
    // MARK: - Playback Controls
    
    public func playQueue(_ newQueue: [AudioTrack], startingAt index: Int = 0) {
        guard !newQueue.isEmpty, newQueue.indices.contains(index) else { return }
        
        self.originalQueue = newQueue
        if isShuffle {
            var shuffled = newQueue
            let startTrack = shuffled.remove(at: index)
            shuffled.shuffle()
            shuffled.insert(startTrack, at: 0)
            self.queue = shuffled
            self.currentIndex = 0
        } else {
            self.queue = newQueue
            self.currentIndex = index
        }
        
        loadAndPlay(track: queue[currentIndex], autoPlay: true)
    }
    
    public func playTrack(_ track: AudioTrack, from queue: [AudioTrack]) {
        if let index = queue.firstIndex(of: track) {
            playQueue(queue, startingAt: index)
        } else {
            playQueue([track], startingAt: 0)
        }
    }
    
    private func loadAndPlay(track: AudioTrack, startAt time: TimeInterval = 0, autoPlay: Bool = true) {
        self.currentTrack = track
        self.duration = track.duration
        self.currentTime = time
        self.currentArtwork = nil
        
        // Remove previous time observer
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        let playerItem = AVPlayerItem(url: track.url)
        
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        if time > 0 {
            let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        
        setupTimeObserver()
        
        if autoPlay {
            configureAudioSession()
            player?.rate = playbackRate
            player?.play()
            self.isPlaying = true
        } else {
            self.isPlaying = false
        }
        
        updateNowPlayingInfo()
        savePlaybackState()
        
        // Load artwork asynchronously
        Task {
            if let artwork = await track.loadArtwork() {
                self.currentArtwork = artwork
                self.updateNowPlayingInfo()
            }
        }
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func play() {
        guard let p = player else {
            if let track = currentTrack {
                loadAndPlay(track: track, startAt: currentTime, autoPlay: true)
            } else if !queue.isEmpty {
                loadAndPlay(track: queue[currentIndex], autoPlay: true)
            }
            return
        }
        configureAudioSession()
        p.rate = playbackRate
        p.play()
        self.isPlaying = true
        updateNowPlayingInfo()
        savePlaybackState()
    }
    
    public func pause() {
        player?.pause()
        self.isPlaying = false
        updateNowPlayingInfo()
        savePlaybackState()
    }
    
    public func stop() {
        player?.pause()
        player?.seek(to: .zero)
        self.isPlaying = false
        self.currentTime = 0
        updateNowPlayingInfo()
        savePlaybackState()
    }
    
    public func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, duration))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = clampedTime
            self.updateNowPlayingInfo()
            self.savePlaybackState()
        }
    }
    
    public func skipForward(seconds: TimeInterval = 3.0) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }
    
    public func skipBackward(seconds: TimeInterval = 3.0) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }
    
    /// Previous song logic:
    /// "Where pressing 'previous song' button when song playing is more then 5 first seconds should just restart song. Otherwise it should move to previous song."
    public func previousTrack() {
        if currentTime > 5.0 {
            seek(to: 0)
            return
        }
        
        guard !queue.isEmpty else { return }
        
        if currentIndex > 0 {
            currentIndex -= 1
            loadAndPlay(track: queue[currentIndex], autoPlay: true)
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
            loadAndPlay(track: queue[currentIndex], autoPlay: true)
        } else {
            seek(to: 0)
        }
    }
    
    public func nextTrack() {
        guard !queue.isEmpty else { return }
        
        if currentIndex < queue.count - 1 {
            currentIndex += 1
            loadAndPlay(track: queue[currentIndex], autoPlay: true)
        } else if repeatMode == .all {
            currentIndex = 0
            loadAndPlay(track: queue[currentIndex], autoPlay: true)
        } else {
            stop()
        }
    }
    
    public func toggleShuffle() {
        isShuffle.toggle()
        guard let current = currentTrack else { return }
        
        if isShuffle {
            var shuffled = originalQueue
            shuffled.removeAll { $0.id == current.id }
            shuffled.shuffle()
            shuffled.insert(current, at: 0)
            self.queue = shuffled
            self.currentIndex = 0
        } else {
            self.queue = originalQueue
            if let idx = originalQueue.firstIndex(where: { $0.id == current.id }) {
                self.currentIndex = idx
            }
        }
        savePlaybackState()
    }
    
    public func toggleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        savePlaybackState()
    }
    
    // MARK: - State Persistence (Remember where user left off)
    
    public func savePlaybackState() {
        guard let track = currentTrack else { return }
        
        let state = SavedPlaybackState(
            track: track,
            queue: queue.isEmpty ? [track] : queue,
            currentIndex: currentIndex,
            currentTime: currentTime,
            duration: duration > 0 ? duration : track.duration,
            isShuffle: isShuffle,
            repeatMode: repeatMode
        )
        
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: playbackStateKey)
        }
    }
    
    public func restorePlaybackState() {
        guard let data = UserDefaults.standard.data(forKey: playbackStateKey),
              let state = try? JSONDecoder().decode(SavedPlaybackState.self, from: data) else {
            return
        }
        
        self.currentTrack = state.track
        self.queue = state.queue
        self.originalQueue = state.queue
        self.currentIndex = state.currentIndex
        self.currentTime = state.currentTime
        self.duration = state.duration
        self.isShuffle = state.isShuffle
        self.repeatMode = state.repeatMode
        
        // Prepare player ready at restored timestamp
        loadAndPlay(track: state.track, startAt: state.currentTime, autoPlay: false)
    }
    
    // MARK: - Time Observer & Notifications
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let secs = CMTimeGetSeconds(time)
            if !secs.isNaN && !secs.isInfinite {
                self.currentTime = secs
                
                // Save playback position periodically every 3 seconds
                if abs(secs - self.lastSavedTime) >= 3.0 {
                    self.lastSavedTime = secs
                    self.savePlaybackState()
                }
            }
            if let item = self.player?.currentItem {
                let itemDur = CMTimeGetSeconds(item.duration)
                if !itemDur.isNaN && !itemDur.isInfinite && itemDur > 0 {
                    self.duration = itemDur
                }
            }
        }
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.repeatMode == .one {
                self.seek(to: 0)
                self.play()
            } else {
                self.nextTrack()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.savePlaybackState()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.savePlaybackState()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyScreenLockSetting()
        }
        
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            
            if type == .began {
                self?.pause()
            } else if type == .ended {
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self?.play()
                    }
                }
            }
        }
    }
    
    // MARK: - Lock Screen & Remote Command Center Integration
    
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.displayName
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.displayArtist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.album
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration > 0 ? duration : track.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        
        if let artworkImage = currentArtwork {
            let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play / Pause / Stop
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        commandCenter.stopCommand.removeTarget(nil)
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }
        
        // 3-Second Skip Commands (standard iOS skip buttons)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [3.0]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward(seconds: 3.0)
            return .success
        }
        
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [3.0]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward(seconds: 3.0)
            return .success
        }
        
        // Next / Previous Commands
        // Handled according to carRemoteQuickPressSkips3s preference
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.carRemoteQuickPressSkips3s {
                self.skipForward(seconds: 3.0)
            } else {
                self.nextTrack()
            }
            return .success
        }
        
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.carRemoteQuickPressSkips3s {
                self.skipBackward(seconds: 3.0)
            } else {
                self.previousTrack()
            }
            return .success
        }
        
        // Seek / Hold commands (Long press on car steering wheel / Bluetooth remote)
        commandCenter.seekForwardCommand.removeTarget(nil)
        commandCenter.seekForwardCommand.isEnabled = true
        commandCenter.seekForwardCommand.addTarget { [weak self] event in
            guard let self = self, let seekEvent = event as? MPSeekCommandEvent else { return .commandFailed }
            if seekEvent.type == .beginSeeking {
                if self.carRemoteQuickPressSkips3s {
                    // Long press in car mode jumps to next song!
                    self.nextTrack()
                } else {
                    self.skipForward(seconds: 3.0)
                }
            }
            return .success
        }
        
        commandCenter.seekBackwardCommand.removeTarget(nil)
        commandCenter.seekBackwardCommand.isEnabled = true
        commandCenter.seekBackwardCommand.addTarget { [weak self] event in
            guard let self = self, let seekEvent = event as? MPSeekCommandEvent else { return .commandFailed }
            if seekEvent.type == .beginSeeking {
                if self.carRemoteQuickPressSkips3s {
                    // Long press in car mode jumps to previous song!
                    self.previousTrack()
                } else {
                    self.skipBackward(seconds: 3.0)
                }
            }
            return .success
        }
        
        // Scrubber position change
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: posEvent.positionTime)
            return .success
        }
    }
}
