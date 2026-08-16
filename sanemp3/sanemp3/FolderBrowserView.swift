//
//  FolderBrowserView.swift
//  sanemp3
//

import SwiftUI
import UniformTypeIdentifiers

struct FolderBrowserView: View {
    @ObservedObject var storage = StorageService.shared
    @ObservedObject var player = AudioPlayerService.shared
    
    @State private var isFileImporterPresented: Bool = false
    @State private var isSelectionMode: Bool = false
    @State private var selectedTrackIds: Set<UUID> = []
    @State private var isAddToPlaylistPresented: Bool = false
    @State private var searchText: String = ""
    @State private var showFoldersMenu: Bool = false
    
    var filteredTracks: [AudioTrack] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storage.currentTracks
        }
        return storage.currentTracks.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.displayArtist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if storage.currentFolderURL == nil {
                    emptyFolderPromptView
                } else {
                    trackListView
                }
            }
            .navigationTitle(storage.currentFolderName)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search tracks in folder")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    folderPickerMenu
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if isSelectionMode && !selectedTrackIds.isEmpty {
                            Button {
                                isAddToPlaylistPresented = true
                            } label: {
                                Label("Add (\(selectedTrackIds.count))", systemImage: "text.badge.plus")
                                    .fontWeight(.bold)
                            }
                        }
                        
                        if !storage.currentTracks.isEmpty {
                            // Sort Menu
                            Menu {
                                ForEach(TrackSortOption.allCases.filter { $0 != .manual }) { option in
                                    Button {
                                        storage.setFolderSortOption(option)
                                    } label: {
                                        HStack {
                                            Text(option.title)
                                            if storage.folderSortOption == option {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            
                            // Select / Done toggle
                            Button(isSelectionMode ? "Done" : "Select") {
                                withAnimation {
                                    isSelectionMode.toggle()
                                    if !isSelectionMode {
                                        selectedTrackIds.removeAll()
                                    }
                                }
                            }
                            .fontWeight(.medium)
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let folderURL = urls.first {
                        storage.openFolder(url: folderURL)
                    }
                case .failure(let error):
                    print("Error selecting folder: \(error)")
                }
            }
            .sheet(isPresented: $isAddToPlaylistPresented) {
                let selectedTracks = storage.currentTracks.filter { selectedTrackIds.contains($0.id) }
                AddToPlaylistSheet(tracksToAdd: selectedTracks)
            }
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyFolderPromptView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
            
            VStack(spacing: 8) {
                Text("No Folder Selected")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Pick a folder from Files containing your MP3 files. Files are streamed in place without making duplicate copies.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button {
                isFileImporterPresented = true
            } label: {
                Label("Open Folder from Files", systemImage: "folder.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            
            if !storage.importedFolders.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Previously Opened Folders")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    ForEach(storage.importedFolders) { bookmark in
                        Button {
                            storage.selectSavedFolder(bookmark)
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(Color.accentColor)
                                Text(bookmark.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(bookmark.trackCount) tracks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 16)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Folder Picker Menu
    
    private var folderPickerMenu: some View {
        Menu {
            if !selectedTrackIds.isEmpty {
                Button {
                    isAddToPlaylistPresented = true
                } label: {
                    Label("Add Selected (\(selectedTrackIds.count)) to Playlist...", systemImage: "text.badge.plus")
                }
                Divider()
            }
            
            Button {
                isFileImporterPresented = true
            } label: {
                Label("Open New Folder...", systemImage: "folder.badge.plus")
            }
            
            if !storage.importedFolders.isEmpty {
                Divider()
                Text("Switch Folder")
                ForEach(storage.importedFolders) { bookmark in
                    Button {
                        storage.selectSavedFolder(bookmark)
                    } label: {
                        HStack {
                            Text(bookmark.name)
                            if bookmark.name == storage.currentFolderName {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.system(size: 15, weight: .semibold))
        }
    }
    
    // MARK: - Track List View
    
    private var trackListView: some View {
        VStack(spacing: 0) {
            // Quick action / header bar
            HStack {
                Text("\(filteredTracks.count) \(filteredTracks.count == 1 ? "track" : "tracks")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !filteredTracks.isEmpty && !isSelectionMode {
                    Button {
                        player.playQueue(filteredTracks, startingAt: 0)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
            
            if storage.isLoadingTracks {
                Spacer()
                ProgressView("Scanning MP3 files...")
                Spacer()
            } else if filteredTracks.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No MP3 files found in this folder")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, track in
                        trackRowView(track: track, index: index)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await storage.scanCurrentFolder()
                }
            }
            
            // Bottom Action Bar when in Selection Mode
            if isSelectionMode {
                selectionBottomBar
            }
        }
    }
    
    // MARK: - Track Row
    
    private func trackRowView(track: AudioTrack, index: Int) -> some View {
        let isCurrentPlaying = player.currentTrack?.id == track.id
        let isSelected = selectedTrackIds.contains(track.id)
        
        return HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            } else {
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
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayName)
                    .font(.body)
                    .fontWeight(isCurrentPlaying ? .bold : .medium)
                    .foregroundStyle(isCurrentPlaying ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(track.displayArtist)
                        .lineLimit(1)
                    if !track.album.isEmpty {
                        Text("•")
                        Text(track.album)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(track.formattedDuration)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                if isSelected {
                    selectedTrackIds.remove(track.id)
                } else {
                    selectedTrackIds.insert(track.id)
                }
            } else {
                player.playQueue(filteredTracks, startingAt: index)
            }
        }
        .contextMenu {
            Button {
                player.playTrack(track, from: filteredTracks)
            } label: {
                Label("Play Now", systemImage: "play")
            }
            
            if !selectedTrackIds.isEmpty {
                Button {
                    if !selectedTrackIds.contains(track.id) {
                        selectedTrackIds.insert(track.id)
                    }
                    isAddToPlaylistPresented = true
                } label: {
                    Label("Add Selected (\(selectedTrackIds.count)) to Playlist...", systemImage: "text.badge.plus")
                }
            } else {
                Button {
                    selectedTrackIds = [track.id]
                    isAddToPlaylistPresented = true
                } label: {
                    Label("Add to Playlist...", systemImage: "plus.circle")
                }
            }
        }
    }
    
    // MARK: - Selection Bottom Bar
    
    private var selectionBottomBar: some View {
        HStack {
            Button(selectedTrackIds.count == filteredTracks.count ? "Deselect All" : "Select All") {
                if selectedTrackIds.count == filteredTracks.count {
                    selectedTrackIds.removeAll()
                } else {
                    selectedTrackIds = Set(filteredTracks.map { $0.id })
                }
            }
            .font(.subheadline)
            
            Spacer()
            
            Button {
                isAddToPlaylistPresented = true
            } label: {
                Label("Add to Playlist (\(selectedTrackIds.count))", systemImage: "text.badge.plus")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTrackIds.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .padding(.bottom, player.currentTrack != nil ? 64 : 0)
        .background(Color(uiColor: .systemBackground))
        .overlay(
            Divider(), alignment: .top
        )
    }
}
