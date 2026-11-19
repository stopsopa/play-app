import Foundation
import Combine

/**
 * The whole logic of LOGIC_FOR_PLAY.md in one object: Queue, press gestures (Decision Window),
 * seeking, track changes and Resume Points.
 *
 * The host app only forwards events in and renders the published state out.
 * It must NOT change tracks or seek the engine behind the controller's back.
 *
 * Usage:
 *   let logic = PlayLogicController(engine: myEngine, store: UserDefaultsResumeStore())
 *   logic.setQueue(tracks, startAt: 0, play: true)   // user opened a folder / playlist
 *   logic.press(.back)                               // media button, key, on-screen button
 *   logic.press(.forward)
 *   logic.togglePlayPause()
 *   logic.select(index: 3)                           // user picked a track from the list
 *   logic.seek(to: 42)                               // scrubber
 *   logic.saveCurrentResumePoint()                   // app goes to background / quits
 *   logic.resetAllResumePoints()                     // settings button
 *   logic.settings.seekStep = 5                      // settings apply from the next press
 *
 * State to render: queue, currentIndex, currentTrack, isPlaying, gestureState,
 * decisionWindowEndsAt, position, duration, resumePoint(for:).
 */
@MainActor
public final class PlayLogicController: ObservableObject {
    @Published public private(set) var queue: [PlayTrack] = []
    @Published public private(set) var currentIndex: Int?
    @Published public private(set) var isPlaying = false
    @Published public private(set) var gestureState: GestureState = .idle
    // When the open Decision Window closes. nil when idle. For a visual indicator.
    @Published public private(set) var decisionWindowEndsAt: Date?
    // Length of the open Decision Window, to draw "remaining / whole".
    @Published public private(set) var decisionWindowDuration: TimeInterval = 0
    // Bumped on every Resume Memory change so lists showing Resume Points re-render.
    @Published public private(set) var resumeRevision = 0
    @Published public var settings: PlayLogicSettings

    private let engine: any PlaybackEngine
    private let store: any ResumeStore
    private let scheduler: any PlayLogicScheduler
    private var cancelTimer: PlayLogicCancel?
    // Position at the moment of the press that opened the gesture (LOGIC_FOR_PLAY.md 7).
    private var pendingPressPosition: TimeInterval = 0

    public init(
        engine: any PlaybackEngine,
        store: any ResumeStore,
        settings: PlayLogicSettings = PlayLogicSettings(),
        scheduler: (any PlayLogicScheduler)? = nil
    ) {
        self.engine = engine
        self.store = store
        self.settings = settings
        self.scheduler = scheduler ?? TaskScheduler()
        engine.onTrackEnded = { [weak self] in
            self?.trackEnded()
        }
    }

    // MARK: - State for rendering

    public var currentTrack: PlayTrack? {
        guard let index = currentIndex else { return nil }
        return queue[index]
    }

    public var position: TimeInterval { engine.position }
    public var duration: TimeInterval { engine.duration }
    public var resumePointCount: Int { store.count }

    // Stored Resume Point of a track. nil = nothing stored (plays from 0).
    public func resumePoint(for key: String) -> TimeInterval? {
        store.resumePoint(for: key)
    }

    // MARK: - Queue

    /**
     * Replaces the Queue (user opened a folder, playlist, album...).
     * The track being left gets its position saved. The track at `index` starts from its
     * Resume Point (this is a user action). Pass nil to load the Queue without a current track.
     */
    public func setQueue(_ tracks: [PlayTrack], startAt index: Int? = nil, play: Bool = false) {
        saveCurrentResumePoint()
        cancelGesture()
        queue = tracks
        if let index, tracks.indices.contains(index) {
            isPlaying = play
            land(on: index, resume: true)
        } else {
            currentIndex = nil
            isPlaying = false
            engine.pause()
        }
    }

    /**
     * User picked a track from the list. Starts playing it from its Resume Point
     * (from the start when it has none). Picking the current track only makes sure it plays.
     */
    public func select(index: Int) {
        guard queue.indices.contains(index) else { return }
        if index == currentIndex {
            play()
            return
        }
        isPlaying = true
        go(to: index)
    }

    // MARK: - Play / pause

    public func play() {
        guard currentIndex != nil else { return }
        isPlaying = true
        engine.play()
    }

