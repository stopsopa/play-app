# Plan: `PlayLogic` library + `logic_for_play_demo` app

Instructions for the AI implementing this. Read it whole before writing any code.

## 1. Goal

`LOGIC_FOR_PLAY.md` (project root) describes two-button navigation with per-track resume.
It is supposed to work in the app `sanemp3/`, but something there is broken.

We fix that by extracting the logic into **one shared library**, and proving it in a small desktop demo:

1. **`PlayLogic`**: a library implementing `LOGIC_FOR_PLAY.md` exactly. This is the real deliverable.
2. **`logic_for_play_demo/`**: a fresh macOS SwiftUI app (already created, empty template). It exists only to test and demo the library by hand.
3. Later (NOT in this task): `sanemp3/` switches to the same library.

`LOGIC_FOR_PLAY.md` is the source of truth for behaviour. If this plan and that file disagree on behaviour, that file wins. Do not modify it.

## 2. Hard rules

- Follow `AGENTS.md` (no CLI commands, ask before reading files outside the ones listed here, keep it simple).
- **Do not modify anything in `sanemp3/` in this task.** Only read it, to design the library interface.
- No logic from `LOGIC_FOR_PLAY.md` may live in the demo app. The demo only wires UI, keyboard and audio to the library. If the demo needs a rule, the rule belongs in the library.
- No copy of the library anywhere. One set of files, used by both apps (see 3).

## 3. Where the library lives

A local Swift Package at the project root:

```
PlayLogic/
  Package.swift
  Sources/PlayLogic/...
  Tests/PlayLogicTests/...
```

- Both `logic_for_play_demo` and (later) `sanemp3` add it as a **local package dependency** by relative path (`../../PlayLogic` or whatever the path is from each `.xcodeproj`). No copies, no symlinks.
- Platforms in `Package.swift`: set to cover both apps (macOS for the demo, plus whatever `sanemp3` targets; check its project settings).
- Adding the local package to the demo `.xcodeproj`: either edit `project.pbxproj` carefully, or (preferred, safer) give the user the exact clicks: Xcode > File > Add Package Dependencies > Add Local > select `PlayLogic`, add to target `logic_for_play_demo`.

## 4. Step 0: look at `sanemp3` before designing

The library interface must fit `sanemp3`, so that dropping it in there is easy and covers everything that app needs.

Before writing code:

1. Ask the user which files in `sanemp3/` hold: the audio player, the queue/playlist model, the Back/Forward (remote command) handling, the existing resume-position storage, the settings.
2. Read only those.
3. Note down, in a short section at the bottom of this file ("Findings from sanemp3"): how tracks are identified, how the queue is represented, which audio API is used, where the media buttons arrive from (`MPRemoteCommandCenter`, etc.), where settings are stored, and what the library must therefore expose.
4. Adjust the interface sketched in 5 to those findings. The sketch is a starting point, not a contract.

## 5. Library design

### 5.1 Principles

- The core is **pure logic**: no AVFoundation, no SwiftUI, no UIKit/AppKit, no `MPRemoteCommandCenter`. That is what makes it usable from both apps and testable without audio.
- Everything it needs from outside comes through small protocols (audio, storage, timer).
- One instance owns the whole state machine. The host app only forwards events in and renders state out.
- Main-actor only. No background threads, no locks.

### 5.2 Suggested shape

