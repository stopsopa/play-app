//
//  Models.swift
//  sanemp3
//

import Foundation
import AVFoundation
import UIKit
import SwiftUI
import Combine

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

// MARK: - Provisioning Profile Expiration Service & View (Debug/Development)

/**
 * Service responsible for locating and decoding `embedded.mobileprovision` bundled with the application,
 * and extracting provisioning profile details such as the expiration date.
 */
enum ProvisioningStatus: Equatable {
    case unknown
    case valid(expirationDate: Date)
    case expired(expirationDate: Date)
}

@MainActor
final class ProvisioningProfileService: ObservableObject {
    static let shared = ProvisioningProfileService()

    @Published private(set) var status: ProvisioningStatus = .unknown
    @Published private(set) var expirationDate: Date?
    @Published private(set) var compactCountdown: String = "???"
    @Published private(set) var detailedRemaining: String = "Unknown"

    private var hasLoaded = false
    private var timer: Timer?

    private init() {}

    deinit {
        timer?.invalidate()
    }

    /**
     * Starts periodic updates and loads profile if not already loaded.
     */
    func startMonitoring() {
        guard !hasLoaded else { return }
        hasLoaded = true
        loadProfile()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                Task { @MainActor in
                    ProvisioningProfileService.shared.updateCountdown()
                }
            }
        }
    }

    /**
     * Reads `embedded.mobileprovision` from Bundle.main and parses the embedded XML plist asynchronously
     * so that app launch and UI interactions are never blocked.
     */
    func loadProfile() {
        Task.detached(priority: .utility) {
            guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
                  let data = try? Data(contentsOf: url),
                  let date = self.extractExpirationDate(from: data) else {
                await MainActor.run {
                    self.status = .unknown
                    self.expirationDate = nil
                    self.compactCountdown = "Unknown"
                    self.detailedRemaining = "embedded.mobileprovision not found or unreadable"
                }
                return
            }

            await MainActor.run {
                self.expirationDate = date
                self.updateCountdown()
            }
        }
    }

    /**
     * Extracts ExpirationDate from raw mobileprovision bytes.
     * Mobileprovision wraps an XML plist inside CMS / PKCS#7 format.
     * We locate `<plist` and `</plist>` and deserialize via PropertyListSerialization.
     */
    nonisolated private func extractExpirationDate(from data: Data) -> Date? {
        guard let startRange = data.range(of: Data("<plist".utf8)),
              let endRange = data.range(of: Data("</plist>".utf8), options: .backwards) else {
            return nil
        }
        guard startRange.lowerBound < endRange.upperBound else {
            return nil
        }

        let plistData = data.subdata(in: startRange.lowerBound..<endRange.upperBound)

        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }

        return plist["ExpirationDate"] as? Date
    }

    /**
     * Updates compact format (e.g. "6d 14h", "5h 22m", "Expired") and detailed string.
     */
    func updateCountdown() {
        guard let expirationDate else {
            status = .unknown
            compactCountdown = "Unknown"
            detailedRemaining = "Profile: Not Available"
            return
        }

        let now = Date()
        let interval = expirationDate.timeIntervalSince(now)

        if interval <= 0 {
            status = .expired(expirationDate: expirationDate)
            compactCountdown = "Expired"
            let past = abs(interval)
            let days = Int(past) / 86400
            let hours = (Int(past) % 86400) / 3600
            detailedRemaining = "Expired \(days)d \(hours)h ago"
        } else {
            status = .valid(expirationDate: expirationDate)
            let totalSeconds = Int(interval)
            let days = totalSeconds / 86400
            let hours = (totalSeconds % 86400) / 3600
            let minutes = (totalSeconds % 3600) / 60

            if days > 0 {
                compactCountdown = "\(days)d \(hours)h"
            } else if hours > 0 {
                compactCountdown = "\(hours)h \(minutes)m"
            } else {
                let seconds = totalSeconds % 60
                compactCountdown = "\(minutes)m \(seconds)s"
            }

            detailedRemaining = "\(days)d \(hours)h \(minutes)m remaining"
        }
    }
}

/**
 * Draggable floating overlay indicator showing provisioning expiration time.
 * Tap opens an alert / sheet with exact date and remaining time details.
 */
struct ProvisioningIndicatorView: View {
    @StateObject private var service = ProvisioningProfileService.shared
    @AppStorage("provisioningIndicator_offsetX") private var offsetX: Double = 16
    @AppStorage("provisioningIndicator_offsetY") private var offsetY: Double = 80
    @State private var dragOffset: CGSize = .zero
    @State private var showingDetails = false

    private var badgeColor: Color {
        switch service.status {
        case .unknown:
            return Color.gray
        case .expired:
            return Color.red
        case .valid(let date):
            let remaining = date.timeIntervalSince(Date())
            if remaining < 86400 * 2 {
                // Low time remaining (< 2 days): warning red/orange
                return Color.red
            } else if remaining < 86400 * 4 {
                // Moderate time (< 4 days): amber
                return Color.orange
            } else {
                // Plenty of time: green
                return Color.green
            }
        }
    }

    private var badgeIcon: String {
        switch service.status {
        case .unknown:
            return "questionmark.circle.fill"
        case .expired:
            return "xmark.octagon.fill"
        case .valid(let date):
            let remaining = date.timeIntervalSince(Date())
            if remaining < 86400 * 2 {
                return "exclamationmark.triangle.fill"
            } else {
                return "clock.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: badgeIcon)
                .font(.system(size: 11, weight: .bold))
            Text(service.compactCountdown)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(badgeColor.opacity(0.88), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        .contentShape(Capsule())
        .offset(x: offsetX + dragOffset.width, y: offsetY + dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    offsetX += value.translation.width
                    offsetY += value.translation.height
                    dragOffset = .zero
                }
        )
        .onTapGesture {
            showingDetails = true
        }
        .alert("Provisioning Profile Expiration", isPresented: $showingDetails) {
            Button("OK", role: .cancel) {}
            Button("Refresh") {
                service.loadProfile()
            }
        } message: {
            if let expDate = service.expirationDate {
                let formatter = DateFormatter()
                let _ = formatter.dateStyle = .medium
                let _ = formatter.timeStyle = .medium
                Text("Expires:\n\(formatter.string(from: expDate))\n\nRemaining:\n\(service.detailedRemaining)")
            } else {
                Text("No valid embedded provisioning profile detected.\n\n\(service.detailedRemaining)")
            }
        }
        .onAppear {
            service.startMonitoring()
        }
    }
}

/**
 * Settings row for provisioning profile info and manual position reset.
 */
struct ProvisioningSettingsRow: View {
    @StateObject private var service = ProvisioningProfileService.shared
    @AppStorage("provisioningIndicator_offsetX") private var offsetX: Double = 16
    @AppStorage("provisioningIndicator_offsetY") private var offsetY: Double = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Profile Status", systemImage: "signature")
                Spacer()
                Text(service.compactCountdown)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let expDate = service.expirationDate {
                let formatter = DateFormatter()
                let _ = formatter.dateStyle = .medium
                let _ = formatter.timeStyle = .short
                HStack {
                    Text("Expires")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatter.string(from: expDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Refresh Profile") {
                    service.loadProfile()
                }
                .buttonStyle(.borderless)
                .font(.footnote)

                Spacer()

                Button("Reset Overlay Position") {
                    offsetX = 16
                    offsetY = 80
                }
                .buttonStyle(.borderless)
                .font(.footnote)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 2)
    }
}
