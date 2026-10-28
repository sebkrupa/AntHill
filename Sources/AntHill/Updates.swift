import AppKit
import AntHillKit

/// Looks for a newer GitHub release at launch and once a day, and tells the user.
/// Releases come from .github/workflows/release.yml, which you run by hand.
@Observable
final class Updates {
    /// The running version, from Info.plist. build.sh writes it.
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// The newer release, while there is one. The menu bar menu offers it.
    private(set) var available: Release?
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

    func download() {
        if let available { NSWorkspace.shared.open(available.page) }
    }

    private func announce(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "AntHill \(release.version) is available"
        alert.informativeText = "You have version \(Self.current). Download the new version from GitHub, then replace AntHill in Applications."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { download() }
    }

    private func show(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}