```swift
/** Stable identity of a track. Never an absolute file path (LOGIC_FOR_PLAY.md 7.6). */
public struct TrackID: Hashable, Codable, Sendable { public let rawValue: String }

public struct Track: Identifiable, Hashable, Sendable {
    public let id: TrackID
    public let title: String
    public let url: URL
}

public enum NavButton: Sendable { case back, forward }

public struct PlayLogicSettings: Codable, Equatable, Sendable {
    public var decisionWindow: TimeInterval = 1.6
    public var seekStep: TimeInterval = 3
    public var resumeOnNaturalAdvance: Bool = true
    public var repeatQueue: Bool = false
}

/** What the library needs from an audio player. The host implements it. */
@MainActor public protocol PlaybackEngine: AnyObject {
    var position: TimeInterval { get }
    var duration: TimeInterval { get }
    func load(_ track: Track, at position: TimeInterval, autoplay: Bool)
    func seek(to position: TimeInterval)
    func play()
    func pause()
    /** Host calls this closure when the current track plays to its end. */
    var onTrackEnded: (() -> Void)? { get set }
}

/** Resume Memory (LOGIC_FOR_PLAY.md 1 and 7). nil = never set. */
@MainActor public protocol ResumeStore: AnyObject {
    func resumePoint(for id: TrackID) -> TimeInterval?
    func setResumePoint(_ position: TimeInterval?, for id: TrackID)
    func resetAll()
}

public enum GestureState: Equatable, Sendable { case idle, pending(NavButton), pendingRestart, seeking }

@MainActor public final class PlayLogicController: ObservableObject {
    @Published public private(set) var queue: [Track]
    @Published public private(set) var currentIndex: Int?
    @Published public private(set) var isPlaying: Bool
    @Published public private(set) var gestureState: GestureState
    /** When the current Decision Window closes. nil when idle. For the UI indicator. */
    @Published public private(set) var decisionWindowEndsAt: Date?
    /** Bumped on every Resume Memory change so lists can re-render. */
    @Published public private(set) var resumeRevision: Int
    public var settings: PlayLogicSettings

    public init(engine: PlaybackEngine, store: ResumeStore, settings: PlayLogicSettings, scheduler: Scheduler = .main)

    public func setQueue(_ tracks: [Track], startAt index: Int?)
    public func press(_ button: NavButton)        // Back / Forward
    public func togglePlayPause()
    public func select(index: Int)                // user picked a track from the list
    public func resumePoint(for id: TrackID) -> TimeInterval?
    public func resetAllResumePoints()
}
```

Also ship in the package:

- `UserDefaultsResumeStore`: default `ResumeStore`, one dictionary under one key. Permanent across launches and rebuilds (7.5).
- `Scheduler`: tiny injectable timer abstraction (`schedule(after:_:) -> cancellable`), with a real implementation and a manual one for tests. The Decision Window timer goes only through it.
- Optionally, in a **separate target** of the same package (`PlayLogicAVFoundation`), an `AVPlayerEngine` implementing `PlaybackEngine`. Only if `sanemp3` findings show both apps can share it; otherwise the demo keeps its own small engine.

### 5.3 Behaviour to implement (all from `LOGIC_FOR_PLAY.md`)

- State machine `IDLE -> PENDING -> PENDING_RESTART -> SEEKING` (section 8). There is no Restart Threshold: the position in the track plays no role.
- Single-press action runs when the window expires (section 4), including queue edges: Forward = next track, Back = previous track from any position.
- Double-Forward (exactly two presses, both Forward) restarts the track when the window expires (section 5). Neither press moves anything.
- Seek gesture (section 6): every other gesture with two or more presses. Back gestures seek from the second press, Forward gestures from the third. Each seeking press moves one Seek Step in the direction of that press, each press restarts the window. Clamp at `0` and at the end.
- Resume Point rules 1 to 6 (section 7): save on leave, restore on land, clear on natural end, restart only seeks, permanent, stable key.
- Natural advance obeys `resumeOnNaturalAdvance` (section 2). User actions always resume.
- Any track change cancels the gesture (section 8). Play/pause state is kept across track changes and seeks. The logic works the same while paused.
- A missing Resume Point (`nil`) plays from `0`.
- Changing settings while a gesture is open: new values apply from the next press; do not rebuild a running timer.

### 5.4 Tests

`Tests/PlayLogicTests` with a fake engine, in-memory store and manual scheduler. No real audio, no real waiting. At minimum:

