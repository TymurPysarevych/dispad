import Foundation
import DispadProtocol

/// Swift-friendly async wrapper around Peertalk's Objective-C callback API.
///
/// Exposes a single `AsyncStream<Event>` for connection lifecycle and incoming
/// frames, plus `send(_:)` / `stop()` for producers. The actor owns the
/// `PTUSBHub`/`PTChannel`/delegate-proxy lifetime and serializes all mutations
/// of that state.
actor UsbChannel {
    enum Event {
        case connected
        case disconnected
        case received(Data)
    }

    enum UsbError: Error {
        case notConnected
    }

    private let port: UInt32
    private var hub: PTUSBHub?
    private var channel: PTChannel?
    private var delegateProxy: UsbChannelDelegateProxy?
    private var deviceID: NSNumber?
    private var isConnected: Bool = false

    private var continuation: AsyncStream<Event>.Continuation?
    private var attachObserver: NSObjectProtocol?
    private var detachObserver: NSObjectProtocol?

    init(port: UInt32 = ProtocolVersion.fixedPort) {
        self.port = port
    }

    /// Starts observing USB attach/detach and emits lifecycle + frame events.
    ///
    /// This stream is designed for **single-consumer lifetime use**: calling
    /// `events()` a second time will `finish()` any previously installed
    /// continuation, terminating prior streams. Do not share the returned
    /// stream across multiple concurrent consumers expecting independent
    /// lifetimes.
    func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task { await self.beginStream(continuation: continuation) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.stop() }
            }
        }
    }

    /// Sends a raw payload as a single Peertalk frame on the active channel.
    /// Throws `UsbError.notConnected` if no channel is currently connected.
    func send(_ data: Data) async throws {
        guard let channel = self.channel, isConnected else {
            throw UsbError.notConnected
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            channel.sendFrame(type: 0, tag: 0, payload: data) { error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    /// Tears down the active channel, observers, and the event stream.
    func stop() {
        if let attachObserver {
            NotificationCenter.default.removeObserver(attachObserver)
        }
        if let detachObserver {
            NotificationCenter.default.removeObserver(detachObserver)
        }
        attachObserver = nil
        detachObserver = nil

        channel?.close()
        channel = nil
        delegateProxy = nil
        deviceID = nil
        isConnected = false
        hub = nil

        continuation?.finish()
        continuation = nil
    }

    // MARK: - Private

    private func beginStream(continuation: AsyncStream<Event>.Continuation) {
        // Terminate any previously installed continuation so the old stream
        // is cleanly finished instead of silently orphaned.
        self.continuation?.finish()
        self.continuation = continuation

        let hub = PTUSBHub.shared()
        self.hub = hub

        attachObserver = NotificationCenter.default.addObserver(
            forName: .deviceDidAttach,
            object: hub,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let id = note.userInfo?[PTUSBHubNotificationKey.deviceID] as? NSNumber
            Task { await self.handleAttach(deviceID: id) }
        }

        detachObserver = NotificationCenter.default.addObserver(
            forName: .deviceDidDetach,
            object: hub,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let id = note.userInfo?[PTUSBHubNotificationKey.deviceID] as? NSNumber
            Task { await self.handleDetach(deviceID: id) }
        }
    }

    private func handleAttach(deviceID: NSNumber?) {
        guard let deviceID, self.deviceID == nil, let hub = self.hub else { return }
        self.deviceID = deviceID

        let proxy = UsbChannelDelegateProxy(owner: self)
        let channel = PTChannel(protocol: nil, delegate: proxy)
        self.delegateProxy = proxy
        self.channel = channel

        channel.connect(to: Int32(port), over: hub, deviceID: deviceID) { [weak self] error in
            guard let self else { return }
            if error != nil {
                Task { await self.teardownChannel(emitDisconnected: false) }
            } else {
                Task { await self.markConnected() }
            }
        }
    }

    private func markConnected() {
        isConnected = true
        emit(.connected)
    }

    private func handleDetach(deviceID: NSNumber?) {
        // Only react if the detach matches our connected device (or if we
        // don't yet know which device we're on).
        if let our = self.deviceID, let incoming = deviceID, our != incoming {
            return
        }
        teardownChannel(emitDisconnected: true)
    }

    fileprivate func deliver(_ event: Event) {
        switch event {
        case .disconnected:
            // Route disconnect through teardown so channel state is cleaned.
            teardownChannel(emitDisconnected: true)
        default:
            emit(event)
        }
    }

    private func emit(_ event: Event) {
        continuation?.yield(event)
    }

    private func teardownChannel(emitDisconnected: Bool) {
        channel?.close()
        channel = nil
        delegateProxy = nil
        deviceID = nil
        isConnected = false
        if emitDisconnected {
            emit(.disconnected)
        }
    }
}

/// Bridges Peertalk's Objective-C delegate callbacks back into the actor.
///
/// Held strongly by `UsbChannel` while a channel is open; `PTChannel` holds
/// the delegate weakly (see `PTChannel.h`), so dropping the proxy reference
/// in the actor is what releases it.
private final class UsbChannelDelegateProxy: NSObject, PTChannelDelegate {
    weak var owner: UsbChannel?

    init(owner: UsbChannel) {
        self.owner = owner
    }

    func channel(_ channel: PTChannel, didRecieveFrame type: UInt32, tag: UInt32, payload: Data?) {
        guard let payload else { return }
        Task { [weak self] in await self?.owner?.deliver(.received(payload)) }
    }

    func channelDidEnd(_ channel: PTChannel, error: Error?) {
        Task { [weak self] in await self?.owner?.deliver(.disconnected) }
    }
}
