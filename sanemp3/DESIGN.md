# sanemp3 — DESIGN

iOS app written in SwiftUI. It plays audio files straight from folders picked in the Files app
(nothing is copied), keeps playlists, and has a big-button player meant for use in a car.

## How the app is built

```
sanemp3App  (@main, scene phase hooks)
└── ContentView  (root: tabs + floating player + overlays)
    ├── TabView
    │   ├── FolderView      tab 0
    │   ├── PlaylistsView   tab 1  ──push──▶ PlaylistDetailView
    │   └── SettingsView    tab 2
    ├── PlaybackErrorBanner + MiniPlayer   (float above the tab bar)
    ├── NowPlayingView   (sheet, opened from MiniPlayer)
    │   ├── queueSheet   (sheet)
    │   └── SettingsView (sheet, with DONE BTN)
    ├── LockOverlayView  (covers everything when the UI lock fires)
    └── ProvisioningIndicatorView  (DEBUG builds only)
```

- **One state object.** `AppState.shared` is the only thing views observe. It holds folders,
  playlists, settings and the UI lock, and forwards every playback action onward.
- **Playback decisions** (Queue, Back / Forward press gestures, Resume Points) live in the local
  Swift package `../PlayLogic` (`PlayLogicController`), outside this folder.
- **Sound** is made only by `AVPlayerEngine`, which implements the package's `PlaybackEngine`
  protocol around `AVPlayer`.
- **Progress** (position / length) is published on a separate small object `PlaybackProgress`,
  observed only by the SCRUBBER, so the 4-per-second tick does not redraw the lists.
- **Storage.** `playlists.json`, `folders.json`, `queue.json` in Application Support/`sanemp3`;
  small settings in `UserDefaults`; folders are remembered as security-scoped bookmarks.
- **Theme.** Brown and orange (`AppTheme`), orange is the app tint.

---

# UI

Every element has a short name in CAPITALS. The same name is used in the drawings and in the
tables. `[ ]` is a button, `( )` is a state marker, `▾` opens a menu, `>` pushes a page.

## 1. APP SHELL

Present on every tab. Source: `ContentView.swift`, `PlayerViews.swift`, `Provisioning.swift`.

```
┌──────────────────────────────────────────┐
│ (CERT BADGE)                             │
│                                          │
│                                          │
│               TAB CONTENT                │
│        (FOLDER / PLAYLISTS / SETTINGS)   │
│                                          │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │            ERROR BANNER            │  │
│  └────────────────────────────────────┘  │
│  ┌────────────────────────────────────┐  │
│  │ ┌────┐ MINI TITLE                  │  │
│  │ │MINI│ MINI ARTIST  [MINI   [MINI  │  │  ◀ MINI PLAYER
│  │ │ART │               SKIP]   PLAY] │  │
│  │ └────┘                             │  │
│  └────────────────────────────────────┘  │
├──────────────────────────────────────────┤
│  [FOLDER TAB] [PLAYLISTS TAB] [SETTINGS  │  ◀ TAB BAR
│                                    TAB]  │
└──────────────────────────────────────────┘
```

| Name | Description |
| --- | --- |
| TAB BAR | Bottom bar with the three tabs. |
| FOLDER TAB | Opens the FOLDER PAGE. |
| PLAYLISTS TAB | Opens the PLAYLISTS PAGE. |
| SETTINGS TAB | Opens the SETTINGS PAGE (without DONE BTN). |
| TAB CONTENT | Area showing the page of the selected tab. |
| MINI PLAYER | Floating rounded bar above the TAB BAR. Shown only when a track is loaded. Tap anywhere on it (outside its buttons) opens the PLAYER PAGE. |
| MINI ART | 44×44 cover of the current track, or a gradient with a note icon. |
| MINI TITLE | Name of the current track, one line. |
| MINI ARTIST | Artist of the current track, one line. |
| MINI SKIP | Jumps forward by one Seek Step. |
| MINI PLAY | Play / pause toggle. |
| ERROR BANNER | Red pill with the last playback problem (track skipped, folder not opened). Hides after 10 s or on tap. Also shown inside the PLAYER PAGE. |
| CERT BADGE | DEBUG only. Draggable capsule with the time left on the developer certificate. Green / orange / red / gray by time left. Tap opens the CERT ALERT. Position is remembered. |
| CERT ALERT | Alert with the exact expiry date and time left. Buttons: OK, REFRESH (re-reads the profile). |

## 2. LOCK OVERLAY

Appears over everything (also over the PLAYER PAGE) after the inactivity delay, when the UI lock
is on. Source: `LockOverlayModifier.swift`, `TouchTrackingWindow.swift`.

```
┌──────────────────────────────────────────┐
│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░ LOCK DIM ░░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░ ┌──────┐ ░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░ │ LOCK │ ░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░ │ ICON │ ░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░ └──────┘ ░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░ LOCK HINT ░░░░░░░░░░░░░░░░░│
│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
└──────────────────────────────────────────┘
```

