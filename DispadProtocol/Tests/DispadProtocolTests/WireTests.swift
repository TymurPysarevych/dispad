import XCTest
@testable import DispadProtocol

final class WireTests: XCTestCase {

    func testHelloRoundTrip() throws {
        let original = Message.hello(protocolVersion: 1, screenWidth: 1920, screenHeight: 1080)
        let encoded = WireCodec.encode(original)
        let payload = try stripLengthPrefix(encoded)
        let decoded = try WireCodec.decode(payload: payload)
        XCTAssertEqual(decoded, original)
    }

    func testConfigRoundTrip() throws {
        let params = Data(repeating: 0xAB, count: 123)
        let original = Message.config(parameterSets: params)
        let encoded = WireCodec.encode(original)
        let payload = try stripLengthPrefix(encoded)
        let decoded = try WireCodec.decode(payload: payload)
        XCTAssertEqual(decoded, original)
    }

    func testVideoFrameRoundTrip() throws {
        let nalu = Data(repeating: 0xCD, count: 4096)
        let original = Message.videoFrame(isKeyframe: true, pts: 123_456_789, naluData: nalu)
        let encoded = WireCodec.encode(original)
        let payload = try stripLengthPrefix(encoded)
        let decoded = try WireCodec.decode(payload: payload)
        XCTAssertEqual(decoded, original)
    }

    func testHeartbeatRoundTrip() throws {
        let original = Message.heartbeat
        let encoded = WireCodec.encode(original)
        let payload = try stripLengthPrefix(encoded)
        let decoded = try WireCodec.decode(payload: payload)
        XCTAssertEqual(decoded, original)
    }

    func testDisplayModeRoundTripFit() throws {
        try assertRoundTrip(.displayMode(.fit))
    }

    func testDisplayModeRoundTripFill() throws {
        try assertRoundTrip(.displayMode(.fill))
    }

    func testDisplayModeRoundTripStretch() throws {
        try assertRoundTrip(.displayMode(.stretch))
    }

    func testUnknownMessageTypeIsRejected() {
        let bogusPayload = Data([0xFF, 0x00, 0x01])
        XCTAssertThrowsError(try WireCodec.decode(payload: bogusPayload)) { error in
            XCTAssertEqual(error as? WireError, WireError.unknownMessageType(0xFF))
        }
    }

    func testTruncatedHelloIsRejected() {
        let truncated = Data([MessageType.hello.rawValue, 0x00, 0x01])
        XCTAssertThrowsError(try WireCodec.decode(payload: truncated)) { error in
            XCTAssertEqual(error as? WireError, WireError.truncatedPayload(expected: 6, got: 2))
        }
    }

    func testFrameReaderHandlesSplitData() throws {
        let m1 = Message.hello(protocolVersion: 1, screenWidth: 1920, screenHeight: 1080)
        let m2 = Message.heartbeat
        let encoded = WireCodec.encode(m1) + WireCodec.encode(m2)

        let reader = FrameReader()
        reader.feed(encoded.prefix(3))
        XCTAssertNil(try reader.nextFrame())

        reader.feed(encoded.dropFirst(3))

        let p1 = try XCTUnwrap(try reader.nextFrame())
        let p2 = try XCTUnwrap(try reader.nextFrame())
        XCTAssertNil(try reader.nextFrame())

        XCTAssertEqual(try WireCodec.decode(payload: p1), m1)
        XCTAssertEqual(try WireCodec.decode(payload: p2), m2)
    }

    func testFrameReaderRejectsOversizedFrame() {
        let reader = FrameReader()
        var data = Data()
        data.appendBigEndian(WireCodec.maxFrameLength + 1)
        reader.feed(data)
        XCTAssertThrowsError(try reader.nextFrame()) { error in
            if case .lengthTooLarge = (error as? WireError) {
                // expected
            } else {
                XCTFail("expected lengthTooLarge, got \(error)")
            }
        }
    }

    private func assertRoundTrip(_ original: Message) throws {
        let encoded = WireCodec.encode(original)
        let payload = try stripLengthPrefix(encoded)
        let decoded = try WireCodec.decode(payload: payload)
        XCTAssertEqual(decoded, original)
    }

    private func stripLengthPrefix(_ framed: Data) throws -> Data {
        XCTAssertGreaterThanOrEqual(framed.count, 4)
        let length: UInt32 = framed.readBigEndian(at: 0)
        XCTAssertEqual(framed.count, 4 + Int(length))
        return framed.subdata(in: 4..<framed.count)
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
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
