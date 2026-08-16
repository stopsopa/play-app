//
//  StorageService.swift
//  sanemp3
//

import Foundation
import SwiftUI
import Combine

@MainActor
public final class StorageService: ObservableObject {
    public static let shared = StorageService()
    
    @Published public var importedFolders: [FolderBookmark] = []
    @Published public var currentFolderURL: URL?
    @Published public var currentFolderName: String = "No Folder Selected"
    @Published public var currentTracks: [AudioTrack] = []
    @Published public var isLoadingTracks: Bool = false
    @Published public var playlists: [Playlist] = []
    @Published public var folderSortOption: TrackSortOption = .nameAscending
    
    private var activeSecurityScopedURL: URL?
    
    private var appSupportDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("sanemp3", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var playlistsFileURL: URL {
        appSupportDirectory.appendingPathComponent("playlists.json")
    }
    
    private var foldersFileURL: URL {
        appSupportDirectory.appendingPathComponent("folders.json")
    }
    
    private let lastFolderKey = "sanemp3_last_folder_id"
    private let folderSortKey = "sanemp3_folder_sort_option"
    
    public init() {
        if let savedSort = UserDefaults.standard.string(forKey: folderSortKey),
           let option = TrackSortOption(rawValue: savedSort) {
            self.folderSortOption = option
        }
        loadFolders()
        loadPlaylists()
        restoreLastFolder()
    }
    
    deinit {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }
    
    // MARK: - Folder Management
    
    public func openFolder(url: URL) {
        // Release previous access
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
        
        let isAccessGranted = url.startAccessingSecurityScopedResource()
        if isAccessGranted {
            activeSecurityScopedURL = url
        }
        
        let bookmarkData = (try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? Data()
        
        saveFolder(url: url, bookmarkData: bookmarkData)
    }
    
    private func saveFolder(url: URL, bookmarkData: Data) {
        currentFolderURL = url
        currentFolderName = url.lastPathComponent
        
        let folderId: UUID
        if let existingIndex = importedFolders.firstIndex(where: { $0.name == url.lastPathComponent }) {
            importedFolders[existingIndex].bookmarkData = bookmarkData
            importedFolders[existingIndex].lastOpened = Date()
            folderId = importedFolders[existingIndex].id
        } else {
            let newBookmark = FolderBookmark(
                name: url.lastPathComponent,
                bookmarkData: bookmarkData,
                lastOpened: Date()
            )
            importedFolders.insert(newBookmark, at: 0)
            folderId = newBookmark.id
        }
        
        UserDefaults.standard.set(folderId.uuidString, forKey: lastFolderKey)
        persistFolders()
        
        Task {
            await scanCurrentFolder()
        }
    }
    
    public func selectSavedFolder(_ bookmark: FolderBookmark) {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark.bookmarkData,
            bookmarkDataIsStale: &isStale
        ) else {
            return
        }
        
        openFolder(url: url)
    }
    
    public func removeSavedFolder(_ bookmark: FolderBookmark) {
        importedFolders.removeAll { $0.id == bookmark.id }
        persistFolders()
        if currentFolderName == bookmark.name {
            currentFolderURL = nil
            currentFolderName = "No Folder Selected"
            currentTracks = []
            activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
        }
    }
    
    private func restoreLastFolder() {
        guard let lastIdString = UserDefaults.standard.string(forKey: lastFolderKey),
              let lastId = UUID(uuidString: lastIdString),
              let bookmark = importedFolders.first(where: { $0.id == lastId }) else {
            if let first = importedFolders.first {
                selectSavedFolder(first)
            }
            return
        }
        selectSavedFolder(bookmark)
    }
    
    public func scanCurrentFolder() async {
        guard let folderURL = currentFolderURL else { return }
        
        isLoadingTracks = true
        let supportedExtensions = Set(["mp3", "m4a", "aac", "wav", "flac", "aiff", "caf"])
        
        var audioURLs: [URL] = []
        let fileManager = FileManager.default
        
        if let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if supportedExtensions.contains(ext) {
                    audioURLs.append(fileURL)
                }
            }
        }
        
