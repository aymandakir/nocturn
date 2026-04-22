import SwiftUI

struct DeviceIconView: View {
    let type: AudioDevice.DeviceType

    var body: some View {
        Image(systemName: symbolName)
            .foregroundStyle(.secondary)
    }

    private var symbolName: String {
        switch type {
        case .builtIn:
            return "laptopcomputer"
        case .headphones:
            return "headphones"
        case .airPlay:
            return "airplayaudio"
        case .bluetooth:
            return "dot.radiowaves.left.and.right"
        case .virtual:
            return "waveform.path.ecg"
        case .speaker:
            return "speaker.wave.2.fill"
        case .unknown:
            return "speaker"
        }
    }
}
