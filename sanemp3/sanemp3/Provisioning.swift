//
//  Provisioning.swift
//  sanemp3
//

import Foundation
import SwiftUI
import Combine
import UserNotifications

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
final class ProvisioningProfileService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ProvisioningProfileService()

    @Published private(set) var status: ProvisioningStatus = .unknown
    @Published private(set) var expirationDate: Date?
    @Published private(set) var compactCountdown: String = "???"
    @Published private(set) var detailedRemaining: String = "Unknown"

    private var hasLoaded = false
    private var timer: Timer?

    override private init() {
        super.init()
    }

    deinit {
        timer?.invalidate()
    }

    /**
     * Starts periodic updates and loads profile if not already loaded.
     */
    func startMonitoring() {
        UNUserNotificationCenter.current().delegate = self
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
                self.scheduleExpiryNotifications(for: date)
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

    /**
     * Schedules local notifications for 24, 18, 12, 6, and 0 hours before developer certificate expiration.
     * The 0-hour notification is dispatched 1 minute prior to exact expiration so iOS delivers it before app execution is evicted.
     * Body format: "XXX hours left - 25 Friday March 2026 expire"
     */
    func scheduleExpiryNotifications(for expirationDate: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                let milestones = [24, 18, 12, 6, 0]
                let now = Date()

                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "d EEEE MMMM yyyy"
                let dateString = formatter.string(from: expirationDate)

                let requestIds = milestones.map { "dev-cert-expiry-\($0)h" }
                center.removePendingNotificationRequests(withIdentifiers: requestIds)

                for hours in milestones {
                    let triggerDate: Date
                    if hours == 0 {
                        // Deliver 1 minute (60 seconds) prior to exact expiration before OS evicts app
                        triggerDate = expirationDate.addingTimeInterval(-60)
                    } else {
                        triggerDate = expirationDate.addingTimeInterval(-Double(hours * 3600))
                    }

                    let timeInterval: TimeInterval
                    if hours == 0 {
                        if now < expirationDate {
                            if triggerDate > now {
                                timeInterval = triggerDate.timeIntervalSince(now)
                            } else {
                                // Less than 1 minute remaining before expiry: trigger in 2 seconds
                                timeInterval = 2
                            }
                        } else {
                            timeInterval = -1
                        }
                    } else {
                        timeInterval = triggerDate.timeIntervalSince(now)
                    }

                    if timeInterval > 0 {
                        let content = UNMutableNotificationContent()
                        content.title = "Certificate Expiry"
                        content.body = "\(hours) hours left - \(dateString) expire"
                        content.sound = .default

                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
                        let request = UNNotificationRequest(
                            identifier: "dev-cert-expiry-\(hours)h",
                            content: content,
                            trigger: trigger
                        )

                        center.add(request)
                    }
                }
            }
        }
    }

    /**
     * Sends an immediate simulated notification for testing purposes using the specified hours milestone.
     * Uses real expiration date if available, or falls back to a simulated future date.
     * Body format: "XXX hours left - 25 Friday March 2026 expire"
     */
    func sendSimulatedNotification(hoursLeft: Int) {
        let center = UNUserNotificationCenter.current()
        /**
         * Read on the main actor, before the permission callback: that callback runs on another
         * queue and must not touch main-actor data.
         */
        let knownExpiration = expirationDate
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                let expDate = knownExpiration ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "d EEEE MMMM yyyy"
                let dateString = formatter.string(from: expDate)

                let content = UNMutableNotificationContent()
                content.title = "Cert Expiry (Sim)"
                content.body = "\(hoursLeft) hours left - \(dateString) expire"
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "simulated-expiry-\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }

    /**
     * Ensures local notifications are presented as banners and sounds even when app is active in foreground.
     */
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
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
 * Settings row for provisioning profile info, manual position reset, and simulated notification trigger.
 */
struct ProvisioningSettingsRow: View {
    @StateObject private var service = ProvisioningProfileService.shared
    @AppStorage("provisioningIndicator_offsetX") private var offsetX: Double = 16
    @AppStorage("provisioningIndicator_offsetY") private var offsetY: Double = 80
    @State private var sliderIndex: Double = 0
    private let intervalPoints: [Int] = [24, 18, 12, 6, 0]

    private var currentHours: Int {
        let index = Int(sliderIndex.rounded())
        if index >= 0 && index < intervalPoints.count {
            return intervalPoints[index]
        }
        return intervalPoints[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .accessibilityIdentifier("cert-refresh-button")

                Spacer()

                Button("Reset Overlay Position") {
                    offsetX = 16
                    offsetY = 80
                }
                .buttonStyle(.borderless)
                .font(.footnote)
                .accessibilityIdentifier("cert-reset-position-button")
            }
            .padding(.top, 2)

            Divider()
                .padding(.vertical, 2)

            // Notification simulation controls
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Simulate Expiry Notification")
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(currentHours)h left")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.orange)
                }

                HStack(spacing: 12) {
                    Slider(value: $sliderIndex, in: 0...Double(intervalPoints.count - 1), step: 1)
                        .accessibilityIdentifier("cert-expiry-sim-slider")

                    Button("Send") {
                        service.sendSimulatedNotification(hoursLeft: currentHours)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.orange)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("cert-expiry-sim-send-button")
                }

                HStack {
                    ForEach(intervalPoints, id: \.self) { pt in
                        Text("\(pt)h")
                            .font(.caption2)
                            .foregroundStyle(currentHours == pt ? AppTheme.orange : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.trailing, 64)
            }
        }
        .padding(.vertical, 2)
    }
}
