import Foundation

enum EQPreset: String, CaseIterable, Codable {
    case flat
    case bassBoost
    case vocalClarity
    case custom

    var bands: [Float] {
        switch self {
        case .flat:
            return [0, 0, 0, 0, 0]
        case .bassBoost:
            return [6, 4, 1, 0, -1]
        case .vocalClarity:
            return [-2, 1, 4, 3, 0]
        case .custom:
            return [0, 0, 0, 0, 0]
        }
    }
}
