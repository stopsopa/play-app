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
import PlayLogic

// MARK: - AppState (storage + glue between the UI, PlayLogic and AVPlayerEngine)

/**
 * Holds the library (folders, playlists), the settings and the UI lock.
 *
 * Playback itself is NOT decided here:
 *   - `logic` (PlayLogicController from the PlayLogic package) owns the Queue, the Back / Forward
 *     press gestures and the Resume Points.
 *   - `engine` (AVPlayerEngine) owns the AVPlayer.
 * AppState only forwards user actions to `logic` and exposes its state to the views.
 *
 * Usage from views:
 *   state.playQueue(tracks, startingAt: 3)   // user tapped a track in a folder / playlist
 *   state.selectQueueIndex(5)                // user tapped a track in the Queue sheet
 *   state.pressBack() / state.pressForward() // Prev / Next buttons, same as the media buttons
 *   state.flashBackward() / flashForward()   // direct jump by one Seek Step
 *   state.togglePlay()
 *   state.seek(to: 42)                       // scrubber
 */
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private static let settingsKey = "playLogicSettings"

    // MARK: - Folder / Library
    @Published var importedFolders: [FolderBookmark] = []
    @Published var currentFolderURL: URL?
    @Published var currentFolderName: String = "No Folder Selected"
    @Published var currentTracks: [AudioTrack] = []
    @Published var isLoadingTracks = false
    @Published var folderSortOption: TrackSortOption = .nameAsc
    private var currentFolderID: UUID?

    /**
     * Folders we currently hold access to, by FolderBookmark.id.
     * Access is opened the first time a folder is needed (browsing it, or playing a track from it)
     * and stays open until the folder is removed, so a Queue can play from several folders
     * at once (SUGGESTED_CHANGES.md A2, C6).
     */
    private var openFolders: [UUID: URL] = [:]
    // Folders where iOS really granted security-scoped access, so it has to be given back.
    private var scopedFolders = Set<UUID>()

    // MARK: - Playlists
    @Published var playlists: [Playlist] = []

    // MARK: - Player
    let engine: AVPlayerEngine
    let logic: PlayLogicController
    @Published private(set) var queue: [AudioTrack] = []
    @Published var currentArtwork: UIImage?
    @Published var playbackRate: Float = 1.0 {
        didSet { engine.rate = playbackRate }
    }
    // Last playback problem to show to the user (for example a file that failed to load).
    @Published var playbackError: String?
    private var errorClearTask: Task<Void, Never>?
    // Broken tracks skipped one after another. Stops an endless skip loop when nothing is playable.
    private var failedInARow = 0
    private var lastSavedPosition: TimeInterval = 0
    private var cancellables = Set<AnyCancellable>()

    // Position and length of the current track. Observe it only where progress is drawn.
    var progress: PlaybackProgress { engine.progress }
    var isPlaying: Bool { logic.isPlaying }
    var currentIndex: Int { logic.currentIndex ?? 0 }
    var currentTrack: AudioTrack? {
        guard let index = logic.currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    // MARK: - Screen lock
    /**
     * "Prevent Screen Lock" choice. Stored, and applied only through applyScreenLockSetting()
     * (SUGGESTED_CHANGES.md D3).
     */
    @Published var preventScreenLock: Bool = true {
        didSet {
            UserDefaults.standard.set(preventScreenLock, forKey: "preventScreenLock")
            applyScreenLockSetting()
        }
    }

    // MARK: - Inactivity UI Lock Screen
    @Published var isUiLockEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isUiLockEnabled, forKey: "isUiLockEnabled")
            if isUiLockEnabled {
                resetInactivityTimer()
            } else {
                stopInactivityTimer()
                isUiLocked = false
            }
        }
    }
    @Published var uiLockTimeout: Double = 3.0 {
        didSet {
            UserDefaults.standard.set(uiLockTimeout, forKey: "uiLockTimeout")
            if isUiLockEnabled {
                resetInactivityTimer()
            }
        }
    }
    @Published var isUiLocked: Bool = false
    private var uiLockTimer: Timer?

    // MARK: - Visual Flash Indicators (Top Squares turn brighter)
    @Published var isRewindActive = false
    @Published var isForwardActive = false
    private var rewindResetTask: Task<Void, Never>?
    private var forwardResetTask: Task<Void, Never>?

    // MARK: - Storage paths
    private var appSupport: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sanemp3")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private var playlistsURL: URL { appSupport.appendingPathComponent("playlists.json") }
    private var foldersURL: URL { appSupport.appendingPathComponent("folders.json") }
    private var queueURL: URL { appSupport.appendingPathComponent("queue.json") }

    init() {
        let engine = AVPlayerEngine()
        self.engine = engine
        logic = PlayLogicController(engine: engine, store: UserDefaultsResumeStore(), settings: Self.loadSettings())

        if let s = UserDefaults.standard.string(forKey: "folderSort"), let o = TrackSortOption(rawValue: s) {
            folderSortOption = o
        }
        preventScreenLock = UserDefaults.standard.object(forKey: "preventScreenLock") as? Bool ?? true
        isUiLockEnabled = UserDefaults.standard.bool(forKey: "isUiLockEnabled")
        let savedTimeout = UserDefaults.standard.double(forKey: "uiLockTimeout")
        if savedTimeout >= 1.0 {
            uiLockTimeout = min(60.0, savedTimeout)
        } else {
            uiLockTimeout = 3.0
        }
        if isUiLockEnabled {
            resetInactivityTimer()
        }
        loadFolders(); loadPlaylists(); restoreLastFolder()
        wireEngine(); setupNotifications(); setupRemoteCommands()
        // Runs once per launch, not on every appearance of the root view (SUGGESTED_CHANGES.md D1).
        restoreQueue()

        // Data of the pre-PlayLogic version: whole queue in UserDefaults, positions keyed by absolute path.
        UserDefaults.standard.removeObject(forKey: "playbackState")
        UserDefaults.standard.removeObject(forKey: "savedTrackPositions")
    }

    /**
     * Stored PlayLogic settings. On the first run with the library it starts from what the app
     * did before: wrap around at the end of the Queue, and the old multi-tap interval.
     */
    private static func loadSettings() -> PlayLogicSettings {
        let defaults = UserDefaults.standard
        if defaults.data(forKey: settingsKey) != nil {
            return PlayLogicSettings.load(from: defaults, key: settingsKey)
        }
        var settings = PlayLogicSettings()
        settings.repeatMode = .all
        let oldInterval = defaults.double(forKey: "multiTapInterval")
        if oldInterval >= 0.2 {
            settings.decisionWindow = (oldInterval * 10).rounded() / 10
        }
        return settings
    }

    // Connects the library and the engine to this object. Called once from init.
    private func wireEngine() {
        // Views observe AppState only, so every change in the library must redraw them.
        logic.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        logic.$settings
            .dropFirst()
            .sink { $0.save(to: .standard, key: AppState.settingsKey) }
            .store(in: &cancellables)

        engine.durationHint = { [weak self] _ in self?.currentTrack?.duration ?? 0 }
        engine.onTrackLoaded = { [weak self] in self?.trackLoaded() }
        engine.onTrackReady = { [weak self] in self?.failedInARow = 0 }
        engine.onTrackFailed = { [weak self] track, reason in self?.trackFailed(track, reason: reason) }
        engine.onStoppedBySystem = { [weak self] in self?.pause() }
        engine.onStateChanged = { [weak self] in self?.updateNowPlaying() }
        engine.onTick = { [weak self] in self?.periodicSave() }
    }

    // MARK: - Folder

    /**
     * URL of an imported folder, with access to it started.
     * Resolves the stored bookmark on first use and refreshes it when iOS says it went stale.
     * nil when the folder is gone or cannot be resolved.
     */
    private func folderURL(for id: UUID) -> URL? {
        if let url = openFolders[id] {
            return url
        }
        guard let i = importedFolders.firstIndex(where: { $0.id == id }) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: importedFolders[i].bookmarkData, bookmarkDataIsStale: &stale) else {
            print("sanemp3: cannot resolve bookmark of folder \(importedFolders[i].name)")
            return nil
        }
        if url.startAccessingSecurityScopedResource() {
            scopedFolders.insert(id)
        } else {
            print("sanemp3: no security-scoped access to folder \(importedFolders[i].name)")
        }
        openFolders[id] = url
        if stale, let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            importedFolders[i].bookmarkData = fresh
            persistFolders()
        }
        return url
    }

    // Gives back access to one folder. Safe to call for a folder that was never opened.
    private func closeFolder(_ id: UUID) {
        guard let url = openFolders.removeValue(forKey: id) else { return }
        if scopedFolders.remove(id) != nil {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // Folder picked in the Files picker.
    func openFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        let bm = (try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
        let folder: FolderBookmark
        if let i = importedFolders.firstIndex(where: { $0.name == url.lastPathComponent }) {
            importedFolders[i].bookmarkData = bm; importedFolders[i].lastOpened = Date()
            folder = importedFolders[i]
        } else {
            folder = FolderBookmark(name: url.lastPathComponent, bookmarkData: bm)
            importedFolders.insert(folder, at: 0)
        }
        // Access held through an older URL of the same folder is replaced by the fresh one.
        closeFolder(folder.id)
        openFolders[folder.id] = url
        if scoped {
            scopedFolders.insert(folder.id)
        }
        show(folder, at: url)
    }

    func selectSavedFolder(_ bookmark: FolderBookmark) {
        guard let url = folderURL(for: bookmark.id) else {
            showPlaybackError("Cannot open folder \"\(bookmark.name)\". Open it again from Files.")
            return
        }
        if let i = importedFolders.firstIndex(where: { $0.id == bookmark.id }) {
            importedFolders[i].lastOpened = Date()
        }
        show(bookmark, at: url)
    }

    // Makes a folder the one shown in the Folder tab and scans it.
    private func show(_ folder: FolderBookmark, at url: URL) {
        currentFolderID = folder.id
        currentFolderURL = url; currentFolderName = folder.name
        UserDefaults.standard.set(folder.id.uuidString, forKey: "lastFolderID")
        persistFolders()
        Task { await scanFolder() }
    }

    func removeFolder(_ bookmark: FolderBookmark) {
        closeFolder(bookmark.id)
        importedFolders.removeAll { $0.id == bookmark.id }
        if currentFolderName == bookmark.name {
            currentFolderURL = nil; currentFolderID = nil; currentFolderName = "No Folder Selected"; currentTracks = []
        }
        persistFolders()
    }

    func scanFolder() async {
        guard let url = currentFolderURL,
              let folderID = currentFolderID,
              let folder = importedFolders.first(where: { $0.id == folderID })
        else { return }
        isLoadingTracks = true
        let exts = Set(["mp3","m4a","aac","wav","flac","aiff","caf"])
        var urls: [URL] = []
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            while let fu = e.nextObject() as? URL {
                if exts.contains(fu.pathExtension.lowercased()) {
                    urls.append(fu)
                }
            }
        }
        let basePath = url.resolvingSymlinksInPath().path + "/"
        var loaded: [AudioTrack] = []
        for u in urls {
            // Path inside the folder: the stable part of a track's identity.
            let path = u.resolvingSymlinksInPath().path
            let relative = path.hasPrefix(basePath) ? String(path.dropFirst(basePath.count)) : u.lastPathComponent
            loaded.append(await AudioTrack.load(from: u, folder: folder, relativePath: relative))
        }
        // The user switched to another folder while this one was being scanned.
        if currentFolderID != folderID { return }
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

    /**
     * Where a track is on disk right now. Built from the folder (resolved from its bookmark,
     * access started) plus the path inside the folder, so it survives relaunches.
     * Tracks saved by old versions have no folder and fall back to their stored URL.
     */
    private func playableURL(for track: AudioTrack) -> URL {
        guard let folderID = track.folderID,
              let relativePath = track.relativePath,
              let base = folderURL(for: folderID)
        else { return track.url }
        return base.appendingPathComponent(relativePath)
    }

    /**
     * Upgrades tracks saved by old versions (random id, absolute URL only) to the stable identity:
     * finds the imported folder each one lives in. Tracks whose folder is not found stay as they are.
     */
    private func adoptLegacyTracks(_ tracks: [AudioTrack]) -> [AudioTrack] {
        guard tracks.contains(where: { $0.folderID == nil }) else { return tracks }
        let bases: [(folder: FolderBookmark, path: String)] = importedFolders.compactMap { folder in
            guard let url = folderURL(for: folder.id) else { return nil }
            return (folder, url.resolvingSymlinksInPath().path + "/")
        }
        return tracks.map { track in
            if track.folderID != nil { return track }
            let path = track.url.resolvingSymlinksInPath().path
            guard let hit = bases.first(where: { path.hasPrefix($0.path) }) else { return track }
            return track.adopted(by: hit.folder, relativePath: String(path.dropFirst(hit.path.count)))
        }
    }

    // MARK: - Playlists

    func createPlaylist(name: String, tracks: [AudioTrack] = []) {
        let p = Playlist(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Playlist" : name.trimmingCharacters(in: .whitespacesAndNewlines), tracks: tracks.uniqueByID())
        playlists.append(p); persistPlaylists()
    }

    // A track can be in a playlist only once: tracks already there are skipped.
    func addTracksToPlaylist(_ tracks: [AudioTrack], playlistId: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[i].tracks = (playlists[i].tracks + tracks).uniqueByID(); persistPlaylists()
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

    private func playTrack(_ track: AudioTrack) -> PlayTrack {
        PlayTrack(key: track.id, title: track.displayName, url: playableURL(for: track))
    }

    // User opened a folder / playlist at a given track. The track starts from its Resume Point.
    func playQueue(_ newQueue: [AudioTrack], startingAt index: Int = 0) {
        guard newQueue.indices.contains(index) else { return }
        failedInARow = 0
        // The queue file is written only when the queue really changed (SUGGESTED_CHANGES.md C1).
        if newQueue != queue {
            queue = newQueue
            persistQueue()
        }
        logic.setQueue(newQueue.map(playTrack), startAt: index, play: true)
    }

    // User picked a track of the current Queue.
    func selectQueueIndex(_ index: Int) {
        failedInARow = 0
        logic.select(index: index)
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        logic.play()
    }

    func pause() {
        logic.pause()
        logic.saveCurrentResumePoint()
    }

    func stop() {
        pause()
        logic.seek(to: 0)
    }

    func seek(to time: TimeInterval) {
        logic.seek(to: time)
    }

    // MARK: - Back / Forward presses (media buttons and the bottom car buttons)

    /**
     * One press of Back or Forward. The library decides what the whole gesture means
     * (next / previous track, restart, or seek). When the press turned out to be a seek,
     * the matching top square flashes.
     */
    func press(_ button: NavButton) {
        logic.press(button)
        if logic.gestureState == .seeking {
            flash(button)
        }
    }

    func pressBack() { press(.back) }
    func pressForward() { press(.forward) }

    // A single Back is waiting for its Decision Window, or two Backs are (restart candidate).
    var isBackPending: Bool { logic.gestureState == .pending(.back) || logic.gestureState == .pendingRestart }
    // Exactly two Backs so far: the track restarts when the Decision Window closes.
    var isRestartPending: Bool { logic.gestureState == .pendingRestart }
    var isForwardPending: Bool { logic.gestureState == .pending(.forward) }

    // MARK: - Rewind / Forward (one Seek Step jump with visual square flashing)

    func flashBackward() { jumpOneStep(.back) }
    func flashForward() { jumpOneStep(.forward) }

    // Direct jump from the on-screen -Ns / +Ns buttons. Not part of any press gesture.
    private func jumpOneStep(_ button: NavButton) {
        let step = button == .forward ? logic.settings.seekStep : -logic.settings.seekStep
        logic.seek(to: logic.position + step)
        flash(button)
    }

    private func flash(_ button: NavButton) {
        let forward = button == .forward
        if forward {
            isForwardActive = true
            forwardResetTask?.cancel()
        } else {
            isRewindActive = true
            rewindResetTask?.cancel()
        }
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            if forward {
                self.isForwardActive = false
            } else {
                self.isRewindActive = false
            }
        }
        if forward {
            forwardResetTask = task
        } else {
            rewindResetTask = task
        }
    }

    // MARK: - Engine events

    // A new track was handed to the player: remember where we are in the Queue, load its artwork.
    private func trackLoaded() {
        UserDefaults.standard.set(currentIndex, forKey: "queueIndex")
        lastSavedPosition = engine.position
        currentArtwork = nil
        guard let track = currentTrack else { return }
        let url = playableURL(for: track)
        Task {
            let art = await AudioTrack.loadArtwork(from: url)
            // The user may have moved on while the artwork was loading.
            if let art, self.currentTrack?.id == track.id {
                self.currentArtwork = art
                self.updateNowPlaying()
            }
        }
    }

    /**
     * The current track cannot be played (missing, not downloaded, unreadable).
     * Shows which one, and while playing moves on to the next track instead of going silent
     * (SUGGESTED_CHANGES.md A1). Stops when a whole round of the Queue failed.
     */
    private func trackFailed(_ track: PlayTrack, reason: String) {
        showPlaybackError("Cannot play \"\(track.title)\": \(reason)")
        guard logic.isPlaying, let index = logic.currentIndex else { return }
        failedInARow += 1
        let wraps = logic.settings.repeatMode == .all
        let next = index + 1 < queue.count ? index + 1 : (wraps ? 0 : index)
        if next != index && failedInARow < queue.count {
            logic.select(index: next)
        } else {
            failedInARow = 0
            logic.pause()
        }
    }

    // Shows a message in the player UI for 10 seconds.
    private func showPlaybackError(_ message: String) {
        playbackError = message
        errorClearTask?.cancel()
        errorClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if Task.isCancelled { return }
            self.playbackError = nil
        }
    }

    // MARK: - State persistence

    /**
     * Saves the position of the current track as its Resume Point (one small value).
     * Called on pause, when the app leaves the foreground and every 15 seconds of playback.
     * The Queue itself is written only when it changes, see persistQueue().
     */
    func saveResumePoint() {
        logic.saveCurrentResumePoint()
    }

    private func periodicSave() {
        guard isPlaying else { return }
        let position = engine.position
        if abs(position - lastSavedPosition) >= 15 {
            lastSavedPosition = position
            logic.saveCurrentResumePoint()
        }
    }

    private func persistQueue() {
        if let data = try? JSONEncoder().encode(queue) { try? data.write(to: queueURL, options: .atomic) }
    }

    // Brings back the Queue of the last session, paused, at the Resume Point of its current track.
    private func restoreQueue() {
        guard let data = try? Data(contentsOf: queueURL),
              let saved = try? JSONDecoder().decode([AudioTrack].self, from: data),
              !saved.isEmpty
        else { return }
        let index = min(max(0, UserDefaults.standard.integer(forKey: "queueIndex")), saved.count - 1)
        queue = saved
        logic.setQueue(saved.map(playTrack), startAt: index, play: false)
    }

    // MARK: - Now Playing / Remote Commands

    private func updateNowPlaying() {
        guard let t = currentTrack else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = t.displayName
        info[MPMediaItemPropertyArtist] = t.displayArtist
        info[MPMediaItemPropertyAlbumTitle] = t.album
        info[MPMediaItemPropertyPlaybackDuration] = engine.duration > 0 ? engine.duration : t.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = engine.position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        if let art = currentArtwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Settings (stored inside PlayLogicSettings) & Resume Point helpers

    // The library's Decision Window: how long we wait after a press for another press.
    var multiTapInterval: Double { logic.settings.decisionWindow }

    func increaseMultiTapInterval() {
        setMultiTapInterval(multiTapInterval + 0.2)
    }

    func decreaseMultiTapInterval() {
        setMultiTapInterval(multiTapInterval - 0.2)
    }

    func resetMultiTapInterval() {
        setMultiTapInterval(1.6)
    }

    func setMultiTapInterval(_ val: Double) {
        logic.settings.decisionWindow = max(0.2, (val * 10).rounded() / 10)
    }

    // How far one seeking press (or the -Ns / +Ns button) moves the position, in seconds.
    var seekStep: Double {
        get { logic.settings.seekStep }
        set { logic.settings.seekStep = max(1, newValue) }
    }

    // Label for the seek buttons, for example "3s".
    var seekStepLabel: String { "\(Int(logic.settings.seekStep))s" }

    // "Resume when a track starts on its own".
    var resumeOnNaturalAdvance: Bool {
        get { logic.settings.resumeOnNaturalAdvance }
        set { logic.settings.resumeOnNaturalAdvance = newValue }
    }

    var repeatMode: RepeatMode {
        get { logic.settings.repeatMode }
        set { logic.settings.repeatMode = newValue }
    }

    var savedTrackPositionsCount: Int {
        logic.resumePointCount
    }

    func clearSavedTrackPositions() {
        logic.resetAllResumePoints()
    }

    // The one place that tells iOS whether the screen may lock by itself.
    func applyScreenLockSetting() {
        UIApplication.shared.isIdleTimerDisabled = preventScreenLock
    }

    // MARK: - Inactivity UI Lock Screen Management

    /**
     Resets the inactivity countdown timer if UI lock is enabled.
     If the screen is currently locked, resetting the timer will not automatically unlock it.
     */
    func resetInactivityTimer() {
        guard isUiLockEnabled else {
            stopInactivityTimer()
            return
        }
        let timeout = max(1.0, min(60.0, uiLockTimeout))
        // If a valid timer already exists, just push its fire date forward
        // instead of destroying and recreating it (avoids race conditions on rapid calls)
        if let existing = uiLockTimer, existing.isValid {
            existing.fireDate = Date().addingTimeInterval(timeout)
            return
        }
        let timer = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isUiLockEnabled else { return }
                self.isUiLocked = true
            }
        }
        // Use .common mode so the timer fires even during scroll tracking
        RunLoop.main.add(timer, forMode: .common)
        uiLockTimer = timer
    }

    /**
     Stops any active inactivity timer.
     */
    func stopInactivityTimer() {
        uiLockTimer?.invalidate()
        uiLockTimer = nil
    }

    /**
     Unlocks the UI from the lock overlay and restarts the inactivity timer countdown.
     */
    func unlockUi() {
        isUiLocked = false
        resetInactivityTimer()
    }

    // MARK: - Remote commands (Bluetooth / lock screen buttons)

    /**
     * Every Back-like command is one press(.back), every Forward-like command one press(.forward).
     * What a press means is decided by the PlayLogic library (LOGIC_FOR_PLAY.md).
     */
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

        // Skip buttons / interval commands
        cc.skipForwardCommand.isEnabled = true
        cc.skipForwardCommand.preferredIntervals = [3]
        cc.skipForwardCommand.addTarget { [weak self] _ in
            self?.press(.forward)
            return .success
        }

        cc.skipBackwardCommand.isEnabled = true
        cc.skipBackwardCommand.preferredIntervals = [3]
        cc.skipBackwardCommand.addTarget { [weak self] _ in
            self?.press(.back)
            return .success
        }

        // Bluetooth Remote Forward buttons (Next track / Seek forward)
        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.press(.forward)
            return .success
        }

        /**
         * Long press. iOS sends this command twice per long press (begin and end), so one long
         * press still counts as two presses. Left as it was on purpose, see SUGGESTED_CHANGES.md B1.
         */
        cc.seekForwardCommand.isEnabled = true
        cc.seekForwardCommand.addTarget { [weak self] _ in
            self?.press(.forward)
            return .success
        }

        // Bluetooth Remote Backward buttons (Prev track / Seek backward)
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.press(.back)
            return .success
        }

        // Long press, same remark as for seekForwardCommand above.
        cc.seekBackwardCommand.isEnabled = true
        cc.seekBackwardCommand.addTarget { [weak self] _ in
            self?.press(.back)
            return .success
        }

        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let self, let ev = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: ev.positionTime)
            return .success
        }
    }

    // Phone call or another app taking the audio: pause, and resume when iOS says we should.
    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let ui = n.userInfo, let tv = ui[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: tv) else { return }
            let shouldResume: Bool
            if let ov = ui[AVAudioSessionInterruptionOptionKey] as? UInt {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: ov).contains(.shouldResume)
            } else {
                shouldResume = false
            }
            Task { @MainActor [weak self] in
                if type == .began {
                    self?.pause()
                } else if shouldResume {
                    self?.play()
                }
            }
        }
    }

    // MARK: - Persistence helpers

    private func persistPlaylists() {
        if let data = try? JSONEncoder().encode(playlists) { try? data.write(to: playlistsURL, options: .atomic) }
    }
    // Also upgrades tracks of old versions and drops tracks that are in a playlist twice.
    private func loadPlaylists() {
        guard let data = try? Data(contentsOf: playlistsURL),
              let stored = try? JSONDecoder().decode([Playlist].self, from: data)
        else { return }
        playlists = stored.map { playlist in
            var upgraded = playlist
            upgraded.tracks = adoptLegacyTracks(playlist.tracks).uniqueByID()
            return upgraded
        }
        if playlists != stored {
            persistPlaylists()
        }
    }
    private func persistFolders() {
        if let data = try? JSONEncoder().encode(importedFolders) { try? data.write(to: foldersURL, options: .atomic) }
    }
    private func loadFolders() {
        if let data = try? Data(contentsOf: foldersURL), let f = try? JSONDecoder().decode([FolderBookmark].self, from: data) { importedFolders = f }
    }
}
