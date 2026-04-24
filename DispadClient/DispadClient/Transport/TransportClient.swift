import Foundation
import Network
import UIKit
import DispadProtocol

enum TransportError: Error {
    case notConnected
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

    func start() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = false
            let port = NWEndpoint.Port(rawValue: UInt16(ProtocolVersion.fixedPort))!
            let listener = try NWListener(using: params, on: port)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.start(queue: queue)
        } catch {
            print("TransportClient listener failed: \(error)")
        }
    }

    func stop() {
        consumerTask?.cancel()
        consumerTask = nil
        byteContinuation?.finish()
        byteContinuation = nil
        listener?.cancel()
        connection?.cancel()
        listener = nil
        connection = nil
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
            Task { @MainActor in
                switch state {
                case .ready:
                    self.isConnected = true
                    let hello = Message.hello(
                        protocolVersion: ProtocolVersion.current,
                        screenWidth: UInt16(UIScreen.main.nativeBounds.width),
                        screenHeight: UInt16(UIScreen.main.nativeBounds.height)
                    )
                    Task {
                        do { try await self.send(hello) }
                        catch { print("TransportClient hello send failed: \(error)") }
                    }
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
            print("TransportClient decode error: \(error)")
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
