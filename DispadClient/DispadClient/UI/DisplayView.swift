import SwiftUI
import UIKit
import AVFoundation
import DispadProtocol

struct DisplayView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> UIView {
        let view = DisplayHostView()
        view.displayLayer = displayLayer
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class DisplayHostView: UIView {
    var displayLayer: AVSampleBufferDisplayLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let newLayer = displayLayer {
                newLayer.frame = bounds
                newLayer.videoGravity = .resizeAspect
                layer.addSublayer(newLayer)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer?.frame = bounds
    }
}

@MainActor
final class ClientCoordinator: ObservableObject {
    @Published var state: ClientState = .waitingForHost
    let displayLayer = AVSampleBufferDisplayLayer()

    private let transport = TransportClient()
    private var formatDescription: CMFormatDescription?
    private var frameCounter = ClientFrameCounter()

    init() {
        displayLayer.videoGravity = .resizeAspect
        transport.onMessage = { [weak self] message in
            self?.handle(message)
        }
    }

    func start() { transport.start() }
    func stop()  { transport.stop() }

    private func handle(_ message: Message) {
        switch message {
        case let .config(parameterSets):
            do {
                formatDescription = try HEVCDecoder.makeFormatDescription(from: parameterSets)
                state = .connected
            } catch {
                state = .error("Bad parameter sets: \(error)")
            }

        case let .videoFrame(isKeyframe: _, pts, naluData):
            guard let format = formatDescription else { return }
            guard let sample = makeSampleBuffer(nalus: naluData, pts: pts, format: format) else { return }
            markDisplayImmediately(sample)
            if displayLayer.isReadyForMoreMediaData {
                displayLayer.enqueue(sample)
                frameCounter.tick(accepted: true)
            } else {
                frameCounter.tick(accepted: false)
            }

        case .hello, .heartbeat:
            break
        }
    }

    /// Tags a sample so `AVSampleBufferDisplayLayer` renders it on arrival
    /// rather than comparing its PTS against the layer's internal clock.
    /// Without this, only the first frame renders because subsequent PTS
    /// values look "in the future" relative to the layer's timebase.
    private func markDisplayImmediately(_ sample: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) else { return }
        guard CFArrayGetCount(attachments) > 0 else { return }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dict,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
    }

    private func makeSampleBuffer(nalus: Data, pts: UInt64, format: CMFormatDescription) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: nalus.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: nalus.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let blockBuffer else { return nil }

        let copyStatus = nalus.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) -> OSStatus in
            guard let base = rawBuf.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: rawBuf.count
            )
        }
        guard copyStatus == noErr else { return nil }

        var sample: CMSampleBuffer?
        var size = nalus.count
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMTime(value: CMTimeValue(pts), timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sample
        )
        guard status == noErr else { return nil }
        return sample
    }
}

/// Per-second rate counter for frames received and frames actually enqueued.
/// A gap between "received" and "enqueued" means the display layer is
/// applying back-pressure and we're dropping frames.
final class ClientFrameCounter {
    private var windowStart = CFAbsoluteTimeGetCurrent()
    private var received = 0
    private var enqueued = 0

    func tick(accepted: Bool) {
        received += 1
        if accepted { enqueued += 1 }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - windowStart
        if elapsed >= 1.0 {
            let message = String(format: "DispadClient: %.1f fps received, %.1f fps enqueued",
                                 Double(received) / elapsed,
                                 Double(enqueued) / elapsed)
            Log.stats.info("\(message, privacy: .public)")
            received = 0
            enqueued = 0
            windowStart = now
        }
    }
}
