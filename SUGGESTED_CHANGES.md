# Suggested changes for `sanemp3`

Based on reading these seven files only, nothing was built or run:
`AppState.swift`, `ContentView.swift`, `FolderView.swift`, `Models.swift`, `PlayerViews.swift`, `PlaylistsView.swift`, `sanemp3App.swift`.

Not seen: `SettingsView`, `applyLockScreenOverlay()` and `trackUserTouches()` are used in `ContentView.swift` but defined in none of the files above, and the Xcode project settings (Info.plist, background modes) were not checked.

Terms like Resume Point, Decision Window, Seek Step and Restart Threshold come from `LOGIC_FOR_PLAY.md`.

## A. Why playback jams (fix these first)

### A1. A finished track gets its end position saved as its Resume Point

`AppState.swift:681-686` and `AppState.swift:379`

When a track plays to its end, the handler removes its saved position and then calls `nextTrack()`.
`nextTrack()` starts with `saveCurrentTrackPosition()`, which stores the current time again, and that time is now the end of the track.

Result: every track that finished naturally is remembered as "resume at the very end".
The next time the player lands on it, it starts a fraction of a second before the end and finishes at once.
Because `nextTrack()` always wraps to the first track, the second pass through a queue becomes a silent, endless run through all tracks. Going Back onto a finished track does the same.

This is the most likely cause of "the app stops playing".

Fix: give natural end its own path that clears the Resume Point and moves on without saving. Only user navigation should save.

### A2. A track that fails to load stops everything silently

`AppState.swift:240-284`

Nothing watches for a failed item. If a file is missing, not downloaded, or not readable, the player sits there with `isPlaying == true` and no end-of-track event ever comes.

Fix: observe `AVPlayerItem.status` (`.failed`), `AVPlayerItemFailedToPlayToEndTime` and `AVPlayerItemPlaybackStalled`. On failure skip to the next track and show which file failed.

### A3. Only one folder is accessible at a time

`AppState.swift:123-127`

`openFolder` stops security-scoped access to the previous folder. A queue still playing from that folder cannot load its next track (and then A2 makes it silent).
The same happens with playlists that mix tracks from several folders, and with the queue restored at launch when it belongs to a folder other than the last opened one.

Related: `AudioTrack.bookmarkData` is created (`Models.swift:114`) but never used. Tracks are opened by their stored `url`, which can go stale between launches.

Fix: keep access open for every folder that has tracks in the queue (resolve the folder bookmark, start access, stop only when nothing uses it). Check the result of `startAccessingSecurityScopedResource()` and the `stale` flag (`AppState.swift:126`, `AppState.swift:143-144`), both ignored now.

### A4. Seeking forward past the end can leave the player stuck at the end

`AppState.swift:320-323`

`seek` clamps to exactly `duration`. Seeking to the exact end does not reliably produce the end-of-track event.

Fix: if the target is at or past the end, run the natural-end path directly instead of seeking.

### A5. End-of-track handler listens to every player item

`AppState.swift:678`

The observer is registered with `object: nil` and hops through a `Task`. By the time it runs, the current track may already be a different one (user pressed Forward at the same moment), so the wrong track's position is cleared and a second skip happens.

Fix: ignore the notification unless its object is `player.currentItem`.

### A6. `isPlaying` is a hand-kept flag

`AppState.swift:268-270`, `AppState.swift:297-299`

`try? setActive(true)` can fail (for example during a call) and the flag still becomes `true`. When headphones are unplugged the system pauses the player and the flag stays `true`, so the play button then does the wrong thing.

Fix: derive `isPlaying` from `player.timeControlStatus`. That also makes stalls visible.

## B. Navigation logic compared with `LOGIC_FOR_PLAY.md`

| # | Where | Now | Should be |
| --- | --- | --- | --- |
| B1 | `AppState.swift:232-238` | Picking a track from a list does not save the Resume Point of the track being left, and the picked track always starts at 0. | Save on leave and restore on land, by any route. |
| B2 | `AppState.swift:360-366` | Position is saved only when above 5 s, so leaving a track early keeps an old, stale Resume Point. | Always save on leave. |
| B3 | `AppState.swift:584-586`, `AppState.swift:392` | Single Back is judged by the position when the wait ends. Press at 4 s with a 1.6 s interval and it restarts instead of going to the previous track. | Judge by the position at the moment of the press. |
| B4 | `AppState.swift:537-539`, `AppState.swift:571-573` | Forward then Back resets the other counter. The Forward press is lost and Back counts as a new single press. | One gesture for both buttons. Any second press makes it a seek in that press's direction. |
| B5 | `AppState.swift:546-556` | A pending single press is not cancelled when the track ends naturally, which gives a double skip. | Any track change cancels the gesture. |
| B6 | `AppState.swift:384`, `AppState.swift:408` | Forward on the last track and Back on the first always wrap. `repeatMode` is ignored. | Wrap only when repeat is on. Back on the first track restarts it. |
| B7 | `AppState.swift:388`, `AppState.swift:397`, `AppState.swift:412` | Changing or restarting a track always starts playback, even when paused. | Keep the play/pause state. |
| B8 | `AppState.swift:357-358` | Fast seek presses are computed from `currentTime`, which the 0.25 s observer overwrites with the pre-seek value. Several quick presses do not add up to 3 s each. | Keep the pending seek target and add each step to that. Ignore observer ticks while a seek is in flight. |
| B9 | `AppState.swift:649-667` | `seekForwardCommand` and `seekBackwardCommand` fire twice per long press (begin and end), so one long press counts as two presses. | Act on one of the two events only, or do not register these commands. |

