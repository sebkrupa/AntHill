import AppKit
import AntHillKit

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
            queue.add("https://www.youtube.com/watch?v=abc&list=PL123")
            check("a playlist link opens the playlist sheet and queues nothing",
                  queue.playlist?.url.hasSuffix("list=PL123") == true && queue.items.count == before + 1)
            if let pick = queue.playlist {
                pick.entries = [.init(id: "a1", title: "One"), .init(id: "b2", title: "Two"), .init(id: "c3", title: "Three")]
                pick.chosen = ["a1", "c3"]
                pick.loading = false
                let count = queue.items.count
                queue.downloadPlaylist()
                check("Download queues only the checked songs, in playlist order",
                      queue.items.suffix(2).map(\.url) == [YTMusic.videoLink(id: "a1"), YTMusic.videoLink(id: "c3")]
                          && queue.items.count == count + 2 && queue.playlist == nil)
            }
            let blocked = DownloadItem(url: "https://youtu.be/age")
            blocked.status = .failed("Sign in to confirm your age.")
            blocked.issue = .signIn
            queue.insertSample(blocked)
            check("a sign-in failure shows the fix button", queue.issue == .signIn)
            let oldBrowser = queue.browser
            queue.useBrowser(.firefox)
            check("choosing a browser saves it and retries the song",
                  MusicQueue(defaults: AppModel.defaults).browser == .firefox && blocked.status == .waiting && queue.issue == nil)
            queue.browser = oldBrowser
            queue.remove(blocked)

            let broken = DownloadItem(url: "https://youtu.be/broken")
            broken.status = .failed("Video unavailable")
            broken.log = ["$ yt-dlp https://youtu.be/broken", "ERROR: Video unavailable"]
            queue.insertSample(broken)
            queue.save()
            let reopened = MusicQueue(defaults: AppModel.defaults, history: Store.history)
            let back = reopened.items.first { $0.url == broken.url }
            check("the history and its logs survive a restart, failed songs ready to retry",
                  reopened.items.map(\.url) == queue.items.map(\.url) && back?.failed == true && back?.log == broken.log)
            queue.remove(broken)
            check("removing an item takes it out of the saved history",
                  !MusicQueue(defaults: AppModel.defaults, history: Store.history).items.contains { $0.url == broken.url })

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

            let llama = model.llama
            let (oldAddress, oldModel) = (llama.address, llama.model)
            llama.address = "http://127.0.0.1:9"
            llama.model = "test-model"
            let saved = LlamaConnection(defaults: AppModel.defaults)
            check("the llama.cpp address and model are saved", saved.address == "http://127.0.0.1:9" && saved.model == "test-model")
            model.musicPage = .library
            llama.status = .connected
            llama.models = ["other-model"]
            check("the Library tab hides while the chosen model is not on the server", model.shownMusicPage == .downloads)
            llama.models = ["test-model"]
            check("the Library tab shows when the model is available", model.shownMusicPage == .library)
            model.library.insertSample(SeedData.tracks)
            model.library.task = .organizeUnknown
            model.library.selection = []
            model.library.start(with: llama)
            check("Run asks about every song the task applies to", model.library.progress?.total == 2)
            for _ in 0..<50 where model.library.running { try? await Task.sleep(for: .seconds(0.1)) }
            check("an unreachable model stops the run, says so, and changes nothing",
                  !model.library.running && model.library.error != nil && model.library.changes == [])
            model.library.changes = nil
            model.musicPage = .downloads
            llama.status = .unknown
            (llama.address, llama.model) = (oldAddress, oldModel)

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
