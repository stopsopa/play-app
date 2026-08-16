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
                    Button { state.skipForward() } label: {
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
                // Full width box with small side padding
                let coverSize = max(width - 24, 120)

                VStack(spacing: 12) {
                    // Drag handle
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 6)

                    // Full-width Cover with 4 big car buttons
                    CoverWithCarButtons(size: coverSize)
                        .environmentObject(state)

                    // Track info
                    VStack(spacing: 3) {
                        Text(state.currentTrack?.displayName ?? "Not Playing")
                            .font(.title3)
                            .bold()
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                        Text(state.currentTrack?.displayArtist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)

                    // Scrubber (progress bar)
                    scrubber
                        .padding(.horizontal, 16)

                    // Massive Full-Width Play / Pause Button
                    bigPlayPauseButton
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
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
                        Toggle(isOn: $state.carRemoteMode) {
                            Label("Car Remote Mode", systemImage: "car.fill")
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

    // MARK: Scrubber

    var scrubber: some View {
        VStack(spacing: 4) {
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
            .onChange(of: state.currentTime) { v in
                if !isDragging { sliderValue = v }
            }

            HStack {
                Text(fmt(isDragging ? sliderValue : state.currentTime))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                let remaining = max(state.duration - (isDragging ? sliderValue : state.currentTime), 0)
                Text("-" + fmt(remaining))
                    .font(.caption)
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
            HStack(spacing: 16) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 42, weight: .black))

                Text(state.isPlaying ? "PAUSE" : "PLAY")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                state.isPlaying
                    ? LinearGradient(colors: [Color.red.opacity(0.85), AppTheme.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [AppTheme.orange, AppTheme.warmBrown], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: AppTheme.orange.opacity(0.35), radius: 10, y: 4)
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
                    CarButton(icon: "gobackward", label: "-3s") {
                        haptic.impactOccurred()
                        state.skipBackward()
                    }
                    CarButton(icon: "goforward", label: "+3s") {
                        haptic.impactOccurred()
                        state.skipForward()
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 3) {
                    CarButton(
                        icon: state.currentTime > 5 ? "arrow.counterclockwise" : "backward.fill",
                        label: state.currentTime > 5 ? "Restart" : "Prev"
                    ) {
                        haptic.impactOccurred()
                        state.previousTrack()
                    }
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

// MARK: - Individual car button

struct CarButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.black.opacity(pressed ? 0.7 : 0.48)
                    .background(.ultraThinMaterial.opacity(0.25))

                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)

                    Text(label)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}
