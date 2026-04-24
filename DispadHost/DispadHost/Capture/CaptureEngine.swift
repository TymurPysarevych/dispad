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

        // Cap capture output at 1920x1080. On a headless Mac mini the
        // fallback display is 4K, and HEVC at 4K@60 saturates the hardware
        // encoder even though bandwidth has plenty of headroom. The iPad
        // scales to fit anyway, so extra pixels are invisible to the user.
        let maxWidth = 1920
        let maxHeight = 1080
        let scale = min(
            Double(maxWidth) / Double(display.width),
            Double(maxHeight) / Double(display.height),
            1.0
        )
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)

        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.queueDepth = 6
        config.showsCursor = true
        print("CaptureEngine: source \(display.width)x\(display.height), capturing at \(config.width)x\(config.height) @ up to 60fps")

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
