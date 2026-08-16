//
//  ContentView.swift
//  sanemp3
//

import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState.shared
    @State private var showNowPlaying = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                FolderView()
                    .tabItem { Label("Folder", systemImage: "folder.fill") }
                    .tag(0)
                PlaylistsView()
                    .tabItem { Label("Playlists", systemImage: "music.note.list") }
                    .tag(1)
            }
            .environmentObject(state)

            // Mini player
            if state.currentTrack != nil {
                MiniPlayer { showNowPlaying = true }
                    .environmentObject(state)
                    .padding(.bottom, 52)
            }
        }
        .tint(AppTheme.orange)
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environmentObject(state)
                .tint(AppTheme.orange)
        }
        .onAppear { state.restorePlaybackState() }
    }
}

#Preview { ContentView() }
