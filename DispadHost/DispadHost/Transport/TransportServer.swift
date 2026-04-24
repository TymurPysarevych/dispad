import Foundation
import DispadProtocol

@MainActor
final class TransportServer: ObservableObject {
    @Published var isConnected: Bool = false

    var onMessage: ((Message) -> Void)?

    private var channel: UsbChannel?
    private var eventTask: Task<Void, Never>?
    private let reader = FrameReader()

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

    func send(_ message: Message) {
        let frame = WireCodec.encode(message)
        Task { [channel] in
            try? await channel?.send(frame)
        }
    }

    private func handle(_ event: UsbChannel.Event) async {
        switch event {
        case .connected:
            self.isConnected = true
        case .disconnected:
            self.isConnected = false
        case let .received(data):
            self.reader.feed(data)
            do {
                while let payload = try reader.nextFrame() {
                    let message = try WireCodec.decode(payload: payload)
                    self.onMessage?(message)
                }
            } catch {
                print("TransportServer decode error: \(error)")
            }
        }
    }
}
