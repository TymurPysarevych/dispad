import Foundation
import DispadProtocol

final class TransportServer {
    var onClientConnected: (() -> Void)?
    var onClientDisconnected: (() -> Void)?

    func start() {
        // TODO: open a Peertalk-style usbmuxd listening channel on ProtocolVersion.fixedPort.
        // Accept a single client at a time; emit onClientConnected / onClientDisconnected.
    }

    func stop() {
        // TODO: close listener and any active client channel.
    }

    func send(_ message: Message) {
        // TODO: WireCodec.encode(message) and write to the active client channel.
    }
}
