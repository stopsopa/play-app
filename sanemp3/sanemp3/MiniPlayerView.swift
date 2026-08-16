//
//  MiniPlayerView.swift
//  sanemp3
//

import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var player = AudioPlayerService.shared
    let onTap: () -> Void
    
    var body: some View {
        if let track = player.currentTrack {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Small thumbnail
                    ZStack {
                        if let artwork = player.currentArtwork {
                            Image(uiImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(radius: 2)
                    
                    // Track Title & Artist
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text(track.displayArtist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Skip 3s button
                    Button {
                        player.skipForward(seconds: 3.0)
                    } label: {
                        Image(systemName: "goforward")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                    }
                    
                    // Play / Pause
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