Hard-coded values: the 5 s threshold is written in `AppState.swift:362`, `AppState.swift:392`, `PlayerViews.swift:354-356`, and the 3 s step in `AppState.swift:339`, `AppState.swift:349`, `AppState.swift:357-358`, `AppState.swift:628`, `AppState.swift:635`. Only the multi-tap interval is a setting. Make them the three settings from `LOGIC_FOR_PLAY.md`.

### B10. The "Restore" feature is not in the logic document

`AppState.swift:371-376`, `AppState.swift:394`

After a restart (single Back above 5 s) the next single Forward jumps back to the old spot instead of going to the next track. Two problems as written:

- It never expires. Minutes after a restart, Forward still restores instead of skipping.
- `playQueue` does not clear it. Restart track A, pick track B from the list, press Forward: track B is seeked to track A's old position.

Decide whether to keep it. If yes, add it to `LOGIC_FOR_PLAY.md` with an expiry (for example: only while still within the Restart Threshold after the restart) and clear it on every track change.

### B11. Move the gesture logic out of `AppState`

`AppState.swift:531-603` is two counters and two tasks spread over two near-identical functions. Replace it with one small state machine (`IDLE`, `PENDING`, `SEEKING`) that takes presses and a clock and returns actions (next, previous, restart, seek by N). It can then be tested without audio, and it is the same code the demo will use.

## C. Storage and library

- **C1. Whole queue written to `UserDefaults` every 3 seconds.** `AppState.swift:417-422`, called from `AppState.swift:719` and from every play, pause and seek. Each track carries its bookmark data, so a large folder means a large JSON write on the main thread several times a minute. Save the queue only when it changes, and the position as its own small value.
- **C2. Tracks get a new id on every scan.** `Models.swift:87`. After a rescan or relaunch the "now playing" highlight in lists is lost (`FolderView.swift:241`) and playlist copies no longer match folder tracks. Use a stable id derived from the file path.
- **C3. Same track twice in a playlist breaks the list.** `AppState.swift:201-204` appends without checking, and `PlaylistsView.swift:107` uses the track id as row id. Duplicate ids give undefined list behaviour. Skip duplicates or use a per-entry id.
- **C4. Folders are matched by name.** `AppState.swift:130`, `AppState.swift:151`, `AppState.swift:173`, `FolderView.swift:65`. Two folders with the same name overwrite each other. Match by `FolderBookmark.id`.
- **C5. Folder scan blocks the UI.** `AppState.swift:157-176`. File enumeration runs on the main actor and metadata is loaded one file at a time. Move enumeration off the main actor and load a few files in parallel.
- **C6. Resume Points are keyed by absolute path.** `AppState.swift:363`. The path can change between installs. Key by path relative to the folder, together with C2.
- **C7. Removing a folder does not stop access to it.** `AppState.swift:149-155`.

## D. App lifecycle and UI

- **D1. `restorePlaybackState()` runs in `onAppear`.** `ContentView.swift:50`. If the root view appears again it reloads the track and pauses playback. Run it once from `AppState.init`.
- **D2. Audio session is configured in a view.** `sanemp3App.swift:22-26`. Move it to app start and do not swallow the error with `try?`.
- **D3. Screen lock is always disabled.** `sanemp3App.swift:20`, `sanemp3App.swift:32`. It is forced back on at every activation, so the "Prevent Screen Lock" toggle (`PlayerViews.swift:133-136`) cannot stay off, and its binding is not observed so the checkmark does not refresh. Store the choice as a setting and apply it from one place.
- **D4. Every view redraws four times a second.** `currentTime` is published on the one `AppState` that all lists observe (`AppState.swift:35`, `AppState.swift:709-714`). Move progress into its own small observable object used only by the scrubber and the player buttons. Low priority until lists feel slow.
- **D5. A single press while paused in the background may not run.** The wait is a `Task.sleep` (`AppState.swift:546-548`). With no audio playing the app can be suspended before it elapses.
- **D6. Buttons nested in a button.** `PlayerViews.swift:16-44`. The mini player is a `Button` containing two more. Use a tap gesture on the row instead.
- **D7. No test identifiers on player controls.** Only the certificate buttons have `accessibilityIdentifier`. Add them to the car buttons, play/pause, mini player, track rows and toolbar actions.
- **D8. Unused state.** `isShuffle`, `originalQueue` and `repeatMode` are stored and saved but nothing can change them (apart from `repeatMode == .one` being read once). Wire them up or remove them.
- **D9. Main-actor data read off the main thread.** `Models.swift:425` reads `self.expirationDate` inside a notification-permission callback, which runs on another queue.

## E. Structure

- `AppState` holds storage, player, gesture handling and the UI lock in one 740-line class. Split out at least the gesture state machine (B11) and the Resume Memory.
- `Models.swift` holds models, theme, and about 450 lines of provisioning service and views. Move the provisioning code to its own file.

## Suggested order

1. A1, A5, A4: small changes, and they should stop the jam.
2. A2, A6: failures become visible instead of silent.
3. B11 with B1 to B9: rebuild navigation on the state machine once the demo has settled the rules.
4. A3 with C2, C6: folder access and stable track identity.
5. C1, then the rest.
