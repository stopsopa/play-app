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

#### A3 in plain words

Think of a doorbell that rings when a song finishes. The old code did not ask "ring when *this* song finishes". It asked "ring when *any* song finishes", and then it answered the door a moment later instead of right away.

In that short moment you may already have switched to another song (tapped a track, pressed Next). When the app finally reacts, it only knows "a song ended" and assumes it was the song that is current now. So the song you just picked is treated as finished: the app jumps past it and forgets its remembered position.

It needs unlucky timing (a song ending in the same instant you change tracks), so it shows up rarely, as "it skipped a track by itself".

#### A3 suggested solution

Two changes, both in the engine:

1. Ask for the bell of **one specific song**. Every time a track is loaded, the engine subscribes to the "finished" event of that track only, and unsubscribes from the previous one.
2. The bell carries a **name tag**. When it rings, the engine compares the tag with the song that is loaded right now and ignores the bell when they differ. This covers the short delay between the ring and the reaction.

Status: **already done**, nothing left to decide. The old handler was part of the navigation code replaced by `PlayLogic`, and the library requires exactly this behaviour from its engine. See `watch(_:)` and `observe(_:of:_:)` in `AVPlayerEngine.swift`. The same check also protects the "track failed" and "track stalled" events.

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

### B in plain words

This section is about the physical buttons: the Back / Forward buttons on a Bluetooth remote, car stereo or headphones. They do not talk to the app directly. iOS receives the button and passes the app a *command*. Which command depends on how the button was pushed:

| What you do | What iOS sends to the app |
| --- | --- |
| Short press Forward | "next track", once |
| Short press Back | "previous track", once |
| Hold Forward | "seek forward **started**", and on release "seek forward **ended**" |
| Hold Back | "seek backward **started**", and on release "seek backward **ended**" |

**B1.** The app counts every incoming command as one press. A short press is one command, so one press: fine. A long press is two commands (started + ended), so the app counts **two presses**. Two Forward presses mean "seek one step forward", two Back presses mean "restart the track". So today holding Forward jumps a few seconds instead of going to the next track, and holding Back restarts the song instead of going to the previous one.

Nothing was changed here yet, the behaviour is the same as before.

**B2.** After a single press the app waits for the Decision Window (1.6 s by default) to see whether a second press follows, and only then changes the track. That waiting is a timer. iOS freezes apps that sit in the background without playing audio, and a frozen app's timers do not tick. So: music paused, phone locked, you press Next once. The app may be frozen before the 1.6 s pass, and the track changes only when the app wakes up (next button press, or opening the app). While music is playing the app is never frozen, so this only concerns presses made while paused.

### B suggested solution

**B1: yes, normalise (started + ended) into one press.** Concretely: count the press when "started" arrives and ignore "ended".

Why "started" and not "ended":

- The app reacts at the moment you push the button, the same as for a short press. Counting on "ended" would add the whole time you hold the button as extra delay.
- "Ended" is the less reliable of the two. If the remote disconnects or iOS drops it, a press counted on "ended" would be lost completely. A lost "ended" costs nothing when we ignore it anyway.

After the change a long press and a short press are the same thing to the app: hold Forward = one Forward press = next track, hold Back = one Back press = previous track, and a long press can be part of a multi-press gesture like any other press.

The change is small, in `setupRemoteCommands()` in `AppState.swift`. Both seek handlers get one check:

```swift
cc.seekForwardCommand.addTarget { [weak self] e in
    // A long press sends "begin" and "end". Only "begin" counts as a press.
    if (e as? MPSeekCommandEvent)?.type == .beginSeeking {
        self?.press(.forward)
    }
    return .success
}
```

Alternative that was considered and rejected: not registering the seek commands at all. Then a long press would do nothing, and on some remotes iOS would handle it on its own in ways the app cannot see.

**B2: two parts.**

1. Turn on the audio background mode: Xcode > target `sanemp3` > Signing & Capabilities > + Capability > Background Modes > tick "Audio, AirPlay, and Picture in Picture". The project file has no such entry today. Without it iOS stops the music itself shortly after the screen locks or the app goes to the background, so this is worth doing regardless of B2. It can also be done by adding `INFOPLIST_KEY_UIBackgroundModes = audio` to both build configurations in `project.pbxproj`.
2. Accept what is left. With the background mode on, the app stays awake while music plays, so the timer always works during playback. A single press made while **paused** with the phone locked can still land late, because iOS may freeze a silent app. The library already handles the worst part (a late timer never turns the next press into a wrong gesture). A complete fix would mean keeping the app awake artificially while paused, which costs battery and is not worth it.

## C. Storage and library

