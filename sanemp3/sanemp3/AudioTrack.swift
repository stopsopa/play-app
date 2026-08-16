//
//  AudioTrack.swift
//  sanemp3
//

import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer

public struct AudioTrack: Identifiable, Codable, Hashable, Equatable {
    public let id: UUID
    public let url: URL
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var fileSize: Int64
    public var creationDate: Date
    public var bookmarkData: Data?
    
    public var fileName: String {
        url.lastPathComponent
    }
    
    public var displayName: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return url.deletingPathExtension().lastPathComponent
    }
    
    public var displayArtist: String {
        if !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return artist
        }
        return "Unknown Artist"
    }
    
    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    public init(
        id: UUID = UUID(),
        url: URL,
        title: String = "",
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        fileSize: Int64 = 0,
        creationDate: Date = Date(),
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileSize = fileSize
        self.creationDate = creationDate
        self.bookmarkData = bookmarkData
    }
    
    public static func load(from url: URL) async -> AudioTrack {
        var trackTitle = ""
        var trackArtist = ""
        var trackAlbum = ""
        var trackDuration: TimeInterval = 0
        var trackFileSize: Int64 = 0
        var trackCreationDate = Date()
        var bookmark: Data? = nil
        
        // File attributes
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            trackFileSize = attrs[.size] as? Int64 ?? 0
            trackCreationDate = attrs[.creationDate] as? Date ?? attrs[.modificationDate] as? Date ?? Date()
        }
        
        // Security bookmark
        bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        
        // AVAsset metadata extraction
        let asset = AVURLAsset(url: url)
        if let dur = try? await asset.load(.duration) {
            trackDuration = CMTimeGetSeconds(dur)
            if trackDuration.isNaN || trackDuration.isInfinite {
                trackDuration = 0
            }
        }
        
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let commonKey = item.commonKey else { continue }
                switch commonKey {
                case .commonKeyTitle:
                    if let stringVal = try? await item.load(.stringValue) {
                        trackTitle = stringVal
                    }
                case .commonKeyArtist:
                    if let stringVal = try? await item.load(.stringValue) {
                        trackArtist = stringVal
                    }
                case .commonKeyAlbumName:
                    if let stringVal = try? await item.load(.stringValue) {
                        trackAlbum = stringVal
                    }
                default:
                    break
                }
            }
        }
        
        if trackTitle.isEmpty {
            trackTitle = url.deletingPathExtension().lastPathComponent
        }
        
        return AudioTrack(
            url: url,
            title: trackTitle,
            artist: trackArtist,
            album: trackAlbum,
            duration: trackDuration,
            fileSize: trackFileSize,
            creationDate: trackCreationDate,
            bookmarkData: bookmark
        )
    }
    
    /// Loads album artwork UIImage asynchronously from the file
    public func loadArtwork() async -> UIImage? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        
        for item in metadata {
            if item.commonKey == .commonKeyArtwork {
                if let data = try? await item.load(.dataValue), let image = UIImage(data: data) {
                    return image
                }
            }
        }
        return nil
    }
}
