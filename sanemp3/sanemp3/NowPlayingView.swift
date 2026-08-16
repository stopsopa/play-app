//
//  NowPlayingView.swift
//  sanemp3
//

import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var player = AudioPlayerService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isDraggingSlider = false
    @State private var sliderValue: Double = 0
    @State private var showQueueSheet = false
    @State private var showSettingsSheet = false
    
    // Haptic feedback generators for car driving ease
    private let hapticImpact = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let availableWidth = geometry.size.width
                let isCompact = geometry.size.height < 700
                
                VStack(spacing: isCompact ? 12 : 20) {
                    // Header / Dismiss handle
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)
                    
                    // Album Cover with 4 Big Car Buttons Overlay
                    coverWithCarControlsView(size: min(availableWidth - 40, isCompact ? 280 : 340))
                    
                    // Track Title & Artist Info
                    VStack(spacing: 6) {
                        Text(player.currentTrack?.displayName ?? "Not Playing")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                        
                        Text(player.currentTrack?.displayArtist ?? "")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 24)
                    
                    // Progress Scrubber Bar
                    scrubberView
                        .padding(.horizontal, 24)
                    
                    // Standard Controls Bar (Play/Pause, Stop, Next, Previous, Repeat, Shuffle)
                    standardControlsView
                        .padding(.horizontal, 20)
                    
                    Spacer(minLength: 4)
                    
                    // Bottom secondary controls (Queue, Car mode toggle, Speed)
                    bottomBarView
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: $player.preventScreenLock) {
                            Label("Prevent Screen Lock", systemImage: "sun.max.fill")
                        }
                        
                        Toggle(isOn: $player.carRemoteQuickPressSkips3s) {
                            Label("Car Remote Mode (Next/Prev skips 3s)", systemImage: "car.fill")
                        }
                        
                        Menu("Playback Speed (\(String(format: "%.1fx", player.playbackRate)))") {
                            Button("0.75x") { player.playbackRate = 0.75; if player.isPlaying { player.play() } }
                            Button("1.0x (Normal)") { player.playbackRate = 1.0; if player.isPlaying { player.play() } }
                            Button("1.25x") { player.playbackRate = 1.25; if player.isPlaying { player.play() } }
                            Button("1.5x") { player.playbackRate = 1.5; if player.isPlaying { player.play() } }
                            Button("2.0x") { player.playbackRate = 2.0; if player.isPlaying { player.play() } }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showQueueSheet) {
                queueSheetView
            }
        }
    }
    
    // MARK: - Album Cover + 4 Big Car Buttons Overlay
    
    private func coverWithCarControlsView(size: CGFloat) -> some View {
        ZStack {
            // Artwork Image / Fallback Background
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    if let artwork = player.currentArtwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.system(size: size * 0.35, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
            
            // 4 Big Touch Areas Overlay (Divided into 4 quadrants)
            VStack(spacing: 3) {
                // Top Row: 3-second Skips (Big, easy to tap in car)
                HStack(spacing: 3) {
                    // Top Left: -3s
                    BigCarOverlayButton(
                        icon: "gobackward.3",
                        label: "-3s"
                    ) {
                        hapticImpact.impactOccurred()
                        player.skipBackward(seconds: 3.0)
                    }
                    
                    // Top Right: +3s
                    BigCarOverlayButton(
                        icon: "goforward.3",
                        label: "+3s"
                    ) {
                        hapticImpact.impactOccurred()
                        player.skipForward(seconds: 3.0)
                    }
                }
                .frame(maxHeight: .infinity)
                
                // Bottom Row: Previous / Next Track
                HStack(spacing: 3) {
                    // Bottom Left: Previous song or restart
                    BigCarOverlayButton(
                        icon: player.currentTime > 5.0 ? "arrow.counterclockwise" : "backward.fill",
                        label: player.currentTime > 5.0 ? "Restart" : "Prev"
                    ) {
                        hapticImpact.impactOccurred()
                        player.previousTrack()
                    }
                    
                    // Bottom Right: Next song
                    BigCarOverlayButton(
                        icon: "forward.fill",
                        label: "Next"
                    ) {
                        hapticImpact.impactOccurred()
                        player.nextTrack()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(width: size, height: size)
    }
    
    // MARK: - Progress Scrubber
    
    private var scrubberView: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: {
                        isDraggingSlider ? sliderValue : player.currentTime
                    },
                    set: { newVal in
                        sliderValue = newVal
                    }
                ),
                in: 0...max(player.duration, 1.0),
                onEditingChanged: { editing in
                    isDraggingSlider = editing
                    if !editing {
                        player.seek(to: sliderValue)
                    }
                }
            )
            .tint(.accentColor)
            
            HStack {
                Text(formatTime(isDraggingSlider ? sliderValue : player.currentTime))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                let remaining = max(player.duration - (isDraggingSlider ? sliderValue : player.currentTime), 0)
                Text("-\(formatTime(remaining))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Standard Playback Controls
    
    private var standardControlsView: some View {
        HStack(spacing: 24) {
            // Stop button
            Button {
                player.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            
            // Previous Track
            Button {
                hapticImpact.impactOccurred()
                player.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
            }
            
            // Play / Pause (Large Primary Button)
            Button {
                hapticImpact.impactOccurred()
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 68, height: 68)
                        .shadow(color: .primary.opacity(0.2), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }
            
            // Next Track
            Button {
                hapticImpact.impactOccurred()
                player.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
            }
            
            // Repeat Button
            Button {
                player.toggleRepeat()
            } label: {
                Image(systemName: player.repeatMode.iconName)
                    .font(.title3)
                    .foregroundStyle(player.repeatMode == .off ? Color.secondary.opacity(0.4) : Color.accentColor)
                    .frame(width: 44, height: 44)
            }
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBarView: some View {
        HStack {
            // Shuffle
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.subheadline)
                    .foregroundStyle(player.isShuffle ? Color.accentColor : Color.secondary)
            }
            
            Spacer()
            
            if player.carRemoteQuickPressSkips3s {
                Label("Car Mode ON", systemImage: "car.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
            
            Spacer()
            
            // Queue Button
            Button {
                showQueueSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                    Text("\(player.currentIndex + 1)/\(player.queue.count)")
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Queue Sheet
    
    private var queueSheetView: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 12) {
                        if index == player.currentIndex {
                            Image(systemName: player.isPlaying ? "speaker.wave.3.fill" : "speaker.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                        } else {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.displayName)
                                .font(.subheadline)
                                .fontWeight(index == player.currentIndex ? .bold : .regular)
                                .foregroundStyle(index == player.currentIndex ? Color.accentColor : Color.primary)
                                .lineLimit(1)
                            
                            Text(track.displayArtist)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Text(track.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.playQueue(player.queue, startingAt: index)
                    }
                }
            }
            .navigationTitle("Current Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showQueueSheet = false
                    }
                }
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Big Car Overlay Button Component

private struct BigCarOverlayButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                // Frosted semi-transparent dark plate with high contrast
                Color.black.opacity(isPressed ? 0.65 : 0.45)
                    .background(.ultraThinMaterial.opacity(0.3))
                
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text(label)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
