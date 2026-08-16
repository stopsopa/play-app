//
//  FolderView.swift
//  sanemp3
//

import SwiftUI
import UniformTypeIdentifiers

struct FolderView: View {
    @EnvironmentObject var state: AppState
    @State private var showFilePicker = false
    @State private var isSelecting = false
    @State private var selected = Set<UUID>()
    @State private var showAddToPlaylist = false
    @State private var showRegexSheet = false
    @State private var search = ""

    var tracks: [AudioTrack] {
        guard !search.isEmpty else { return state.currentTracks }
        return state.currentTracks.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) ||
            $0.displayArtist.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.currentFolderURL == nil {
                    emptyState
                } else {
                    trackList
                }
            }
            .navigationTitle(state.currentFolderName)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search tracks")
            .toolbar {
                // Left: folder + playlist actions
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if !selected.isEmpty {
                            Button { showAddToPlaylist = true } label: {
                                Label("Add \(selected.count) to Playlist…", systemImage: "text.badge.plus")
                            }
                            Divider()
                        }
                        if !tracks.isEmpty {
                            Button { showRegexSheet = true } label: {
                                Label("Select by Regex…", systemImage: "line.3.horizontal.decrease.circle")
                            }
                            Divider()
                        }
                        Button { showFilePicker = true } label: {
                            Label("Open Folder…", systemImage: "folder.badge.plus")
                        }
                        if !state.importedFolders.isEmpty {
                            Menu("Switch Folder") {
                                ForEach(state.importedFolders) { bm in
                                    Button {
                                        state.selectSavedFolder(bm)
                                    } label: {
                                        HStack {
                                            Text(bm.name)
                                            if bm.name == state.currentFolderName { Image(systemName: "checkmark") }
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                            Image(systemName: "chevron.down").font(.caption2)
                        }.font(.system(size: 15, weight: .semibold))
                    }
                }
                // Right: sort + select
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !selected.isEmpty && isSelecting {
                        Button { showAddToPlaylist = true } label: {
                            Label("Add (\(selected.count))", systemImage: "text.badge.plus")
                        }
                    }
                    if !state.currentTracks.isEmpty {
                        Menu {
                            ForEach(TrackSortOption.allCases.filter { $0 != .manual }) { opt in
                                Button {
                                    state.setFolderSort(opt)
                                } label: {
                                    HStack {
                                        Text(opt.title)
                                        if state.folderSortOption == opt { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: { Image(systemName: "arrow.up.arrow.down") }

                        Button(isSelecting ? "Done" : "Select") {
                            withAnimation { isSelecting.toggle(); if !isSelecting { selected.removeAll() } }
                        }.fontWeight(.medium)
                    }
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { state.openFolder(url) }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistSheet(tracks: tracks.filter { selected.contains($0.id) })
                    .environmentObject(state)
            }
            .sheet(isPresented: $showRegexSheet) {
                RegexSelectionSheet(
                    tracks: tracks,
                    currentSelection: selected,
                    onApply: { matchedIds in
                        withAnimation {
                            isSelecting = true
                            selected = matchedIds
                        }
                    }
                )
            }
        }
    }

    // MARK: - Empty state

    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder.badge.plus").font(.system(size: 64)).foregroundStyle(.tint)
            Text("No Folder Selected").font(.title2).bold()
            Text("Open a folder from the Files app.\nFiles stream in place — nothing is copied.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button { showFilePicker = true } label: {
                Label("Open Folder", systemImage: "folder.fill").font(.headline).padding(.horizontal, 24).padding(.vertical, 12)
            }.buttonStyle(.borderedProminent)
            if !state.importedFolders.isEmpty {
                VStack(spacing: 8) {
                    Text("Recent Folders").font(.caption).foregroundStyle(.secondary)
                    ForEach(state.importedFolders) { bm in
                        Button { state.selectSavedFolder(bm) } label: {
                            HStack {
                                Image(systemName: "folder").foregroundStyle(.tint)
                                Text(bm.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(bm.trackCount)").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        }.padding(.horizontal)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Track list

    var trackList: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                Text("\(tracks.count) tracks").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !isSelecting {
                    Button {
                        showRegexSheet = true
                    } label: {
                        Label("Select Regex", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)

                    Button { state.playQueue(tracks) } label: {
                        Label("Play All", systemImage: "play.fill").font(.caption).fontWeight(.semibold)
                    }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                } else {
                    Button {
                        showRegexSheet = true
                    } label: {
                        Label("By Regex…", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                    }

                    Button(selected.count == tracks.count ? "Deselect All" : "Select All") {
                        selected = selected.count == tracks.count ? [] : Set(tracks.map(\.id))
                    }.font(.caption).fontWeight(.medium)
                }
            }
            .padding(.horizontal).padding(.vertical, 7)
            .background(Color(.secondarySystemBackground).opacity(0.5))

            if state.isLoadingTracks {
                Spacer(); ProgressView("Scanning…"); Spacer()
            } else if tracks.isEmpty {
                Spacer()
                Text("No audio files found").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                        TrackRow(track: track, index: idx, isSelecting: isSelecting, isSelected: selected.contains(track.id)) {
                            if isSelecting {
                                if selected.contains(track.id) { selected.remove(track.id) } else { selected.insert(track.id) }
                            } else {
                                state.playQueue(tracks, startingAt: idx)
                            }
                        }
                        .contextMenu {
                            Button { state.playQueue(tracks, startingAt: idx) } label: { Label("Play Now", systemImage: "play") }
                            Button { selected = selected.isEmpty ? [track.id] : selected.union([track.id]); showAddToPlaylist = true } label: {
                                Label(selected.isEmpty ? "Add to Playlist…" : "Add Selected (\(selected.union([track.id]).count)) to Playlist…", systemImage: "plus.circle")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await state.scanFolder() }
            }
        }
    }
}

// MARK: - TrackRow

struct TrackRow: View {
    @EnvironmentObject var state: AppState
    let track: AudioTrack
    let index: Int
    let isSelecting: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var isCurrent: Bool { state.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? AppTheme.orange : Color.secondary)
            } else {
                if isCurrent {
                    Image(systemName: state.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .foregroundStyle(AppTheme.orange).frame(width: 22)
                } else {
                    Text("\(index + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 22)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayName)
                    .font(.body).fontWeight(isCurrent ? .bold : .medium)
                    .foregroundStyle(isCurrent ? AppTheme.orange : .primary).lineLimit(1)
                Text(track.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(track.formattedDuration).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(Rectangle()).onTapGesture { onTap() }
    }
}

// MARK: - RegexSelectionSheet

struct RegexSelectionSheet: View {
    let tracks: [AudioTrack]
    let currentSelection: Set<UUID>
    let onApply: (Set<UUID>) -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("lastSelectionRegex") private var savedRegex: String = ""
    @State private var pattern: String = ""
    @State private var isCaseSensitive: Bool = false
    @State private var matchFilenamesOnly: Bool = false

    private let examples: [(title: String, pattern: String, note: String)] = [
        ("Live", "(?i)live", "Matches 'Live', 'live', etc."),
        ("Remix", "(?i)remix", "Matches remix versions"),
        ("Track Numbers", "^\\d+", "Starts with track numbers (01, 1, 2)"),
        ("Acoustic", "(?i)acoustic", "Matches acoustic tracks"),
        ("CD / Disc", "(?i)(cd|disc)\\s*\\d", "Matches CD1, Disc 2, etc."),
        ("Year in Name", "\\b(19|20)\\d{2}\\b", "Matches 4-digit years (e.g. 1999, 2024)")
    ]

    private var compiledRegex: NSRegularExpression? {
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var options: NSRegularExpression.Options = []
        if !isCaseSensitive {
            options.insert(.caseInsensitive)
        }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    private var regexError: String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: trimmed, options: isCaseSensitive ? [] : [.caseInsensitive])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var matchedTracks: [AudioTrack] {
        guard let regex = compiledRegex else { return [] }
        return tracks.filter { track in
            let textToMatch = matchFilenamesOnly ? track.fileName : "\(track.displayName) \(track.fileName)"
            let range = NSRange(location: 0, length: (textToMatch as NSString).length)
            return regex.firstMatch(in: textToMatch, options: [], range: range) != nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "regularshape.and.cursor")
                            .foregroundStyle(.secondary)
                        TextField("Regex pattern (e.g. (?i)live|remix)", text: $pattern)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.system(.body, design: .monospaced))
                        if !pattern.isEmpty {
                            Button { pattern = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let error = regexError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if !pattern.isEmpty {
                        HStack {
                            Text("Matched: **\(matchedTracks.count)** of \(tracks.count) tracks")
                                .font(.subheadline)
                                .foregroundStyle(matchedTracks.isEmpty ? .secondary : AppTheme.orange)
                            Spacer()
                        }
                    }
                } header: {
                    Text("Regular Expression")
                } footer: {
                    Text("Matches song titles and file names in this folder.")
                }

                Section("Examples (Tap to Use)") {
                    ForEach(examples, id: \.pattern) { ex in
                        Button {
                            pattern = ex.pattern
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(ex.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(ex.pattern)
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(AppTheme.orange)
                                }
                                Text(ex.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !matchedTracks.isEmpty {
                    Section("Preview Matches (\(matchedTracks.count))") {
                        ForEach(matchedTracks.prefix(8)) { track in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.orange)
                                    .font(.caption)
                                Text(track.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        if matchedTracks.count > 8 {
                            Text("... and \(matchedTracks.count - 8) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Select by Regex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select (\(matchedTracks.count))") {
                        applyMatches(unionWithExisting: false)
                    }
                    .fontWeight(.bold)
                    .disabled(matchedTracks.isEmpty)
                }
            }
            .onAppear {
                if pattern.isEmpty {
                    pattern = savedRegex
                }
            }
        }
    }

    private func applyMatches(unionWithExisting: Bool) {
        let matchedIds = Set(matchedTracks.map(\.id))
        savedRegex = pattern
        if unionWithExisting {
            onApply(currentSelection.union(matchedIds))
        } else {
            onApply(matchedIds)
        }
        dismiss()
    }
}

