import AppKit
import AntHillKit

/// Looks for a newer GitHub release at launch and once a day, tells the user, and installs it.
/// Releases come from .github/workflows/release.yml, which you run by hand.
/// shortcut: trusts any release on the repo (HTTPS plus codesign --verify, no update signature); add Sparkle EdDSA if others use the app.
@Observable
final class Updates {
    /// The running version, from Info.plist. build.sh writes it.
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// The newer release, while there is one. The menu bar menu offers it.
    private(set) var available: Release?
    /// True from the download until AntHill quits for the new version.
    private(set) var installing = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func checkDaily() {
        Task {
            while true {
                await check(userAsked: false)
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    /// A check the user asked for always answers. A daily check speaks once per new version.
    func check(userAsked: Bool) async {
        do {
            let (data, response) = try await URLSession.shared.data(from: Release.latestURL)
            // 404: nothing published yet.
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                available = nil
            } else {
                let release = try JSONDecoder().decode(Release.self, from: data)
                available = Release.isNewer(release.version, than: Self.current) ? release : nil
            }
        } catch {
            if userAsked { show("Can’t check for updates", "GitHub did not answer. Try again later.") }
            return
        }
        if let available, userAsked || defaults.string(forKey: "updates.announced") != available.version {
            defaults.set(available.version, forKey: "updates.announced")
            announce(available)
        } else if userAsked {
            show("AntHill is up to date", "You have version \(Self.current), the newest one.")
        }
    }

    func openPage() {
        if let available { NSWorkspace.shared.open(available.page) }
    }

    /// Downloads the new version, checks it, and swaps it in for this copy as AntHill quits and reopens.
    /// A release without a zip opens its page instead.
    func install() {
        guard let available, !installing else { return }
        guard let zip = available.zip else { return openPage() }
        installing = true
        Task {
            do {
                let app = Bundle.main.bundleURL
                let (file, _) = try await URLSession.shared.download(from: zip)
                // Next to the app, so the swap is a rename on the same disk.
                let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
                try await Self.run("/usr/bin/ditto", "-x", "-k", file.path, folder.path)
                let new = folder.appending(path: "AntHill.app")
                try await Self.run("/usr/bin/codesign", "--verify", "--strict", new.path)
                guard Bundle(url: new)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == available.version else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try Self.relaunch(replacing: app, with: new)
            } catch {
                installing = false
                let alert = NSAlert()
                alert.messageText = "Can’t install AntHill \(available.version)"
                alert.informativeText = "The download failed or did not check out. Download it from GitHub instead."
                alert.addButton(withTitle: "Open GitHub")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate()
                if alert.runModal() == .alertFirstButtonReturn { openPage() }
            }
        }
    }

    /// Starts a script that waits for AntHill to quit, puts the new copy in place, and opens it. Then quits.
    private static func relaunch(replacing app: URL, with new: URL) throws {
        let script = """
            while kill -0 $1 2>/dev/null; do sleep 0.2; done
            if mv "$2" "$2.old"; then
              if mv "$3" "$2"; then rm -rf "$2.old"; else mv "$2.old" "$2"; fi
            fi
            rm -rf "${3:h}"
            open "$2"
            """
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-c", script, "anthill-update", "\(getpid())", app.path, new.path]
        try process.run()
        NSApp.terminate(nil)
    }

    private nonisolated static func run(_ tool: String, _ arguments: String...) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: tool)
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 { throw CocoaError(.fileReadCorruptFile) }
        }.value
    }

    private func announce(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "AntHill \(release.version) is available"
        alert.informativeText = "You have version \(Self.current). AntHill downloads the new version, quits, and opens again."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { install() }
    }

    private func show(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}
