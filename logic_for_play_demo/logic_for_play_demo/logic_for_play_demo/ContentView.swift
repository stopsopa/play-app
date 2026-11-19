//
//  ContentView.swift
//  logic_for_play_demo
//
//  Created by szdz on 19/11/2026.
//

import SwiftUI
import AppKit
import PlayLogic

struct ContentView: View {
    @StateObject private var model = DemoModel()

    var body: some View {
        PlayerScreen(model: model, logic: model.logic)
    }
}

/**
 * Whole demo screen, top to bottom:
 *   Decision Window indicator, settings, track table, transport (Back / Play-Pause / Forward).
 */
struct PlayerScreen: View {
    @ObservedObject var model: DemoModel
    @ObservedObject var logic: PlayLogicController

    var body: some View {
        VStack(spacing: 0) {
            DecisionWindowIndicator(logic: logic)
            SettingsBar(model: model, logic: logic)
            Divider()
            TrackTable(logic: logic)
            Divider()
            TransportBar(logic: logic)
        }
        .frame(minWidth: 780, minHeight: 520)
        .onChange(of: logic.settings) {
            model.saveSettings()
        }
        // Do not lose the position of the current track when the app quits.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            logic.saveCurrentResumePoint()
        }
    }
}

#Preview {
    ContentView()
}
