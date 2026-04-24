import Foundation
import ScreenCaptureKit
import CoreMedia

final class CaptureEngine: NSObject {
    var onSample: ((CMSampleBuffer) -> Void)?

    private var stream: SCStream?

    func start() async throws {
        // TODO: build SCContentFilter for the main display, configure SCStreamConfiguration
        // for 60fps BGRA/420v capture, attach self as SCStreamOutput, and start.
    }

    func stop() async {
        // TODO: stopCapture and release stream.
    }
}

extension CaptureEngine: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        onSample?(sampleBuffer)
    }
}
