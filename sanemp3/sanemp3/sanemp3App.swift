//
//  sanemp3App.swift
//  sanemp3
//
//  Created by szdz on 16/08/2026.
//

import SwiftUI

@main
struct sanemp3App: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var player = AudioPlayerService.shared
    @StateObject private var storage = StorageService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    player.applyScreenLockSetting()
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        player.applyScreenLockSetting()
                    case .inactive, .background:
                        player.savePlaybackState()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
