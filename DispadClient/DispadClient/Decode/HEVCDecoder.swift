import Foundation
import VideoToolbox
import CoreMedia

final class HEVCDecoder {
    var onDecoded: ((CMSampleBuffer) -> Void)?

    // Implementation deferred — MVP uses AVSampleBufferDisplayLayer which
    // decodes internally. Keep this class as a placeholder for future
    // Metal-based rendering.

    func configure(parameterSets: Data) throws {
        // TODO: create VTDecompressionSession for explicit decode path
    }

    func decode(naluData: Data, pts: UInt64, isKeyframe: Bool) {
        // TODO: VTDecompressionSessionDecodeFrame for explicit decode path
    }

    func invalidate() {
        // TODO
    }

    /// Builds a CMFormatDescription from concatenated AVCC-format HEVC
    /// parameter sets (VPS + SPS + PPS), each prefixed with a 4-byte
    /// big-endian u32 length. Used by `AVSampleBufferDisplayLayer`.
    static func makeFormatDescription(from parameterSets: Data) throws -> CMFormatDescription {
        let parsed = try splitAVCCParameterSets(parameterSets)
        guard !parsed.isEmpty else { throw DecoderError.noParameterSets }

        // Copy each parameter set into a heap buffer we own. Pointers
        // captured from Data.withUnsafeBytes are only guaranteed valid
        // inside that closure; CMVideoFormatDescriptionCreateFromHEVCParameterSets
        // requires stable pointers that outlive the closure, so we make
        // our own. `defer` deallocates regardless of success or error.
        let heapBuffers: [UnsafeMutablePointer<UInt8>] = parsed.map { data in
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
            data.withUnsafeBytes { rawBuf in
                if let base = rawBuf.baseAddress {
                    buf.update(from: base.assumingMemoryBound(to: UInt8.self), count: data.count)
                }
            }
            return buf
        }
        defer {
            for p in heapBuffers { p.deallocate() }
        }

        let sizes: [Int] = parsed.map { $0.count }
        let constPointers: [UnsafePointer<UInt8>] = heapBuffers.map { UnsafePointer($0) }

        var format: CMFormatDescription?
        let status = constPointers.withUnsafeBufferPointer { p in
            sizes.withUnsafeBufferPointer { s in
                CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: nil,
                    parameterSetCount: p.count,
                    parameterSetPointers: p.baseAddress!,
                    parameterSetSizes: s.baseAddress!,
                    nalUnitHeaderLength: 4,
                    extensions: nil,
                    formatDescriptionOut: &format
                )
            }
        }
        guard status == noErr, let format else {
            throw DecoderError.formatCreationFailed(status)
        }
        return format
    }

    private static func splitAVCCParameterSets(_ data: Data) throws -> [Data] {
        var result: [Data] = []
        var offset = 0
        while offset + 4 <= data.count {
            let lengthBytes = data[offset..<(offset + 4)]
            let length = Int(UInt32(bigEndian: lengthBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            offset += 4
            guard offset + length <= data.count else { throw DecoderError.truncatedParameterSet }
            result.append(data.subdata(in: offset..<(offset + length)))
            offset += length
        }
        return result
    }

    enum DecoderError: Error {
        case noParameterSets
        case formatCreationFailed(OSStatus)
        case sessionCreationFailed(OSStatus)
        case truncatedParameterSet
    }
}
