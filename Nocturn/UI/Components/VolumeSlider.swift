import SwiftUI

struct VolumeSlider: View {
    @Binding var volume: Float
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { Double(volume) },
                    set: { volume = Float($0) }
                ),
                in: 0...1.0
            )
            .tint(.accentColor)
            .disabled(isMuted)

            Text(labelText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
        .animation(.spring(response: 0.2), value: volume)
    }

    private var labelText: String {
        "\(Int(volume * 100))%"
    }
}
