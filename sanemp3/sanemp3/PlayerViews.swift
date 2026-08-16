//
//  PlayerViews.swift
//  sanemp3
//

import SwiftUI

// MARK: - Mini Player (floating bar)

struct MiniPlayer: View {
    @EnvironmentObject var state: AppState
    let onTap: () -> Void

    var body: some View {
        if let track = state.currentTrack {
            Button(action: onTap) {
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

                    // Skip +3s
                    Button { state.flashForward() } label: {
                        Image(systemName: "goforward").font(.title3).frame(width: 36, height: 36)
                    }
                    // Play / Pause
                    Button { state.togglePlay() } label: {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Now Playing

struct NowPlayingView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var isDragging = false
    @State private var sliderValue: Double = 0
    @State private var showQueue = false
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

                    // 95% width Cover with 4 big car buttons (-3s, +3s, Prev, Next)
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

                    // Compact Scrubber (progress bar)
                    scrubber
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

                    Menu {
                        Toggle(isOn: Binding(get: { UIApplication.shared.isIdleTimerDisabled },
                                            set: { UIApplication.shared.isIdleTimerDisabled = $0 })) {
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                    }
                }
            }
            .sheet(isPresented: $showQueue) { queueSheet }
        }
    }

    // MARK: Compact Scrubber

    var scrubber: some View {
        VStack(spacing: 1) {
            Slider(
                value: Binding(get: { isDragging ? sliderValue : state.currentTime },
                               set: { sliderValue = $0 }),
                in: 0...max(state.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        sliderValue = state.currentTime
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
            .onChange(of: state.currentTime) { v in
                if !isDragging { sliderValue = v }
            }

            HStack {
                Text(fmt(isDragging ? sliderValue : state.currentTime))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                let remaining = max(state.duration - (isDragging ? sliderValue : state.currentTime), 0)
                Text("-" + fmt(remaining))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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
    }

    // MARK: Queue sheet

    var queueSheet: some View {
        NavigationStack {
            List(Array(state.queue.enumerated()), id: \.element.id) { idx, track in
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
                .onTapGesture { state.playQueue(state.queue, startingAt: idx) }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showQueue = false }
                }
            }
        }
    }

    func fmt(_ s: TimeInterval) -> String {
        let t = Int(max(s, 0))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Cover with 4 big car overlay buttons

struct CoverWithCarButtons: View {
    @EnvironmentObject var state: AppState
    let size: CGFloat
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
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

            // 4 large tap zones covering the full square
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    // Top-Left: -3s (turns brighter when triggered via remote or tap)
                    CarButton(
                        icon: "gobackward",
                        label: "-3s",
                        isFlashing: state.isRewindActive
                    ) {
                        haptic.impactOccurred()
                        state.flashBackward()
                    }

                    // Top-Right: +3s (turns brighter when triggered via remote or tap)
                    CarButton(
                        icon: "goforward",
                        label: "+3s",
                        isFlashing: state.isForwardActive
                    ) {
                        haptic.impactOccurred()
                        state.flashForward()
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 3) {
                    // Bottom-Left: Prev / Restart
                    CarButton(
                        icon: state.currentTime > 5 ? "arrow.counterclockwise" : "backward.fill",
                        label: state.currentTime > 5 ? "Restart" : "Prev"
                    ) {
                        haptic.impactOccurred()
                        state.previousTrack()
                    }

                    // Bottom-Right: Next
                    CarButton(icon: "forward.fill", label: "Next") {
                        haptic.impactOccurred()
                        state.nextTrack()
                    }
                }
                .frame(maxHeight: .infinity)
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
    var isFlashing: Bool = false
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

                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(isFlashing ? .white : .white)

                    Text(label)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(isFlashing ? .white : .white.opacity(0.95))
                }
                .scaleEffect(isFlashing ? 1.1 : 1.0)
                .shadow(color: isFlashing ? Color.orange : Color.black.opacity(0.8), radius: isFlashing ? 8 : 4, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.2), value: isFlashing)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}
