import SwiftUI

struct VolumeSlider: View {
    @Binding var volume: Float
    let isMuted: Bool
    let boostEnabled: Bool
    let onToggleBoost: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { Double(volume) },
                    set: { volume = Float($0) }
                ),
                in: 0...Double(boostEnabled ? 1.5 : 1.0)
            )
            .tint(boostEnabled && volume > 1.0 ? .orange : .accentColor)
            .disabled(isMuted)
            .contextMenu {
                Button(boostEnabled ? "Disable Boost" : "Enable Boost", action: onToggleBoost)
            }

            Text(labelText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(boostEnabled && volume > 1.0 ? .orange : .secondary)
                .frame(width: 54, alignment: .trailing)
        }
        .animation(.spring(response: 0.2), value: volume)
    }

    private var labelText: String {
        "\(Int(volume * 100))%"
    }
}
