import Foundation
import DispadProtocol

enum TransportError: Error {
    case notConnected
}

@MainActor
final class TransportServer: ObservableObject {
    @Published var isConnected: Bool = false

    var onMessage: ((Message) -> Void)?

    private var channel: UsbChannel?
    private var eventTask: Task<Void, Never>?
    private var reader = FrameReader()

    func start() {
        let channel = UsbChannel()
        self.channel = channel

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in await channel.events() {
                await self.handle(event)
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        Task { [channel] in await channel?.stop() }
        channel = nil
    }

    func send(_ message: Message) async throws {
        guard let channel else { throw TransportError.notConnected }
        let frame = WireCodec.encode(message)
        try await channel.send(frame)
    }

    private func handle(_ event: UsbChannel.Event) async {
        switch event {
        case .connected:
            self.isConnected = true
        case .disconnected:
            self.isConnected = false
            self.reader = FrameReader()
        case let .received(data):
            self.reader.feed(data)
            do {
                while let payload = try reader.nextFrame() {
                    let message = try WireCodec.decode(payload: payload)
                    self.onMessage?(message)
                }
            } catch {
                Log.transport.error("TransportServer decode error: \(error, privacy: .public)")
            }
        }
    }
}
