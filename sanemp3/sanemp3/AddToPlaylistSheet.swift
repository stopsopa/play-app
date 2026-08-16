//
//  AddToPlaylistSheet.swift
//  sanemp3
//

import SwiftUI

struct AddToPlaylistSheet: View {
    let tracksToAdd: [AudioTrack]
    @ObservedObject var storage = StorageService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var newPlaylistName: String = ""
    @State private var isShowingCreateField: Bool = false
    @State private var selectedPlaylistId: UUID? = nil
    @State private var showAddedSuccess: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isShowingCreateField {
                        HStack {
                            TextField("Playlist Name", text: $newPlaylistName)
                                .textInputAutocapitalization(.words)
                            
                            Button("Create & Add") {
                                guard !newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                let _ = storage.createPlaylist(name: newPlaylistName, tracks: tracksToAdd)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        Button {
                            isShowingCreateField = true
                        } label: {
                            Label("New Playlist...", systemImage: "plus.circle.fill")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } header: {
                    Text("Create New")
                }
                
                Section {
                    if storage.playlists.isEmpty {
                        Text("No playlists yet. Create one above!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(storage.playlists) { playlist in
                            Button {
                                storage.addTracks(tracksToAdd, to: playlist.id)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        
                                        Text("\(playlist.tracks.count) songs")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "plus.circle")
                                        .font(.title3)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Existing Playlists")
                }
            }
            .navigationTitle("Add \(tracksToAdd.count) \(tracksToAdd.count == 1 ? "Song" : "Songs")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
