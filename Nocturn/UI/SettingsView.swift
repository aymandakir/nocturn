import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var launchAtLogin = Permissions.launchAtLoginEnabled()
    @State private var defaultPresetRawValue = UserDefaults.standard.string(forKey: "nocturn.defaultEQPreset") ?? EQPreset.flat.rawValue
    @State private var launchError: String?
    @State private var driverState: Permissions.DriverState = .notInstalled
    @State private var driverError: String?
    @State private var isWorkingOnDriver = false

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

            driverSection

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
        .onAppear { refreshDriverState() }
    }

    @ViewBuilder
    private var driverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Driver")
                Spacer()
                Text(driverBadgeLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(driverBadgeColor.opacity(0.2)))
                    .foregroundStyle(driverBadgeColor)
            }

            HStack {
                Button(driverActionLabel) { performDriverAction() }
                    .disabled(isWorkingOnDriver)

                if case .installed = driverState {
                    Button("Uninstall") { uninstallDriver() }
                        .disabled(isWorkingOnDriver)
                }
                Spacer()
                if isWorkingOnDriver {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let driverError {
                Text(driverError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var driverBadgeLabel: String {
        switch driverState {
        case .notInstalled:
            return "Not Installed"
        case let .installed(version):
            return "Installed v\(version)"
        case let .updateAvailable(installed, latest):
            return "Update \(installed) → \(latest)"
        }
    }

    private var driverBadgeColor: Color {
        switch driverState {
        case .notInstalled:
            return .red
        case .installed:
            return .green
        case .updateAvailable:
            return .yellow
        }
    }

    private var driverActionLabel: String {
        switch driverState {
        case .notInstalled:
            return "Install Driver"
        case .installed:
            return "Reinstall"
        case .updateAvailable:
            return "Update Driver"
        }
    }

    private func refreshDriverState() {
        driverState = Permissions.driverState()
    }

    private func performDriverAction() {
        isWorkingOnDriver = true
        driverError = nil
        Task.detached {
            do {
                try Permissions.installDriver()
                await MainActor.run {
                    refreshDriverState()
                    isWorkingOnDriver = false
                }
            } catch {
                await MainActor.run {
                    driverError = error.localizedDescription
                    isWorkingOnDriver = false
                }
            }
        }
    }

    private func uninstallDriver() {
        isWorkingOnDriver = true
        driverError = nil
        Task.detached {
            do {
                try Permissions.uninstallDriver()
                await MainActor.run {
                    refreshDriverState()
                    isWorkingOnDriver = false
                }
            } catch {
                await MainActor.run {
                    driverError = error.localizedDescription
                    isWorkingOnDriver = false
                }
            }
        }
    }
}
