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

        // We must keep the parameter-set Data alive for the duration of
        // the Create call, since CMVideoFormatDescriptionCreateFromHEVCParameterSets
        // takes raw pointers into the buffers.
        var pointers: [UnsafePointer<UInt8>] = []
        var sizes: [Int] = []
        for data in parsed {
            data.withUnsafeBytes { buf in
                if let base = buf.baseAddress {
                    pointers.append(base.assumingMemoryBound(to: UInt8.self))
                    sizes.append(buf.count)
                }
            }
        }
        guard pointers.count == parsed.count else { throw DecoderError.formatCreationFailed(-1) }

        var format: CMFormatDescription?
        let status = pointers.withUnsafeBufferPointer { p in
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
