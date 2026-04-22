import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.audioEngine) private var audioEngine

    @State private var launchAtLogin = Permissions.launchAtLoginEnabled()
    @State private var launchError: String?
    @State private var diagnosticsMode = UserDefaults.standard.bool(forKey: "nocturn.diagnosticsMode")
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Manager Settings")
                .font(.title3.bold())

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    do {
                        try Permissions.setLaunchAtLogin(newValue)
                        launchAtLogin = newValue
                        UserDefaults.standard.set(newValue, forKey: "nocturn.launchAtLogin")
                    } catch {
                        launchError = error.localizedDescription
                    }
                }
            ))

            Text("Nocturn v0.1 focuses on active app visibility and safe volume/mute control.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Advanced audio processing and driver integrations are intentionally hidden in this version.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Diagnostics Mode", isOn: Binding(
                get: { diagnosticsMode },
                set: {
                    diagnosticsMode = $0
                    UserDefaults.standard.set($0, forKey: "nocturn.diagnosticsMode")
                }
            ))

            HStack {
                Button("Refresh Audio Apps") {
                    isRefreshing = true
                    Task {
                        await audioEngine.refreshNow()
                        await MainActor.run { isRefreshing = false }
                    }
                }
                .disabled(isRefreshing)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if diagnosticsMode {
                diagnosticsSection
            }

            Button("Open GitHub") {
                guard let url = URL(string: "https://github.com/aymandakir/nocturn") else { return }
                NSWorkspace.shared.open(url)
            }

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let launchError {
                Text(launchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Diagnostics")
                .font(.headline)

            Text("Detected active audio apps: \(audioEngine.audioApps.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if audioEngine.audioApps.isEmpty {
                Text("No active audio apps detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(audioEngine.audioApps, id: \.id) { app in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text("PID: \(app.id)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text("controlAvailable: \(app.controlAvailable ? "true" : "false")")
                                    .font(.caption2.monospacedDigit())
                                Text("tapSessionStarted: \(audioEngine.tapSessionStarted(for: app) ? "true" : "false")")
                                    .font(.caption2.monospacedDigit())
                                Text("reason: \(app.controlUnavailableReason ?? "none")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.2)))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }
}
