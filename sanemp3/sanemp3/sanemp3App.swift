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
                        options: []
                    )
                    try? AVAudioSession.sharedInstance().setActive(true)
                    // Monitor developer certificate expiration and schedule milestone notifications
                    ProvisioningProfileService.shared.startMonitoring()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        UIApplication.shared.isIdleTimerDisabled = true
                        ProvisioningProfileService.shared.updateCountdown()
                    }
                    if phase == .background || phase == .inactive {
                        AppState.shared.savePlaybackState()
                    }
                }
        }
    }
}
