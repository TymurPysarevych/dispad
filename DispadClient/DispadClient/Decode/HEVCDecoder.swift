import Foundation
import VideoToolbox
import CoreMedia

final class HEVCDecoder {
    var onDecodedSample: ((CMSampleBuffer) -> Void)?

    private var session: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?

    func configure(parameterSets: Data) throws {
        // TODO: parse VPS/SPS/PPS from parameterSets, build CMVideoFormatDescription
        // via CMVideoFormatDescriptionCreateFromHEVCParameterSets, and create
        // a low-latency VTDecompressionSession.
    }

    func decode(naluData: Data, pts: UInt64, isKeyframe: Bool) {
        // TODO: wrap bytes in CMBlockBuffer, build CMSampleBuffer with PTS,
        // call VTDecompressionSessionDecodeFrame with low-latency flag.
    }

    func invalidate() {
        // TODO: VTDecompressionSessionInvalidate and release.
    }
}
