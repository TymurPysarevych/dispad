import Foundation
import ScreenCaptureKit
import CoreMedia

final class CaptureEngine: NSObject, SCStreamOutput {
    var onSample: ((CMSampleBuffer) -> Void)?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "dispad.capture", qos: .userInteractive)

    func start() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // Capture at point-resolution (1x). The iPad scales to fit anyway, and
        // cutting pixel count 4x relative to Retina (2x) dramatically reduces
        // encoder load and lets the pipeline hit frame-rate targets.
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.queueDepth = 6
        config.showsCursor = true
        Log.capture.info("CaptureEngine: starting at \(config.width, privacy: .public)x\(config.height, privacy: .public) @ up to 60fps")

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let statusRawValue = info[.status] as? Int,
              SCFrameStatus(rawValue: statusRawValue) == .complete else { return }
        onSample?(sampleBuffer)
    }

    enum CaptureError: Error { case noDisplay }
}