| Name | Description |
| --- | --- |
| LOCK OVERLAY | The whole locked state: the page under it turns gray and stops reacting. One tap anywhere unlocks and restarts the countdown. |
| LOCK DIM | Full-screen 40% black layer that catches the tap. |
| LOCK ICON | Large white padlock in the centre. |
| LOCK HINT | Text "Tap anywhere to unlock". |

## 3. FOLDER PAGE

Source: `FolderView.swift`. Three looks: no folder, track list, select mode.

### 3a. No folder opened

```
┌──────────────────────────────────────────┐
│ [FOLDER MENU ▾]     FOLDER TITLE         │  ◀ FOLDER BAR
│ ┌──────────────────────────────────────┐ │
│ │ SEARCH FIELD                         │ │
│ └──────────────────────────────────────┘ │
│                                          │
│               FOLDER ICON                │
│             FOLDER EMPTY TITLE           │
│             FOLDER EMPTY TEXT            │
│            ┌────────────────┐            │
│            │  [OPEN FOLDER] │            │
│            └────────────────┘            │
│               RECENT LABEL               │
│  ┌────────────────────────────────────┐  │
│  │ RECENT ROW            RECENT COUNT │  │  ◀ RECENT LIST
│  ├────────────────────────────────────┤  │
│  │ RECENT ROW            RECENT COUNT │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

### 3b. Track list

```
┌──────────────────────────────────────────┐
│ [FOLDER MENU ▾]  FOLDER TITLE            │  ◀ FOLDER BAR
│                     [SORT MENU ▾][SELECT]│
│ ┌──────────────────────────────────────┐ │
│ │ SEARCH FIELD                         │ │
│ └──────────────────────────────────────┘ │
├──────────────────────────────────────────┤
│ TRACK COUNT        [REGEX BTN][PLAY ALL] │  ◀ FOLDER HEADER
├──────────────────────────────────────────┤
│ ROW MARK  TRACK TITLE         TRACK TIME │  ◀ TRACK ROW
│           TRACK ARTIST                   │
├──────────────────────────────────────────┤
│ ROW MARK  TRACK TITLE         TRACK TIME │  ◀ TRACK LIST
│           TRACK ARTIST                   │
├──────────────────────────────────────────┤
│              (SCAN SPINNER)              │
│              (NO FILES TEXT)             │
│               LIST SPACER                │
└──────────────────────────────────────────┘
```

### 3c. Select mode

```
┌──────────────────────────────────────────┐
│ [FOLDER MENU ▾]  FOLDER TITLE            │
│           [ADD BTN][SORT MENU ▾][SELECT] │  ◀ SELECT reads "Done"
├──────────────────────────────────────────┤
│ TRACK COUNT      [REGEX BTN][SELECT ALL] │  ◀ FOLDER HEADER
├──────────────────────────────────────────┤
│ (●) ROW MARK  TRACK TITLE     TRACK TIME │  ◀ ticked
│               TRACK ARTIST               │
├──────────────────────────────────────────┤
│ (○) ROW MARK  TRACK TITLE     TRACK TIME │  ◀ not ticked
│               TRACK ARTIST               │
└──────────────────────────────────────────┘
```

### 3d. Menus of the FOLDER PAGE

```
 FOLDER MENU ▾                SORT MENU ▾            TRACK MENU (long press on TRACK ROW)
