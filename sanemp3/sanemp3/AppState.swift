//
//  AppState.swift
//  sanemp3
//

import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import SwiftUI
import Combine

// MARK: - AppState (combines StorageService + AudioPlayerService)

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Folder / Library
    @Published var importedFolders: [FolderBookmark] = []
    @Published var currentFolderURL: URL?
    @Published var currentFolderName: String = "No Folder Selected"
    @Published var currentTracks: [AudioTrack] = []
    @Published var isLoadingTracks = false
    @Published var folderSortOption: TrackSortOption = .nameAsc

    // MARK: - Playlists
    @Published var playlists: [Playlist] = []

    // MARK: - Player
    @Published var currentTrack: AudioTrack?
    @Published var queue: [AudioTrack] = []
    @Published var currentIndex: Int = 0
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentArtwork: UIImage?
    @Published var repeatMode: RepeatMode = .all
    @Published var isShuffle = false
    @Published var playbackRate: Float = 1.0

    // MARK: - Visual Flash Indicators (Top Squares turn brighter)
    @Published var isRewindActive = false
    @Published var isForwardActive = false
    @Published var savedResetPosition: TimeInterval? = nil
    private var savedTrackPositions: [String: TimeInterval] = [:]
    private var rewindResetTask: Task<Void, Never>?
    private var forwardResetTask: Task<Void, Never>?

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var originalQueue: [AudioTrack] = []
    private var lastSavedTime: TimeInterval = 0
    private var activeFolderURL: URL?

    // MARK: - Storage paths
    private var appSupport: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sanemp3")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private var playlistsURL: URL { appSupport.appendingPathComponent("playlists.json") }
    private var foldersURL: URL { appSupport.appendingPathComponent("folders.json") }

    init() {
        if let saved = UserDefaults.standard.dictionary(forKey: "savedTrackPositions") as? [String: Double] {
            savedTrackPositions = saved
        }
        if let s = UserDefaults.standard.string(forKey: "folderSort"), let o = TrackSortOption(rawValue: s) {
            folderSortOption = o
        }
        loadFolders(); loadPlaylists(); restoreLastFolder()
        setupNotifications(); setupRemoteCommands()
    }

    deinit { activeFolderURL?.stopAccessingSecurityScopedResource() }

    // MARK: - Folder

    func openFolder(_ url: URL) {
        activeFolderURL?.stopAccessingSecurityScopedResource()
        activeFolderURL = nil
        let _ = url.startAccessingSecurityScopedResource()
        activeFolderURL = url
        let bm = (try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
        currentFolderURL = url; currentFolderName = url.lastPathComponent
        if let i = importedFolders.firstIndex(where: { $0.name == url.lastPathComponent }) {
            importedFolders[i].bookmarkData = bm; importedFolders[i].lastOpened = Date()
            UserDefaults.standard.set(importedFolders[i].id.uuidString, forKey: "lastFolderID")
        } else {
            let b = FolderBookmark(name: url.lastPathComponent, bookmarkData: bm)
            importedFolders.insert(b, at: 0)
            UserDefaults.standard.set(b.id.uuidString, forKey: "lastFolderID")
        }
        persistFolders()
        Task { await scanFolder() }
    }

    func selectSavedFolder(_ bookmark: FolderBookmark) {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bookmark.bookmarkData, bookmarkDataIsStale: &stale) {
            openFolder(url)
        }
    }

    func removeFolder(_ bookmark: FolderBookmark) {
        importedFolders.removeAll { $0.id == bookmark.id }
        if currentFolderName == bookmark.name {
            currentFolderURL = nil; currentFolderName = "No Folder Selected"; currentTracks = []
        }
        persistFolders()
    }

    func scanFolder() async {
        guard let url = currentFolderURL else { return }
        isLoadingTracks = true
        let exts = Set(["mp3","m4a","aac","wav","flac","aiff","caf"])
        var urls: [URL] = []
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fu as URL in e where exts.contains(fu.pathExtension.lowercased()) { urls.append(fu) }
        }
        var loaded: [AudioTrack] = []
        for u in urls { loaded.append(await AudioTrack.load(from: u)) }
        currentTracks = folderSortOption.sort(loaded)
        isLoadingTracks = false
        if let i = importedFolders.firstIndex(where: { $0.name == url.lastPathComponent }) {
            importedFolders[i].trackCount = loaded.count; persistFolders()
        }
    }

    func setFolderSort(_ opt: TrackSortOption) {
        folderSortOption = opt
        UserDefaults.standard.set(opt.rawValue, forKey: "folderSort")
        currentTracks = opt.sort(currentTracks)
    }

    private func restoreLastFolder() {
        guard let idStr = UserDefaults.standard.string(forKey: "lastFolderID"),
              let id = UUID(uuidString: idStr),
              let bm = importedFolders.first(where: { $0.id == id }) else {
            if let first = importedFolders.first { selectSavedFolder(first) }
            return
        }
        selectSavedFolder(bm)
    }

    // MARK: - Playlists

    func createPlaylist(name: String, tracks: [AudioTrack] = []) {
        let p = Playlist(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Playlist" : name.trimmingCharacters(in: .whitespacesAndNewlines), tracks: tracks)
        playlists.append(p); persistPlaylists()
    }

    func addTracksToPlaylist(_ tracks: [AudioTrack], playlistId: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[i].tracks.append(contentsOf: tracks); persistPlaylists()
    }

    func removeTrack(at offsets: IndexSet, from playlistId: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[i].tracks.remove(atOffsets: offsets); persistPlaylists()
    }

    func moveTracks(from source: IndexSet, to dest: Int, in playlistId: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[i].tracks.move(fromOffsets: source, toOffset: dest); persistPlaylists()
    }

    func renamePlaylist(_ id: UUID, name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = name; persistPlaylists()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }; persistPlaylists()
    }

    func sortPlaylist(_ id: UUID, option: TrackSortOption) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].tracks = option.sort(playlists[i].tracks); persistPlaylists()
    }

    // MARK: - Playback

    func playQueue(_ newQueue: [AudioTrack], startingAt index: Int = 0) {
        guard !newQueue.isEmpty, newQueue.indices.contains(index) else { return }
        originalQueue = newQueue
        queue = newQueue
        currentIndex = index
        load(track: queue[currentIndex], autoPlay: true)
    }

    private func load(track: AudioTrack, startAt time: TimeInterval = 0, autoPlay: Bool = true) {
        currentTrack = track
        currentTime = time
        duration = track.duration
        currentArtwork = nil

        if let t = timeObserverToken, let p = player {
            p.removeTimeObserver(t)
            timeObserverToken = nil
        }

        let item = AVPlayerItem(url: track.url)

        if player == nil {
            player = AVPlayer(playerItem: item)
            player?.automaticallyWaitsToMinimizeStalling = false
        } else {
            player?.automaticallyWaitsToMinimizeStalling = false
            player?.replaceCurrentItem(with: item)
        }

        if time > 0 {
            player?.seek(to: CMTime(seconds: time, preferredTimescale: 44100), toleranceBefore: .zero, toleranceAfter: .zero)
        }

        setupTimeObserver()

        if autoPlay {
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.playImmediately(atRate: playbackRate)
            isPlaying = true
        } else {
            isPlaying = false
        }

        updateNowPlaying()
        savePlaybackState()

        Task {
            if let art = await track.loadArtwork() {
                currentArtwork = art
                updateNowPlaying()
            }
        }
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard let p = player else {
            if let t = currentTrack {
                load(track: t, startAt: currentTime, autoPlay: true)
            } else if !queue.isEmpty {
                load(track: queue[currentIndex], autoPlay: true)
            }
            return
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        p.playImmediately(atRate: playbackRate)
        isPlaying = true
        updateNowPlaying()
        savePlaybackState()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
        savePlaybackState()
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        currentTime = 0
        updateNowPlaying()
        savePlaybackState()
    }

    func seek(to time: TimeInterval) {
        let t = max(0, min(time, duration))
        currentTime = t
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 44100), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            if self.isPlaying {
                self.player?.playImmediately(atRate: self.playbackRate)
            }
            self.updateNowPlaying()
            self.savePlaybackState()
        }
    }

    // MARK: - Rewind / Forward (3 seconds jump with visual square flashing)

    func flashBackward() {
        isRewindActive = true
        skipBackward(3)
        rewindResetTask?.cancel()
        rewindResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled { self.isRewindActive = false }
        }
    }

    func flashForward() {
        isForwardActive = true
        skipForward(3)
        forwardResetTask?.cancel()
        forwardResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled { self.isForwardActive = false }
        }
    }

    func skipForward(_ s: TimeInterval = 3) { seek(to: currentTime + s) }
    func skipBackward(_ s: TimeInterval = 3) { seek(to: currentTime - s) }

    private func saveCurrentTrackPosition() {
        guard let track = currentTrack else { return }
        if currentTime > 5 {
            savedTrackPositions[track.url.path] = currentTime
            UserDefaults.standard.set(savedTrackPositions, forKey: "savedTrackPositions")
        }
    }

    func nextTrack() {
        // Accidental reset recovery: If the user reset the current song by mistake,
        // pressing Next first jumps back to that memorized spot!
        if let restoreSpot = savedResetPosition {
            savedResetPosition = nil
            seek(to: restoreSpot)
            if !isPlaying { play() }
            return
        }

        savedResetPosition = nil
        saveCurrentTrackPosition()
        guard !queue.isEmpty else { return }
        if currentIndex < queue.count - 1 {
            currentIndex += 1
        } else {
            currentIndex = 0 // Wrap around to the first song immediately
        }
        let nextTrk = queue[currentIndex]
        let resumeTime = savedTrackPositions[nextTrk.url.path] ?? 0
        load(track: nextTrk, startAt: resumeTime, autoPlay: true)
    }

    func previousTrack() {
        if currentTime > 5 {
            // Accidental reset: memorize last spot before resetting to 0
            savedResetPosition = currentTime
            saveCurrentTrackPosition()
            seek(to: 0)
            if !isPlaying { play() }
            return
        }

        // Under 5s: navigate to previous song
        savedResetPosition = nil
        saveCurrentTrackPosition()
        guard !queue.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            currentIndex = queue.count - 1 // Wrap around to last song
        }
        let prevTrk = queue[currentIndex]
        let resumeTime = savedTrackPositions[prevTrk.url.path] ?? 0
        load(track: prevTrk, startAt: resumeTime, autoPlay: true)
    }

    // MARK: - State persistence

    func savePlaybackState() {
        guard let track = currentTrack else { return }
        let state = SavedPlaybackState(track: track, queue: queue.isEmpty ? [track] : queue,
            currentIndex: currentIndex, currentTime: currentTime, repeatMode: repeatMode, isShuffle: isShuffle)
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: "playbackState") }
    }

    func restorePlaybackState() {
        guard let data = UserDefaults.standard.data(forKey: "playbackState"),
              let state = try? JSONDecoder().decode(SavedPlaybackState.self, from: data) else { return }
        queue = state.queue; originalQueue = state.queue; currentIndex = state.currentIndex
        currentTime = state.currentTime; duration = state.duration > 0 ? state.duration : state.track.duration
        repeatMode = state.repeatMode; isShuffle = state.isShuffle; currentTrack = state.track
        load(track: state.track, startAt: state.currentTime, autoPlay: false)
    }

    // MARK: - Now Playing / Remote Commands

    private func updateNowPlaying() {
        guard let t = currentTrack else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = t.displayName
        info[MPMediaItemPropertyArtist] = t.displayArtist
        info[MPMediaItemPropertyAlbumTitle] = t.album
        info[MPMediaItemPropertyPlaybackDuration] = duration > 0 ? duration : t.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        if let art = currentArtwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.removeTarget(nil); cc.pauseCommand.removeTarget(nil)
        cc.togglePlayPauseCommand.removeTarget(nil); cc.stopCommand.removeTarget(nil)
        cc.nextTrackCommand.removeTarget(nil); cc.previousTrackCommand.removeTarget(nil)
        cc.seekForwardCommand.removeTarget(nil); cc.seekBackwardCommand.removeTarget(nil)
        cc.skipForwardCommand.removeTarget(nil); cc.skipBackwardCommand.removeTarget(nil)
        cc.changePlaybackPositionCommand.removeTarget(nil)

        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in self?.play(); return .success }

        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }

        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlay(); return .success }

        cc.stopCommand.isEnabled = true
        cc.stopCommand.addTarget { [weak self] _ in self?.stop(); return .success }

        // Skip buttons: rewind / forward 3s
        cc.skipForwardCommand.isEnabled = true
        cc.skipForwardCommand.preferredIntervals = [3]
        cc.skipForwardCommand.addTarget { [weak self] _ in
            self?.flashForward()
            return .success
        }

        cc.skipBackwardCommand.isEnabled = true
        cc.skipBackwardCommand.preferredIntervals = [3]
        cc.skipBackwardCommand.addTarget { [weak self] _ in
            self?.flashBackward()
            return .success
        }

        // Bluetooth Remote Forward buttons (Next track / Seek forward): all jump +3s
        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.flashForward()
            return .success
        }

        cc.seekForwardCommand.isEnabled = true
        cc.seekForwardCommand.addTarget { [weak self] _ in
            self?.flashForward()
            return .success
        }

        // Bluetooth Remote Backward buttons (Prev track / Seek backward): all jump -3s
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.flashBackward()
            return .success
        }

        cc.seekBackwardCommand.isEnabled = true
        cc.seekBackwardCommand.addTarget { [weak self] _ in
            self?.flashBackward()
            return .success
        }

        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let self, let ev = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: ev.positionTime)
            return .success
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if let track = self.currentTrack {
                self.savedTrackPositions.removeValue(forKey: track.url.path)
                UserDefaults.standard.set(self.savedTrackPositions, forKey: "savedTrackPositions")
            }
            self.savedResetPosition = nil
            if self.repeatMode == .one { self.seek(to: 0); self.play() } else { self.nextTrack() }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let ui = n.userInfo, let tv = ui[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: tv) else { return }
            if type == .began { self?.pause() }
            else if let ov = ui[AVAudioSessionInterruptionOptionKey] as? UInt,
                    AVAudioSession.InterruptionOptions(rawValue: ov).contains(.shouldResume) { self?.play() }
        }
    }

    private func setupTimeObserver() {
        let iv = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: iv, queue: .main) { [weak self] t in
            guard let self else { return }
            let s = CMTimeGetSeconds(t)
            if !s.isNaN && !s.isInfinite { self.currentTime = s }
            if let item = self.player?.currentItem {
                let d = CMTimeGetSeconds(item.duration)
                if !d.isNaN && !d.isInfinite && d > 0 { self.duration = d }
            }
            if abs(s - self.lastSavedTime) >= 3 { self.lastSavedTime = s; self.savePlaybackState() }
        }
    }

    // MARK: - Persistence helpers

    private func persistPlaylists() {
        if let data = try? JSONEncoder().encode(playlists) { try? data.write(to: playlistsURL, options: .atomic) }
    }
    private func loadPlaylists() {
        if let data = try? Data(contentsOf: playlistsURL), let p = try? JSONDecoder().decode([Playlist].self, from: data) { playlists = p }
    }
    private func persistFolders() {
        if let data = try? JSONEncoder().encode(importedFolders) { try? data.write(to: foldersURL, options: .atomic) }
    }
    private func loadFolders() {
        if let data = try? Data(contentsOf: foldersURL), let f = try? JSONDecoder().decode([FolderBookmark].self, from: data) { importedFolders = f }
    }
}

// Expose duration on SavedPlaybackState for restore
private extension SavedPlaybackState {
    var duration: TimeInterval { track.duration }
}
