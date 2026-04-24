import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = ClientCoordinator()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            DisplayView(displayLayer: coordinator.displayLayer)
                .ignoresSafeArea()

            overlay
        }
        .onAppear { coordinator.start() }
        .onDisappear { coordinator.stop() }
    }

    @ViewBuilder private var overlay: some View {
        switch coordinator.state {
        case .waitingForHost:
            statusText("Waiting for Mac…")
        case .connected:
            EmptyView()
        case .disconnected:
            statusText("Disconnected. Retrying…")
        case let .error(message):
            statusText(message)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.title)
            .foregroundStyle(.white.opacity(0.8))
            .padding()
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum ClientState {
    case waitingForHost
    case connected
    case disconnected
    case error(String)
}
