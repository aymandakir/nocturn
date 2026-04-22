import SwiftUI

struct AppRowView: View {
    @Environment(\.audioEngine) private var audioEngine
    let app: AudioApp
    let devices: [AudioDevice]
    let defaultDevice: AudioDevice?

    @State private var isExpanded = false
    private var controlsAvailable: Bool { audioEngine.tapAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                AppIconView(app: app)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.displayName)
                                .font(.subheadline.weight(.medium))
                            Text(app.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if controlsAvailable {
                            DevicePickerView(app: app, devices: devices, defaultDevice: defaultDevice)
                        }
                    }

                    VolumeSlider(
                        volume: Binding(
                            get: { app.volume },
                            set: { audioEngine.updateVolume(for: app, volume: $0) }
                        ),
                        isMuted: app.isMuted,
                        boostEnabled: app.isBoostEnabled,
                        onToggleBoost: { audioEngine.setBoostEnabled(for: app, enabled: !app.isBoostEnabled) }
                    )
                    .opacity(app.isMuted ? 0.4 : 1.0)
                    .disabled(!controlsAvailable)

                    if !controlsAvailable {
                        Text("AudioTap unavailable on this macOS/runtime; controls are disabled.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    if controlsAvailable {
                        audioEngine.updateMute(for: app, muted: !app.isMuted)
                    }
                } label: {
                    Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(app.isMuted ? .orange : .secondary)
                .disabled(!controlsAvailable)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded, controlsAvailable {
                EffectsView(app: app)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.25))
        }
    }
}