┌──────────────────────┐     ┌───────────────────┐  ┌────────────────────────┐
│ ADD SELECTED ITEM    │     │ SORT ITEM  (✓)    │  │ PLAY NOW ITEM          │
│ REGEX ITEM           │     │ SORT ITEM         │  │ ADD TO PLAYLIST ITEM   │
│ OPEN FOLDER ITEM     │     │ SORT ITEM         │  └────────────────────────┘
│ SWITCH FOLDER ITEM > │     │ SORT ITEM         │
│   └ FOLDER ITEM (✓)  │     └───────────────────┘
│   └ FOLDER ITEM      │
└──────────────────────┘
```

| Name | Description |
| --- | --- |
| FOLDER PAGE | First tab. Browses the tracks of one opened folder. |
| FOLDER BAR | Navigation bar of the page. |
| FOLDER TITLE | Name of the opened folder. Same-named folders get parent directories appended ("Music — Car"). Reads "No Folder Selected" when none. |
| FOLDER MENU | Top-left folder icon with a chevron. Opens the menu below. |
| ADD SELECTED ITEM | "Add N to Playlist…". Only when something is ticked. Opens the ADD SHEET. |
| REGEX ITEM | "Select by Regex…". Only when the list has tracks. Opens the REGEX SHEET. |
| OPEN FOLDER ITEM | "Open Folder…". Opens the system FOLDER PICKER. |
| SWITCH FOLDER ITEM | Submenu listing every folder opened before. |
| FOLDER ITEM | One remembered folder. Checkmark on the current one. Tap shows that folder. |
| FOLDER PICKER | System Files picker limited to folders. |
| SEARCH FIELD | "Search tracks". Filters the list by track name or artist. |
| SORT MENU | Up/down arrows icon. Only when the folder has tracks. |
| SORT ITEM | One order: Name A→Z, Name Z→A, Date newest, Date oldest. Checkmark on the active one. |
| SELECT | Toggles select mode. Reads "Select", then "Done". Leaving the mode clears the ticks. |
| ADD BTN | "Add (N)". Only in select mode with at least one tick. Opens the ADD SHEET. |
| FOLDER HEADER | Gray strip under the bar with the count and the list actions. |
| TRACK COUNT | "N tracks", counts what the search left. |
| REGEX BTN | Opens the REGEX SHEET. Capsule "Select Regex" normally, plain "By Regex…" in select mode. |
| PLAY ALL | Starts the whole visible list as the Queue, from the first track. Hidden in select mode. |
| SELECT ALL | Select mode only. Ticks every visible track; reads "Deselect All" when all are ticked. |
| TRACK LIST | Scrollable list of tracks. Pull down to rescan the folder. |
| TRACK ROW | One track. Tap plays the list from this track; in select mode tap ticks / unticks it. Used in the FOLDER PAGE and the PLAYLIST PAGE. |
| ROW MARK | Left slot of a row: position number, or a speaker icon on the current track (waves while playing), or the tick circle in select mode. |
| TRACK TITLE | Track name, one line. Orange and bold on the current track. |
| TRACK ARTIST | Artist, or "Unknown Artist". |
| TRACK TIME | Track length, `m:ss`. |
| TRACK MENU | Long-press menu of a TRACK ROW in the folder. |
| PLAY NOW ITEM | Plays the list from this track. |
| ADD TO PLAYLIST ITEM | Opens the ADD SHEET with this track plus anything already ticked. |
| SCAN SPINNER | "Scanning…" shown in place of the list while the folder is read. |
| NO FILES TEXT | "No audio files found" shown in place of an empty list. |
| LIST SPACER | Invisible last row so the MINI PLAYER never covers the last track. Used at the end of every list. |
| FOLDER ICON | Large folder icon of the empty state. |
| FOLDER EMPTY TITLE | "No Folder Selected". |
| FOLDER EMPTY TEXT | Explains that files are streamed in place, not copied. |
| OPEN FOLDER | Big button opening the FOLDER PICKER. |
| RECENT LABEL | "Recent Folders" caption. Only when at least one folder is remembered. |
| RECENT LIST | The remembered folders on the empty state. |
| RECENT ROW | One remembered folder. Tap shows it. |
| RECENT COUNT | Number of tracks found in that folder at the last scan. |

## 4. REGEX SHEET

Sheet for ticking many tracks at once by a pattern. Source: `FolderView.swift`
(`RegexSelectionSheet`).

```
┌──────────────────────────────────────────┐
│ [REGEX CANCEL]  REGEX TITLE [REGEX APPLY]│
├──────────────────────────────────────────┤
│ ┌──────────────────────────────────────┐ │
│ │ REGEX FIELD             [REGEX CLEAR]│ │
│ ├──────────────────────────────────────┤ │
│ │ MATCH COUNT   /   (REGEX ERROR)      │ │
│ └──────────────────────────────────────┘ │
│ REGEX NOTE                               │
│                                          │
│ ┌──────────────────────────────────────┐ │
│ │ EXAMPLE TITLE        EXAMPLE PATTERN │ │  ◀ EXAMPLE ROW
│ │ EXAMPLE NOTE                         │ │
│ ├──────────────────────────────────────┤ │  ◀ EXAMPLE LIST
│ │ EXAMPLE TITLE        EXAMPLE PATTERN │ │
│ │ EXAMPLE NOTE                         │ │
│ └──────────────────────────────────────┘ │
│ ┌──────────────────────────────────────┐ │
│ │ MATCH ROW                            │ │
│ │ MATCH ROW                            │ │  ◀ MATCH LIST
│ │ MATCH MORE                           │ │
│ └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

