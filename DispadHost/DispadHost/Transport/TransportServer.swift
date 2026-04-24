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

    private var outboundContinuation: AsyncStream<Message>.Continuation?
    private var outboundTask: Task<Void, Never>?

    func start() {
        let channel = UsbChannel()
        self.channel = channel

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in await channel.events() {
                await self.handle(event)
            }
        }

        let (stream, continuation) = AsyncStream<Message>.makeStream(bufferingPolicy: .unbounded)
        self.outboundContinuation = continuation
        outboundTask = Task { [weak self] in
            guard let self else { return }
            for await message in stream {
                await self.deliverOutbound(message)
            }
        }
    }

    func stop() {
        outboundTask?.cancel()
        outboundTask = nil
        outboundContinuation?.finish()
        outboundContinuation = nil

        eventTask?.cancel()
        eventTask = nil
        Task { [channel] in await channel?.stop() }
        channel = nil
    }

    /// Enqueues a message for in-order delivery. Non-blocking. Use this
    /// from callback sites (e.g. encoder.onFrame) where you want
    /// order-preserving fire-and-forget semantics. Errors are logged
    /// but not propagated — the pipeline will drop frames until the
    /// next keyframe if the channel dies mid-send.
    func enqueue(_ message: Message) {
        outboundContinuation?.yield(message)
    }

    func send(_ message: Message) async throws {
        guard let channel else { throw TransportError.notConnected }
        let frame = WireCodec.encode(message)
        try await channel.send(frame)
    }

    private func deliverOutbound(_ message: Message) async {
        let frame = WireCodec.encode(message)
        do {
            try await channel?.send(frame)
        } catch {
            Log.transport.error("TransportServer send error: \(error, privacy: .public)")
        }
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
