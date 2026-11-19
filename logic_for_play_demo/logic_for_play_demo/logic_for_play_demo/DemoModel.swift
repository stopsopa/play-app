import SwiftUI
import AppKit
import Combine
import PlayLogic

/**
 * Glue of the demo: owns the PlayLogic controller and feeds it with
 *   - the playlist (mp3 files of a folder chosen by the user)
 *   - keyboard presses (left = Back, right = Forward, space = play/pause)
 * It contains no navigation or resume logic of its own.
 */
final class DemoModel: ObservableObject {
    // "v2": defaults changed (Decision Window 1.6 s), old stored values are ignored.
    static let settingsKey = "demo.playLogicSettings.v2"
    static let bookmarkKey = "demo.folderBookmark"

    /**
     * Default playlist folder: "World Of Goo Soundtrack (mp3)" in the project root.
     * Found relative to this source file (path known at compile time), so no user path is hardcoded.
     * It is only where "Choose folder" opens; any other folder can still be picked.
     */
    static let defaultFolderURL: URL = {
        var root = URL(fileURLWithPath: #filePath)
        // DemoModel.swift -> logic_for_play_demo -> logic_for_play_demo -> logic_for_play_demo -> project root
        for _ in 0..<4 {
            root.deleteLastPathComponent()
        }
        return root.appendingPathComponent("World Of Goo Soundtrack (mp3)", isDirectory: true)
    }()

    let engine = DemoAudioEngine()
    let logic: PlayLogicController
    @Published var folderName: String?

    private var folderURL: URL?
    private var keyMonitor: Any?

    init() {
        logic = PlayLogicController(
            engine: engine,
            store: UserDefaultsResumeStore(),
            settings: PlayLogicSettings.load(from: .standard, key: DemoModel.settingsKey)
        )
        installKeyMonitor()
        restoreFolder()
    }

    func saveSettings() {
        logic.settings.save(to: .standard, key: DemoModel.settingsKey)
    }

    // MARK: - Playlist folder

    /**
     * The app is sandboxed, so the user has to point at the folder with mp3 files once.
     * A security-scoped bookmark lets us reopen it on the next launch.
     */
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder with mp3 files"
        // Open the panel inside the default playlist folder: pressing "Open" right away picks it.
        panel.directoryURL = DemoModel.defaultFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: DemoModel.bookmarkKey)
        openFolder(url)
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: DemoModel.bookmarkKey) else { return }
        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard let url else { return }
        openFolder(url)
    }

    private func openFolder(_ url: URL) {
        folderURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        folderURL = url
        folderName = url.lastPathComponent

        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        let tracks = files
            .filter { $0.pathExtension.lowercased() == "mp3" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { file in
                // Stable key: folder name + path inside the folder, never the absolute path.
                PlayTrack(
                    key: "\(url.lastPathComponent)/\(file.lastPathComponent)",
                    title: file.deletingPathExtension().lastPathComponent,
                    url: file
                )
            }
        logic.setQueue(tracks, startAt: tracks.isEmpty ? nil : 0, play: false)
    }

    // MARK: - Keyboard

    /**
     * Window-wide keys, independent of which control has focus.
     * Auto-repeat of a held key is swallowed: one physical push = one Press.
     */
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Leave the "Choose folder" panel and Cmd shortcuts alone.
            if event.window is NSPanel || event.modifierFlags.contains(.command) {
                return event
            }
            switch event.keyCode {
            case 123: // left arrow
                if !event.isARepeat { self.logic.press(.back) }
            case 124: // right arrow
                if !event.isARepeat { self.logic.press(.forward) }
            case 49: // space
                if !event.isARepeat { self.logic.togglePlayPause() }
            default:
                return event
            }
            return nil
        }
    }
}

// 75.4 -> "1:15"
func formatTime(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
}
