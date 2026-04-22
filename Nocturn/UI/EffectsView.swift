import SwiftUI

struct EffectsView: View {
    @Environment(\.audioEngine) private var audioEngine
    let app: AudioApp

    private let labels = ["80Hz", "250Hz", "1kHz", "4kHz", "12kHz"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Preset", selection: Binding(
                get: { app.eqPreset },
                set: { audioEngine.updateEQPreset(for: app, preset: $0) }
            )) {
                Text("Flat").tag(EQPreset.flat)
                Text("Bass+").tag(EQPreset.bassBoost)
                Text("Vocal").tag(EQPreset.vocalClarity)
                Text("Custom").tag(EQPreset.custom)
            }
            .pickerStyle(.segmented)

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<min(labels.count, app.eqBands.count), id: \.self) { index in
                    VStack {
                        Slider(
                            value: Binding(
                                get: { Double(app.eqBands[index]) },
                                set: { newValue in
                                    var updated = app.eqBands
                                    updated[index] = Float(newValue)
                                    audioEngine.updateEQBands(for: app, bands: updated)
                                }
                            ),
                            in: -12...12
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(height: 70)

                        Text(labels[index])
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("\(Int(app.eqBands[index])) dB")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)
        }
        .padding(.top, 6)
    }
}
