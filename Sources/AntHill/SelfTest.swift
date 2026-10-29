import AppKit
import AntHillKit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/AntHill-self.store /Applications/AntHill.app/Contents/MacOS/AntHill --selftest
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
            check("Run waits for the model while the chosen model is not on the server", !llama.available)
            llama.models = ["test-model"]
            check("Run is ready when the model is available", llama.available)
            model.library.insertSample(SeedData.tracks)
            model.library.selection = []
            check("all library tasks are checked by default", model.library.tasks == Set(Library.Task.allCases))
            model.library.start(with: llama)
            check("Run asks about all songs in one batch plus each duplicate group", model.library.progress?.total == 2)
            for _ in 0..<50 where model.library.running { try? await Task.sleep(for: .seconds(0.1)) }
            check("an unreachable model stops the run, says so, and changes nothing",
                  !model.library.running && model.library.error != nil && model.library.changes == [] && model.library.notes.isEmpty)
            model.library.changes = nil
            model.library.tasks = [.organizeUnknown]
            model.library.start(with: llama)
            check("Organize Unknown alone asks one batch about the songs without an artist", model.library.progress?.total == 1)
            for _ in 0..<50 where model.library.running { try? await Task.sleep(for: .seconds(0.1)) }
            model.library.changes = nil
            model.library.tasks = Set(Library.Task.allCases)
            model.library.changes = SeedData.changes
            model.library.discard()
            check("a cancelled review logs every change as not applied and marks nothing cleaned",
                  model.library.notes.count == 3 && model.library.notes.values.allSatisfy { !$0.cleaned && $0.log.hasPrefix("Not applied") })
            model.library.notes = [:]
            model.musicPage = .downloads
            llama.status = .unknown
            (llama.address, llama.model) = (oldAddress, oldModel)

            let shops = model.shopChecks
            shops.startsChecks = false
            check("text that is no web address starts no shop check", !shops.check("hello") && shops.running == nil)
            for report in SeedData.shopReports { shops.add(report) }
            let reloaded = ShopChecks(history: Store.shopChecks)
            check("shop check reports survive a restart, newest first",
                  reloaded.reports.prefix(2).map(\.id) == shops.reports.prefix(2).map(\.id) && reloaded.reports.count == shops.reports.count)
            if let first = shops.reports.first {
                shops.remove(first.id)
                check("removing a report takes it out of the saved history",
                      !ShopChecks(history: Store.shopChecks).reports.contains { $0.id == first.id })
            }
            shops.clearHistory()
            check("Clear History removes every saved report", ShopChecks(history: Store.shopChecks).reports.isEmpty)

            let watch = model.network
            let oldName = watch.name
            watch.insertSample(SeedData.connections)
            watch.name = "OLLAMA"
            check("a typed app name shows its connections, ignoring case",
                  watch.connections.count == 4 && watch.apps == ["ControlCenter", "ollama", "ollama runner"])
            check("the watched app is saved", NetworkWatch(defaults: AppModel.defaults).name == "OLLAMA")
            await watch.refresh()
            check("lsof reads this Mac's connections", watch.error == nil && !watch.apps.isEmpty, watch.error ?? "")
            watch.name = oldName

            await filesfer(model.transfers)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// Real rsync, zip, and ditto runs on folders in /tmp.
    private static func filesfer(_ transfers: Transfers) async {
        let manager = FileManager.default
        let root = "/tmp/AntHill-filesfer"
        try? manager.removeItem(atPath: root)
        func write(_ path: String, _ text: String) {
            try? manager.createDirectory(atPath: (root + "/" + path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: URL(fileURLWithPath: root + "/" + path))
        }
        func exists(_ path: String) -> Bool { manager.fileExists(atPath: root + "/" + path) }
        func read(_ path: String) -> String { (try? String(contentsOfFile: root + "/" + path, encoding: .utf8)) ?? "" }
        func run(_ job: Filesfer.Job) async -> Filesfer.Outcome? {
            transfers.commit(job)
            transfers.run(job.id)
            for _ in 0..<100 where transfers.running { try? await Task.sleep(for: .seconds(0.1)) }
            return transfers.job(job.id)?.last
        }
        write("src/a.txt", "one")
        write("src/sub/b.jpg", "photo")
        write("src/.DS_Store", "x")

        var copy = Filesfer.Job()
        copy.from = root + "/src"
        copy.to = root + "/out"
        let first = await run(copy)
        check("Copy takes what is in the folder into WHERE, without .DS_Store",
              first?.error == nil && first?.files == 2 && read("out/a.txt") == "one" && exists("out/sub/b.jpg") && !exists("out/.DS_Store"),
              first?.error ?? "")
        _ = await run(copy)
        check("running again with the same files makes no copies", !exists("out/a 2.txt"))
        write("src/a.txt", "two!")
        _ = await run(copy)
        check("Keep Both copies a changed file as “a 2.txt” and keeps the old one",
              read("out/a 2.txt") == "two!" && read("out/a.txt") == "one")
        copy.conflict = .overwrite
        _ = await run(copy)
        check("Overwrite replaces the file", read("out/a.txt") == "two!" && !exists("out/a 3.txt"))

        var cut = Filesfer.Job()
        cut.from = root + "/src"
        cut.to = root + "/moved"
        cut.operation = .cut
        cut.selection = .extensions
        cut.pattern = "JPG"
        let moved = await run(cut)
        check("Cut with a filter moves only matching files and removes the folders left empty",
              moved?.error == nil && exists("moved/sub/b.jpg") && !exists("src/sub") && exists("src/a.txt"), moved?.error ?? "")

        var zip = Filesfer.Job()
        zip.from = root + "/src"
        zip.to = root + "/zips"
        zip.operation = .zip
        let name = Filesfer.zipName(from: zip.from, isFolder: true, date: .now)
        _ = await run(zip)
        _ = await run(zip)
        check("Zip and Copy makes a dated zip, and a second one as “2”",
              exists("zips/" + name) && exists("zips/" + name.replacingOccurrences(of: ".zip", with: " 2.zip")))

        write("films/one.mov", "1")
        write("films/series/two.mov", "2")
        var empty = Filesfer.Job()
        empty.from = root + "/films"
        empty.to = root + "/drive/films"
        empty.operation = .cut
        let emptied = await run(empty)
        check("Cut of a whole folder moves what is in it and leaves the folder empty",
              emptied?.error == nil && exists("drive/films/one.mov") && exists("drive/films/series/two.mov")
                  && exists("films") && (try? manager.contentsOfDirectory(atPath: root + "/films"))?.isEmpty == true, emptied?.error ?? "")

        let before = manager.fileExists(atPath: root + "/out/a.txt")
        var due = copy
        due.schedule.kind = .daily
        transfers.commit(due)
        if let index = transfers.jobs.firstIndex(where: { $0.id == due.id }) {
            // Pretend the app was closed for three days.
            due.anchor = .now.addingTimeInterval(-3 * 86_400)
            transfers.insertSample(transfers.jobs.enumerated().map { $0.offset == index ? due : $0.element },
                                   previews: transfers.previews, running: nil, waiting: [:])
        }
        transfers.tick()
        let queued = transfers.isBusy(due.id)
        for _ in 0..<100 where transfers.running { try? await Task.sleep(for: .seconds(0.1)) }
        transfers.tick()
        check("missed scheduled runs run once", before && queued && !transfers.isBusy(due.id))

        var away = copy
        away.id = UUID()
        away.to = "/Volumes/AntHill-No-Such-Disk/out"
        away.schedule.kind = .hours
        transfers.commit(away)
        transfers.insertSample(transfers.jobs.map { $0.id == away.id ? { var job = $0; job.anchor = .distantPast; return job }($0) : $0 },
                               previews: transfers.previews, running: nil, waiting: [:])
        transfers.tick()
        check("a scheduled job waits for its drive", transfers.waitingForDisk[away.id] == "AntHill-No-Such-Disk" && !transfers.isBusy(away.id))

        let reopened = Transfers(history: Store.filesfer)
        check("jobs and their last result survive a restart",
              reopened.jobs.map(\.id) == transfers.jobs.map(\.id) && reopened.job(copy.id)?.last?.error == nil && reopened.job(copy.id)?.last != nil)
        for job in transfers.jobs { transfers.remove(job.id) }
        check("deleting a job takes it out of the saved list", Transfers(history: Store.filesfer).jobs.isEmpty)
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
