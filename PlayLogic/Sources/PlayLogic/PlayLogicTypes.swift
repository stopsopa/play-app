import Foundation

/**
 * One track of the Queue, as the library sees it.
 *
 * `key` is the stable identity used for the Resume Point (LOGIC_FOR_PLAY.md 6.6).
 * It must not change between launches or rebuilds, so never use an absolute file path
 * or a freshly generated UUID. Good key: "<folder name>/<path inside the folder>".
 */
public struct PlayTrack: Identifiable, Hashable, Sendable {
    public let key: String
    public let title: String
    public let url: URL

    public var id: String { key }

    public init(key: String, title: String, url: URL) {
        self.key = key
        self.title = title
        self.url = url
    }
}

// The two media buttons.
public enum NavButton: Equatable, Sendable {
    case back
    case forward
}

/**
 * State of the press gesture (LOGIC_FOR_PLAY.md 7).
 *   idle     - no gesture open
 *   pending  - one press received, waiting for the Decision Window to decide
 *   seeking  - two or more presses, the gesture is a seek and will never change track
 */
public enum GestureState: Equatable, Sendable {
    case idle
    case pending(NavButton)
    case seeking
}

/**
 * What happens at the end of a track / end of the Queue.
 *   off - stop after the last track
 *   all - wrap from the last track to the first
 *   one - repeat the current track when it ends on its own
 */
public enum RepeatMode: String, Codable, Sendable {
    case off
    case all
    case one
}

/**
 * All settings from LOGIC_FOR_PLAY.md section 2 (plus repeat).
 *
 * Usage:
 *   var settings = PlayLogicSettings.load(from: .standard, key: "playLogicSettings")
 *   settings.seekStep = 5
 *   settings.save(to: .standard, key: "playLogicSettings")
 */
public struct PlayLogicSettings: Codable, Equatable, Sendable {
    // How long we wait after a press for another press.
    public var decisionWindow: TimeInterval = 5
    // How far one seeking press moves the position.
    public var seekStep: TimeInterval = 3
    // Single Back at or below this position goes to the previous track, above it restarts.
    public var restartThreshold: TimeInterval = 5
    // "Resume when a track starts on its own".
    public var resumeOnNaturalAdvance: Bool = true
    public var repeatMode: RepeatMode = .off

    public init() {}

    // Returns stored settings, or defaults when nothing (or something unreadable) is stored.
    public static func load(from defaults: UserDefaults, key: String) -> PlayLogicSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(PlayLogicSettings.self, from: data)
        else {
            return PlayLogicSettings()
        }
        return settings
    }

    public func save(to defaults: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }
}

/**
 * What the library needs from an audio player. The host app implements it
 * (AVAudioPlayer in the demo, AVPlayer in sanemp3).
 *
 * Requirements the implementation must keep:
 *   - `position` must reflect a `seek(to:)` immediately, even when the real player seeks
 *     asynchronously (AVPlayer): remember the seek target and return it until the seek lands.
 *     Otherwise fast multi-press seeking loses steps.
 *   - `load` replaces the current track, positions it and plays only when `autoplay` is true.
 *   - `onTrackEnded` is called once when the CURRENT track plays to its end. Never for a track
 *     that was already replaced by `load`.
 *   - `duration` is 0 while unknown.
 */
@MainActor
public protocol PlaybackEngine: AnyObject {
    var position: TimeInterval { get }
    var duration: TimeInterval { get }
    var onTrackEnded: (@MainActor () -> Void)? { get set }

    func load(_ track: PlayTrack, at position: TimeInterval, autoplay: Bool)
    func seek(to position: TimeInterval)
    func play()
    func pause()
}

/**
 * Resume Memory: storage of all Resume Points keyed by `PlayTrack.key`.
 * nil means "nothing stored for this track" and plays from 0.
 */
@MainActor
public protocol ResumeStore: AnyObject {
    var count: Int { get }
    func resumePoint(for key: String) -> TimeInterval?
    func setResumePoint(_ position: TimeInterval, for key: String)
    func resetAll()
}

/**
 * Default Resume Memory: one dictionary in UserDefaults.
 * Permanent: survives closing the app and rebuilding from Xcode (LOGIC_FOR_PLAY.md 6.5).
 *
 * Usage:
 *   let store = UserDefaultsResumeStore()
 *   let store = UserDefaultsResumeStore(defaults: .standard, key: "myResumePoints")
 */
@MainActor
public final class UserDefaultsResumeStore: ResumeStore {
    private let defaults: UserDefaults
    private let key: String
    private var points: [String: Double]

    public init(defaults: UserDefaults = .standard, key: String = "PlayLogic.resumePoints") {
        self.defaults = defaults
        self.key = key
        self.points = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    public var count: Int { points.count }

    public func resumePoint(for key: String) -> TimeInterval? {
        points[key]
    }

    public func setResumePoint(_ position: TimeInterval, for key: String) {
        points[key] = position
        defaults.set(points, forKey: self.key)
    }

    public func resetAll() {
        points = [:]
        defaults.removeObject(forKey: key)
    }
}

// Cancels a scheduled action. Safe to call more than once.
public typealias PlayLogicCancel = @MainActor () -> Void

/**
 * Timer + clock used for the Decision Window. Injected so tests run without real waiting.
 */
@MainActor
public protocol PlayLogicScheduler: AnyObject {
    var now: Date { get }
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> PlayLogicCancel
}

// Real scheduler: wall clock and Task.sleep on the main actor.
@MainActor
public final class TaskScheduler: PlayLogicScheduler {
    public init() {}

    public var now: Date { Date() }

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> PlayLogicCancel {
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            if Task.isCancelled { return }
            action()
        }
        return { task.cancel() }
    }
}
