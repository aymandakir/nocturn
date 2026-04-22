import SwiftUI

struct DevicePickerView: View {
    @Environment(\.audioEngine) private var audioEngine

    let app: AudioApp
    let devices: [AudioDevice]
    let defaultDevice: AudioDevice?

    var body: some View {
        Menu {
            if let defaultDevice {
                Button {
                    audioEngine.updateOutputDevice(for: app, deviceUID: defaultDevice.uid)
                } label: {
                    Label("Default (\(defaultDevice.name))", systemImage: "arrow.turn.down.right")
                }
            }

            ForEach(devices, id: \.uid) { device in
                Button {
                    audioEngine.updateOutputDevice(for: app, deviceUID: device.uid)
                } label: {
                    Label(device.name, systemImage: currentDeviceUID == device.uid ? "checkmark" : "circle")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                Text(currentDeviceLabel)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
    }

    private var currentDeviceUID: String? {
        app.outputDeviceUID ?? defaultDevice?.uid
    }

    private var currentDeviceLabel: String {
        if let currentDeviceUID, let device = devices.first(where: { $0.uid == currentDeviceUID }) {
            return device.name
        }
        return "Default"
    }
}
