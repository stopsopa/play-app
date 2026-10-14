//
//  TouchTrackingWindow.swift
//  sanemp3
//

import UIKit
import SwiftUI
import ObjectiveC

// MARK: - TouchTrackingWindow

/**
 UIWindow subclass that intercepts ALL touch events (taps, scrolls, drags) via sendEvent,
 which fires before any view sees the event. Used to drive the inactivity timer debounce.
 */
class TouchTrackingWindow: UIWindow {
    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
        // Only react to touch events (covers taps, scrolls, drags — everything the user does)
        guard event.type == .touches else { return }
        let state = AppState.shared
        if !state.isUiLocked {
            state.resetInactivityTimer()
        }
    }
}

// MARK: - WindowUpgraderView

/**
 Invisible UIView that upgrades the app's UIWindow to TouchTrackingWindow once it's
 attached to the hierarchy. Uses object_setClass — safe because TouchTrackingWindow
 adds no stored properties over UIWindow.
 */
class WindowUpgraderUIView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window = self.window, !(window is TouchTrackingWindow) else { return }
        object_setClass(window, TouchTrackingWindow.self)
    }
}

struct WindowUpgrader: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowUpgraderUIView {
        WindowUpgraderUIView()
    }
    func updateUIView(_ uiView: WindowUpgraderUIView, context: Context) {}
}

// MARK: - View extension

extension View {
    /**
     Installs TouchTrackingWindow on the app's UIWindow so that all user interactions
     (taps, scrolls, drags) reset the inactivity lock timer — without blocking any gesture.
     Call once on the root view.
     */
    func trackUserTouches() -> some View {
        self.background(WindowUpgrader())
    }
}
