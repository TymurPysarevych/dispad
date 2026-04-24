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

/// Tiny thread-safe sliding-window FPS + bytes/sec reporter. `tick(bytes:)`
/// is called once per encoded frame from the VideoToolbox output thread.
/// Prints a summary once per second.
final class FrameCounter {
    private let lock = NSLock()
    private var windowStart = CFAbsoluteTimeGetCurrent()
    private var frames = 0
    private var bytes = 0

    func tick(bytes: Int) {
        lock.lock(); defer { lock.unlock() }
        frames += 1
        self.bytes += bytes
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - windowStart
        if elapsed >= 1.0 {
            let fps = Double(frames) / elapsed
            let mbps = Double(self.bytes * 8) / elapsed / 1_000_000
            print(String(format: "HostCoordinator: %.1f fps, %.1f Mbps", fps, mbps))
            frames = 0
            self.bytes = 0
            windowStart = now
        }
    }
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

        // Simple 1-second sliding FPS + throughput counter for the encoder
        // output. Logged once per second so we can see actual rate without
        // flooding the console on every frame.
        let counter = FrameCounter()

        encoder.onFrame = { frame in
            counter.tick(bytes: frame.nalus.count)
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
