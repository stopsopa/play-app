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
| **Single-press gesture** | A gesture with exactly one press. Means "change track". |
| **Double-Forward gesture** | A gesture with exactly two presses, both Forward. Means "restart the current track". |
| **Seek gesture** | Any other gesture with two or more presses. Means "seek inside the track". |

## 2. Settings

| Setting | Default | What it controls |
| --- | --- | --- |
| **Decision Window** | 1.6 s | How long we wait after a press for another press. No further press = the gesture is over. |
| **Seek Step** | 3 s | How far one seeking press moves the position. |
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

There is no Restart Threshold any more: what a gesture does depends only on the presses in it, never on the position in the track.

## 3. Natural playback

- A track plays to its end, then the next track in the Queue starts.
- At the end of the last track playback stops (or wraps to the first track if repeat is on).

## 4. Single-press gesture (change track)

A press arrives and no other press follows within the Decision Window.
The action runs **when the window expires**, not at the moment of the press. The track keeps playing while we wait.
This delay is accepted: it is the natural price of one button doing several jobs.

| Button | Action |
| --- | --- |
| Forward | Go to the **next** track. |
| Back | Go to the **previous** track, from any position in the current track. |

Edges of the Queue:

- Forward on the last track: nothing (or wrap to first if repeat is on).
- Back on the first track: restart the current track (seek to `0`).

## 5. Double-Forward gesture (restart track)

Exactly two presses, both Forward, and no third press within the Decision Window.

- Neither press moves anything.
- When the window expires, the current track **restarts** (seek to `0`).
- Like the single press, the action is delayed: we have to wait to know that no third press is coming.

## 6. Seek gesture

Every gesture with two or more presses, except the Double-Forward. Once a gesture has become a seek it will never change or restart the track.

How a gesture becomes a seek:

| Presses so far | Next press | Result |
| --- | --- | --- |
| Back | Back | seek back one Seek Step |
| Back | Forward | seek forward one Seek Step |
| Forward | Back | seek back one Seek Step |
| Forward | Forward | nothing yet: this is a Double-Forward so far |
| Forward, Forward | Forward | seek forward one Seek Step |
| Forward, Forward | Back | seek back one Seek Step |

From then on:

- **Every further press** moves one more Seek Step.
- Each press moves in the direction of **that** press.
- Every press restarts the Decision Window.
- The gesture ends when the window expires with no new press. Nothing else happens then.

Examples (Seek Step 3 s):

- Back, Back = -3 s
- Back, Back, Back, Back = -9 s
- Forward, Forward = restart the track (Double-Forward, not a seek)
- Forward, Forward, Forward = +3 s
- Forward, Forward, Forward, Forward = +6 s
- Forward, Back = -3 s
- Back, Forward = +3 s

Clamping:

- Seeking back below `0` stops at `0`. It does not jump to the previous track.
- Seeking forward past the end lands on the end, the track finishes, and natural playback takes over.

## 7. Resume Point rules

1. **Save on leave.** Every time we leave a track for any reason (next, previous, picking another track from the list), the current position is saved as that track's Resume Point.
2. **Restore on land.** Every time we land on a track through a user action (Back, Forward, picking it from a list), it starts from its Resume Point. When we land on it because the previous track ended, the setting "Resume when a track starts on its own" decides: on = Resume Point, off = `0`.
3. **Clear on natural end.** When a track plays to its end, its Resume Point is reset to `0`. Otherwise returning to it would land at the end and finish immediately.
4. Restarting a track (Double-Forward) only seeks to `0`. The Resume Point is rewritten later, by rule 1, when we leave.
5. **Resume Points are permanent.** They are stored on the device and survive closing the app, restarting the phone and rebuilding the app from Xcode. They are removed only by "Reset all Resume Points" in settings (or by deleting the app).
6. **Stable key.** A Resume Point is stored under an identity of the track that does not change between launches or rebuilds (for example folder plus path inside the folder), never under the absolute file path, which can change.

Consequence worth knowing: a single Back always leaves the track, even in the middle of it. The position is not lost, it is saved as the Resume Point (rule 1), so a single Forward brings you back to the same spot.

## 8. State machine

```
           press            Forward after Forward             press
  IDLE ----------> PENDING -------------------> PENDING_RESTART ------+
   ^                 |  |                              |              |
   |                 |  | any other second press       |              v
   |                 |  +------------------------------|---------> SEEKING <--+
   |                 |    (seek one step)              |  (seek      |  |     |
   |                 |                                 |  one step)  |  +-----+
   |  timer expires: |                 timer expires:  |             |  press (seek one step)
   |  change track   |                 restart track   |             |
   +-----------------+---------------------------------+-------------+
                                                         timer expires: do nothing
```

- `PENDING` remembers the button.
- `PENDING_RESTART` means "two Forwards so far".
- Every press restarts the timer. The timer is the Decision Window.
- **Any track change cancels the gesture** and returns to `IDLE` (track ended naturally, user picked a track from the list). This prevents a double skip when a track ends while a Forward press is still pending.
- The same logic applies when playback is paused. Play/pause state is kept across track changes and seeks.

## 9. Example timeline

Queue: A, B, C. All settings as in the table above.

| Time | Event | Result |
| --- | --- | --- |
| 0:00 | A starts | A plays from 0:00 |
| 1:00 | Forward | pending |
| 1:01.6 | window expires | A's Resume Point = 1:01.6, B starts at 0:00 |
| 1:10 | Back (B at 0:08.4) | pending |
| 1:11.6 | window expires | single Back: B's Resume Point = 0:10, A starts at **1:01.6** |
| 1:20 | Back (A at 1:10) | pending |
| 1:21 | Back | second press, now a seek: A to 1:08 (1:11 - 0:03) |
| 1:22 | Back | seek: A to 1:06 (1:09 - 0:03) |
| 1:23.6 | window expires | gesture over, A keeps playing (now at 1:07.6) |
| 1:30 | Forward (A at 1:14) | pending |
| 1:31 | Forward | two Forwards: pending restart, nothing moves yet |
| 1:32.6 | window expires | exactly two Forwards: A restarts from 0:00 |

## 10. Decisions taken

1. **Track change is delayed by the whole Decision Window.** Accepted as is.
2. **Single Back always goes to the previous track.** Restarting a track is a Double-Forward. The position in the track plays no role, so there is no Restart Threshold.
3. **Back: the second press seeks one Seek Step.** The first press only opens the gesture.
4. **Forward: the third press seeks one Seek Step.** The first two presses move nothing.
5. **Resume Points are permanent**, with a "Reset all Resume Points" button in settings.
6. **Resume on natural advance is a setting**, "Resume when a track starts on its own", on by default.
