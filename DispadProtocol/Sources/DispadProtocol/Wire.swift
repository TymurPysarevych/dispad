import Foundation

public enum MessageType: UInt8 {
    case hello = 1
    case config = 2
    case videoFrame = 3
    case heartbeat = 4
    case displayMode = 5
}

public enum DisplayFillMode: UInt8 {
    /// Preserve aspect ratio with letterbox bars (current default).
    case fit = 0
    /// Preserve aspect ratio, fill the screen, crop overflow.
    case fill = 1
    /// Stretch to fill, distorting the image.
    case stretch = 2
}

public enum Message: Equatable {
    case hello(protocolVersion: UInt16, screenWidth: UInt16, screenHeight: UInt16)
    case config(parameterSets: Data)
    case videoFrame(isKeyframe: Bool, pts: UInt64, naluData: Data)
    case heartbeat
    case displayMode(DisplayFillMode)

    public var type: MessageType {
        switch self {
        case .hello: return .hello
        case .config: return .config
        case .videoFrame: return .videoFrame
        case .heartbeat: return .heartbeat
        case .displayMode: return .displayMode
        }
    }
}

public enum WireError: Error, Equatable {
    case unknownMessageType(UInt8)
    case truncatedPayload(expected: Int, got: Int)
    case lengthTooLarge(UInt32)
    case emptyFrame
}

public enum WireCodec {
    public static let maxFrameLength: UInt32 = 16 * 1024 * 1024

    public static func encode(_ message: Message) -> Data {
        var payload = Data()
        payload.append(message.type.rawValue)

        switch message {
        case let .hello(protocolVersion, screenWidth, screenHeight):
            payload.appendBigEndian(protocolVersion)
            payload.appendBigEndian(screenWidth)
            payload.appendBigEndian(screenHeight)
        case let .config(parameterSets):
            payload.append(parameterSets)
        case let .videoFrame(isKeyframe, pts, naluData):
            payload.append(isKeyframe ? 1 : 0)
            payload.appendBigEndian(pts)
            payload.append(naluData)
        case .heartbeat:
            break
        case let .displayMode(mode):
            payload.append(mode.rawValue)
        }

        var frame = Data()
        frame.appendBigEndian(UInt32(payload.count))
        frame.append(payload)
        return frame
    }

    public static func decode(payload: Data) throws -> Message {
        guard let typeByte = payload.first else {
            throw WireError.emptyFrame
        }
        guard let type = MessageType(rawValue: typeByte) else {
            throw WireError.unknownMessageType(typeByte)
        }

        let body = payload.dropFirst()

        switch type {
        case .hello:
            guard body.count == 6 else {
                throw WireError.truncatedPayload(expected: 6, got: body.count)
            }
            let version: UInt16 = body.readBigEndian(at: 0)
            let width: UInt16 = body.readBigEndian(at: 2)
            let height: UInt16 = body.readBigEndian(at: 4)
            return .hello(protocolVersion: version, screenWidth: width, screenHeight: height)

        case .config:
            return .config(parameterSets: Data(body))

        case .videoFrame:
            guard body.count >= 9 else {
                throw WireError.truncatedPayload(expected: 9, got: body.count)
            }
            let flags = body[body.startIndex]
            let pts: UInt64 = body.readBigEndian(at: 1)
            let nalu = Data(body.dropFirst(9))
            return .videoFrame(isKeyframe: (flags & 0x01) != 0, pts: pts, naluData: nalu)

        case .heartbeat:
            return .heartbeat

        case .displayMode:
            guard body.count == 1 else {
                throw WireError.truncatedPayload(expected: 1, got: body.count)
            }
            let raw = body[body.startIndex]
            guard let mode = DisplayFillMode(rawValue: raw) else {
                throw WireError.unknownMessageType(raw)
            }
            return .displayMode(mode)
        }
    }
}

public final class FrameReader {
    private var buffer = Data()
    public init() {}

    public func feed(_ data: Data) {
        buffer.append(data)
    }

    public func nextFrame() throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length: UInt32 = buffer.readBigEndian(at: 0)
        guard length <= WireCodec.maxFrameLength else {
            throw WireError.lengthTooLarge(length)
        }
        let total = 4 + Int(length)
        guard buffer.count >= total else { return nil }
        let payload = buffer.subdata(in: 4..<total)
        buffer.removeSubrange(0..<total)
        return payload
    }
}

extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: UInt32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: UInt64) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    func readBigEndian<T: FixedWidthInteger>(at offset: Int) -> T {
        let start = index(startIndex, offsetBy: offset)
        let end = index(start, offsetBy: MemoryLayout<T>.size)
        let slice = self[start..<end]
        return slice.withUnsafeBytes { $0.loadUnaligned(as: T.self).bigEndian }
    }
}
