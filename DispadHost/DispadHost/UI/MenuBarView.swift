import SwiftUI

struct MenuBarView: View {
    @ObservedObject var coordinator: HostCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            Divider()
            Button("Send test heartbeat") { coordinator.sendTest() }
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
}
