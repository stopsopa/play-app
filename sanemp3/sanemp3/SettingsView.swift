//
//  SettingsView.swift
//  sanemp3
//

import SwiftUI
import PlayLogic

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var showDoneButton: Bool = true
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var isDefaultInterval: Bool {
        abs(state.multiTapInterval - 1.6) < 0.01
    }

    var isMinInterval: Bool {
        state.multiTapInterval <= 0.21
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Multi-Tap Interval Section
                Section {
                    VStack(alignment: .center, spacing: 14) {
                        Text("MULTI-TAP SKIP INTERVAL")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .tracking(1)

                        Text(String(format: "%.1f s", state.multiTapInterval))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.orange)
                            .monospacedDigit()

                        HStack(spacing: 12) {
                            // Decrease by 0.2s
                            Button {
                                haptic.impactOccurred()
                                state.decreaseMultiTapInterval()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "minus.circle.fill")
                                    Text("- 0.2s")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isMinInterval)

                            // Reset to default (1.6s)
                            Button {
                                haptic.impactOccurred()
                                state.resetMultiTapInterval()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Reset")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .tint(isDefaultInterval ? .secondary : AppTheme.orange)
                            .disabled(isDefaultInterval)

                            // Increase by 0.2s
                            Button {
                                haptic.impactOccurred()
                                state.increaseMultiTapInterval()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("+ 0.2s")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("Media Remote Multi-Tap")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Configures the time window allowed between button presses:")
                            .fontWeight(.medium)
                        Text("• **1 Press (Forward)**: Next track")
                        Text("• **1 Press (Backward)**: Previous track")
                        Text("• **2 Presses (Backward, Backward)**: Restart song to 0:00")
                        Text("• **Any other 2+ presses within \(String(format: "%.1f", state.multiTapInterval))s of each other**: each further press skips \(state.seekStepLabel) in its direction")
                        Text("• Minimum allowed interval is **0.2s**.")
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }

                // MARK: - Inactivity UI Lock Section
                Section {
                    Toggle(isOn: $state.isUiLockEnabled) {
                        Label("Enable UI Inactivity Lock", systemImage: "lock.fill")
                    }

                    if state.isUiLockEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Inactivity Delay")
                                Spacer()
                                Text("\(Int(state.uiLockTimeout.rounded()))s")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(
                                value: $state.uiLockTimeout,
                                in: 1...60,
                                step: 1
                            ) {
                                Text("Inactivity Delay")
                            } minimumValueLabel: {
                                Text("1s").font(.caption2).foregroundStyle(.secondary)
                            } maximumValueLabel: {
                                Text("60s").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("UI Inactivity Lock")
                } footer: {
                    Text("When enabled, the entire UI turns gray with a lock symbol after inactivity. Tapping the screen unlocks the UI so accidental touches are prevented.")
                }

                // MARK: - Playback Settings
                Section("Playback") {
                    Toggle(isOn: $state.preventScreenLock) {
                        Label("Prevent Screen Lock", systemImage: "sun.max.fill")
                    }

                    Picker("Playback Speed", selection: Binding(
                        get: { state.playbackRate },
                        set: {
                            state.playbackRate = $0
                            if state.isPlaying { state.play() }
                        }
                    )) {
                        ForEach([Float(0.75), 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Text("\(String(format: "%.2g", rate))×").tag(rate)
                        }
                    }
                }

                // MARK: - Navigation (settings of the PlayLogic library)
                Section {
                    Stepper(value: $state.seekStep, in: 1...30, step: 1) {
                        HStack {
                            Label("Seek Step", systemImage: "goforward")
                            Spacer()
                            Text(state.seekStepLabel)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityIdentifier("settings-seek-step-stepper")

                    Toggle(isOn: $state.resumeOnNaturalAdvance) {
                        Label("Resume when a track starts on its own", systemImage: "arrow.turn.down.right")
                    }
                    .accessibilityIdentifier("settings-resume-on-advance-toggle")

                    Picker("Repeat", selection: $state.repeatMode) {
                        Text("Off").tag(RepeatMode.off)
                        Text("All").tag(RepeatMode.all)
                        Text("One").tag(RepeatMode.one)
                    }
                    .accessibilityIdentifier("settings-repeat-picker")
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Seek Step is how far one seeking press moves. When a track ends and the next one starts by itself, it continues from its remembered position only if the toggle is on. Tracks you pick yourself always resume.")
                }

                // MARK: - Song Position Memory
                Section {
                    HStack {
                        Label("Memorized Tracks", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text("\(state.savedTrackPositionsCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if state.savedTrackPositionsCount > 0 {
                        Button(role: .destructive) {
                            state.clearSavedTrackPositions()
                        } label: {
                            Label("Clear Memorized Positions", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Position Memory")
                } footer: {
                    Text("The app remembers the playback position of every song you leave, allowing you to resume where you left off. A song that played to its end starts from the beginning next time.")
                }

                // MARK: - Provisioning Profile & Notification Simulation
                Section {
                    ProvisioningSettingsRow()
                } header: {
                    Text("Developer Certificate & Notifications")
                } footer: {
                    Text("Displays expiration data extracted from embedded.mobileprovision and provides notification simulation slider.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showDoneButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
