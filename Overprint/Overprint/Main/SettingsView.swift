import SwiftUI

/// Settings: the launch preference and the Claude Code connection that powers the AI features.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var ai: AIManager
    @ObservedObject var updater: UpdaterController

    @State private var tokenInput = ""
    @State private var cliResult: CommandLineTool.InstallResult?
    @State private var cliInstalledPath: String? = CommandLineTool.installedPath

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Show the launch window when Overprint opens", isOn: Binding(
                get: { model.showLaunchAtStart },
                set: { model.setShowLaunchAtStart($0) }
            ))

            if updater.isConfigured {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
            }

            if !model.hiddenExamples.isEmpty {
                HStack {
                    Text("\(model.hiddenExamples.count) example\(model.hiddenExamples.count == 1 ? "" : "s") hidden from the launch window")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show examples") { model.restoreExamples() }
                }
            }

            Divider()

            commandLineSection

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Claude").font(.headline)

                HStack(spacing: 8) {
                    Circle()
                        .fill(ai.isAvailable ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(ai.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Recheck") { ai.refreshAvailability() }
                }

                Picker("Model", selection: $ai.selectedModel) {
                    ForEach(AIModel.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!ai.isAvailable)

                Divider().padding(.vertical, 2)

                Text("Subscription token").font(.subheadline).fontWeight(.medium)

                SecureField("Long-lived token (sk-ant-oat01-…)", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text(ai.tokenSource)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        ai.clearToken()
                        tokenInput = ""
                    }
                    .disabled(!ai.hasToken)
                    Button("Save") {
                        ai.setToken(tokenInput)
                        tokenInput = ""
                    }
                    .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Text("For headless use, run claude setup-token in a terminal and paste the token here. It is stored in your Keychain.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 440, height: 500)
    }

    /// Installs the bundled `overprint` CLI onto the user's PATH.
    private var commandLineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command line tool").font(.headline)

            if CommandLineTool.bundledURL == nil {
                Text("Ships with release builds only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(cliInstalledPath != nil ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(cliInstalledPath.map { "Installed at \($0)" } ?? "Not installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if cliInstalledPath != nil {
                        Button("Remove") {
                            CommandLineTool.uninstall()
                            cliResult = nil
                            cliInstalledPath = CommandLineTool.installedPath
                        }
                    }
                    Button(cliInstalledPath != nil ? "Reinstall" : "Install") {
                        cliResult = CommandLineTool.install()
                        cliInstalledPath = CommandLineTool.installedPath
                    }
                }

                if case .installedNeedsPath(_, let directory) = cliResult {
                    Text("Installed, but \(directory) is not on your PATH. Add this to your shell profile:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("export PATH=\"\(directory):$PATH\"")
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
                if case .failed(let message) = cliResult {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Adds an `overprint` command for building, serving, and validating sites from the terminal.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
