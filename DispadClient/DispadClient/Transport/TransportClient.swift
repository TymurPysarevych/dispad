import Foundation
import Network
import UIKit
import DispadProtocol

@MainActor
final class TransportClient: ObservableObject {
    @Published var isConnected: Bool = false

    var onMessage: ((Message) -> Void)?

    private var listener: NWListener?
    private var connection: NWConnection?
    private let reader = FrameReader()
    private let queue = DispatchQueue(label: "dispad.transport.client")

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
        listener?.cancel()
        connection?.cancel()
        listener = nil
        connection = nil
    }

    func send(_ message: Message) {
        guard let connection else { return }
        let frame = WireCodec.encode(message)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func accept(_ connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection

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
                    self.send(hello)
                case .failed, .cancelled:
                    self.isConnected = false
                default: break
                }
            }
        }

        connection.start(queue: queue)
        receive(on: connection)
    }

    private nonisolated func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task { @MainActor in
                    self.reader.feed(data)
                    do {
                        while let payload = try self.reader.nextFrame() {
                            let message = try WireCodec.decode(payload: payload)
                            self.onMessage?(message)
                        }
                    } catch {
                        print("TransportClient decode error: \(error)")
                        connection.cancel()
                        return
                    }
                }
            }
            if isComplete || error != nil {
                connection.cancel()
                Task { @MainActor in self.isConnected = false }
                return
            }
            self.receive(on: connection)
        }
    }
}
