import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.audioEngine) private var audioEngine
    @State private var showSettings = false
    @State private var pulse = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                permissionBanner
                header
                outputSection
                appsSection
            }
            .padding(12)
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Nocturn Audio Manager")
                .font(.headline)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYSTEM OUTPUT")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let defaultOutput = audioEngine.deviceManager.defaultOutput {
                HStack {
                    DeviceIconView(type: defaultOutput.type)
                    Text(defaultOutput.name)
                        .lineLimit(1)
                    Spacer()
                }
                .font(.subheadline)
            }

            VolumeSlider(
                volume: Binding(
                    get: { audioEngine.deviceManager.globalOutputVolume },
                    set: { audioEngine.deviceManager.setGlobalOutputVolume($0) }
                ),
                isMuted: false,
                boostEnabled: false,
                onToggleBoost: {}
            )
        }
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if !audioEngine.tapAvailable {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Per-app volume control is unavailable on this macOS/runtime.")
                    .font(.caption)
                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
        } else if audioEngine.microphonePermissionDenied {
            HStack(spacing: 8) {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(.orange)
                Text("Nocturn needs microphone access.")
                    .font(.caption)
                Spacer()
                Button("Open Settings") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                }
                .font(.caption)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVE APPS")
                .font(.caption)
                .foregroundStyle(.secondary)

            if audioEngine.audioApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .scaleEffect(pulse ? 1.08 : 0.92)
                        .foregroundStyle(.secondary)
                    Text("No apps are playing audio")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(audioEngine.audioApps, id: \.id) { app in
                    AppRowView(app: app)
                }
            }
        }
    }
}
