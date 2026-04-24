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

    private let decoder = HEVCDecoder()
    private let transport = TransportClient()

    init() {
        displayLayer.videoGravity = .resizeAspect
        transport.onMessage = { [weak self] message in
            self?.handle(message)
        }
    }

    func start() {
        transport.start()
    }

    func stop() {
        transport.stop()
    }

    private func handle(_ message: Message) {
        print("DispadClient received: \(message)")
    }
}
