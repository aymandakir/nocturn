import Foundation
import SwiftData

/// SwiftData model holding per-app EQ configuration. The spec calls for
/// UserDefaults for lightweight scalar prefs (volume, mute) and SwiftData for
/// richer structured state (per-app EQ/device assignments).
@Model
final class StoredEQPreset {
    @Attribute(.unique) var bundleID: String
    var presetRawValue: String
    var bands: [Float]
    var outputDeviceUID: String?
    var lastUpdated: Date

    init(
        bundleID: String,
        presetRawValue: String,
        bands: [Float],
        outputDeviceUID: String?,
        lastUpdated: Date = .now
    ) {
        self.bundleID = bundleID
        self.presetRawValue = presetRawValue
        self.bands = bands
        self.outputDeviceUID = outputDeviceUID
        self.lastUpdated = lastUpdated
    }
}

/// Central SwiftData container for Nocturn. Kept separate so tests can override.
enum NocturnDataStore {
    static let shared: ModelContainer = {
        do {
            let schema = Schema([StoredEQPreset.self])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            AppLogger.app.error("SwiftData container failed: \(error.localizedDescription, privacy: .public)")
            do {
                let schema = Schema([StoredEQPreset.self])
                let fallback = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                return try ModelContainer(for: schema, configurations: fallback)
            } catch {
                fatalError("Unable to create fallback SwiftData container: \(error)")
            }
        }
    }()

    @MainActor
    static func upsert(bundleID: String, preset: EQPreset, bands: [Float], outputDeviceUID: String?) {
        let context = shared.mainContext
        let descriptor = FetchDescriptor<StoredEQPreset>(
            predicate: #Predicate { $0.bundleID == bundleID }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                existing.presetRawValue = preset.rawValue
                existing.bands = bands
                existing.outputDeviceUID = outputDeviceUID
                existing.lastUpdated = .now
            } else {
                let stored = StoredEQPreset(
                    bundleID: bundleID,
                    presetRawValue: preset.rawValue,
                    bands: bands,
                    outputDeviceUID: outputDeviceUID
                )
                context.insert(stored)
            }
            try context.save()
        } catch {
            AppLogger.app.error("SwiftData upsert failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    static func load(bundleID: String) -> StoredEQPreset? {
        let context = shared.mainContext
        let descriptor = FetchDescriptor<StoredEQPreset>(
            predicate: #Predicate { $0.bundleID == bundleID }
        )
        return (try? context.fetch(descriptor))?.first
    }
}
