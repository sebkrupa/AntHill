import AppKit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/AntHill-self.store ~/Applications/AntHill.app/Contents/MacOS/AntHill --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let queue = model.music
            queue.startsDownloads = false
            let before = queue.items.count

            check("text that is not a link adds nothing", !queue.add("hello") && queue.items.count == before)
            check("empty text adds nothing", !queue.add("  ") && queue.items.count == before)
            check("a link is queued as Waiting", queue.add("https://youtu.be/abc") && queue.items.last?.status == .waiting)
            if let item = queue.items.last {
                queue.togglePause(item)
                check("pausing a waiting item marks it Paused", item.status == .paused)
                queue.togglePause(item)
                check("resuming puts it back to Waiting", item.status == .waiting)
                item.status = .done
                queue.add("https://youtu.be/def")
                let failed = DownloadItem(url: "https://youtu.be/ghi")
                failed.status = .failed("x")
                queue.insertSample(failed)
                queue.clearFinished()
                check("Clear Finished removes only Done items",
                      !queue.items.contains { $0.status == .done } && queue.items.count == before + 2)
                if let last = queue.items.last {
                    queue.remove(last)
                    check("removing an item takes it off the list", !queue.items.contains { $0.id == last.id })
                }
            }
            model.menuBarHidden = []
            check("every module is in the menu bar by default", model.menuBarModules == Module.allCases)
            model.menuBarHidden = [Module.ytMusic.rawValue]
            check("a hidden module leaves the menu bar", !model.menuBarModules.contains(.ytMusic))
            model.menuBarHidden = []

            let old = queue.folder
            queue.folder = "/tmp/AntHill-music"
            check("the download folder is saved",
                  MusicQueue(defaults: AppModel.defaults).folder == "/tmp/AntHill-music")
            queue.folder = old

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
