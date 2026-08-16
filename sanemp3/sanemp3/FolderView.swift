//
//  FolderView.swift
//  sanemp3
//

import SwiftUI
import UniformTypeIdentifiers

struct FolderView: View {
    @Environment(AppState.self) var state
    @State private var showFilePicker = false
    @State private var isSelecting = false
    @State private var selected = Set<UUID>()
    @State private var showAddToPlaylist = false
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
                    .environment(state)
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
            HStack {
                Text("\(tracks.count) tracks").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !isSelecting {
                    Button { state.playQueue(tracks) } label: {
                        Label("Play All", systemImage: "play.fill").font(.caption).fontWeight(.semibold)
                    }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                } else {
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
    @Environment(AppState.self) var state
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
                    .font(.title3).foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            } else {
                if isCurrent {
                    Image(systemName: state.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .foregroundStyle(.tint).frame(width: 22)
                } else {
                    Text("\(index + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 22)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayName)
                    .font(.body).fontWeight(isCurrent ? .bold : .medium)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary).lineLimit(1)
                Text(track.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(track.formattedDuration).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(Rectangle()).onTapGesture { onTap() }
    }
}
