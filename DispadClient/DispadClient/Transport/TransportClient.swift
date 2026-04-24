import Foundation
import Network
import UIKit
import DispadProtocol

enum TransportError: Error {
    case notConnected
}

private func isLoopback(_ host: NWEndpoint.Host) -> Bool {
    switch host {
    case .ipv4(let addr): return addr == .loopback
    case .ipv6(let addr): return addr == .loopback
    case .name(let name, _): return name == "localhost" || name == "ip6-localhost"
    @unknown default: return false
    }
}

@MainActor
final class TransportClient: ObservableObject {
    @Published var isConnected: Bool = false

    var onMessage: ((Message) -> Void)?

    private var listener: NWListener?
    private var connection: NWConnection?
    private var reader = FrameReader()
    private let queue = DispatchQueue(label: "dispad.transport.client")
    private var byteContinuation: AsyncStream<Data>.Continuation?
    private var consumerTask: Task<Void, Never>?

    private var outboundContinuation: AsyncStream<Message>.Continuation?
    private var outboundTask: Task<Void, Never>?

    func start() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = false
            let port = NWEndpoint.Port(rawValue: UInt16(ProtocolVersion.fixedPort))!
            let listener = try NWListener(using: params, on: port)
            self.listener = listener

            listener.stateUpdateHandler = { state in
                Log.transport.info("TransportClient listener state: \(String(describing: state), privacy: .public)")
            }
            listener.newConnectionHandler = { [weak self] connection in
                let endpoint = connection.endpoint
                Log.transport.info("TransportClient: new connection from \(String(describing: endpoint), privacy: .public)")

                // Peertalk's usbmuxd tunnel terminates at 127.0.0.1 on this device.
                // Any non-loopback peer is a Wi-Fi stranger — reject to avoid
                // exposing our listener to the local network.
                if case let .hostPort(host, _) = endpoint, !isLoopback(host) {
                    Log.transport.info("TransportClient: rejecting non-loopback peer \(String(describing: host), privacy: .public)")
                    connection.cancel()
                    return
                }

                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.start(queue: queue)
            Log.transport.info("TransportClient: starting listener on port \(port.rawValue, privacy: .public)")

            let (stream, continuation) = AsyncStream<Message>.makeStream(bufferingPolicy: .unbounded)
            self.outboundContinuation = continuation
            outboundTask = Task { [weak self] in
                guard let self else { return }
                for await message in stream {
                    await self.deliverOutbound(message)
                }
            }
        } catch {
            Log.transport.error("TransportClient listener failed: \(error, privacy: .public)")
        }
    }

    func stop() {
        // Drain outbound first so an in-flight send finishes before we
        // tear down the connection underneath it.
        outboundContinuation?.finish()
        outboundContinuation = nil
        let drainingOutbound = outboundTask
        outboundTask = nil

        consumerTask?.cancel()
        consumerTask = nil
        byteContinuation?.finish()
        byteContinuation = nil

        let closingConnection = connection
        let closingListener = listener
        listener = nil
        connection = nil

        Task { [drainingOutbound, closingConnection, closingListener] in
            await drainingOutbound?.value
            closingConnection?.cancel()
            closingListener?.cancel()
        }
    }

    /// Enqueues a message for in-order delivery. Non-blocking. Use this
    /// from callback sites where you want order-preserving fire-and-forget
    /// semantics. Errors are logged but not propagated.
    func enqueue(_ message: Message) {
        guard let continuation = outboundContinuation else {
            Log.transport.error("TransportClient.enqueue called before start() or after stop(); dropping message")
            return
        }
        continuation.yield(message)
    }

    func send(_ message: Message) async throws {
        guard let connection else { throw TransportError.notConnected }
        let frame = WireCodec.encode(message)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    private func deliverOutbound(_ message: Message) async {
        do {
            try await send(message)
        } catch {
            Log.transport.error("TransportClient send error: \(error, privacy: .public)")
        }
    }

    private func accept(_ connection: NWConnection) {
        self.reader = FrameReader()
        self.connection?.cancel()
        self.connection = connection

        // Tear down any previous consumer pipeline.
        byteContinuation?.finish()
        consumerTask?.cancel()

        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        self.byteContinuation = continuation

        consumerTask = Task { [weak self] in
            guard let self else { return }
            for await chunk in stream {
                await self.consume(chunk, connection: connection)
            }
        }

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Log.transport.info("TransportClient connection state: \(String(describing: state), privacy: .public)")
            Task { @MainActor in
                switch state {
                case .ready:
                    self.isConnected = true
                    let hello = Message.hello(
                        protocolVersion: ProtocolVersion.current,
                        screenWidth: UInt16(UIScreen.main.nativeBounds.width),
                        screenHeight: UInt16(UIScreen.main.nativeBounds.height)
                    )
                    self.enqueue(hello)
                case .failed, .cancelled:
                    self.isConnected = false
                    self.byteContinuation?.finish()
                default: break
                }
            }
        }

        connection.start(queue: queue)
        receive(on: connection, continuation: continuation)
    }

    private func consume(_ chunk: Data, connection: NWConnection) async {
        reader.feed(chunk)
        do {
            while let payload = try reader.nextFrame() {
                let message = try WireCodec.decode(payload: payload)
                onMessage?(message)
            }
        } catch {
            Log.transport.error("TransportClient decode error: \(error, privacy: .public)")
            connection.cancel()
            byteContinuation?.finish()
            reader = FrameReader()
        }
    }

    private nonisolated func receive(on connection: NWConnection, continuation: AsyncStream<Data>.Continuation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                // Thread-safe and order-preserving: we're on the serial NW queue
                // and yield is synchronous.
                continuation.yield(data)
            }
            if isComplete || error != nil {
                continuation.finish()
                Task { @MainActor in self.isConnected = false }
                return
            }
            self.receive(on: connection, continuation: continuation)
        }
    }
}
