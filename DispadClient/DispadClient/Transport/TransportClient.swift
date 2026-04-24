import Foundation
import DispadProtocol

final class TransportClient {
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onMessage: ((Message) -> Void)?

    func start() {
        // TODO: open a Peertalk-style listening channel on ProtocolVersion.fixedPort,
        // feed incoming bytes into a FrameReader, decode with WireCodec, emit via onMessage.
    }

    func stop() {
        // TODO: close channel.
    }

    func send(_ message: Message) {
        // TODO: WireCodec.encode(message) and write to the active channel.
    }
}
