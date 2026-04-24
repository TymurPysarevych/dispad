import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

final class HEVCEncoder {
    struct EncodedFrame {
        let isKeyframe: Bool
        let pts: UInt64
        let nalus: Data                // AVCC: [u32 length][NALU bytes], repeated
        let parameterSets: Data?       // non-nil on first keyframe & format changes
    }

    var onFrame: ((EncodedFrame) -> Void)?

    private var session: VTCompressionSession?
    private var width: Int32 = 0
    private var height: Int32 = 0

    func configure(width: Int32, height: Int32) throws {
        if session != nil, width == self.width, height == self.height { return }
        invalidate()

        var outSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { refcon, _, status, _, sampleBuffer in
                guard status == noErr, let sampleBuffer, let refcon else { return }
                let encoder = Unmanaged<HEVCEncoder>.fromOpaque(refcon).takeUnretainedValue()
                encoder.handleEncoded(sampleBuffer)
            },
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &outSession
        )

        guard status == noErr, let session = outSession else {
            throw EncoderError.sessionCreationFailed(status)
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: 15_000_000))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: 60))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 1.0))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)

        VTCompressionSessionPrepareToEncodeFrames(session)
        self.session = session
        self.width = width
        self.height = height
    }

    func encode(_ sampleBuffer: CMSampleBuffer) {
        guard let session, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    func invalidate() {
        if let session {
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }

    private func handleEncoded(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let isKeyframe = !notSync

        var parameterSets: Data? = nil
        if isKeyframe {
            parameterSets = Self.extractHEVCParameterSets(from: formatDescription)
        }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == noErr,
              let dataPointer else { return }

        let nalus = Data(bytes: dataPointer, count: totalLength)
        let pts = UInt64(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).value)

        onFrame?(EncodedFrame(isKeyframe: isKeyframe, pts: pts, nalus: nalus, parameterSets: parameterSets))
    }

    private static func extractHEVCParameterSets(from format: CMFormatDescription) -> Data {
        var count = 0
        CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)

        var result = Data()
        for i in 0..<count {
            var ptr: UnsafePointer<UInt8>?
            var size = 0
            if CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: i, parameterSetPointerOut: &ptr, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
               let ptr {
                var length = UInt32(size).bigEndian
                withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
                result.append(ptr, count: size)
            }
        }
        return result
    }

    enum EncoderError: Error { case sessionCreationFailed(OSStatus) }
}
