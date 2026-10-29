import AppKit
import AntHillKit

/// Network Lock: blocks all network traffic on this Mac except for the chosen apps.
/// The bundled netlock script does the blocking as root; it keeps running after AntHill quits.
@Observable
final class NetworkLock {
    /// The apps that keep the network while the lock is on, as .app paths.
    var apps: [String] {
        didSet { defaults.set(apps, forKey: "netlock.apps") }
    }
    /// The apps the running lock lets through. Differs from `apps` after an edit until Apply Changes.
    private(set) var lockedApps: [String] {
        didSet { defaults.set(lockedApps, forKey: "netlock.lockedApps") }
    }
    private(set) var isOn = false
    /// Waiting on the administrator prompt or on netlock.
    private(set) var busy = false
    var error: String?
    private let defaults: UserDefaults

    static let script = Bundle.main.url(forResource: "netlock", withExtension: nil)?.path
    static let log = URL.applicationSupportDirectory.appending(path: "AntHill/netlock.log")

    init(defaults: UserDefaults) {
        self.defaults = defaults
        apps = defaults.stringArray(forKey: "netlock.apps") ?? []
        lockedApps = defaults.stringArray(forKey: "netlock.lockedApps") ?? []
        refresh()
    }

    var hasChanges: Bool { isOn && apps != lockedApps }

    var status: String {
        guard isOn else { return "Network open" }
        let count = lockedApps.count
        return count == 0 ? "Locked: every app blocked" : "Locked: \(count) \(count == 1 ? "app has" : "apps have") network"
    }

    /// Reads whether netlock runs. pgrep sees root processes without a prompt. Test runs keep their sample state.
    func refresh() {
        guard !Store.isOverridden, let script = Self.script else { return }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pgrep")
        process.arguments = ["-f", NetLock.pattern(script: script)]
        process.standardOutput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
        isOn = process.terminationStatus == 0
    }

    /// Starts the lock, or restarts it with the edited app list.
    func lock() {
        run { script in
            try? FileManager.default.createDirectory(at: Self.log.deletingLastPathComponent(), withIntermediateDirectories: true)
            return NetLock.startCommand(script: script, apps: self.apps, log: Self.log.path)
        } then: {
            // netlock stops within a moment when it can't start, like for an app that is gone.
            try? await Task.sleep(for: .seconds(1))
            self.refresh()
            if self.isOn {
                self.lockedApps = self.apps
            } else {
                let log = (try? String(contentsOf: Self.log, encoding: .utf8)) ?? ""
                self.error = log.split(separator: "\n").last { $0.hasPrefix("netlock:") }.map(String.init) ?? "netlock stopped right after it started."
            }
        }
    }

    func unlock() { run { NetLock.stopCommand(script: $0) } then: { self.refresh() } }

    /// For a lock that crashed and left its rules in pf.
    func restore() { run { NetLock.restoreCommand(script: $0) } then: { self.refresh() } }

    func toggle() { isOn ? unlock() : lock() }

    func add(_ urls: [URL]) {
        for path in urls.map(\.path) where NetLock.canAllow(path) && !apps.contains(path) { apps.append(path) }
        let skipped = urls.filter { !NetLock.canAllow($0.path) }
        error = skipped.isEmpty ? nil : "Can’t allow \(skipped.map(\.lastPathComponent).joined(separator: ", ")): pick an app whose name has no comma."
    }

    func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Allow"
        panel.message = "Choose the apps that keep the network while the lock is on."
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func remove(_ paths: Set<String>) { apps.removeAll { paths.contains($0) } }

    func insertSample(apps: [String], locked: Bool) {
        self.apps = apps
        lockedApps = locked ? apps : []
        isOn = locked
    }

    /// Runs a root command after the administrator prompt. Cancelling the prompt is no error.
    private func run(_ command: @escaping (String) -> String, then: @escaping () async -> Void) {
        guard !busy, !Store.isOverridden else { return }
        guard let script = Self.script else {
            error = "The netlock script is missing from AntHill.app. Install AntHill with build.sh."
            return
        }
        busy = true
        error = nil
        let source = NetLock.appleScript(command(script))
        Task {
            let (status, output) = await Self.osascript(source)
            if status != 0 && !output.contains("(-128)") { error = output.trimmingCharacters(in: .whitespacesAndNewlines) }
            await then()
            busy = false
        }
    }

    private nonisolated static func osascript(_ source: String) async -> (Int32, String) {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let pipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = pipe
            do { try process.run() } catch { return (1, error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
