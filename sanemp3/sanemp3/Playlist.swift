//
//  Playlist.swift
//  sanemp3
//

import Foundation

public struct Playlist: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var tracks: [AudioTrack]
    
    public var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
    
    public var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        let seconds = Int(totalDuration) % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm %02ds", minutes, seconds)
        }
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tracks: [AudioTrack] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tracks = tracks
    }
}
