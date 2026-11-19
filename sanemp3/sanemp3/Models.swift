//
//  Models.swift
//  sanemp3
//

import Foundation
import AVFoundation
import UIKit
import SwiftUI
import Combine
import CryptoKit

// MARK: - App Theme (Brown & Orange Palette)

struct AppTheme {
    static let orange = Color(red: 0.96, green: 0.48, blue: 0.12)
    static let warmBrown = Color(red: 0.46, green: 0.26, blue: 0.14)
    static let darkBrown = Color(red: 0.28, green: 0.15, blue: 0.08)
    static let softAmber = Color(red: 0.88, green: 0.60, blue: 0.28)

    static var brownOrangeGradient: LinearGradient {
        LinearGradient(
            colors: [warmBrown, orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var coverPlaceholderGradient: LinearGradient {
        LinearGradient(
            colors: [darkBrown, warmBrown, orange.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Bottom List Spacer
/**
 * Extra non-interactive transparent element placed at the bottom of scrollable lists
 * to prevent items from being obscured by the floating Mini Player bar, bottom Tab Bar, or home indicator.
 */
struct BottomListSpacer: View {
    @EnvironmentObject var state: AppState
    var defaultHeight: CGFloat = 40
    var playerHeight: CGFloat = 90

    var body: some View {
        Color.clear
            .frame(height: state.currentTrack != nil ? playerHeight : defaultHeight)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .allowsHitTesting(false)
    }
}


// MARK: - AudioTrack

/**
 * One audio file.
 *
 * `id` is stable: a hash of "<folder name>/<path inside the folder>". The same file gets the
 * same id on every scan and every launch, so the "now playing" highlight, playlists and
 * Resume Points keep matching it. It is also the track's key in the PlayLogic library.
 *
 * The hash is NOT made from the absolute path on purpose: on iOS the beginning of an absolute
 * path contains container ids that change between installs, which would change every id.
 *
 * `folderID` + `relativePath` say where the file lives. The playable URL is rebuilt from them
 * (AppState.playableURL), `url` is only the location seen at scan time.
 * Tracks saved by old versions have neither and keep their old random id.
 */
struct AudioTrack: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var creationDate: Date
    var folderID: UUID?
    var relativePath: String?

    var fileName: String {
        url.lastPathComponent
    }
    var displayName: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? url.deletingPathExtension().lastPathComponent
            : title
    }
    var displayArtist: String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Artist" : artist
    }
    var formattedDuration: String {
        let m = Int(duration) / 60; let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }

    init(id: String, url: URL, title: String = "", artist: String = "",
         album: String = "", duration: TimeInterval = 0, creationDate: Date = Date(),
         folderID: UUID? = nil, relativePath: String? = nil) {
        self.id = id; self.url = url; self.title = title; self.artist = artist
        self.album = album; self.duration = duration; self.creationDate = creationDate
        self.folderID = folderID; self.relativePath = relativePath
    }

    /**
     * Stable track id: first 16 bytes of SHA-256 of "<folder name>/<path inside the folder>", as hex.
     *
     * Usage:
     *   AudioTrack.stableID(folderName: "Music", relativePath: "Album/01 Intro.mp3")
     */
    static func stableID(folderName: String, relativePath: String) -> String {
        let digest = SHA256.hash(data: Data("\(folderName)/\(relativePath)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // Reads metadata of one file found while scanning `folder`.
    static func load(from url: URL, folder: FolderBookmark, relativePath: String) async -> AudioTrack {
        var t = "", ar = "", al = "", dur: TimeInterval = 0, cd = Date()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            cd = attrs[.creationDate] as? Date ?? attrs[.modificationDate] as? Date ?? Date()
        }
        let asset = AVURLAsset(url: url)
        if let d = try? await asset.load(.duration) { dur = max(0, CMTimeGetSeconds(d)) }
        if let meta = try? await asset.load(.commonMetadata) {
            for item in meta {
                guard let key = item.commonKey, let str = try? await item.load(.stringValue) else { continue }
                switch key {
                case .commonKeyTitle: t = str
                case .commonKeyArtist: ar = str
                case .commonKeyAlbumName: al = str
                default: break
                }
            }
        }
        if t.isEmpty { t = url.deletingPathExtension().lastPathComponent }
        return AudioTrack(id: stableID(folderName: folder.name, relativePath: relativePath), url: url,
                          title: t, artist: ar, album: al, duration: dur, creationDate: cd,
                          folderID: folder.id, relativePath: relativePath)
    }

    // Same track, now tied to a folder: gets the stable id. Used to upgrade tracks of old versions.
    func adopted(by folder: FolderBookmark, relativePath: String) -> AudioTrack {
        AudioTrack(id: AudioTrack.stableID(folderName: folder.name, relativePath: relativePath), url: url,
                   title: title, artist: artist, album: album, duration: duration, creationDate: creationDate,
                   folderID: folder.id, relativePath: relativePath)
    }

    static func loadArtwork(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        guard let meta = try? await asset.load(.commonMetadata) else { return nil }
        for item in meta where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue) { return UIImage(data: data) }
        }
        return nil
    }
}

extension Array where Element == AudioTrack {
    // Keeps the first occurrence of every track. The same track is never listed twice.
    func uniqueByID() -> [AudioTrack] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Playlist

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var tracks: [AudioTrack]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, tracks: [AudioTrack] = [], createdAt: Date = Date()) {
        self.id = id; self.name = name; self.tracks = tracks; self.createdAt = createdAt
    }
    var totalDuration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }
    var formattedTotal: String {
        let h = Int(totalDuration) / 3600, m = (Int(totalDuration) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - FolderBookmark

struct FolderBookmark: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bookmarkData: Data
    var lastOpened: Date
    var trackCount: Int

    init(id: UUID = UUID(), name: String, bookmarkData: Data,
         lastOpened: Date = Date(), trackCount: Int = 0) {
        self.id = id; self.name = name; self.bookmarkData = bookmarkData
        self.lastOpened = lastOpened; self.trackCount = trackCount
    }
}

// MARK: - Sort Option

enum TrackSortOption: String, CaseIterable, Identifiable, Codable {
    case nameAsc = "name_asc", nameDesc = "name_desc"
    case dateNewest = "date_newest", dateOldest = "date_oldest"
    case manual = "manual"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nameAsc: return "Name (A → Z)"
        case .nameDesc: return "Name (Z → A)"
        case .dateNewest: return "Date (Newest)"
        case .dateOldest: return "Date (Oldest)"
        case .manual: return "Custom Order"
        }
    }
    func sort(_ tracks: [AudioTrack]) -> [AudioTrack] {
        switch self {
        case .nameAsc: return tracks.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .nameDesc: return tracks.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedDescending }
        case .dateNewest: return tracks.sorted { $0.creationDate > $1.creationDate }
        case .dateOldest: return tracks.sorted { $0.creationDate < $1.creationDate }
        case .manual: return tracks
        }
    }
}
