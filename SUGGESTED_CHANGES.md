# Suggested changes for `sanemp3`

Based on reading these seven files only, nothing was built or run:
`AppState.swift`, `ContentView.swift`, `FolderView.swift`, `Models.swift`, `PlayerViews.swift`, `PlaylistsView.swift`, `sanemp3App.swift`.

Not seen: `SettingsView`, `applyLockScreenOverlay()` and `trackUserTouches()` are used in `ContentView.swift` but defined in none of the files above, and the Xcode project settings (Info.plist, background modes) were not checked.

This list assumes navigation, gestures and Resume Points move to the shared `PlayLogic` library (see `logic_for_play_demo.md`, "Findings from sanemp3", for the adoption steps). Everything the library fixes by itself has been removed from this file. What is left is what `sanemp3` still has to do on its own.

Terms like Resume Point, Decision Window and Seek Step come from `LOGIC_FOR_PLAY.md`.

## A. Playback engine (the `PlaybackEngine` wrapper around `AVPlayer`)

The library drives the player only through `PlaybackEngine`. These points are about that wrapper; the library cannot fix them.

### A1. A track that fails to load stops everything silently

`AppState.swift:240-284`

Nothing watches for a failed item. If a file is missing, not downloaded, or not readable, the player sits there with `isPlaying == true` and no end-of-track event ever comes.

Fix: observe `AVPlayerItem.status` (`.failed`), `AVPlayerItemFailedToPlayToEndTime` and `AVPlayerItemPlaybackStalled`. On failure skip to the next track and show which file failed.

### A2. Only one folder is accessible at a time

`AppState.swift:123-127`

`openFolder` stops security-scoped access to the previous folder. A queue still playing from that folder cannot load its next track (and then A1 makes it silent).
The same happens with playlists that mix tracks from several folders, and with the queue restored at launch when it belongs to a folder other than the last opened one.

Related: `AudioTrack.bookmarkData` is created (`Models.swift:114`) but never used. Tracks are opened by their stored `url`, which can go stale between launches.

Fix: keep access open for every folder that has tracks in the queue (resolve the folder bookmark, start access, stop only when nothing uses it). Check the result of `startAccessingSecurityScopedResource()` and the `stale` flag (`AppState.swift:126`, `AppState.swift:143-144`), both ignored now.

### A3. End-of-track handler listens to every player item

`AppState.swift:678`

The observer is registered with `object: nil` and hops through a `Task`. By the time it runs, the current track may already be a different one, so the end is reported for the wrong track.

Fix: the engine must call `onTrackEnded` only when the notification's object is `player.currentItem`.

### A4. Position must reflect a seek immediately

`AppState.swift:357-358`, `AppState.swift:709-714`

`currentTime` is overwritten by the 0.25 s observer with the pre-seek value while an `AVPlayer` seek is still in flight. The library reads `engine.position` on every seeking press, so several quick presses would not add up to one Seek Step each.

Fix: in the engine keep the pending seek target and return it as `position` until the seek lands. Ignore observer ticks while a seek is in flight.

### A5. Seeking to the exact end with the scrubber can leave the player stuck

`AppState.swift:320-323`

Button seeks past the end are handled by the library (it finishes the track itself). The scrubber and the lock-screen position slider still clamp to exactly `duration`, and seeking to the exact end does not reliably produce the end-of-track event.

Fix: in the engine, clamp a direct seek slightly before the end, or report the end directly.

### A6. `isPlaying` does not follow the system

`AppState.swift:268-270`, `AppState.swift:297-299`

`try? setActive(true)` can fail (for example during a call) and playback is still reported as running. When headphones are unplugged or an interruption begins the system pauses the player on its own.

Fix: watch `player.timeControlStatus` and route changes, and call the library's `pause()` / `play()` so its `isPlaying` matches reality. That also makes stalls visible.

## B. Media buttons

