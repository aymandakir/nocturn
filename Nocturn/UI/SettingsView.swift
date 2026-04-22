import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var launchAtLogin = Permissions.launchAtLoginEnabled()
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Manager Settings")
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

            Text("Nocturn v0.1 focuses on active app visibility and safe volume/mute control.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Advanced audio processing and driver integrations are intentionally hidden in this version.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
