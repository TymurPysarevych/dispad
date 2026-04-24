import Foundation

enum LaunchAgentInstaller {
    static let label = "com.dispad.host"

    static var installedPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedPlistURL.path)
    }

    static func install() throws {
        // TODO: copy the bundled plist template to ~/Library/LaunchAgents/,
        // substituting the app's actual path, then launchctl load it.
    }

    static func uninstall() throws {
        // TODO: launchctl unload and remove the plist.
    }
}
