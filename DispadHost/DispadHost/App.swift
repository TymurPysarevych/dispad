import SwiftUI
import Combine
import CoreGraphics
import CoreMedia
import CoreVideo
import DispadProtocol

extension DisplayFillMode {
    /// `@AppStorage` and similar UserDefaults APIs prefer `Int` for
    /// persistence. Use the raw `Int` value as the storage representation.
    var storageValue: Int { Int(rawValue) }

    static func from(storageValue value: Int) -> DisplayFillMode {
        DisplayFillMode(rawValue: UInt8(clamping: value)) ?? .fit
    }
}

@main
struct DispadHostApp: App {
    @StateObject private var coordinator = HostCoordinator()
    @State private var showWelcome: Bool = !UserDefaults.standard.bool(forKey: "com.dispad.host.welcomeSeen")
        && !LaunchAgentInstaller.isInstalled

    var body: some Scene {
        MenuBarExtra("dispad", systemImage: statusIcon(for: coordinator.state)) {
            MenuBarView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to dispad", id: "welcome") {
            if showWelcome {
                WelcomeSheet()
                    .onDisappear { showWelcome = false }
            } else {
                EmptyView()
                    .frame(width: 1, height: 1)
            }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
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
            let message = String(format: "HostCoordinator: %.1f fps, %.1f Mbps", fps, mbps)
            Log.stats.info("\(message, privacy: .public)")
            frames = 0
            self.bytes = 0
            windowStart = now
        }
    }
}

@MainActor
final class HostCoordinator: ObservableObject {
    @Published var state: HostState = .idle

    @Published var displayMode: DisplayFillMode = {
        let raw = UserDefaults.standard.integer(forKey: "com.dispad.host.displayMode")
        return DisplayFillMode.from(storageValue: raw)
    }()

    private let capture = CaptureEngine()
    private let encoder = HEVCEncoder()
    private let transport = TransportServer()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Ask for Screen Recording permission at launch instead of waiting
        // for the iPad's hello to trigger SCShareableContent. Without this,
        // a user who hasn't connected an iPad yet will never see the TCC
        // prompt and will think the app is silently broken.
        if !CGPreflightScreenCaptureAccess() {
            Log.pipeline.info("Screen Recording permission not yet granted — requesting")
            _ = CGRequestScreenCaptureAccess()
        }

        // If the user has auto-launch enabled and they just launched us
        // manually (from Finder/Dock/Xcode rather than via launchd), refresh
        // the LaunchAgent plist on disk so upgrades to its contents take
        // effect without a manual disable/enable round trip.
        //
        // Skip this when launchd is our parent (XPC_SERVICE_NAME is set to
        // our label) — otherwise install() would `bootout` the very service
        // hosting us and we'd be terminated mid-launch.
        let xpcService = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"]
        if xpcService != LaunchAgentInstaller.label, LaunchAgentInstaller.isInstalled {
            do {
                try LaunchAgentInstaller.install()
                Log.pipeline.info("LaunchAgent refreshed from bundled template")
            } catch {
                Log.pipeline.error("LaunchAgent refresh failed: \(error, privacy: .public)")
            }
        }

        transport.onMessage = { [weak self] message in
            Log.pipeline.debug("received \(String(describing: message), privacy: .public)")
            if case .hello = message {
                Task { @MainActor in
                    guard let self else { return }
                    self.start()
                    self.transport.enqueue(.displayMode(self.displayMode))
                }
            }
        }

        // Reflect transport disconnect in the UI so the menu-bar status
        // doesn't lie that we're "Streaming" after the iPad goes away.
        // Skip the initial value (false) since startTransport() will flip
        // us to .waitingForClient explicitly.
        transport.$isConnected
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                if !connected {
                    Task { @MainActor in self.handleClientDisconnected() }
                }
            }
            .store(in: &cancellables)

        startTransport()
    }

    private func handleClientDisconnected() {
        // Only react if we were actually streaming. If we were already
        // .waitingForClient, .idle, or in an .error state, leave it alone.
        guard case .streaming = state else { return }
        Log.pipeline.info("Client disconnected; stopping capture and returning to waiting")
        Task { await capture.stop() }
        encoder.invalidate()
        state = .waitingForClient
    }

    func setDisplayMode(_ mode: DisplayFillMode) {
        displayMode = mode
        UserDefaults.standard.set(mode.storageValue, forKey: "com.dispad.host.displayMode")
        transport.enqueue(.displayMode(mode))
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
                Log.transport.error("DispadHost send heartbeat failed: \(error, privacy: .public)")
            }
        }
    }

    func start() {
        Log.pipeline.info("HostCoordinator.start(): current state = \(String(describing: self.state), privacy: .public)")
        guard case .waitingForClient = state else {
            Log.pipeline.info("HostCoordinator.start(): not in waitingForClient, ignoring")
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
                transport.enqueue(.config(parameterSets: ps))
            }
            transport.enqueue(.videoFrame(isKeyframe: frame.isKeyframe, pts: frame.pts, naluData: frame.nalus))
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
                Log.pipeline.info("HostCoordinator: starting capture")
                try await capture.start()
                Log.pipeline.info("HostCoordinator: capture started")
                self.state = .streaming
            } catch {
                Log.pipeline.error("HostCoordinator: capture failed: \(error, privacy: .public)")
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
