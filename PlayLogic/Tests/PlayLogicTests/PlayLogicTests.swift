import XCTest
@testable import PlayLogic

// Audio player stand-in: position only moves when the test says so.
@MainActor
final class FakeEngine: PlaybackEngine {
    var position: TimeInterval = 0
    var duration: TimeInterval = 300
    var playing = false
    var loaded: PlayTrack?
    var onTrackEnded: (@MainActor () -> Void)?

    func load(_ track: PlayTrack, at position: TimeInterval, autoplay: Bool) {
        loaded = track
        self.position = position
        playing = autoplay
    }

    func seek(to position: TimeInterval) { self.position = position }
    func play() { playing = true }
    func pause() { playing = false }
}

@MainActor
final class MemoryStore: ResumeStore {
    var points: [String: TimeInterval] = [:]
    var count: Int { points.count }
    func resumePoint(for key: String) -> TimeInterval? { points[key] }
    func setResumePoint(_ position: TimeInterval, for key: String) { points[key] = position }
    func resetAll() { points = [:] }
}

// Clock that only moves when the test advances it.
@MainActor
final class ManualScheduler: PlayLogicScheduler {
    private struct Item {
        let id: Int
        let fireAt: Date
        let action: @MainActor () -> Void
    }

    var now = Date(timeIntervalSince1970: 0)
    private var items: [Item] = []
    private var nextID = 0

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> PlayLogicCancel {
        let id = nextID
        nextID += 1
        items.append(Item(id: id, fireAt: now.addingTimeInterval(delay), action: action))
        return { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    // Moves the clock and fires every timer that became due, in order.
    func advance(by seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let item = items.filter({ $0.fireAt <= target }).min(by: { $0.fireAt < $1.fireAt }) {
            items.removeAll { $0.id == item.id }
            now = item.fireAt
            item.action()
        }
        now = target
    }

    // Moves the clock WITHOUT firing timers: simulates a suspended app.
    func skip(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/**
 * Everything one test needs: controller with fake engine, store and clock.
 * Queue is A, B, C. `tick` lets time pass: the track plays (when playing), then timers fire.
 */
@MainActor
final class Rig {
    let engine = FakeEngine()
    let store = MemoryStore()
    let scheduler = ManualScheduler()
    let logic: PlayLogicController
    let tracks = ["A", "B", "C"].map {
        PlayTrack(key: "folder/\($0).mp3", title: $0, url: URL(fileURLWithPath: "/tmp/\($0).mp3"))
    }

    init(startAt index: Int = 0, play: Bool = true, position: TimeInterval = 0) {
        logic = PlayLogicController(engine: engine, store: store, scheduler: scheduler)
        logic.setQueue(tracks, startAt: index, play: play)
        engine.position = position
    }

    func tick(_ seconds: TimeInterval) {
        if engine.playing {
            engine.position += seconds
        }
        scheduler.advance(by: seconds)
    }

    func resume(_ index: Int) -> TimeInterval? {
        store.points[tracks[index].key]
    }

    // Presses given buttons one second apart.
    func presses(_ buttons: [NavButton]) {
        for (i, button) in buttons.enumerated() {
            if i > 0 { tick(1) }
            logic.press(button)
        }
    }
}

@MainActor
final class PlayLogicTests: XCTestCase {

    // LOGIC_FOR_PLAY.md section 9, step by step.
    func testExampleTimeline() {
        let r = Rig()

        let accuracy = 0.001

        // 1:00 Forward, 1:01.6 window expires
        r.tick(60)
        r.logic.press(.forward)
        XCTAssertEqual(r.logic.gestureState, .pending(.forward))
        r.tick(1.6)
        XCTAssertEqual(r.resume(0) ?? -1, 61.6, accuracy: accuracy)
        XCTAssertEqual(r.logic.currentIndex, 1)
        XCTAssertEqual(r.engine.position, 0)

        // 1:10 Back (B at 0:08.4), 1:11.6 window expires
        r.tick(8.4)
        r.logic.press(.back)
        r.tick(1.6)
        XCTAssertEqual(r.resume(1) ?? -1, 10, accuracy: accuracy)
        XCTAssertEqual(r.logic.currentIndex, 0)
        XCTAssertEqual(r.engine.position, 61.6, accuracy: accuracy)

        // 1:20 Back (A at 1:10), 1:21 Back, 1:22 Back, 1:23 Back, 1:24.6 window expires
        r.tick(8.4)
        r.logic.press(.back)
        XCTAssertEqual(r.engine.position, 70, accuracy: accuracy)
        r.tick(1)
        r.logic.press(.back)
        XCTAssertEqual(r.logic.gestureState, .pendingRestart)
        XCTAssertEqual(r.engine.position, 71, accuracy: accuracy)
        r.tick(1)
        r.logic.press(.back)
        XCTAssertEqual(r.logic.gestureState, .seeking)
        XCTAssertEqual(r.engine.position, 69, accuracy: accuracy)
        r.tick(1)
        r.logic.press(.back)
        XCTAssertEqual(r.engine.position, 67, accuracy: accuracy)
        r.tick(1.6)
        XCTAssertEqual(r.logic.gestureState, .idle)
        XCTAssertEqual(r.logic.currentIndex, 0)
        XCTAssertEqual(r.engine.position, 68.6, accuracy: accuracy)

        // 1:30 Back (A at 1:14), 1:31 Back, 1:32.6 window expires
        r.tick(5.4)
        r.logic.press(.back)
        XCTAssertEqual(r.engine.position, 74, accuracy: accuracy)
        r.tick(1)
        r.logic.press(.back)
        r.tick(1.6)
        XCTAssertEqual(r.logic.currentIndex, 0)
        XCTAssertEqual(r.engine.position, 0)
        XCTAssertTrue(r.engine.playing)
    }

    // Section 6 examples. Paused, so only the seeks move the position.
    func testSeekExamples() {
        let cases: [([NavButton], TimeInterval)] = [
            ([.forward, .forward], 103),
            ([.forward, .forward, .forward, .forward], 109),
            ([.back, .back, .back], 97),
            ([.back, .back, .back, .back], 94),
            ([.forward, .back], 97),
            ([.back, .forward], 103),
            ([.back, .back, .forward], 103),
        ]
        for (buttons, expected) in cases {
            let r = Rig(startAt: 1, play: false, position: 100)
            r.presses(buttons)
            XCTAssertEqual(r.engine.position, expected)
            r.tick(5)
            XCTAssertEqual(r.logic.gestureState, .idle)
            XCTAssertEqual(r.logic.currentIndex, 1)
            XCTAssertEqual(r.engine.position, expected)
        }
    }

    func testSeekBackClampsAtZeroAndStaysOnTrack() {
        let r = Rig(startAt: 1, play: false, position: 2)
        r.presses([.back, .back, .back])
        r.tick(5)
        XCTAssertEqual(r.engine.position, 0)
        XCTAssertEqual(r.logic.currentIndex, 1)
    }

    func testSeekPastEndFinishesTrack() {
        let r = Rig(startAt: 0, play: false, position: 299)
        r.presses([.forward, .forward])
        XCTAssertEqual(r.logic.currentIndex, 1)
        XCTAssertEqual(r.resume(0), 0)
        XCTAssertEqual(r.logic.gestureState, .idle)
    }

    func testForwardOnLastTrack() {
        let off = Rig(startAt: 2, play: false, position: 50)
        off.logic.press(.forward)
        off.tick(5)
        XCTAssertEqual(off.logic.currentIndex, 2)
        XCTAssertEqual(off.engine.position, 50)

        let all = Rig(startAt: 2, play: false, position: 50)
        all.logic.settings.repeatMode = .all
        all.logic.press(.forward)
        all.tick(5)
        XCTAssertEqual(all.logic.currentIndex, 0)
        XCTAssertEqual(all.resume(2), 50)
    }

    func testSingleBackOnFirstTrackRestarts() {
        let r = Rig(startAt: 0, play: false, position: 50)
        r.logic.press(.back)
        r.tick(5)
        XCTAssertEqual(r.logic.currentIndex, 0)
        XCTAssertEqual(r.engine.position, 0)
    }

    // Single Back leaves the track no matter how far into it we are.
    func testSingleBackGoesToPreviousFromAnyPosition() {
        let r = Rig(startAt: 1, play: false, position: 100)
        r.logic.press(.back)
        r.tick(5)
        XCTAssertEqual(r.logic.currentIndex, 0)
        XCTAssertEqual(r.resume(1), 100)
    }

    // Exactly two Backs: nothing moves until the window expires, then the track restarts.
    func testDoubleBackRestartsTrack() {
        let r = Rig(startAt: 1, play: false, position: 100)
        r.presses([.back, .back])
        XCTAssertEqual(r.logic.gestureState, .pendingRestart)
        XCTAssertEqual(r.engine.position, 100)
        r.tick(5)
        XCTAssertEqual(r.logic.gestureState, .idle)
        XCTAssertEqual(r.logic.currentIndex, 1)
        XCTAssertEqual(r.engine.position, 0)
        // Restart only seeks, the Resume Point is not touched.
        XCTAssertNil(r.resume(1))
    }

    func testTrackEndWhileForwardPendingAdvancesOnce() {
        let r = Rig()
        r.logic.press(.forward)
        r.tick(1)
        r.engine.onTrackEnded?()
        XCTAssertEqual(r.logic.currentIndex, 1)
        XCTAssertEqual(r.logic.gestureState, .idle)
        r.tick(10)
        XCTAssertEqual(r.logic.currentIndex, 1)
    }

    func testNaturalAdvanceResumeSetting() {
        let on = Rig()
        on.store.points[on.tracks[1].key] = 50
        on.engine.onTrackEnded?()
        XCTAssertEqual(on.logic.currentIndex, 1)
        XCTAssertEqual(on.engine.position, 50)

        let off = Rig()
        off.logic.settings.resumeOnNaturalAdvance = false
        off.store.points[off.tracks[1].key] = 50
        off.engine.onTrackEnded?()
        XCTAssertEqual(off.logic.currentIndex, 1)
        XCTAssertEqual(off.engine.position, 0)
        XCTAssertEqual(off.resume(1), 50)
    }

    func testNaturalEndClearsResumePoint() {
        let r = Rig()
        r.store.points[r.tracks[0].key] = 30
        r.engine.onTrackEnded?()
        XCTAssertEqual(r.resume(0), 0)
    }

    func testEndOfQueueStopsOrWraps() {
        let off = Rig(startAt: 2)
        off.engine.onTrackEnded?()
        XCTAssertEqual(off.logic.currentIndex, 2)
        XCTAssertFalse(off.logic.isPlaying)
        XCTAssertFalse(off.engine.playing)

        let all = Rig(startAt: 2)
        all.logic.settings.repeatMode = .all
        all.engine.onTrackEnded?()
        XCTAssertEqual(all.logic.currentIndex, 0)
        XCTAssertTrue(all.engine.playing)

        let one = Rig(startAt: 1, position: 200)
        one.logic.settings.repeatMode = .one
        one.engine.onTrackEnded?()
        XCTAssertEqual(one.logic.currentIndex, 1)
        XCTAssertEqual(one.engine.position, 0)
        XCTAssertTrue(one.engine.playing)
    }

    func testResetAll() {
        let r = Rig()
        r.tick(20)
        r.logic.select(index: 1)
        XCTAssertEqual(r.resume(0), 20)
        r.logic.resetAllResumePoints()
        XCTAssertNil(r.logic.resumePoint(for: r.tracks[0].key))
        XCTAssertEqual(r.logic.resumePointCount, 0)
    }

    func testSelectSavesLeavingTrackAndResumesPickedOne() {
        let r = Rig(startAt: 0, play: false, position: 40)
        r.store.points[r.tracks[2].key] = 90
        r.logic.press(.forward)
        r.logic.select(index: 2)
        XCTAssertEqual(r.resume(0), 40)
        XCTAssertEqual(r.logic.currentIndex, 2)
        XCTAssertEqual(r.engine.position, 90)
        XCTAssertTrue(r.engine.playing)
        // The pending Forward was cancelled by the track change.
        XCTAssertEqual(r.logic.gestureState, .idle)
        r.tick(10)
        XCTAssertEqual(r.logic.currentIndex, 2)

        // A track with no Resume Point starts from 0.
        r.logic.select(index: 1)
        XCTAssertEqual(r.engine.position, 0)
    }

    func testPausedStateIsKeptAcrossTrackChange() {
        let r = Rig(startAt: 0, play: false, position: 10)
        r.logic.press(.forward)
        r.tick(5)
        XCTAssertEqual(r.logic.currentIndex, 1)
        XCTAssertFalse(r.engine.playing)
        XCTAssertFalse(r.logic.isPlaying)
    }

    // Timer did not fire (app suspended). The next press must not become a seek.
    func testLateTimerIsResolvedByTheNextPress() {
        let r = Rig(startAt: 0, play: false, position: 10)
        r.logic.press(.forward)
        r.scheduler.skip(by: 10)
        r.logic.press(.forward)
        XCTAssertEqual(r.logic.currentIndex, 1)
        XCTAssertEqual(r.logic.gestureState, .pending(.forward))
    }

    // New settings apply from the next press; the running window keeps its length.
    func testSettingsChangeDuringGesture() {
        let r = Rig(startAt: 1, play: false, position: 100)
        r.logic.press(.forward)
        r.logic.settings.seekStep = 10
        r.logic.settings.decisionWindow = 1
        r.tick(1.5)
        XCTAssertEqual(r.logic.gestureState, .pending(.forward))
        r.logic.press(.forward)
        XCTAssertEqual(r.engine.position, 110)
        r.tick(1)
        XCTAssertEqual(r.logic.gestureState, .idle)
    }
}
