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
        // 1) Close the outbound stream so the consumer's `for await` exits
        //    naturally after processing what's already buffered.
        outboundContinuation?.finish()
        outboundContinuation = nil

        // 2) Wait for the consumer task to drain and exit. We don't need to
        //    actively cancel it — finishing the continuation makes `for await`
        //    return on its own, and awaiting the task prevents shutting the
        //    channel down mid-send.
        let drainingOutbound = outboundTask
        outboundTask = nil

        // 3) Stop the inbound event task and close the channel.
        eventTask?.cancel()
        eventTask = nil
        Task { [channel, drainingOutbound] in
            await drainingOutbound?.value
            await channel?.stop()
        }
        channel = nil
    }

    /// Enqueues a message for in-order delivery. Non-blocking. Use this
    /// from callback sites (e.g. encoder.onFrame) where you want
    /// order-preserving fire-and-forget semantics. Errors are logged
    /// but not propagated — the pipeline will drop frames until the
    /// next keyframe if the channel dies mid-send.
    func enqueue(_ message: Message) {
        guard let continuation = outboundContinuation else {
            Log.transport.error("TransportServer.enqueue called before start() or after stop(); dropping message")
            return
        }
        continuation.yield(message)
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
