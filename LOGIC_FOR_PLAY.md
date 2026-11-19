# Logic for play: two-button navigation with per-track resume

How the player moves through a list of tracks using only two media buttons, **Back** and **Forward**.
The same two buttons do both jobs: changing track and seeking inside a track.

## 1. Terms

| Term | Meaning |
| --- | --- |
| **Track** | One song on the list. |
| **Queue** | The ordered list of tracks currently being played (playlist, album, folder...). |
| **Resume Point** | Saved playback position of one track. Every track has its own. Starts at `0`. (This is the "ME" from the original description.) |
| **Resume Memory** | Storage of all Resume Points, keyed by track id. |
| **Press** | One push of Back or Forward. |
| **Gesture** | A burst of presses where each press comes within the Decision Window of the one before. |
| **Single-press gesture** | A gesture with exactly one press. Means "change track" (or "restart track"). |
| **Multi-press gesture** | A gesture with two or more presses. Means "seek inside the track". |

## 2. Settings

| Setting | Default | What it controls |
| --- | --- | --- |
| **Decision Window** | 1.6 s | How long we wait after a press for another press. No further press = the gesture is over. |
| **Seek Step** | 3 s | How far one seeking press moves the position. |
| **Restart Threshold** | 3 s | Single Back at or below this position goes to the previous track; above it restarts the current track. |
| **Resume when a track starts on its own** | on | See below. |
| **Reset all Resume Points** | button | Forgets the saved position of every track in the app. Every track starts from the beginning next time. |

**Resume when a track starts on its own** decides what happens when the previous track plays to its end and the player moves to the next one by itself, with no button pressed:

- **On:** the next track continues from where you last left it.
- **Off:** the next track starts from the beginning. Its saved position is kept, and is still used when you reach that track with Back, Forward or by picking it from a list.

Suggested text for the settings screen:

> **Resume when a track starts on its own**
> When one track ends and the next starts automatically, continue it from where you last stopped listening. Turn off to always start it from the beginning. Tracks you switch to yourself always continue from where you stopped.

Decision Window and Seek Step are separate on purpose: one is "how long do I have to press again",
the other is "how far does a press move". They are different things and want different values (1.6 s and 3 s).

Restart Threshold can simply reuse the Decision Window value if one setting less is preferred.
It is listed separately because the Decision Window is also the delay before a track change happens (see 8),
so it may end up shortened, and the threshold should not shrink with it.

## 3. Natural playback

- A track plays to its end, then the next track in the Queue starts.
- At the end of the last track playback stops (or wraps to the first track if repeat is on).

## 4. Single-press gesture (change track)

A press arrives and no other press follows within the Decision Window.
The action runs **when the window expires**, not at the moment of the press. The track keeps playing while we wait.
This delay is accepted: it is the natural price of one button doing two jobs.

| Button | Position at the moment of the press | Action |
| --- | --- | --- |
| Forward | any | Go to the **next** track. |
| Back | at or below Restart Threshold | Go to the **previous** track. |
| Back | above Restart Threshold | **Restart** the current track (seek to `0`). |

Edges of the Queue:

- Forward on the last track: nothing (or wrap to first if repeat is on).
- Back on the first track, at or below the threshold: restart the current track.

## 5. Multi-press gesture (seek)

A second press arrives within the Decision Window of the first one. From now on the gesture is a seek and will never change track.

- The **first press** moves nothing. It only opens the gesture.
- The **second press** turns the gesture into a seek and moves the position by one Seek Step (not two).
- **Every press after it** moves one more Seek Step.
- Each press moves in the direction of **that** press.
- Every press restarts the Decision Window.
- The gesture ends when the window expires with no new press. Nothing else happens then.

Examples (Seek Step 3 s):

- Forward, Forward = +3 s
- Forward, Forward, Forward, Forward = +9 s
- Back, Back, Back = -6 s
- Forward, Back = -3 s (direction of the first press does not matter once there is a second one)

Clamping:

- Seeking back below `0` stops at `0`. It does not jump to the previous track.
- Seeking forward past the end lands on the end, the track finishes, and natural playback takes over.

## 6. Resume Point rules

1. **Save on leave.** Every time we leave a track for any reason (next, previous, picking another track from the list), the current position is saved as that track's Resume Point.
2. **Restore on land.** Every time we land on a track through a user action (Back, Forward, picking it from a list), it starts from its Resume Point. When we land on it because the previous track ended, the setting "Resume when a track starts on its own" decides: on = Resume Point, off = `0`.
3. **Clear on natural end.** When a track plays to its end, its Resume Point is reset to `0`. Otherwise returning to it would land at the end and finish immediately.
4. Restarting a track (single Back above the threshold) only seeks to `0`. The Resume Point is rewritten later, by rule 1, when we leave.
5. **Resume Points are permanent.** They are stored on the device and survive closing the app, restarting the phone and rebuilding the app from Xcode. They are removed only by "Reset all Resume Points" in settings (or by deleting the app).
6. **Stable key.** A Resume Point is stored under an identity of the track that does not change between launches or rebuilds (for example folder plus path inside the folder), never under the absolute file path, which can change.

Consequence worth knowing: after landing on a track at, say, `2:00`, the first single Back restarts it (position is above the threshold), and the second single Back goes to the previous track.

## 7. State machine

```
            press                      press (seek one step, restart timer)
  IDLE ------------> PENDING ------------------------------> SEEKING <--+
   ^                    |                                       |  |    |
   |                    | timer expires:                        |  +----+
   |                    | run single-press action               |  press (seek one step, restart timer)
   +--------------------+                                       |
   +------------------------------------------------------------+
                          timer expires: do nothing
```

- `PENDING` remembers the button and the position at the moment of the press.
- The timer is the Decision Window.
- **Any track change cancels the gesture** and returns to `IDLE` (track ended naturally, user picked a track from the list). This prevents a double skip when a track ends while a Forward press is still pending.
- The same logic applies when playback is paused. Play/pause state is kept across track changes and seeks.

## 8. Example timeline

Queue: A, B, C. All three settings as in the table above.

| Time | Event | Result |
| --- | --- | --- |
| 0:00 | A starts | A plays from 0:00 |
| 1:00 | Forward | pending |
| 1:01.6 | window expires | A's Resume Point = 1:01.6, B starts at 0:00 |
| 1:03 | Back (B at 0:01.4) | pending, position 0:01.4 remembered |
| 1:04.6 | window expires | 0:01.4 is below threshold: B's Resume Point = 0:03, A starts at **1:01.6** |
| 1:10 | Back (A at 1:07) | pending |
| 1:11 | Back | seek: A to 1:05 (1:08 - 0:03) |
| 1:12 | Back | seek: A to 1:03 (1:06 - 0:03) |
| 1:13.6 | window expires | gesture over, A keeps playing (now at 1:04.6) |
| 1:20 | Back (A at 1:11) | pending |
| 1:21.6 | window expires | above threshold: A restarts from 0:00 |

## 9. Decisions taken

1. **Track change is delayed by the whole Decision Window.** Accepted as is.
2. **The second press seeks one Seek Step.** The first press only opens the gesture.
3. **Resume Points are permanent**, with a "Reset all Resume Points" button in settings.
4. **Resume on natural advance is a setting**, "Resume when a track starts on its own", on by default.