| Name | Description |
| --- | --- |
| REGEX SHEET | Selects tracks of the visible list whose title or file name matches a regular expression. |
| REGEX TITLE | "Select by Regex". |
| REGEX CANCEL | Closes the sheet, selection unchanged. |
| REGEX APPLY | "Select (N)". Replaces the selection with the matches, switches the FOLDER PAGE to select mode, remembers the pattern. Disabled with no matches. |
| REGEX FIELD | Monospaced input for the pattern. Prefilled with the last applied pattern. Case-insensitive. |
| REGEX CLEAR | Small ✕ that empties the field. Only when the field has text. |
| MATCH COUNT | "Matched: N of M tracks". Orange when N > 0. |
| REGEX ERROR | Red message shown instead of MATCH COUNT when the pattern is not valid. |
| REGEX NOTE | Footer: what the pattern is matched against. |
| EXAMPLE LIST | Six ready-made patterns (Live, Remix, Track Numbers, Acoustic, CD / Disc, Year in Name). |
| EXAMPLE ROW | One example. Tap copies its pattern into the REGEX FIELD. |
| EXAMPLE TITLE | Name of the example. |
| EXAMPLE PATTERN | The pattern itself, in an orange monospaced chip. |
| EXAMPLE NOTE | What the example matches. |
| MATCH LIST | Preview of the first 8 matching tracks. Only when there are matches. |
| MATCH ROW | One matching track name with a tick. |
| MATCH MORE | "... and N more" when over 8 tracks match. |

## 5. ADD SHEET

Sheet for putting the chosen tracks into a playlist. Source: `PlaylistsView.swift`
(`AddToPlaylistSheet`).

```
┌──────────────────────────────────────────┐
│ [ADD CANCEL]        ADD TITLE            │
├──────────────────────────────────────────┤
│ CREATE NEW                               │
│ ┌──────────────────────────────────────┐ │
│ │ [NEW PLAYLIST BTN]                   │ │  ◀ before tap
│ │ NEW NAME FIELD            [NEW ADD]  │ │  ◀ after tap
│ └──────────────────────────────────────┘ │
│ EXISTING PLAYLISTS                       │
│ ┌──────────────────────────────────────┐ │
│ │ TARGET NAME                      (+) │ │  ◀ TARGET ROW
│ │ TARGET COUNT                         │ │
│ ├──────────────────────────────────────┤ │  ◀ TARGET LIST
│ │ TARGET NAME                      (+) │ │
│ │ TARGET COUNT                         │ │
│ └──────────────────────────────────────┘ │
│ (NO TARGETS TEXT)                        │
└──────────────────────────────────────────┘
```

| Name | Description |
| --- | --- |
| ADD SHEET | Adds the chosen tracks to a new or an existing playlist. A track already in the playlist is skipped. |
| ADD TITLE | "Add N Song(s)". |
| ADD CANCEL | Closes the sheet without adding. |
| NEW PLAYLIST BTN | "New Playlist…". Turns into the NEW NAME FIELD row. |
| NEW NAME FIELD | Input for the new playlist's name. Return key does the same as NEW ADD. |
| NEW ADD | Creates the playlist with the chosen tracks and closes the sheet. Disabled while the name is empty. |
| TARGET LIST | Every existing playlist. |
| TARGET ROW | One playlist. Tap adds the tracks to it and closes the sheet. |
| TARGET NAME | Playlist name. |
| TARGET COUNT | "N tracks" currently in it. |
| NO TARGETS TEXT | "No playlists yet", in place of the TARGET LIST. |

## 6. PLAYLISTS PAGE

Source: `PlaylistsView.swift` (`PlaylistsView`).

```
        with playlists                              empty
┌──────────────────────────────────────────┐ ┌───────────────────────────┐
│ PLAYLISTS TITLE          [NEW PLAYLIST]  │ │ PLAYLISTS TITLE [NEW      │
├──────────────────────────────────────────┤ │                  PLAYLIST]│
│ ┌────┐ PLAYLIST NAME                   > │ │                           │
│ │LIST│ PLAYLIST INFO                     │ │      PLAYLISTS ICON       │
│ │ICON│                                   │ │  PLAYLISTS EMPTY TITLE    │
│ └────┘                                   │ │  PLAYLISTS EMPTY TEXT     │
├──────────────────────────────────────────┤ │   ┌───────────────────┐   │
│ ┌────┐ PLAYLIST NAME                   > │ │   │ [CREATE PLAYLIST] │   │
│ │LIST│ PLAYLIST INFO                     │ │   └───────────────────┘   │
│ │ICON│                    ◀ PLAYLIST ROW │ │                           │
│ └────┘                                   │ └───────────────────────────┘
│               LIST SPACER                │
└──────────────────────────────────────────┘        NAME ALERT
        ▲ PLAYLIST LIST                      ┌───────────────────────────┐
                                             │       ALERT TITLE         │
                                             │  ┌─────────────────────┐  │
                                             │  │ ALERT FIELD         │  │
                                             │  └─────────────────────┘  │
                                             │ [ALERT CANCEL] [ALERT OK] │
                                             └───────────────────────────┘
```

