//
//  PlaylistDetailView.swift
//  sanemp3
//

import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: UUID
    @ObservedObject var storage = StorageService.shared
    @ObservedObject var player = AudioPlayerService.shared
    
    @State private var isEditing: Bool = false
    @State private var isRenameAlertPresented: Bool = false
    @State private var newPlaylistName: String = ""
    @State private var selectedSort: TrackSortOption = .manual
    
    var playlist: Playlist? {
        storage.playlists.first(where: { $0.id == playlistId })
    }
    
    var body: some View {
        Group {
            if let playlist = playlist {
                VStack(spacing: 0) {
                    // Header Actions (Play All, Shuffle, Sort)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(playlist.tracks.count) \(playlist.tracks.count == 1 ? "track" : "tracks")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if playlist.totalDuration > 0 {
                                Text(playlist.formattedTotalDuration)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if !playlist.tracks.isEmpty {
                            Button {
                                player.playQueue(playlist.tracks, startingAt: 0)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            
                            Button {
                                player.isShuffle = true
                                player.playQueue(playlist.tracks, startingAt: 0)
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
                    
                    if playlist.tracks.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("This playlist is empty")
                                .font(.headline)
                            Text("Select songs in any folder and choose 'Add to Playlist'")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                                playlistTrackRow(track: track, index: index, playlist: playlist)
                            }
                            .onDelete { offsets in
                                storage.removeTracks(at: offsets, from: playlistId)
                            }
                            .onMove { source, destination in
                                storage.moveTracks(from: source, to: destination, in: playlistId)
                            }
                        }
                        .listStyle(.plain)
                        .environment(\.editMode, isEditing ? .constant(.active) : .constant(.inactive))
                    }
                }
                .navigationTitle(playlist.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            if !playlist.tracks.isEmpty {
                                // Sort Menu
                                Menu {
                                    ForEach(TrackSortOption.allCases) { option in
                                        Button {
                                            selectedSort = option
                                            storage.sortPlaylistTracks(playlistId: playlistId, option: option)
                                        } label: {
                                            HStack {
                                                Text(option.title)
                                                if selectedSort == option {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                
                                Button(isEditing ? "Done" : "Reorder") {
                                    withAnimation {
                                        isEditing.toggle()
                                    }
                                }
                                .fontWeight(.medium)
                            }
                            
                            Menu {
                                Button {
                                    newPlaylistName = playlist.name
                                    isRenameAlertPresented = true
                                } label: {
                                    Label("Rename Playlist", systemImage: "pencil")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
                .alert("Rename Playlist", isPresented: $isRenameAlertPresented) {
                    TextField("Playlist Name", text: $newPlaylistName)
                    Button("Save") {
                        storage.renamePlaylist(playlist, newName: newPlaylistName)
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                Text("Playlist not found")
            }
        }
    }
    
    private func playlistTrackRow(track: AudioTrack, index: Int, playlist: Playlist) -> some View {
        let isCurrentPlaying = player.currentTrack?.id == track.id
        
        return HStack(spacing: 12) {
            if isCurrentPlaying {
                Image(systemName: player.isPlaying ? "speaker.wave.3.fill" : "speaker.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
            } else {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayName)
                    .font(.body)
                    .fontWeight(isCurrentPlaying ? .bold : .medium)
                    .foregroundStyle(isCurrentPlaying ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                
                Text(track.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(track.formattedDuration)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            player.playQueue(playlist.tracks, startingAt: index)
        }
    }
}
