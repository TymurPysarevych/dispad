import SwiftUI
import CoreMedia
import CoreVideo
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
        transport.onMessage = { [weak self] message in
            print("HostCoordinator: received \(message)")
            if case .hello = message {
                Task { @MainActor in self?.start() }
            }
        }
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
        print("HostCoordinator.start(): current state = \(state)")
        guard case .waitingForClient = state else {
            print("HostCoordinator.start(): not in waitingForClient, ignoring")
            return
        }

        // Capture non-isolated references so callbacks invoked off the MainActor
        // (VideoToolbox output thread, capture dispatch queue) don't touch
        // MainActor-isolated state.
        let encoder = self.encoder
        let transport = self.transport

        encoder.onFrame = { frame in
            print("HostCoordinator: encoder emitted frame keyframe=\(frame.isKeyframe) nalus=\(frame.nalus.count)B parameterSets=\(frame.parameterSets?.count ?? 0)B")
            if let ps = frame.parameterSets {
                Task { try? await transport.send(.config(parameterSets: ps)) }
            }
            Task {
                try? await transport.send(
                    .videoFrame(isKeyframe: frame.isKeyframe, pts: frame.pts, naluData: frame.nalus)
                )
            }
        }

        capture.onSample = { sample in
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { return }
            let w = Int32(CVPixelBufferGetWidth(pb))
            let h = Int32(CVPixelBufferGetHeight(pb))
            try? encoder.configure(width: w, height: h)
            encoder.encode(sample)
        }

        Task {
            do {
                print("HostCoordinator: starting capture")
                try await capture.start()
                print("HostCoordinator: capture started")
                self.state = .streaming
            } catch {
                print("HostCoordinator: capture failed: \(error)")
                self.state = .error(String(describing: error))
            }
        }
    }

    func stop() {
        Task { await capture.stop() }
        encoder.invalidate()
        transport.stop()
        state = .idle
    }
}
