import SwiftUI

struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to dispad").font(.title2).bold()
            Text("dispad streams your Mac's screen to an iPad over USB-C. For a headless Mac mini setup, it needs to launch automatically when you log in.")
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
            HStack {
                Button("Skip") {
                    UserDefaults.standard.set(true, forKey: "com.dispad.host.welcomeSeen")
                    dismiss()
                }
                Spacer()
                Button("Install auto-launch") {
                    do {
                        try LaunchAgentInstaller.install()
                        Log.pipeline.info("LaunchAgent: installed")
                        UserDefaults.standard.set(true, forKey: "com.dispad.host.welcomeSeen")
                        dismiss()
                    } catch {
                        Log.pipeline.error("LaunchAgent install failed: \(error, privacy: .public)")
                        errorMessage = "Install failed: \(error)"
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
