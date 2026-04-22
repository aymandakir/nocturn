import AVFoundation
import Foundation

struct EffectsChain {
    static let frequencies: [Float] = [80, 250, 1_000, 4_000, 12_000]

    static func configure(equalizer: AVAudioUnitEQ, bands: [Float]) {
        for index in 0..<min(equalizer.bands.count, bands.count, frequencies.count) {
            let band = equalizer.bands[index]
            band.filterType = .parametric
            band.frequency = frequencies[index]
            band.bandwidth = 1
            band.gain = min(max(bands[index], -12), 12)
            band.bypass = false
        }
    }
}