| Name | Description |
| --- | --- |
| PLAYLISTS PAGE | Second tab. Lists the playlists. |
| PLAYLISTS TITLE | Large title "Playlists". |
| NEW PLAYLIST | "+" in the bar. Opens the NAME ALERT titled "New Playlist". |
| PLAYLIST LIST | Grouped list of playlists. |
| PLAYLIST ROW | One playlist. Tap pushes the PLAYLIST PAGE. Swipe left deletes the playlist. |
| LIST ICON | Gradient square with a list icon. |
| PLAYLIST NAME | Name of the playlist. |
| PLAYLIST INFO | "N tracks · total time". |
| PLAYLISTS ICON | Large list icon of the empty state. |
| PLAYLISTS EMPTY TITLE | "No Playlists". |
| PLAYLISTS EMPTY TEXT | One line inviting to create a playlist. |
| CREATE PLAYLIST | Big button, same action as NEW PLAYLIST. |
| NAME ALERT | System alert with one text field. Used to create a playlist here and to rename one on the PLAYLIST PAGE. |
| ALERT TITLE | "New Playlist" or "Rename". |
| ALERT FIELD | The name. An empty name becomes "New Playlist" on create. |
| ALERT OK | "Create" or "Save". |
| ALERT CANCEL | Closes the alert, nothing changes. |

## 7. PLAYLIST PAGE

Pushed from a PLAYLIST ROW. Source: `PlaylistsView.swift` (`PlaylistDetailView`).

```
┌──────────────────────────────────────────┐
│ [BACK]   PLAYLIST TITLE                  │  ◀ PLAYLIST BAR
│       [ORDER MENU ▾][REORDER][MORE MENU ▾]
├──────────────────────────────────────────┤
│ PLAYLIST TOTAL                    [PLAY] │  ◀ PLAYLIST HEADER
├──────────────────────────────────────────┤
│ ROW MARK  TRACK TITLE         TRACK TIME │  ◀ TRACK ROW
│           TRACK ARTIST                   │
├──────────────────────────────────────────┤
│ (DELETE HANDLE) TRACK TITLE (DRAG HANDLE)│  ◀ while reordering
│                 TRACK ARTIST             │
├──────────────────────────────────────────┤
│            (NO TRACKS TEXT)              │
│               LIST SPACER                │
└──────────────────────────────────────────┘

 ORDER MENU ▾            MORE MENU ▾
┌──────────────────┐    ┌──────────────────┐
│ ORDER ITEM       │    │ RENAME ITEM      │
│ ORDER ITEM       │    └──────────────────┘
│ ORDER ITEM       │
└──────────────────┘
```

| Name | Description |
| --- | --- |
| PLAYLIST PAGE | Tracks of one playlist. |
| PLAYLIST BAR | Navigation bar of the page. |
| BACK | System back button to the PLAYLISTS PAGE. |
| PLAYLIST TITLE | Name of the playlist. |
| ORDER MENU | Up/down arrows icon. Only when the playlist has tracks. Sorts the playlist once and saves that order. |
| ORDER ITEM | One order: Name A→Z, Name Z→A, Date newest, Date oldest, Custom Order (leaves it as is). |
| REORDER | Toggles reorder mode. Reads "Reorder", then "Done". Only when the playlist has tracks. |
| MORE MENU | "…" icon. |
| RENAME ITEM | Opens the NAME ALERT titled "Rename", prefilled with the current name. |
| PLAYLIST HEADER | Gray strip under the bar. |
| PLAYLIST TOTAL | "N tracks · total time". |
| PLAY | Starts the playlist as the Queue from its first track. Hidden when the playlist is empty. |
| TRACK ROW | Same row as on the FOLDER PAGE (no select mode here). Tap plays the playlist from this track. Swipe left removes the track from the playlist. |
| DELETE HANDLE | Red minus shown on each row in reorder mode. Removes the track. |
| DRAG HANDLE | Grip on the right of each row in reorder mode. Drag moves the track. |
| NO TRACKS TEXT | "No tracks yet. Add songs from the Folder tab." in place of the list. |

## 8. SETTINGS PAGE

Third tab, and also a sheet opened from the PLAYER PAGE. Source: `SettingsView.swift`,
`Provisioning.swift` (`ProvisioningSettingsRow`).

