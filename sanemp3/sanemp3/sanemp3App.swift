//
//  sanemp3App.swift
//  sanemp3
//
//  Created by szdz on 16/08/2026.
//

import SwiftUI
import AVFoundation

@main
struct sanemp3App: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Prevent screen from locking while app is open
                    UIApplication.shared.isIdleTimerDisabled = true
                    // Configure audio session for background playback
                    try? AVAudioSession.sharedInstance().setCategory(
                        .playback, mode: .default,
                        options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
                    )
                    try? AVAudioSession.sharedInstance().setActive(true)
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                    if phase == .background || phase == .inactive {
                        AppState.shared.savePlaybackState()
                    }
                }
        }
    }
}
