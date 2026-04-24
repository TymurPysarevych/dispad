import SwiftUI
import DispadProtocol

@main
struct DispadHostApp: App {
    @StateObject private var coordinator = HostCoordinator()

    var body: some Scene {
        MenuBarExtra("dispad", systemImage: statusIcon(for: coordinator.state)) {
            MenuBarView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)
    }

    private func statusIcon(for state: HostState) -> String {
        switch state {
        case .idle: return "display"
        case .waitingForClient: return "display.trianglebadge.exclamationmark"
        case .streaming: return "dot.radiowaves.left.and.right"
        case .error: return "exclamationmark.triangle"
        }
    }
}

enum HostState {
    case idle
    case waitingForClient
    case streaming
    case error(String)
}

@MainActor
final class HostCoordinator: ObservableObject {
    @Published var state: HostState = .idle

    private let capture = CaptureEngine()
    private let encoder = HEVCEncoder()
    private let transport = TransportServer()

    init() {
        startTransport()
    }

    func startTransport() {
        transport.start()
        state = .waitingForClient
    }

    func sendTest() {
        Task {
            do {
                try await transport.send(.heartbeat)
            } catch {
                print("DispadHost send heartbeat failed: \(error)")
            }
        }
    }

    func start() {
        // TODO: wire capture → encoder → transport pipeline
    }

    func stop() {
        // TODO: tear down pipeline
    }
}
