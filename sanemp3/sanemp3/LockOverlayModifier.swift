//
//  LockOverlayModifier.swift
//  sanemp3
//

import SwiftUI

/**
 LockOverlayView renders the full-screen dimming overlay, center lock icon,
 and intercepts taps to unlock the UI.
 */
struct LockOverlayView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        if state.isUiLocked {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 4)

                    Text("Tap anywhere to unlock")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                state.unlockUi()
            }
            .ignoresSafeArea()
        }
    }
}

/**
 View modifier that applies grayscale & saturation filter to the content when locked,
 and places the LockOverlayView on top.
 */
struct LockOverlayModifier: ViewModifier {
    @ObservedObject private var state = AppState.shared

    func body(content: Content) -> some View {
        content
            .grayscale(state.isUiLocked ? 1.0 : 0.0)
            .saturation(state.isUiLocked ? 0.0 : 1.0)
            .overlay {
                LockOverlayView()
            }
    }
}

extension View {
    func applyLockScreenOverlay() -> some View {
        self.modifier(LockOverlayModifier())
    }
}
