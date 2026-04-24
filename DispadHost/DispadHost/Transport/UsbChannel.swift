import Foundation
import Dispatch
import DispadProtocol

/// Swift-friendly async wrapper around Peertalk's Objective-C USB API.
///
/// Exposes a single `AsyncStream<Event>` for connection lifecycle and incoming
/// raw bytes, plus `send(_:)` / `stop()` for producers.
///
/// Implementation detail: we use `PTUSBHub.connectToDevice(port:onStart:onEnd:)`
/// which gives a raw `DispatchIO` channel over the usbmuxd tunnel, then do
/// plain read/write on it. We deliberately do NOT use `PTChannel`, because
/// `PTChannel` wraps every send in Peertalk's own framing (type, tag, length
/// header) which expects the peer to also be running Peertalk. Our iPad side
/// is plain `NWConnection` and would reject those framed bytes.
actor UsbChannel {
    enum Event {
        case connected
        case disconnected
        case received(Data)
    }

    enum UsbError: Error {
        case notConnected
        case writeFailed(Int32)
    }

    private let port: UInt32
    private let ioQueue = DispatchQueue(label: "dispad.usbchannel.io", qos: .userInitiated)
    private var hub: PTUSBHub?
    private var io: DispatchIO?
    private var deviceID: NSNumber?
    private var isConnected: Bool = false

    private var continuation: AsyncStream<Event>.Continuation?
    private var attachObserver: NSObjectProtocol?
    private var detachObserver: NSObjectProtocol?

    init(port: UInt32 = ProtocolVersion.fixedPort) {
        self.port = port
    }

    /// Single-consumer stream of lifecycle + byte events.
    func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task { await self.beginStream(continuation: continuation) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.stop() }
            }
        }
    }

    /// Writes `data` as raw bytes onto the USB-tunnelled socket.
    func send(_ data: Data) async throws {
        guard let io, isConnected else { throw UsbError.notConnected }
        let dispatchData = data.withUnsafeBytes { ptr -> DispatchData in
            DispatchData(bytes: UnsafeRawBufferPointer(start: ptr.baseAddress, count: ptr.count))
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            io.write(offset: 0, data: dispatchData, queue: ioQueue) { done, _, error in
                if error != 0 {
                    cont.resume(throwing: UsbError.writeFailed(error))
                } else if done {
                    cont.resume()
                }
            }
        }
    }

    func stop() {
        if let attachObserver {
            NotificationCenter.default.removeObserver(attachObserver)
        }
        if let detachObserver {
            NotificationCenter.default.removeObserver(detachObserver)
        }
        attachObserver = nil
        detachObserver = nil

        io?.close(flags: [])
        io = nil
        deviceID = nil
        isConnected = false
        hub = nil

        continuation?.finish()
        continuation = nil
    }

    // MARK: - Private

    private func beginStream(continuation: AsyncStream<Event>.Continuation) {
        self.continuation?.finish()
        self.continuation = continuation

        // Register observers BEFORE touching the shared hub so retroactive
        // attach events (for devices already plugged in at launch) aren't
        // missed.
        attachObserver = NotificationCenter.default.addObserver(
            forName: .deviceDidAttach,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let id = note.userInfo?[PTUSBHubNotificationKey.deviceID] as? NSNumber
            let props = note.userInfo?[PTUSBHubNotificationKey.properties] as? [String: Any]
            let connectionType = props?["ConnectionType"] as? String ?? "unknown"
            let serial = (props?["SerialNumber"] as? String) ?? "unknown"
            let productID = (props?["ProductID"] as? NSNumber)?.stringValue ?? "?"
            let locationID = (props?["LocationID"] as? NSNumber)?.stringValue ?? "?"
            print("UsbChannel: deviceDidAttach id=\(id?.stringValue ?? "nil") type=\(connectionType) productID=\(productID) location=\(locationID) serial=\(serial)")
            guard connectionType == "USB" else {
                print("UsbChannel: skipping non-USB device (type=\(connectionType))")
                return
            }
            Task { await self.handleAttach(deviceID: id) }
        }

        detachObserver = NotificationCenter.default.addObserver(
            forName: .deviceDidDetach,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let id = note.userInfo?[PTUSBHubNotificationKey.deviceID] as? NSNumber
            print("UsbChannel: deviceDidDetach id=\(id?.stringValue ?? "nil")")
            Task { await self.handleDetach(deviceID: id) }
        }

        let hub = PTUSBHub.shared()
        self.hub = hub
        print("UsbChannel: hub listening on port \(port)")
    }

    private func handleAttach(deviceID: NSNumber?) {
        guard let deviceID, self.deviceID == nil, let hub = self.hub else { return }
        self.deviceID = deviceID

        print("UsbChannel: attempting raw connect to device \(deviceID) on port \(port)")
        hub.connect(
            toDevice: deviceID,
            port: Int32(port),
            onStart: { [weak self] error, rawIO in
                guard let self else { return }
                if let error {
                    print("UsbChannel: connect failed: \(error)")
                    Task { await self.teardown(emitDisconnected: false) }
                    return
                }
                guard let rawIO else {
                    print("UsbChannel: connect returned nil io channel")
                    Task { await self.teardown(emitDisconnected: false) }
                    return
                }
                print("UsbChannel: raw io channel ready")
                Task { await self.attachIO(rawIO) }
            },
            onEnd: { [weak self] error in
                guard let self else { return }
                if let error {
                    print("UsbChannel: onEnd with error: \(error)")
                } else {
                    print("UsbChannel: onEnd clean")
                }
                Task { await self.teardown(emitDisconnected: true) }
            }
        )
    }

    private func attachIO(_ rawIO: DispatchIO) {
        self.io = rawIO

        // One long-running read drains bytes for the life of the channel.
        // length: Int.max means "read until EOF"; handler fires per chunk
        // with done:false, and once with done:true at EOF/error.
        print("UsbChannel: starting read loop on ioQueue")
        rawIO.read(offset: 0, length: Int.max, queue: ioQueue) { [weak self] done, data, error in
            guard let self else { return }
            let dataCount = data?.count ?? 0
            print("UsbChannel: read fire done=\(done) bytes=\(dataCount) error=\(error)")
            if let data, !data.isEmpty {
                let bytes = Data(data)
                Task { await self.deliverReceived(bytes) }
            }
            if error != 0 {
                print("UsbChannel: read error: \(error)")
                Task { await self.teardown(emitDisconnected: true) }
                return
            }
            if done {
                print("UsbChannel: read done (EOF)")
                Task { await self.teardown(emitDisconnected: true) }
            }
        }

        markConnected()
    }

    private func markConnected() {
        isConnected = true
        emit(.connected)
    }

    private func handleDetach(deviceID: NSNumber?) {
        if let our = self.deviceID, let incoming = deviceID, our != incoming {
            return
        }
        teardown(emitDisconnected: true)
    }

    private func deliverReceived(_ data: Data) {
        emit(.received(data))
    }

    private func emit(_ event: Event) {
        continuation?.yield(event)
    }

    private func teardown(emitDisconnected: Bool) {
        io?.close(flags: [])
        io = nil
        deviceID = nil
        isConnected = false
        if emitDisconnected {
            emit(.disconnected)
        }
    }
}
