import Foundation

enum LaunchAgentInstaller {
    static let label = "com.dispad.host"

    enum InstallError: Error {
        case missingBundledPlist
        case writeFailed(Error)
        case launchctlFailed(Int32, String)
    }

    static var installedPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedPlistURL.path)
    }

    /// Copies the bundled plist into `~/Library/LaunchAgents/`, rewriting
    /// the ProgramArguments so the LaunchAgent points at THIS running
    /// app bundle rather than the hardcoded `/Applications/DispadHost.app`
    /// in the template. Then runs `launchctl bootstrap gui/<uid> <plist>`
    /// so it's active immediately.
    static func install() throws {
        guard let bundledURL = Bundle.main.url(forResource: "com.dispad.host", withExtension: "plist") else {
            throw InstallError.missingBundledPlist
        }

        let data = try Data(contentsOf: bundledURL)
        guard var plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any] else {
            throw InstallError.missingBundledPlist
        }

        // Rewrite ProgramArguments to the currently running executable path
        // so a DMG installed to a non-default path still works.
        if let exec = Bundle.main.executableURL {
            plist["ProgramArguments"] = [exec.path]
        }

        let destURL = installedPlistURL
        try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            let out = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try out.write(to: destURL, options: .atomic)
        } catch {
            throw InstallError.writeFailed(error)
        }

        // Bootout any prior instance first so this is idempotent across
        // upgrades that change the plist contents (e.g., KeepAlive
        // semantics). bootout fails harmlessly if nothing is loaded.
        try? runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        try runLaunchctl(["bootstrap", "gui/\(getuid())", destURL.path])
    }

    /// Stops the agent and removes its plist.
    static func uninstall() throws {
        let destURL = installedPlistURL
        if isInstalled {
            // bootout may fail if the agent isn't currently loaded; that's
            // fine for uninstall purposes — still want to remove the file.
            try? runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
            try FileManager.default.removeItem(at: destURL)
        }
    }

    private static func runLaunchctl(_ args: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw InstallError.launchctlFailed(task.terminationStatus, out)
        }
    }
}