- **B1. `seekForwardCommand` and `seekBackwardCommand` fire twice per long press** (begin and end), so one long press would reach the library as two presses. `AppState.swift:649-667`. Act on one of the two events only, or do not register these commands.
- **B2. A single press while paused in the background may run late.** The Decision Window is a timer. With no audio playing the app can be suspended before it elapses. The library finishes an overdue gesture on the next press, but the track change itself waits until the app runs again. Check that the audio background mode is enabled; beyond that, accept it.

## C. Storage and library

- **C1. Whole queue written to `UserDefaults` every 3 seconds.** `AppState.swift:417-422`, called from `AppState.swift:719` and from every play, pause and seek. Each track carries its bookmark data, so a large folder means a large JSON write on the main thread several times a minute. Save the queue only when it changes, and the position as its own small value.
- **C2. Tracks get a new id on every scan.** `Models.swift:87`. After a rescan or relaunch the "now playing" highlight in lists is lost (`FolderView.swift:241`) and playlist copies no longer match folder tracks. Use a stable id derived from the folder plus the path inside the folder. The same value is what the library needs as `PlayTrack.key` for Resume Points.
- **C3. Same track twice in a playlist breaks the list.** `AppState.swift:201-204` appends without checking, and `PlaylistsView.swift:107` uses the track id as row id. Duplicate ids give undefined list behaviour. Skip duplicates or use a per-entry id.
- **C4. Folders are matched by name.** `AppState.swift:130`, `AppState.swift:151`, `AppState.swift:173`, `FolderView.swift:65`. Two folders with the same name overwrite each other. Match by `FolderBookmark.id`.
- **C5. Folder scan blocks the UI.** `AppState.swift:157-176`. File enumeration runs on the main actor and metadata is loaded one file at a time. Move enumeration off the main actor and load a few files in parallel.
- **C6. Removing a folder does not stop access to it.** `AppState.swift:149-155`.

## D. App lifecycle and UI

- **D1. `restorePlaybackState()` runs in `onAppear`.** `ContentView.swift:50`. If the root view appears again it reloads the track and pauses playback. Run it once from `AppState.init`.
- **D2. Audio session is configured in a view.** `sanemp3App.swift:22-26`. Move it to app start and do not swallow the error with `try?`.
- **D3. Screen lock is always disabled.** `sanemp3App.swift:20`, `sanemp3App.swift:32`. It is forced back on at every activation, so the "Prevent Screen Lock" toggle (`PlayerViews.swift:133-136`) cannot stay off, and its binding is not observed so the checkmark does not refresh. Store the choice as a setting and apply it from one place.
- **D4. Every view redraws four times a second.** `currentTime` is published on the one `AppState` that all lists observe (`AppState.swift:35`, `AppState.swift:709-714`). Move progress into its own small observable object used only by the scrubber and the player buttons. Low priority until lists feel slow.
- **D5. Buttons nested in a button.** `PlayerViews.swift:16-44`. The mini player is a `Button` containing two more. Use a tap gesture on the row instead.
- **D6. No test identifiers on player controls.** Only the certificate buttons have `accessibilityIdentifier`. Add them to the car buttons, play/pause, mini player, track rows and toolbar actions.
- **D7. Unused state.** `isShuffle` and `originalQueue` are stored and saved but nothing can change them. Wire them up or remove them. `repeatMode` maps to the library's `settings.repeatMode`, but still has no UI.
- **D8. Main-actor data read off the main thread.** `Models.swift:425` reads `self.expirationDate` inside a notification-permission callback, which runs on another queue.

## E. Structure

- After the library is in, `AppState` still holds storage, the player and the UI lock in one class. Move the `AVPlayer` code into its own `PlaybackEngine` class (section A).
- `Models.swift` holds models, theme, and about 450 lines of provisioning service and views. Move the provisioning code to its own file.

## Suggested order

1. Adopt `PlayLogic` together with the engine wrapper: A3, A4, A5, B1, and C2 for the track key. This is what should stop the jam.
2. A1, A6: failures become visible instead of silent.
3. A2: folder access.
4. C1, then the rest.
