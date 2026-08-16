//
//  AppState.swift
//  sanemp3
//

import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import SwiftUI

// MARK: - AppState (combines StorageService + AudioPlayerService)

@Observable
final class AppState {
    static let shared = AppState()

    // MARK: - Folder / Library
    var importedFolders: [FolderBookmark] = []
    var currentFolderURL: URL?
    var currentFolderName: String = "No Folder Selected"
    var currentTracks: [AudioTrack] = []
    var isLoadingTracks = false
    var folderSortOption: TrackSortOption = .nameAsc

    // MARK: - Playlists
    var playlists: [Playlist] = []

    // MARK: - Player
    var currentTrack: AudioTrack?
    var queue: [AudioTrack] = []
    var currentIndex: Int = 0
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentArtwork: UIImage?
    var repeatMode: RepeatMode = .all
    var isShuffle = false
    var playbackRate: Float = 1.0
    var carRemoteMode = false {
        didSet { UserDefaults.standard.set(carRemoteMode, forKey: "carRemoteMode"); setupRemoteCommands() }
    }

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
        carRemoteMode = UserDefaults.standard.bool(forKey: "carRemoteMode")
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
        if isShuffle {
            var s = newQueue; let t = s.remove(at: index); s.shuffle(); s.insert(t, at: 0)
            queue = s; currentIndex = 0
        } else {
            queue = newQueue; currentIndex = index
        }
        load(track: queue[currentIndex], autoPlay: true)
    }

    private func load(track: AudioTrack, startAt time: TimeInterval = 0, autoPlay: Bool = true) {
        currentTrack = track; currentTime = time; duration = track.duration; currentArtwork = nil
        if let t = timeObserverToken, let p = player { p.removeTimeObserver(t); timeObserverToken = nil }
        let item = AVPlayerItem(url: track.url)
        if player == nil { player = AVPlayer(playerItem: item) } else { player!.replaceCurrentItem(with: item) }
        if time > 0 { player!.seek(to: CMTime(seconds: time, preferredTimescale: 44100)) }
        setupTimeObserver()
        if autoPlay { try? AVAudioSession.sharedInstance().setActive(true); player!.rate = playbackRate; player!.play(); isPlaying = true }
        else { isPlaying = false }
        updateNowPlaying(); savePlaybackState()
        Task { if let art = await track.loadArtwork() { currentArtwork = art; updateNowPlaying() } }
    }

    func togglePlay() { isPlaying ? pause() : play() }
    func play() {
        guard let p = player else { if let t = currentTrack { load(track: t, startAt: currentTime) }; return }
        try? AVAudioSession.sharedInstance().setActive(true)
        p.rate = playbackRate; p.play(); isPlaying = true; updateNowPlaying(); savePlaybackState()
    }
    func pause() { player?.pause(); isPlaying = false; updateNowPlaying(); savePlaybackState() }
    func stop() { player?.pause(); player?.seek(to: .zero); isPlaying = false; currentTime = 0; updateNowPlaying(); savePlaybackState() }

    func seek(to time: TimeInterval) {
        let t = max(0, min(time, duration))
        currentTime = t
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 44100), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            if self.isPlaying { self.player?.rate = self.playbackRate }
            self.updateNowPlaying(); self.savePlaybackState()
        }
    }

    func skipForward(_ s: TimeInterval = 3) { seek(to: currentTime + s) }
    func skipBackward(_ s: TimeInterval = 3) { seek(to: currentTime - s) }

    func nextTrack() {
        guard !queue.isEmpty else { return }
        if currentIndex < queue.count - 1 { currentIndex += 1 }
        else if repeatMode == .all { currentIndex = 0 }
        else { stop(); return }
        load(track: queue[currentIndex], autoPlay: true)
    }

    func previousTrack() {
        if currentTime > 5 { seek(to: 0); return }
        guard !queue.isEmpty else { return }
        if currentIndex > 0 { currentIndex -= 1 }
        else if repeatMode == .all { currentIndex = queue.count - 1 }
        else { seek(to: 0); return }
        load(track: queue[currentIndex], autoPlay: true)
    }

    func toggleShuffle() {
        isShuffle.toggle()
        guard let cur = currentTrack else { return }
        if isShuffle {
            var s = originalQueue; s.removeAll { $0.id == cur.id }; s.shuffle(); s.insert(cur, at: 0)
            queue = s; currentIndex = 0
        } else {
            queue = originalQueue
            currentIndex = originalQueue.firstIndex(where: { $0.id == cur.id }) ?? 0
        }
    }

    func toggleRepeat() {
        switch repeatMode { case .off: repeatMode = .all; case .all: repeatMode = .one; case .one: repeatMode = .off }
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

        cc.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlay(); return .success }
        cc.stopCommand.addTarget { [weak self] _ in self?.stop(); return .success }

        cc.skipForwardCommand.preferredIntervals = [3]; cc.skipBackwardCommand.preferredIntervals = [3]
        cc.skipForwardCommand.addTarget { [weak self] _ in self?.skipForward(); return .success }
        cc.skipBackwardCommand.addTarget { [weak self] _ in self?.skipBackward(); return .success }

        // Car remote: quick press = 3s skip, long press (seekForward/Backward) = song change
        cc.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.carRemoteMode { self.skipForward() } else { self.nextTrack() }; return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.carRemoteMode { self.skipBackward() } else { self.previousTrack() }; return .success
        }
        cc.seekForwardCommand.addTarget { [weak self] e in
            guard let self, let ev = e as? MPSeekCommandEvent, ev.type == .beginSeeking else { return .commandFailed }
            if self.carRemoteMode { self.nextTrack() } else { self.skipForward() }; return .success
        }
        cc.seekBackwardCommand.addTarget { [weak self] e in
            guard let self, let ev = e as? MPSeekCommandEvent, ev.type == .beginSeeking else { return .commandFailed }
            if self.carRemoteMode { self.previousTrack() } else { self.skipBackward() }; return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let self, let ev = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: ev.positionTime); return .success
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
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
