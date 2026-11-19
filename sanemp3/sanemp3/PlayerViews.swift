//
//  PlayerViews.swift
//  sanemp3
//

import SwiftUI

// MARK: - Playback error banner

/**
 * Red line of text shown when a track could not be played (and was skipped) or a folder
 * could not be opened. Disappears by itself after a few seconds, or on tap.
 */
struct PlaybackErrorBanner: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let message = state.playbackError {
            Text(message)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .onTapGesture { state.playbackError = nil }
                .accessibilityIdentifier("playback-error-banner")
        }
    }
}

// MARK: - Mini Player (floating bar)

struct MiniPlayer: View {
    @EnvironmentObject var state: AppState
    let onTap: () -> Void

    var body: some View {
        if let track = state.currentTrack {
            // A plain row with a tap gesture, not a Button: it contains buttons of its own.
            HStack(spacing: 12) {
                // Artwork thumbnail
                ZStack {
                    if let art = state.currentArtwork {
                        Image(uiImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        AppTheme.brownOrangeGradient
                        Image(systemName: "music.note").foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayName).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                    Text(track.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()

                // Skip forward by one Seek Step
                Button { state.flashForward() } label: {
                    Image(systemName: "goforward").font(.title3).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mini-player-seek-forward-button")
                // Play / Pause
                Button { state.togglePlay() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mini-player-play-pause-button")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mini-player")
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Now Playing

struct NowPlayingView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var showQueue = false
    @State private var showSettings = false
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let width = geo.size.width
                // 95% of screen width for the entire 4-button square
                let coverSize = max(width * 0.95, 120)

                VStack(spacing: 8) {
                    // Drag handle
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 36, height: 4)
                        .padding(.top, 4)

                    // 95% width Cover with 4 big car buttons (-step, +step, Prev, Next)
                    CoverWithCarButtons(size: coverSize)
                        .environmentObject(state)

                    // Track info
                    VStack(spacing: 2) {
                        Text(state.currentTrack?.displayName ?? "Not Playing")
                            .font(.headline)
                            .bold()
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                        Text(state.currentTrack?.displayArtist ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, width * 0.025)

                    PlaybackErrorBanner()

                    // Compact Scrubber (progress bar)
                    ScrubberView(progress: state.progress)
                        .padding(.horizontal, width * 0.025)

                    // Massive Play / Pause Button (95% width)
                    bigPlayPauseButton
                        .padding(.horizontal, width * 0.025)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .accessibilityIdentifier("now-playing-close-button")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showQueue = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet")
                            if !state.queue.isEmpty {
                                Text("\(state.currentIndex + 1)/\(state.queue.count)")
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .accessibilityIdentifier("now-playing-queue-button")

                    Menu {
                        Toggle(isOn: $state.preventScreenLock) {
                            Label("Prevent Screen Lock", systemImage: "sun.max.fill")
                        }
                        Menu("Speed (\(String(format: "%.2gx", state.playbackRate)))") {
                            ForEach([Float(0.75), 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                                Button("\(String(format: "%.2g", rate))×") {
                                    state.playbackRate = rate
                                    if state.isPlaying { state.play() }
                                }
                            }
                        }
                        Divider()
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings…", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                    }
                    .accessibilityIdentifier("now-playing-more-menu")
                }
            }
            .sheet(isPresented: $showQueue) { queueSheet }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(state)
            }
        }
    }

    // MARK: Big Play / Pause Button

    var bigPlayPauseButton: some View {
        Button {
            haptic.impactOccurred()
            state.togglePlay()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .black))

                Text(state.isPlaying ? "PAUSE" : "PLAY")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 52, maxHeight: 72)
            .background(
                state.isPlaying
                    ? LinearGradient(colors: [Color.red.opacity(0.85), AppTheme.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [AppTheme.orange, AppTheme.warmBrown], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: AppTheme.orange.opacity(0.3), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("play-pause-button")
    }

    // MARK: Queue sheet

    var queueSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(state.queue.enumerated()), id: \.element.id) { idx, track in
                    HStack(spacing: 12) {
                        if idx == state.currentIndex {
                            Image(systemName: state.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                                .foregroundStyle(AppTheme.orange)
                                .frame(width: 24)
                        } else {
                            Text("\(idx + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.displayName)
                                .fontWeight(idx == state.currentIndex ? .bold : .regular)
                                .foregroundStyle(idx == state.currentIndex ? AppTheme.orange : Color.primary)
                                .lineLimit(1)
                            Text(track.displayArtist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(track.formattedDuration)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { state.selectQueueIndex(idx) }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("queue-row-\(track.id)")
                }

                // Extra bottom space so the last queue items are never clipped or hard to tap
                BottomListSpacer(defaultHeight: 40, playerHeight: 40)
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showQueue = false }
                        .accessibilityIdentifier("queue-done-button")
                }
            }
        }
    }
}

// MARK: - Compact Scrubber

/**
 * Progress slider with elapsed / remaining time.
 * It is the only view observing PlaybackProgress, so the 4-times-a-second progress update
 * redraws just this view and not the whole screen.
 *
 * Usage:
 *   ScrubberView(progress: state.progress)
 */
struct ScrubberView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var progress: PlaybackProgress
    @State private var isDragging = false
    @State private var sliderValue: Double = 0

    var body: some View {
        VStack(spacing: 1) {
            Slider(
                value: Binding(get: { isDragging ? sliderValue : progress.currentTime },
                               set: { sliderValue = $0 }),
                in: 0...max(progress.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        sliderValue = progress.currentTime
                        isDragging = true
                    } else {
                        let t = sliderValue
                        isDragging = false
                        state.seek(to: t)
                    }
                }
            )
            .tint(AppTheme.orange)
            .frame(height: 18)
            .accessibilityIdentifier("scrubber-slider")

            HStack {
                Text(fmt(isDragging ? sliderValue : progress.currentTime))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                let remaining = max(progress.duration - (isDragging ? sliderValue : progress.currentTime), 0)
                Text("-" + fmt(remaining))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fmt(_ s: TimeInterval) -> String {
        let t = Int(max(s, 0))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Cover with 4 big car overlay buttons

/**
 * Top row: direct jump by one Seek Step, back and forward.
 * Bottom row: Back and Forward presses, exactly the same as the Bluetooth media buttons.
 * A press there is a gesture: the track changes when the Decision Window closes,
 * and the pressed square stays lit while it is open.
 *   Forward            -> next track         Back        -> previous track
 *   Back, Back         -> restart the track  anything else with 2+ presses -> seek
 */
struct CoverWithCarButtons: View {
    @EnvironmentObject var state: AppState
    let size: CGFloat
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        let spacing: CGFloat = 3
        let leftWidth = (size - spacing) * 3.0 / 5.0
        let rightWidth = (size - spacing) * 2.0 / 5.0
        let topHeight = (size - spacing) * 3.0 / 5.0
        let bottomHeight = (size - spacing) * 2.0 / 5.0

        ZStack {
            // Artwork or placeholder
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    if let art = state.currentArtwork {
                        Image(uiImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            AppTheme.coverPlaceholderGradient
                            Image(systemName: "music.note")
                                .font(.system(size: max(size * 0.35, 32), weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)

            // 4 large tap zones covering the full square (3:2 ratio favoring the seek-back button)
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    // Top-Left: one Seek Step back (turns brighter when triggered via remote or tap)
                    CarButton(
                        icon: "gobackward",
                        label: "-\(state.seekStepLabel)",
                        isFlashing: state.isRewindActive,
                        iconColor: .yellow,
                        testID: "car-seek-back-button"
                    ) {
                        haptic.impactOccurred()
                        state.flashBackward()
                    }
                    .frame(width: leftWidth, height: topHeight)

                    // Top-Right: one Seek Step forward (turns brighter when triggered via remote or tap)
                    CarButton(
                        icon: "goforward",
                        label: "+\(state.seekStepLabel)",
                        isFlashing: state.isForwardActive,
                        testID: "car-seek-forward-button"
                    ) {
                        haptic.impactOccurred()
                        state.flashForward()
                    }
                    .frame(width: rightWidth, height: topHeight)
                }

                HStack(spacing: spacing) {
                    // Bottom-Left: Back press. One = previous track, two = restart the track.
                    CarButton(
                        icon: state.isRestartPending ? "arrow.counterclockwise" : "backward.fill",
                        label: state.isRestartPending ? "Restart" : "Prev Track",
                        subtitle: state.isRestartPending ? "to 0:00" : nil,
                        isFlashing: state.isBackPending,
                        testID: "car-back-button"
                    ) {
                        haptic.impactOccurred()
                        state.pressBack()
                    }
                    .frame(width: leftWidth, height: bottomHeight)

                    // Bottom-Right: Forward press. One = next track.
                    CarButton(
                        icon: "forward.fill",
                        label: "Next Track",
                        isFlashing: state.isForwardPending,
                        testID: "car-forward-button"
                    ) {
                        haptic.impactOccurred()
                        state.pressForward()
                    }
                    .frame(width: rightWidth, height: bottomHeight)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Individual car button (with square brightening when active)

struct CarButton: View {
    let icon: String
    let label: String
    var subtitle: String? = nil
    var isFlashing: Bool = false
    var iconColor: Color = .white
    // Identifier for UI tests.
    let testID: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background dark tint by default
                Color.black.opacity(pressed ? 0.7 : 0.48)
                    .background(.ultraThinMaterial.opacity(0.25))

                // Bright highlight layer when flashing / active
                if isFlashing {
                    LinearGradient(
                        colors: [AppTheme.orange.opacity(0.85), Color.yellow.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .transition(.opacity)
                }

                VStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(isFlashing ? .white : iconColor)

                    Text(label)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isFlashing ? .white : .white.opacity(0.95))

                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isFlashing ? .white : .white.opacity(0.8))
                    }
                }
                .scaleEffect(isFlashing ? 1.1 : 1.0)
                .shadow(color: isFlashing ? Color.orange : Color.black.opacity(0.8), radius: isFlashing ? 8 : 4, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.2), value: isFlashing)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(testID)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}
