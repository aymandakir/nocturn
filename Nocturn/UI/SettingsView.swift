import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var launchAtLogin = Permissions.launchAtLoginEnabled()
    @State private var defaultPresetRawValue = UserDefaults.standard.string(forKey: "nocturn.defaultEQPreset") ?? EQPreset.flat.rawValue
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title3.bold())

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    do {
                        try Permissions.setLaunchAtLogin(newValue)
                        launchAtLogin = newValue
                        UserDefaults.standard.set(newValue, forKey: "nocturn.launchAtLogin")
                    } catch {
                        launchError = error.localizedDescription
                    }
                }
            ))

            HStack {
                Text("Driver")
                Spacer()
                Text("Not Installed")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(0.2)))
            }

            Picker("Default EQ Preset", selection: Binding(
                get: { EQPreset(rawValue: defaultPresetRawValue) ?? .flat },
                set: {
                    defaultPresetRawValue = $0.rawValue
                    UserDefaults.standard.set($0.rawValue, forKey: "nocturn.defaultEQPreset")
                }
            )) {
                ForEach(EQPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }

            Button("Open GitHub") {
                guard let url = URL(string: "https://github.com/aymandakir/nocturn") else { return }
                NSWorkspace.shared.open(url)
            }

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let launchError {
                Text(launchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
