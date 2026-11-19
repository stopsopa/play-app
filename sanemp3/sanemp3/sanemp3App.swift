//
//  sanemp3App.swift
//  sanemp3
//
//  Created by szdz on 16/08/2026.
//

import SwiftUI

/**
 * The audio session is configured once at app start by AVPlayerEngine (created together with
 * AppState.shared), not here in a view.
 */
@main
struct sanemp3App: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Apply the stored "Prevent Screen Lock" choice
                    AppState.shared.applyScreenLockSetting()
                    // Monitor developer certificate expiration and schedule milestone notifications
                    ProvisioningProfileService.shared.startMonitoring()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        AppState.shared.applyScreenLockSetting()
                        ProvisioningProfileService.shared.updateCountdown()
                    }
                    if phase == .background || phase == .inactive {
                        // Do not lose the position of the current track
                        AppState.shared.saveResumePoint()
                    }
                }
        }
    }
}
