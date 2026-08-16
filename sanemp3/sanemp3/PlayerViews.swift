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
                            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "music.note").foregroundStyle(.white.opacity(0.8))
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
                let compact = geo.size.height < 700
                let coverSize = max(min(width - 40, compact ? 270 : 340), 120)

                ScrollView {
                    VStack(spacing: compact ? 12 : 20) {
                        // Drag handle
                        Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 8)

                        // Cover + 4 car buttons
                        CoverWithCarButtons(size: coverSize)
                            .environmentObject(state)

                        // Track info
                        VStack(spacing: 4) {
                            Text(state.currentTrack?.displayName ?? "Not Playing")
                                .font(.title2).bold().multilineTextAlignment(.center).lineLimit(2)
                            Text(state.currentTrack?.displayArtist ?? "")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.horizontal, 24)

                        // Scrubber
                        scrubber.padding(.horizontal, 24)

                        // Controls
                        controls

                        // Bottom bar
                        bottomBar.padding(.horizontal, 24).padding(.bottom, 12)
                    }
                    .frame(minHeight: geo.size.height)
                }
                .scrollDisabled(!compact)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 16, weight: .bold)) }
                }
                ToolbarItem(placement: .topBarTrailing) {
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
                                Button("\(String(format: "%.2g", rate))×") { state.playbackRate = rate; if state.isPlaying { state.play() } }
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 18)) }
                }
            }
            .sheet(isPresented: $showQueue) { queueSheet }
        }
    }

    // MARK: Scrubber

    var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { isDragging ? sliderValue : state.currentTime },
                               set: { sliderValue = $0 }),
                in: 0...max(state.duration, 1),
                onEditingChanged: { editing in
                    if editing { sliderValue = state.currentTime; isDragging = true }
                    else { let t = sliderValue; isDragging = false; state.seek(to: t) }
                }
            ).tint(.accentColor)
            .onChange(of: state.currentTime) { v in if !isDragging { sliderValue = v } }

            HStack {
                Text(fmt(isDragging ? sliderValue : state.currentTime)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text("-" + fmt(max(state.duration - (isDragging ? sliderValue : state.currentTime), 0))).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Controls

    var controls: some View {
        HStack(spacing: 26) {
            Button { state.stop() } label: { Image(systemName: "stop.fill").font(.title3).foregroundStyle(.secondary).frame(width: 44, height: 44) }

            Button { haptic.impactOccurred(); state.previousTrack() } label: {
                Image(systemName: "backward.fill").font(.title2).frame(width: 48, height: 48)
            }
            Button { haptic.impactOccurred(); state.togglePlay() } label: {
                ZStack {
                    Circle().fill(Color.primary).frame(width: 68, height: 68).shadow(color: .primary.opacity(0.2), radius: 8, x: 0, y: 4)
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold)).foregroundStyle(Color(.systemBackground))
                        .offset(x: state.isPlaying ? 0 : 2)
                }
            }
            Button { haptic.impactOccurred(); state.nextTrack() } label: {
                Image(systemName: "forward.fill").font(.title2).frame(width: 48, height: 48)
            }
            Button { state.toggleRepeat() } label: {
                Image(systemName: state.repeatMode.icon).font(.title3)
                    .foregroundStyle(state.repeatMode == .off ? Color.secondary.opacity(0.4) : Color.accentColor)
                    .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: Bottom bar

    var bottomBar: some View {
        HStack {
            Button { state.toggleShuffle() } label: {
                Image(systemName: "shuffle").font(.subheadline).foregroundStyle(state.isShuffle ? Color.accentColor : .secondary)
            }
            Spacer()
            if state.carRemoteMode {
                Label("Car Mode", systemImage: "car.fill").font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Color.orange.opacity(0.12), in: Capsule())
            }
            Spacer()
            Button { showQueue = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                    Text("\(state.currentIndex + 1)/\(state.queue.count)").monospacedDigit()
                }.font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Queue sheet

    var queueSheet: some View {
        NavigationStack {
            List(Array(state.queue.enumerated()), id: \.element.id) { idx, track in
                HStack(spacing: 12) {
                    if idx == state.currentIndex {
                        Image(systemName: state.isPlaying ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(.tint).frame(width: 24)
                    } else {
                        Text("\(idx + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 24)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.displayName).fontWeight(idx == state.currentIndex ? .bold : .regular).foregroundStyle(idx == state.currentIndex ? Color.accentColor : .primary).lineLimit(1)
                        Text(track.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(track.formattedDuration).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { state.playQueue(state.queue, startingAt: idx) }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showQueue = false } } }
        }
    }

    func fmt(_ s: TimeInterval) -> String {
        let t = Int(max(s, 0)); return String(format: "%d:%02d", t / 60, t % 60)
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    if let art = state.currentArtwork {
                        Image(uiImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            LinearGradient(colors: [.blue.opacity(0.7), .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "music.note").font(.system(size: max(size * 0.35, 32), weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)

            // 4 large tap zones
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    CarButton(icon: "gobackward", label: "-3s") { haptic.impactOccurred(); state.skipBackward() }
                    CarButton(icon: "goforward",  label: "+3s") { haptic.impactOccurred(); state.skipForward() }
                }.frame(maxHeight: .infinity)
                HStack(spacing: 3) {
                    CarButton(icon: state.currentTime > 5 ? "arrow.counterclockwise" : "backward.fill",
                              label: state.currentTime > 5 ? "Restart" : "Prev") { haptic.impactOccurred(); state.previousTrack() }
                    CarButton(icon: "forward.fill", label: "Next") { haptic.impactOccurred(); state.nextTrack() }
                }.frame(maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Individual car button

struct CarButton: View {
    let icon: String; let label: String; let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.black.opacity(pressed ? 0.65 : 0.45).background(.ultraThinMaterial.opacity(0.3))
                VStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                    Text(label).font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                }.shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
    }
}