        var loadedTracks: [AudioTrack] = []
        for url in audioURLs {
            let track = await AudioTrack.load(from: url)
            loadedTracks.append(track)
        }
        
        self.currentTracks = folderSortOption.sort(tracks: loadedTracks)
        self.isLoadingTracks = false
        
        // Update track count on bookmark
        if let index = importedFolders.firstIndex(where: { $0.name == folderURL.lastPathComponent }) {
            importedFolders[index].trackCount = loadedTracks.count
            persistFolders()
        }
    }
    
    public func setFolderSortOption(_ option: TrackSortOption) {
        self.folderSortOption = option
        UserDefaults.standard.set(option.rawValue, forKey: folderSortKey)
        self.currentTracks = option.sort(tracks: self.currentTracks)
    }
    
    // MARK: - Playlist Management
    
    public func createPlaylist(name: String, tracks: [AudioTrack] = []) -> Playlist {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "New Playlist" : trimmedName
        let newPlaylist = Playlist(name: finalName, tracks: tracks)
        playlists.append(newPlaylist)
        persistPlaylists()
        return newPlaylist
    }
    
    public func addTracks(_ tracks: [AudioTrack], to playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        // Append tracks that aren't already duplicate, or append all
        playlists[index].tracks.append(contentsOf: tracks)
        playlists[index].updatedAt = Date()
        persistPlaylists()
    }
    
    public func removeTrack(at index: Int, from playlistId: UUID) {
        guard let pIndex = playlists.firstIndex(where: { $0.id == playlistId }),
              playlists[pIndex].tracks.indices.contains(index) else { return }
        playlists[pIndex].tracks.remove(at: index)
        playlists[pIndex].updatedAt = Date()
        persistPlaylists()
    }
    
    public func removeTracks(at offsets: IndexSet, from playlistId: UUID) {
        guard let pIndex = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[pIndex].tracks.remove(atOffsets: offsets)
        playlists[pIndex].updatedAt = Date()
        persistPlaylists()
    }
    
    public func moveTracks(from source: IndexSet, to destination: Int, in playlistId: UUID) {
        guard let pIndex = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[pIndex].tracks.move(fromOffsets: source, toOffset: destination)
        playlists[pIndex].updatedAt = Date()
        persistPlaylists()
    }
    
    public func renamePlaylist(_ playlist: Playlist, newName: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        playlists[index].updatedAt = Date()
        persistPlaylists()
    }
    
    public func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        persistPlaylists()
    }
    
    public func sortPlaylistTracks(playlistId: UUID, option: TrackSortOption) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].tracks = option.sort(tracks: playlists[index].tracks)
        playlists[index].updatedAt = Date()
        persistPlaylists()
    }
    
    // MARK: - Persistence Helpers
    
    private func persistPlaylists() {
        do {
            let data = try JSONEncoder().encode(playlists)
            try data.write(to: playlistsFileURL, options: .atomic)
        } catch {
            print("Failed to save playlists: \(error)")
        }
    }
    
    private func loadPlaylists() {
        guard FileManager.default.fileExists(atPath: playlistsFileURL.path),
              let data = try? Data(contentsOf: playlistsFileURL),
              let loaded = try? JSONDecoder().decode([Playlist].self, from: data) else {
            self.playlists = []
            return
        }
        self.playlists = loaded
    }
    
    private func persistFolders() {
        do {
            let data = try JSONEncoder().encode(importedFolders)
            try data.write(to: foldersFileURL, options: .atomic)
        } catch {
            print("Failed to save folder bookmarks: \(error)")
        }
    }
    
    private func loadFolders() {
        guard FileManager.default.fileExists(atPath: foldersFileURL.path),
              let data = try? Data(contentsOf: foldersFileURL),
              let loaded = try? JSONDecoder().decode([FolderBookmark].self, from: data) else {
            self.importedFolders = []
            return
        }
        self.importedFolders = loaded
    }
}
