//
//  ContentView.swift
//  sanemp3
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var player = AudioPlayerService.shared
    @State private var selectedTab: Int = 0
    @State private var isNowPlayingPresented: Bool = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                FolderBrowserView()
                    .tabItem {
                        Label("Folder", systemImage: "folder.fill")
                    }
                    .tag(0)
                
                PlaylistsView()
                    .tabItem {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                    .tag(1)
            }
            
            // Floating Mini Player above bottom tab bar
            if player.currentTrack != nil {
                MiniPlayerView {
                    isNowPlayingPresented = true
                }
                .padding(.bottom, 52) // sits right above standard tab bar
            }
        }
        .sheet(isPresented: $isNowPlayingPresented) {
            NowPlayingView()
        }
    }
}

#Preview {
    ContentView()
}