```
┌──────────────────────────────────────────┐
│             SETTINGS TITLE    [DONE BTN] │  ◀ DONE BTN only in the sheet
├──────────────────────────────────────────┤
│ MEDIA REMOTE MULTI-TAP                   │  ◀ TAP SECTION
│ ┌──────────────────────────────────────┐ │
│ │              TAP LABEL               │ │
│ │              TAP VALUE               │ │
│ │ [TAP MINUS] [TAP RESET]   [TAP PLUS] │ │
│ └──────────────────────────────────────┘ │
│ TAP HELP                                 │
│                                          │
│ UI INACTIVITY LOCK                       │  ◀ LOCK SECTION
│ ┌──────────────────────────────────────┐ │
│ │ LOCK TOGGLE                    (on)  │ │
│ │ DELAY LABEL             DELAY VALUE  │ │
│ │ ──────────○──────────── DELAY SLIDER │ │
│ └──────────────────────────────────────┘ │
│ LOCK HELP                                │
│                                          │
│ PLAYBACK                                 │  ◀ PLAYBACK SECTION
│ ┌──────────────────────────────────────┐ │
│ │ AWAKE TOGGLE                   (on)  │ │
│ │ SPEED PICKER                  1× ▾   │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ NAVIGATION                               │  ◀ NAV SECTION
│ ┌──────────────────────────────────────┐ │
│ │ STEP STEPPER      STEP VALUE  [-][+] │ │
│ │ RESUME TOGGLE                  (on)  │ │
│ │ REPEAT PICKER                All ▾   │ │
│ └──────────────────────────────────────┘ │
│ NAV HELP                                 │
│                                          │
│ POSITION MEMORY                          │  ◀ MEMORY SECTION
│ ┌──────────────────────────────────────┐ │
│ │ MEMORY COUNT                      12 │ │
│ │ [MEMORY CLEAR]                       │ │
│ └──────────────────────────────────────┘ │
│ MEMORY HELP                              │
│                                          │
│ DEVELOPER CERTIFICATE & NOTIFICATIONS    │  ◀ CERT SECTION
│ ┌──────────────────────────────────────┐ │
│ │ CERT STATUS               CERT LEFT  │ │
│ │ CERT EXPIRES              CERT DATE  │ │
│ │ [CERT REFRESH]       [BADGE RESET]   │ │
│ │ ──────────────────────────────────── │ │
│ │ SIM LABEL                 SIM VALUE  │ │
│ │ ───○────────── SIM SLIDER [SIM SEND] │ │
│ │ SIM TICKS  24h  18h  12h  6h  0h     │ │
│ └──────────────────────────────────────┘ │
│ CERT HELP                                │
└──────────────────────────────────────────┘
```

| Name | Description |
| --- | --- |
| SETTINGS PAGE | Form with all settings. Every change is saved at once. |
| SETTINGS TITLE | "Settings". |
| DONE BTN | Closes the page. Only when it was opened as a sheet from the PLAYER PAGE. |
| TAP SECTION | "Media Remote Multi-Tap": how long the app waits after a Back / Forward press for another press. |
| TAP LABEL | Caption "MULTI-TAP SKIP INTERVAL". |
| TAP VALUE | Big orange number, for example "1.6 s". |
| TAP MINUS | Shortens the interval by 0.2 s. Disabled at the 0.2 s minimum. |
| TAP RESET | Sets the interval back to 1.6 s. Disabled when it is already 1.6 s. |
| TAP PLUS | Lengthens the interval by 0.2 s. |
| TAP HELP | Footer listing what 1 press, 2 Back presses and longer series do. |
| LOCK SECTION | "UI Inactivity Lock". |
| LOCK TOGGLE | Turns the LOCK OVERLAY feature on / off. |
| DELAY LABEL | "Inactivity Delay". Only when LOCK TOGGLE is on. |
| DELAY VALUE | Chosen delay in seconds. |
| DELAY SLIDER | 1–60 s without a touch before the UI locks. |
| LOCK HELP | Footer explaining the lock. |
| PLAYBACK SECTION | "Playback". |
| AWAKE TOGGLE | "Prevent Screen Lock": keeps the phone screen on while the app is open. |
| SPEED PICKER | Playback speed: 0.75×, 1×, 1.25×, 1.5×, 2×. Applies at once when playing. |
| NAV SECTION | "Navigation": settings of the PlayLogic package. |
| STEP STEPPER | "Seek Step": 1–30 s, how far one seek press moves. |
| STEP VALUE | Current Seek Step, for example "3s". |
| RESUME TOGGLE | "Resume when a track starts on its own": a track reached by the previous one ending continues from its remembered position. |
| REPEAT PICKER | Repeat mode: Off, All, One. |
| NAV HELP | Footer explaining Seek Step and resuming. |
| MEMORY SECTION | "Position Memory". |
| MEMORY COUNT | "Memorized Tracks": how many tracks have a remembered position. |
| MEMORY CLEAR | Red "Clear Memorized Positions". Only when the count is above 0. |
| MEMORY HELP | Footer explaining position memory. |
| CERT SECTION | "Developer Certificate & Notifications". |
| CERT STATUS | Label "Profile Status". |
| CERT LEFT | Time left on the certificate, same text as the CERT BADGE. |
| CERT EXPIRES | Label "Expires". Row shown only when the date is known. |
| CERT DATE | Expiry date and time. |
| CERT REFRESH | "Refresh Profile": reads the embedded profile again. |
| BADGE RESET | "Reset Overlay Position": puts the CERT BADGE back in the top-left corner. |
| SIM LABEL | "Simulate Expiry Notification". |
| SIM VALUE | Chosen milestone, for example "12h left". |
| SIM SLIDER | Picks one of five milestones: 24, 18, 12, 6, 0 hours. |
| SIM SEND | Fires a test notification for the chosen milestone one second later. |
| SIM TICKS | Scale under the slider, the chosen value is orange. |
| CERT HELP | Footer explaining the section. |