    public func pause() {
        guard currentIndex != nil else { return }
        isPlaying = false
        engine.pause()
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    // Direct seek (scrubber, lock-screen position slider). Not part of any gesture.
    public func seek(to position: TimeInterval) {
        guard currentIndex != nil else { return }
        let duration = engine.duration
        let upper = duration > 0 ? duration : position
        engine.seek(to: min(max(0, position), upper))
    }

    // MARK: - Back / Forward

    /**
     * One Press of Back or Forward (LOGIC_FOR_PLAY.md 4, 5, 7).
     *   first press            - opens the gesture, moves nothing
     *   second and later press - seeks one Seek Step in the direction of that press
     *   every press            - restarts the Decision Window
     * The single-press action (change / restart track) runs when the window expires.
     */
    public func press(_ button: NavButton) {
        guard currentIndex != nil else { return }

        /**
         * The timer can fire late when the app was suspended (iOS background).
         * If the window is already over, finish the old gesture first,
         * so this press starts a new gesture instead of turning the old one into a seek.
         */
        if let endsAt = decisionWindowEndsAt, scheduler.now >= endsAt {
            windowExpired()
        }

        switch gestureState {
        case .idle:
            pendingPressPosition = engine.position
            gestureState = .pending(button)
        case .pending, .seeking:
            gestureState = .seeking
            seekOneStep(button)
        }

        // seekOneStep can run past the end of the track, which ends the gesture.
        if gestureState != .idle {
            startWindow()
        }
    }

    // MARK: - Resume Points

    /**
     * Saves the position of the current track as its Resume Point without leaving it.
     * Call it when the app goes to background or quits, so the position is not lost.
     */
    public func saveCurrentResumePoint() {
        guard let track = currentTrack else { return }
        setResumePoint(engine.position, for: track)
    }

    // "Reset all Resume Points" from settings.
    public func resetAllResumePoints() {
        store.resetAll()
        resumeRevision += 1
    }

    // MARK: - Internals

    private func setResumePoint(_ position: TimeInterval, for track: PlayTrack) {
        store.setResumePoint(position, for: track.key)
        resumeRevision += 1
    }

    private func startWindow() {
        cancelTimer?()
        let window = max(0.05, settings.decisionWindow)
        decisionWindowDuration = window
        decisionWindowEndsAt = scheduler.now.addingTimeInterval(window)
        cancelTimer = scheduler.schedule(after: window) { [weak self] in
            self?.windowExpired()
        }
    }

    // Any track change cancels the gesture and returns to idle.
    private func cancelGesture() {
        cancelTimer?()
        cancelTimer = nil
        gestureState = .idle
        decisionWindowEndsAt = nil
    }

    // Decision Window is over: run the single-press action, or nothing after a seek.
    private func windowExpired() {
        let state = gestureState
        cancelGesture()
        guard case .pending(let button) = state, let index = currentIndex else { return }

        switch button {
        case .forward:
            // Forward on the last track with repeat off: nothing.
            if let next = nextIndex(after: index) {
                go(to: next)
            }
        case .back:
            /**
             * Above the threshold: restart. Only seeks to 0, the Resume Point is rewritten
             * later, when we leave. First track at or below the threshold: restart as well.
             */
            if pendingPressPosition > settings.restartThreshold || index == 0 {
                engine.seek(to: 0)
            } else {
                go(to: index - 1)
            }
        }
    }

    // One seeking press. Clamps at 0; past the end the track finishes naturally.
    private func seekOneStep(_ button: NavButton) {
        let step = button == .forward ? settings.seekStep : -settings.seekStep
        let target = engine.position + step
        let duration = engine.duration
        if duration > 0 && target >= duration {
            trackEnded()
            return
        }
        engine.seek(to: max(0, target))
    }

    private func nextIndex(after index: Int) -> Int? {
        if index + 1 < queue.count {
            return index + 1
        }
        return settings.repeatMode == .all ? 0 : nil
    }

    // User-driven track change: save on leave, restore on land.
    private func go(to index: Int) {
        guard index != currentIndex else { return }
        saveCurrentResumePoint()
        cancelGesture()
        land(on: index, resume: true)
    }

    private func land(on index: Int, resume: Bool) {
        currentIndex = index
        let track = queue[index]
        let start = resume ? (store.resumePoint(for: track.key) ?? 0) : 0
        engine.load(track, at: start, autoplay: isPlaying)
    }

    /**
     * The current track played to its end (LOGIC_FOR_PLAY.md 3 and 6.3).
     * Clears its Resume Point, cancels any open gesture (no double skip when a Forward
     * was pending) and moves on by itself.
     */
    private func trackEnded() {
        guard let index = currentIndex else { return }
        cancelGesture()
        setResumePoint(0, for: queue[index])

        let next = settings.repeatMode == .one ? index : nextIndex(after: index)
        if let next {
            land(on: next, resume: settings.resumeOnNaturalAdvance)
        } else {
            // End of the last track, repeat off: playback stops.
            isPlaying = false
            engine.pause()
            engine.seek(to: 0)
        }
    }
}
