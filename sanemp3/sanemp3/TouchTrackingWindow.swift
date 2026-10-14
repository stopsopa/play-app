//
//  TouchTrackingWindow.swift
//  sanemp3
//

import UIKit
import SwiftUI

/**
 A transparent UIView subclass inserted into the hierarchy that intercepts all hit tests
 without blocking them, resetting the inactivity timer when touches occur while unlocked.
 */
class TouchTrackingUIView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        // Only react to real touch events, not system layout hitTest calls (event == nil)
        if view != nil, let event = event, event.type == .touches {
            DispatchQueue.main.async {
                let state = AppState.shared
                if !state.isUiLocked {
                    state.resetInactivityTimer()
                }
            }
        }
        return view
    }
}

/**
 SwiftUI wrapper around TouchTrackingUIView to track touches seamlessly across all screens and sheets
 without blocking standard gestures or list scrolling.
 */
struct TouchTrackingViewModifier: UIViewRepresentable {
    func makeUIView(context: Context) -> TouchTrackingUIView {
        let view = TouchTrackingUIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        return view
    }

    func updateUIView(_ uiView: TouchTrackingUIView, context: Context) {}
}

extension View {
    func trackUserTouches() -> some View {
        self.background(TouchTrackingViewModifier())
    }
}
