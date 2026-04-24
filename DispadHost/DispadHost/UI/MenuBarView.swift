import SwiftUI

struct MenuBarView: View {
    @ObservedObject var coordinator: HostCoordinator
    @State private var launchAgentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            Divider()
            Button("Send test heartbeat") { coordinator.sendTest() }
            Divider()
            launchAgentSection
            Divider()
            Button("Open log file") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/dispad-host.log"))
            }
            Button("Quit dispad") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
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
}