## 9. PLAYER PAGE

Full-screen sheet opened from the MINI PLAYER. Built for big targets. Source: `PlayerViews.swift`
(`NowPlayingView`, `CoverWithCarButtons`, `CarButton`, `ScrubberView`).

```
┌──────────────────────────────────────────┐
│ [PLAYER CLOSE]   [QUEUE BTN] [PLAYER MENU ▾]  ◀ PLAYER BAR
│                 GRABBER                  │
│ ┌────────────────────────┬─────────────┐ │
│ │             (BACK DOT) │   (FWD DOT) │ │
│ │                        │             │ │
│ │       SEEK BACK        │  SEEK FWD   │ │
│ │                        │             │ │
│ │                        │             │ │  ◀ COVER
│ ├────────────────────────┼─────────────┤ │    (artwork under the
│ │                        │             │ │     four CAR BUTTONs)
│ │       PREV TRACK       │ NEXT TRACK  │ │
│ │                        │             │ │
│ └────────────────────────┴─────────────┘ │
│              PLAYER TITLE                │
│              PLAYER ARTIST               │
│            (ERROR BANNER)                │
│  ─────────────○──────────────────────    │  ◀ SCRUBBER
│  TIME PLAYED                  TIME LEFT  │
│ ┌──────────────────────────────────────┐ │
│ │              BIG PLAY                │ │
│ └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘

 PLAYER MENU ▾
┌──────────────────────┐
│ AWAKE ITEM       (✓) │
│ SPEED ITEM         > │
│   └ RATE ITEM        │
│ SETTINGS ITEM        │
└──────────────────────┘
```

| Name | Description |
| --- | --- |
| PLAYER PAGE | The main player. Swipe down or PLAYER CLOSE dismisses it. |
| PLAYER BAR | Navigation bar of the sheet. |
| PLAYER CLOSE | Chevron-down. Closes the page. |
| QUEUE BTN | List icon with "current/total". Opens the QUEUE SHEET. |
| PLAYER MENU | "…" icon. |
| AWAKE ITEM | "Prevent Screen Lock" toggle, same setting as AWAKE TOGGLE. |
| SPEED ITEM | Submenu "Speed (1x)". |
| RATE ITEM | One speed: 0.75×, 1×, 1.25×, 1.5×, 2×. |
| SETTINGS ITEM | Opens the SETTINGS PAGE as a sheet (with DONE BTN). |
| GRABBER | Small gray capsule hinting the sheet can be dragged down. |
| COVER | Square, 95% of the screen width. Shows the track's artwork (or a gradient with a note) under four dark tap zones. Left column and top row are wider (3:2). |
| CAR BUTTON | One of the four zones: icon + label. Darkens while pressed, lights up orange when active. Each gives a haptic tick. |
| SEEK BACK | Top-left. Jumps back by one Seek Step at once. Label "-3s", yellow icon. Flashes for 0.5 s, also when a remote press ended up as a seek back. While a Seek gesture is open the label shows how far the gesture moved back so far, as a multiple of the Seek Step ("-6s", "-9s"...), and returns to "-3s" when the Decision Window closes. |
| SEEK FWD | Top-right. Jumps forward by one Seek Step at once. Label "+3s". Flashes like SEEK BACK, and its label grows the same way ("+6s", "+9s"...). |
| BACK DOT | Small dot in the top-right corner of SEEK BACK. Gray; shows the physical Back (previous track) media button. A short press lights it green for 0.3 s (iOS reports a short press as one event, without "down" and "up"). A long press keeps it green until the button is released, on remotes that report long presses. |
| FWD DOT | Small dot in the top-right corner of SEEK FWD. Same, for the Forward (next track) media button. |
| PREV TRACK | Bottom-left. One Back press, same as the Bluetooth button: one press = previous track. Stays lit while the app waits for another press. |
| NEXT TRACK | Bottom-right. One Forward press, same as the Bluetooth button: one press = next track, two = restart the track. Stays lit while the app waits for another press; after two presses it reads "Restart / to 0:00". |
| PLAYER TITLE | Name of the current track, or "Not Playing". |
| PLAYER ARTIST | Artist of the current track. |
| SCRUBBER | Orange slider of the position. Drag and release to seek. |
| TIME PLAYED | Elapsed time, `m:ss`. Follows the thumb while dragging. |
| TIME LEFT | Remaining time, `-m:ss`. |
| BIG PLAY | Full-width play / pause button. Reads "PLAY" (orange-brown) or "PAUSE" (red-orange). Haptic tick. |

