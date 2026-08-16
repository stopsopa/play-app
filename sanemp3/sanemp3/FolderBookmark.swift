//
//  FolderBookmark.swift
//  sanemp3
//

import Foundation

public struct FolderBookmark: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var bookmarkData: Data
    public var lastOpened: Date
    public var trackCount: Int
    
    public init(
        id: UUID = UUID(),
        name: String,
        bookmarkData: Data,
        lastOpened: Date = Date(),
        trackCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.lastOpened = lastOpened
        self.trackCount = trackCount
    }
}
