import Foundation
import VideoToolbox
import CoreMedia

final class HEVCEncoder {
    var onEncodedSample: ((CMSampleBuffer) -> Void)?

    private var session: VTCompressionSession?

    func configure(width: Int32, height: Int32) throws {
        // TODO: create VTCompressionSession with kCMVideoCodecType_HEVC,
        // set RealTime = true, AverageBitRate ~15 Mbps, MaxKeyFrameInterval = 60,
        // ProfileLevel_Main_AutoLevel. Attach output callback that forwards to onEncodedSample.
    }

    func encode(_ sampleBuffer: CMSampleBuffer) {
        // TODO: VTCompressionSessionEncodeFrame on sampleBuffer's pixel buffer.
    }

    func invalidate() {
        // TODO: VTCompressionSessionInvalidate and release.
    }
}