## 10. QUEUE SHEET

Sheet opened from QUEUE BTN. Source: `PlayerViews.swift` (`queueSheet`).

```
┌──────────────────────────────────────────┐
│              QUEUE TITLE    [QUEUE DONE] │
├──────────────────────────────────────────┤
│ QUEUE MARK  QUEUE NAME        QUEUE TIME │  ◀ QUEUE ROW
│             QUEUE ARTIST                 │
├──────────────────────────────────────────┤
│ QUEUE MARK  QUEUE NAME        QUEUE TIME │  ◀ QUEUE LIST
│             QUEUE ARTIST                 │
├──────────────────────────────────────────┤
│               LIST SPACER                │
└──────────────────────────────────────────┘
```

| Name | Description |
| --- | --- |
| QUEUE SHEET | The list of tracks being played, in order. |
| QUEUE TITLE | "Queue". |
| QUEUE DONE | Closes the sheet. |
| QUEUE LIST | All tracks of the Queue. |
| QUEUE ROW | One track. Tap jumps to it. |
| QUEUE MARK | Position number, or a speaker icon on the current track. |
| QUEUE NAME | Track name. Orange and bold on the current track. |
| QUEUE ARTIST | Artist. |
| QUEUE TIME | Track length. |

## Outside the app's own screens

| Name | Description |
| --- | --- |
| SYSTEM PLAYER | iOS lock screen / Control Centre player. Shows title, artist, album, artwork, position. Its buttons and Bluetooth media buttons act like PREV TRACK / NEXT TRACK / BIG PLAY, its slider like the SCRUBBER. |
| CERT NOTICE | Local notification "Certificate Expiry" sent 24, 18, 12, 6 and 0 hours before the developer certificate runs out. |

---

# Files

```
sanemp3/
├── DESIGN.md                        This document: UI element names, page drawings, file map.
├── sanemp3.xcodeproj/
│   └── project.pbxproj              Xcode project: target, build settings, link to the local
│                                    Swift package ../PlayLogic.
└── sanemp3/                         App source.
    ├── sanemp3App.swift             Entry point (@main). Shows ContentView; on scene changes
    │                                applies the screen-lock setting, refreshes the certificate
    │                                countdown and saves the Resume Point.
    ├── ContentView.swift            APP SHELL: TAB BAR with the three pages, floating
    │                                ERROR BANNER + MINI PLAYER, PLAYER PAGE sheet,
    │                                LOCK OVERLAY, CERT BADGE (DEBUG).
    ├── FolderView.swift             FOLDER PAGE (empty state, TRACK LIST, select mode, menus),
    │                                TRACK ROW, REGEX SHEET.
    ├── PlaylistsView.swift          PLAYLISTS PAGE, PLAYLIST PAGE, ADD SHEET, NAME ALERT.
    ├── PlayerViews.swift            ERROR BANNER, MINI PLAYER, PLAYER PAGE, QUEUE SHEET,
    │                                SCRUBBER, COVER and CAR BUTTON.
    ├── SettingsView.swift           SETTINGS PAGE (all sections except the inside of
    │                                CERT SECTION).
    ├── LockOverlayModifier.swift    LOCK OVERLAY view and the modifier that grays out the
    │                                content under it (applyLockScreenOverlay).
    ├── TouchTrackingWindow.swift    UIWindow subclass that sees every touch and restarts the
    │                                inactivity countdown of the UI lock (trackUserTouches).
    ├── Provisioning.swift           Reads the expiry date from embedded.mobileprovision,
    │                                schedules CERT NOTICEs; CERT BADGE, CERT ALERT and the
    │                                rows of CERT SECTION.
    ├── AppState.swift               The single observable state: folders (bookmarks, scan,
    │                                sort), playlists, Queue, settings, UI lock timer, flash
    │                                state of the CAR BUTTONs, lock-screen info and remote
    │                                commands, JSON persistence. Forwards playback to PlayLogic.
    ├── AVPlayerEngine.swift         The only code touching AVPlayer. Implements PlayLogic's
    │                                PlaybackEngine (load, seek, play, pause), reports track
    │                                end / failure / system pause; PlaybackProgress object
    │                                for the SCRUBBER.
    ├── Models.swift                 AppTheme (colours, gradients), LIST SPACER view, data
    │                                types AudioTrack, Playlist, FolderBookmark and
    │                                TrackSortOption.
    └── Assets.xcassets/             Asset catalog.
        ├── Contents.json            Catalog manifest.
        ├── AccentColor.colorset/
        │   └── Contents.json        Accent colour definition.
        └── AppIcon.appiconset/
            └── Contents.json        App icon slots.

../PlayLogic/                        Local Swift package (outside this folder) that owns the
                                     playback rules: Queue, Back / Forward press gestures,
                                     Resume Points, PlayLogicSettings.
```
