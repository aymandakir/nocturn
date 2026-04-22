import SwiftUI

struct AppRowView: View {
    @Environment(\.audioEngine) private var audioEngine
    let app: AudioApp
    private var controlsAvailable: Bool { audioEngine.tapAvailable }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconView(app: app)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if controlsAvailable {
                    VolumeSlider(
                        volume: Binding(
                            get: { app.volume },
                            set: { audioEngine.updateVolume(for: app, volume: $0) }
                        ),
                        isMuted: app.isMuted,
                        boostEnabled: false,
                        onToggleBoost: {}
                    )
                    .opacity(app.isMuted ? 0.4 : 1.0)
                } else {
                    Text("Per-app controls unavailable on this runtime.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

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
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.25))
        }
    }
}
