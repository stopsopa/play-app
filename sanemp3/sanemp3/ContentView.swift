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
                SettingsView(showDoneButton: false)
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(2)
            }
            .environmentObject(state)

            // Mini player
            if state.currentTrack != nil {
                MiniPlayer { showNowPlaying = true }
                    .environmentObject(state)
                    .padding(.bottom, 52)
            }
        }
        .applyLockScreenOverlay()
        .trackUserTouches()
        .tint(AppTheme.orange)
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environmentObject(state)
                .applyLockScreenOverlay()
                .tint(AppTheme.orange)
        }
        .overlay(alignment: .topLeading) {
            #if DEBUG
            ProvisioningIndicatorView()
            #endif
        }
        .onAppear {
            state.restorePlaybackState()
            if state.isUiLockEnabled {
                state.resetInactivityTimer()
            }
        }
    }
}

#Preview { ContentView() }
