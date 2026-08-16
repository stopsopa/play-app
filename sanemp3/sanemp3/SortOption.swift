//
//  SortOption.swift
//  sanemp3
//

import Foundation

public enum TrackSortOption: String, CaseIterable, Identifiable, Codable {
    case nameAscending = "name_asc"
    case nameDescending = "name_desc"
    case dateNewest = "date_newest"
    case dateOldest = "date_oldest"
    case durationAscending = "duration_asc"
    case durationDescending = "duration_desc"
    case manual = "manual"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .nameAscending:
            return "Name (A → Z)"
        case .nameDescending:
            return "Name (Z → A)"
        case .dateNewest:
            return "Date Added (Newest first)"
        case .dateOldest:
            return "Date Added (Oldest first)"
        case .durationAscending:
            return "Duration (Shortest first)"
        case .durationDescending:
            return "Duration (Longest first)"
        case .manual:
            return "Custom Order"
        }
    }
    
    public var iconName: String {
        switch self {
        case .nameAscending:
            return "textformat.abc"
        case .nameDescending:
            return "textformat.abc"
        case .dateNewest:
            return "calendar.badge.clock"
        case .dateOldest:
            return "calendar"
        case .durationAscending:
            return "hourglass.bottomhalf.filled"
        case .durationDescending:
            return "hourglass.tophalf.filled"
        case .manual:
            return "arrow.up.and.down.and.sparkles"
        }
    }
    
    public func sort(tracks: [AudioTrack]) -> [AudioTrack] {
        switch self {
        case .nameAscending:
            return tracks.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .nameDescending:
            return tracks.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedDescending }
        case .dateNewest:
            return tracks.sorted { $0.creationDate > $1.creationDate }
        case .dateOldest:
            return tracks.sorted { $0.creationDate < $1.creationDate }
        case .durationAscending:
            return tracks.sorted { $0.duration < $1.duration }
        case .durationDescending:
            return tracks.sorted { $0.duration > $1.duration }
        case .manual:
            return tracks
        }
    }
}
