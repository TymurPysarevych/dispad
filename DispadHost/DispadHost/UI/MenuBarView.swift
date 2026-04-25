import SwiftUI
import DispadProtocol

struct MenuBarView: View {
    @ObservedObject var coordinator: HostCoordinator
    @State private var launchAgentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            Divider()
            Button("Send test heartbeat") { coordinator.sendTest() }
            Divider()
            displayModePicker
            Divider()
            launchAgentSection
            Divider()
            Button("Open recent logs") { exportAndOpenLogs() }
            Button("Quit dispad") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
    }

    @ViewBuilder private var displayModePicker: some View {
        Picker("Display fill", selection: Binding(
            get: { coordinator.displayMode },
            set: { coordinator.setDisplayMode($0) }
        )) {
            Text("Fit").tag(DisplayFillMode.fit)
            Text("Fill").tag(DisplayFillMode.fill)
            Text("Stretch").tag(DisplayFillMode.stretch)
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder private var statusRow: some View {
        switch coordinator.state {
        case .idle:
            Label("Idle", systemImage: "display")
        case .waitingForClient:
            Label("Waiting for iPad…", systemImage: "display.trianglebadge.exclamationmark")
        case .streaming:
            Label("Streaming", systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.green)
        case let .error(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder private var launchAgentSection: some View {
        if LaunchAgentInstaller.isInstalled {
            HStack {
                Text("Auto-launch: enabled").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Button("Disable auto-launch") {
                do {
                    try LaunchAgentInstaller.uninstall()
                    Log.pipeline.info("LaunchAgent: uninstalled")
                    launchAgentError = nil
                } catch {
                    Log.pipeline.error("LaunchAgent uninstall failed: \(error, privacy: .public)")
                    launchAgentError = "Disable failed: \(error)"
                }
            }
        } else {
            Button("Enable auto-launch") {
                do {
                    try LaunchAgentInstaller.install()
                    Log.pipeline.info("LaunchAgent: installed")
                    launchAgentError = nil
                } catch {
                    Log.pipeline.error("LaunchAgent install failed: \(error, privacy: .public)")
                    launchAgentError = "Install failed: \(error)"
                }
            }
        }
        if let launchAgentError {
            Text(launchAgentError).foregroundStyle(.red).font(.caption)
        }
    }

    /// Dumps the last hour of `com.dispad.host` log entries to a temp file
    /// and opens it. We can't ask Console.app to apply a subsystem filter
    /// for us, so this is the most practical way to give users something
    /// readable in one click without teaching them log show predicates.
    private func exportAndOpenLogs() {
        Task.detached {
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("dispad-host.log")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "show",
                "--predicate", "subsystem == \"com.dispad.host\"",
                "--last", "1h",
                "--style", "compact"
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                try data.write(to: url)
                await MainActor.run { NSWorkspace.shared.open(url) }
            } catch {
                Log.pipeline.error("Failed to export logs: \(error, privacy: .public)")
            }
        }
    }
}