- the whole example timeline from section 9, step by step;
- every example in section 6 (`F,F` = +3; `F,F,F,F` = +9; `B,B,B` = -3; `B,B,B,B` = -6; `F,B` = -3; `B,F` = +3);
- single Back goes to the previous track from any position; `B,B` restarts the track;
- both clamps;
- queue edges (Forward on last, Back on first, with repeat on and off);
- track ends while a Forward is pending: exactly one advance, no double skip;
- natural advance with the setting on and off;
- clear on natural end;
- reset all.

The user runs the tests; ask them to and wait for the output.

## 6. Demo app (`logic_for_play_demo/`)

macOS SwiftUI. Files so far: `logic_for_play_demoApp.swift`, `ContentView.swift`. Add new files next to them; keep it small.

### 6.1 Playlist

- Source: the mp3 files in `World Of Goo Soundtrack (mp3)/` at the project root, sorted by file name.
- The app is sandboxed by default, so it cannot just read that folder. Use a **"Choose folder"** button (`NSOpenPanel`), store a security-scoped bookmark, and reopen it on launch. First launch shows an empty list with that button. (Requires "User Selected File: Read Only" in the target's sandbox capabilities; tell the user the exact click if it has to be done in Xcode.)
- `TrackID` = chosen folder name + path relative to that folder. Never the absolute path.

### 6.2 Audio

A small `PlaybackEngine` implementation over `AVPlayer` or `AVAudioPlayer`. It reports end-of-track through `onTrackEnded`. Nothing clever in it.

### 6.3 Keyboard

| Key | Action |
| --- | --- |
| Left arrow | `press(.back)` |
| Right arrow | `press(.forward)` |
| Space | `togglePlayPause()` |

Keys must work whenever the window is active, regardless of which control has focus (a text field being edited is the only exception). Key auto-repeat from holding a key down must be ignored: one physical push = one Press.

### 6.4 Layout, top to bottom

1. **Decision Window indicator**, always at the top of the view. Clearly inactive when idle. When active: visibly lit, shows the state (`PENDING back` / `PENDING forward` / `PENDING restart` / `SEEKING`) and a bar that drains over the remaining window time, restarting on every press. Driven by `gestureState` and `decisionWindowEndsAt`.
2. **Settings / controls row**:
   - Decision Window (seconds, numeric)
   - Seek Step (seconds, numeric)
   - "Resume when a track starts on its own" (toggle)
   - **"Reset all Resume Points"** (button)
   - "Choose folder" (button)
   - Play/Pause, Back, Forward buttons too (same calls as the keys), handy for mouse testing.

   Settings changes apply immediately and are persisted across launches.
3. **Track table**, one row per track, two columns:
   - **Track column: name and progress bar are one element.** The track name is drawn on top of the progress bar that fills the whole cell.
     - Default row: white background, dark gray text.
     - Row of the current track: background slightly darker than white (a very light gray), still clearly "almost white".
     - On the current row, the part from the left edge up to `position / duration` is **inverted**: dark gray background, white text. The split cuts through the letters, so a letter half way across the edge is half white, half dark gray. (Draw the label twice, normal and inverted, and mask the inverted one to the progress width.)
     - Progress updates smoothly while playing (several times a second is enough) and immediately on seek.
   - **Resume Point column** (right): the current stored Resume Point of that track, always shown, for every track, updated live whenever it changes. Show `null` when nothing is stored for that track. Format `m:ss`. Note a stored `0` (after natural end) is shown as `0:00`, not `null`; `null` appears only for tracks never saved and after "Reset all Resume Points".
   - **Clicking a row** calls `select(index:)`: switches to that track, starting from its Resume Point, or from the start when it has none. The track being left gets its position saved (rule 7.1). This is all done by the library, the row only makes the call.

### 6.5 `data-testid` equivalent

Give every interactive element and every row a unique `accessibilityIdentifier` (rows: based on track id). Same purpose as `data-testid` in the web parts of this project.

## 7. Order of work

1. Step 0 (section 4): read the agreed `sanemp3` files, write the findings, adjust the interface.
2. Create the `PlayLogic` package: types, protocols, controller, `UserDefaultsResumeStore`, scheduler.
3. Write the tests. Ask the user to run them. Fix until green.
4. Wire the package into the demo project.
5. Build the demo: engine, folder picker, keyboard, indicator, settings row, table.
6. Give the user a short manual test checklist that follows `LOGIC_FOR_PLAY.md` section 9.
7. Stop. Integration into `sanemp3` is a separate task. Finish by listing, in "Findings from sanemp3", what will have to change there to adopt the library.

## 8. Done when

- All package tests pass.
- In the demo, the section 9 timeline can be reproduced by hand with the arrow keys, and the indicator, the inverted progress and the Resume Point column show what is happening at every step.
- Resume Points survive quitting and relaunching the demo, and vanish only on "Reset all Resume Points".
- The demo contains no navigation/resume logic of its own.
- `sanemp3/` is untouched.

## Status

Implemented: `PlayLogic/` package (with tests) and the demo app. The transport buttons (Back / Play-Pause / Forward) and the PLAYING / PAUSED indicator sit at the bottom of the demo window. `sanemp3/` is untouched.

Final library interface differs slightly from the sketch in 5.2: tracks are `PlayTrack { key, title, url }` (`key` is the stable identity), repeat is `RepeatMode { off, all, one }`, and `select(index:)` always starts playback.

## Findings from sanemp3

All playback code is in `sanemp3/sanemp3/AppState.swift` (`@MainActor final class AppState: ObservableObject`, one `AVPlayer`). iOS only, target deployment 16.6, Swift 5, default MainActor isolation, no package dependencies yet.

Bugs found there, all of which the library avoids by design:

1. A finished track gets a Resume Point at its end: the end observer clears it, then `nextTrack()` saves `currentTime` again. Next visit ends immediately.
2. Pending taps are not cancelled on track change (natural end, `playQueue`, `load`): double skip, or a skip after the user picked a track.
3. `savedResetPosition` ("Restore") survives a track change and seeks the new track to the old position.
4. No `UIBackgroundModes` audio entry found in build settings: background playback, remote commands and the window timer can stop when the app is suspended. Check the generated Info.plist.
5. `seekForwardCommand` / `seekBackwardCommand` send begin and end events; both are counted as presses.
6. `currentTime` can be overwritten by a stale periodic-observer value during fast multi-press seeking, losing steps.
7. Resume Points are keyed by absolute path (`url.path`), and saved only when `currentTime > 5`.
8. On-screen buttons bypass the multi-tap logic; `repeatMode = .off` is ignored (always wraps).
9. Seek Step (3), Restart Threshold (5) and resume-on-natural-advance are hardcoded, not settings.

What adopting the library will need in `sanemp3` (separate task):

- Add `PlayLogic` as a local package (`../PlayLogic` relative to `sanemp3.xcodeproj`).
- Wrap the `AVPlayer` in a `PlaybackEngine`. `position` must return the pending seek target until the seek lands (fixes 6). Report end of track only for the current item, observing that item instead of `object: nil`.
- Map `AudioTrack` to `PlayTrack` with `key` = folder name + path inside the folder (fixes 7). Old path-keyed positions are dropped or migrated.
- Route `nextTrackCommand` / `previousTrackCommand` and the on-screen buttons to `press(.forward)` / `press(.back)`. Do not route the seek commands, or handle only their begin event (fixes 5, 8).
- Replace `playQueue` with `setQueue(_:startAt:play:)`, list taps with `select(index:)`, the scrubber with `seek(to:)`.
- Remove `forwardClickCount`, tap tasks, `savedResetPosition`, `savedTrackPositions` and `nextTrack` / `previousTrack` (fixes 1, 2, 3).
- Call `saveCurrentResumePoint()` when the app goes to background.
- Map `multiTapInterval` to `settings.decisionWindow`; add settings UI for Seek Step and "Resume when a track starts on its own". The hardcoded 5 s restart threshold goes away: single Back = previous track, Double-Forward = restart.
- Add the audio background mode (fixes 4). The library also resolves a late timer on the next press.
