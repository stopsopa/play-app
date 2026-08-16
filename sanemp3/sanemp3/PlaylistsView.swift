//
//  PlaylistsView.swift
//  sanemp3
//

import SwiftUI

// MARK: - Playlists list

struct PlaylistsView: View {
    @Environment(AppState.self) var state
    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if state.playlists.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(state.playlists) { pl in
                            NavigationLink(destination: PlaylistDetailView(playlistId: pl.id).environment(state)) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 48, height: 48)
                                        Image(systemName: "music.note.list").foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(pl.name).font(.body).fontWeight(.semibold)
                                        Text("\(pl.tracks.count) tracks · \(pl.formattedTotal)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 3)
                            }
                        }
                        .onDelete { idx in idx.forEach { state.deletePlaylist(state.playlists[$0].id) } }
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; showCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("New Playlist", isPresented: $showCreate) {
                TextField("Name", text: $newName)
                Button("Create") { state.createPlaylist(name: newName) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "music.note.list").font(.system(size: 64)).foregroundStyle(.tint)
            Text("No Playlists").font(.title2).bold()
            Text("Create playlists to organise your favourite songs.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button { newName = ""; showCreate = true } label: {
                Label("Create Playlist", systemImage: "plus").font(.headline).padding(.horizontal, 24).padding(.vertical, 12)
            }.buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

// MARK: - Playlist detail

struct PlaylistDetailView: View {
    @Environment(AppState.self) var state
    let playlistId: UUID
    @State private var isEditing = false
    @State private var showRename = false
    @State private var newName = ""

    var playlist: Playlist? { state.playlists.first(where: { $0.id == playlistId }) }

    var body: some View {
        Group {
            if let pl = playlist {
                VStack(spacing: 0) {
                    // Header bar
                    HStack {
                        Text("\(pl.tracks.count) tracks · \(pl.formattedTotal)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !pl.tracks.isEmpty {
                            Button { state.playQueue(pl.tracks) } label: {
                                Label("Play", systemImage: "play.fill").font(.caption).fontWeight(.semibold)
                            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground).opacity(0.5))

                    if pl.tracks.isEmpty {
                        Spacer()
                        Text("No tracks yet.\nAdd songs from the Folder tab.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Spacer()
                    } else {
                        List {
                            ForEach(Array(pl.tracks.enumerated()), id: \.element.id) { idx, track in
                                TrackRow(track: track, index: idx, isSelecting: false, isSelected: false) {
                                    state.playQueue(pl.tracks, startingAt: idx)
                                }
                                .environment(state)
                            }
                            .onDelete { state.removeTrack(at: $0, from: playlistId) }
                            .onMove { state.moveTracks(from: $0, to: $1, in: playlistId) }
                        }
                        .listStyle(.plain)
                        .environment(\.editMode, isEditing ? .constant(.active) : .constant(.inactive))
                    }
                }
                .navigationTitle(pl.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if !pl.tracks.isEmpty {
                            Menu {
                                ForEach(TrackSortOption.allCases) { opt in
                                    Button { state.sortPlaylist(playlistId, option: opt) } label: { Text(opt.title) }
                                }
                            } label: { Image(systemName: "arrow.up.arrow.down") }
                            Button(isEditing ? "Done" : "Reorder") { withAnimation { isEditing.toggle() } }.fontWeight(.medium)
                        }
                        Menu {
                            Button { newName = pl.name; showRename = true } label: { Label("Rename", systemImage: "pencil") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .alert("Rename", isPresented: $showRename) {
                    TextField("Name", text: $newName)
                    Button("Save") { state.renamePlaylist(playlistId, name: newName) }
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                Text("Playlist not found")
            }
        }
    }
}

// MARK: - Add to playlist sheet

struct AddToPlaylistSheet: View {
    @Environment(AppState.self) var state
    @Environment(\.dismiss) var dismiss
    let tracks: [AudioTrack]
    @State private var newName = ""
    @State private var showCreate = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Create New") {
                    if showCreate {
                        HStack {
                            TextField("Playlist name", text: $newName)
                                .focused($isNameFocused)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit {
                                    createAndAdd()
                                }
                            Button("Add") {
                                createAndAdd()
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        Button {
                            withAnimation {
                                showCreate = true
                            }
                            isNameFocused = true
                        } label: {
                            Label("New Playlist…", systemImage: "plus.circle.fill").foregroundStyle(.tint).fontWeight(.semibold)
                        }
                    }
                }
                Section("Existing Playlists") {
                    if state.playlists.isEmpty {
                        Text("No playlists yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(state.playlists) { pl in
                            Button {
                                state.addTracksToPlaylist(tracks, playlistId: pl.id); dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(pl.name).foregroundStyle(.primary).fontWeight(.medium)
                                        Text("\(pl.tracks.count) tracks").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add \(tracks.count) Song\(tracks.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
    }

    private func createAndAdd() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.createPlaylist(name: trimmed, tracks: tracks)
        dismiss()
    }
}
