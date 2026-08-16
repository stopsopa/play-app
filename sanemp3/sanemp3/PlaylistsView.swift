//
//  PlaylistsView.swift
//  sanemp3
//

import SwiftUI

struct PlaylistsView: View {
    @ObservedObject var storage = StorageService.shared
    
    @State private var isCreateAlertPresented: Bool = false
    @State private var newPlaylistName: String = ""
    
    var body: some View {
        NavigationStack {
            Group {
                if storage.playlists.isEmpty {
                    emptyPlaylistsView
                } else {
                    List {
                        ForEach(storage.playlists) { playlist in
                            NavigationLink(destination: PlaylistDetailView(playlistId: playlist.id)) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 48, height: 48)
                                        
                                        Image(systemName: "music.note.list")
                                            .font(.title3)
                                            .foregroundStyle(.white)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.name)
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                        
                                        Text("\(playlist.tracks.count) \(playlist.tracks.count == 1 ? "track" : "tracks")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                storage.deletePlaylist(storage.playlists[index])
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPlaylistName = ""
                        isCreateAlertPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .alert("New Playlist", isPresented: $isCreateAlertPresented) {
                TextField("Playlist Name", text: $newPlaylistName)
                Button("Create") {
                    let _ = storage.createPlaylist(name: newPlaylistName)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    
    private var emptyPlaylistsView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            
            VStack(spacing: 8) {
                Text("No Playlists")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Create playlists to organize your favorite songs from different folders.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button {
                newPlaylistName = ""
                isCreateAlertPresented = true
            } label: {
                Label("Create Playlist", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
    }
}
