//
//  Models.swift
//  sanemp3
//

import Foundation
import AVFoundation
import UIKit
import SwiftUI

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

// MARK: - AudioTrack

struct AudioTrack: Identifiable, Codable, Hashable, Equatable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var creationDate: Date
    var bookmarkData: Data?

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

    init(id: UUID = UUID(), url: URL, title: String = "", artist: String = "",
         album: String = "", duration: TimeInterval = 0, creationDate: Date = Date(),
         bookmarkData: Data? = nil) {
        self.id = id; self.url = url; self.title = title; self.artist = artist
        self.album = album; self.duration = duration; self.creationDate = creationDate
        self.bookmarkData = bookmarkData
    }

    static func load(from url: URL) async -> AudioTrack {
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
        let bm = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return AudioTrack(url: url, title: t, artist: ar, album: al, duration: dur, creationDate: cd, bookmarkData: bm)
    }

    func loadArtwork() async -> UIImage? {
        let asset = AVURLAsset(url: url)
        guard let meta = try? await asset.load(.commonMetadata) else { return nil }
        for item in meta where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue) { return UIImage(data: data) }
        }
        return nil
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

// MARK: - Saved Playback State

struct SavedPlaybackState: Codable {
    var track: AudioTrack
    var queue: [AudioTrack]
    var currentIndex: Int
    var currentTime: TimeInterval
    var repeatMode: RepeatMode
    var isShuffle: Bool
}

enum RepeatMode: String, CaseIterable, Identifiable, Codable {
    case off, all, one
    var id: String { rawValue }
    var icon: String {
        switch self { case .off: return "repeat"; case .all: return "repeat"; case .one: return "repeat.1" }
    }
}