- **C1. Whole queue written to `UserDefaults` every 3 seconds.** `AppState.swift:417-422`, called from `AppState.swift:719` and from every play, pause and seek. Each track carries its bookmark data, so a large folder means a large JSON write on the main thread several times a minute. Save the queue only when it changes, and the position as its own small value.
- **C2. Tracks get a new id on every scan.** `Models.swift:87`. After a rescan or relaunch the "now playing" highlight in lists is lost (`FolderView.swift:241`) and playlist copies no longer match folder tracks. Use a stable id derived from the folder plus the path inside the folder. The same value is what the library needs as `PlayTrack.key` for Resume Points.
- **C3. Same track twice in a playlist breaks the list.** `AppState.swift:201-204` appends without checking, and `PlaylistsView.swift:107` uses the track id as row id. Duplicate ids give undefined list behaviour. Skip duplicates or use a per-entry id.
- **C4. Folders are matched by name.** `AppState.swift:130`, `AppState.swift:151`, `AppState.swift:173`, `FolderView.swift:65`. Two folders with the same name overwrite each other. Match by `FolderBookmark.id`.
- **C5. Folder scan blocks the UI.** `AppState.swift:157-176`. File enumeration runs on the main actor and metadata is loaded one file at a time. Move enumeration off the main actor and load a few files in parallel.
- **C6. Removing a folder does not stop access to it.** `AppState.swift:149-155`.

### C4 in plain words

Every folder you import gets a card in the app's memory: its name, a permanent "key" to open it again later (the bookmark), and the number of tracks. Each card also has a unique number (`FolderBookmark.id`), but the app does not use it to find a card. It looks the card up by the **folder name**, which is only the last part of the path.

Example: you import `Podcasts/2024/Music` and later `Car/Music`. Both are called `Music`. On the second import the app looks for a card named `Music`, finds the first one, and overwrites its key with the key of the second folder. Result:

- the list shows one `Music` folder, not two;
- the first folder can no longer be opened from the list, it has to be picked in Files again (which then overwrites the second one);
- the track count and the checkmark in "Switch Folder" belong to whichever was written last.

There is a second, quieter effect since C2: a track's id is made from "folder name + path inside the folder". Two files with the same name inside two same-named folders (`Music/01.mp3` twice) get the same id, so they share one remembered position and count as the same track in a playlist.

Why it has not hurt yet: it only happens when two imported folders have exactly the same name.

### C4 suggested solution

Three steps, all in `AppState.swift` plus one line in `FolderView.swift`:

1. **Inside the app, always find a card by its unique number.** The app already knows the number of the folder being shown (`currentFolderID`). Use it in `scanFolder` (track count), `removeFolder` and for the checkmark in "Switch Folder", instead of comparing names.
2. **When a folder is picked in Files, decide "same folder or new folder" by its location, not its name.** Compare the full path of the picked folder with the full paths of the folders already imported. Same path: refresh that card. Different path: create a new card, even when the name is the same. This is the only place where a lookup by number is impossible, because a freshly picked folder has no number yet.
3. **Show the parent folder when two cards share a name**, for example `Music (2024)` and `Music (Car)`, so they can be told apart in the list.

What I would deliberately leave alone: the track id stays "folder name + path inside the folder". Switching it to the folder's unique number sounds cleaner, but that number is created at import time, so removing a folder and importing it again would give every track a new id and wipe all remembered positions and playlist matches. The price of keeping the name is the rare collision described above (same folder name **and** same path inside it), and the only effect there is a shared remembered position.

Not done yet.

### C5 in plain words

When you open a folder the app does two things: it walks through the folder to list every audio file, and then opens every file to read its title, artist and length.

Both happen on the app's "main thread". That is the single worker that also draws the screen and reacts to your finger. While it is busy reading files it cannot do anything else, so the app stutters or freezes: the spinner stops, scrolling and buttons react late. Second problem: the files are read strictly one after another, file 2 does not start before file 1 is done.

With 30 files nobody notices. With a few hundred or a few thousand files, or a folder in iCloud where every file is slow to open, opening the folder takes many seconds and the app feels stuck during that time. Music that is already playing keeps playing, only the screen is affected.

### C5 suggested solution

Two changes in `scanFolder()` in `AppState.swift`, plus marking `AudioTrack.load` in `Models.swift` as allowed to run off the main thread:

1. **Do the folder walk on a background worker.** The main thread only starts the scan and receives the finished list, so the spinner keeps spinning and the rest of the app stays usable.
2. **Read several files at the same time**, 6 at once. Not all at once: opening hundreds of files together makes things slower and uses a lot of memory. The results are sorted afterwards exactly as today, so the order in the list does not change.

What stays the same: the list appears when the whole scan is finished, as it does now. Showing tracks one by one while the scan runs is possible but adds complexity (the list would jump around while sorting), so I would not do it unless big folders still feel slow after these two changes.

Honest expectation: for a folder of a few dozen files you will see no difference. The gain is for folders with hundreds of files or files stored in iCloud. If your folders are small, this one can stay at the bottom of the list.

Not done yet.

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
