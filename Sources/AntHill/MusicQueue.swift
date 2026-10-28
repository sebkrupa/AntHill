import AppKit
import AntHillKit

/// One link in the YT-Music queue.
@Observable
final class DownloadItem: Identifiable {
    enum Status: Equatable, Codable {
        case waiting, downloading, paused, done
        case failed(String)
    }

    let id = UUID()
    let url: String
    var title: String?
    var status: Status = .waiting
    var progress: Double = 0
    var file: String?
    /// A problem behind the failure that the person fixes once (the toolbar's fix button).
    var issue: YTMusic.Issue?
    /// The stage yt-dlp works on now; on failure, the stage that failed.
    var stage: YTMusic.Stage = .start
    /// yt-dlp output, without the progress lines; the Log button shows it.
    var log: [String] = []
    fileprivate var process: Process?
    fileprivate var lastError: String?

    init(url: String) { self.url = url }

    var name: String { title ?? url }
    var canPause: Bool { status == .waiting || status == .downloading || status == .paused }
    var failed: Bool { if case .failed = status { true } else { false } }
}

/// The songs of a pasted playlist link; the person picks which ones to download.
@Observable
final class PlaylistPick: Identifiable {
    let id = UUID()
    let url: String
    var entries: [YTMusic.Entry] = []
    /// Video ids of the songs to download.
    var chosen: Set<String> = []
    var loading = true
    var error: String?
    var issue: YTMusic.Issue?
    fileprivate var process: Process?
    fileprivate var lastError: String?

    init(url: String) { self.url = url }
}

/// The YT-Music queue: runs yt-dlp for one item at a time, in order.
@Observable
final class MusicQueue {
    static let defaultFolder = NSString(string: "~/Music/Music/Media.localized/Automatically Add to Music.localized").expandingTildeInPath
    nonisolated static let installHint = "yt-dlp not found. Install: brew install yt-dlp ffmpeg"

    private(set) var items: [DownloadItem] = []
    /// The playlist sheet; set while the person picks songs.
    var playlist: PlaylistPick?
    /// Shows the fix popover beside the page title.
    var showsFix = false
    private(set) var installing = false
    /// Self-test turns this off so no real download starts.
    var startsDownloads = true
    private let defaults: UserDefaults
    /// Where the history is saved; nil keeps it in memory only.
    private let history: URL?

    var folder: String {
        didSet { defaults.set(folder, forKey: "music.folder") }
    }

    init(defaults: UserDefaults, history: URL? = nil) {
        self.defaults = defaults
        self.history = history
        folder = defaults.string(forKey: "music.folder") ?? Self.defaultFolder
        browser = defaults.string(forKey: "music.browser").flatMap(YTMusic.Browser.init)
        if let history, let data = try? Data(contentsOf: history),
           let saved = try? JSONDecoder().decode([Saved].self, from: data) {
            items = saved.map(\.item)
        }
        // Test runs never start yt-dlp on their own.
        if !Store.isOverridden { startNext() }
    }

    /// One history entry on disk.
    private struct Saved: Codable {
        var url: String
        var title: String?
        var status: DownloadItem.Status
        var progress: Double
        var file: String?
        var issue: YTMusic.Issue?
        var stage: YTMusic.Stage
        var log: [String]

        init(_ item: DownloadItem) {
            url = item.url; title = item.title; status = item.status; progress = item.progress
            file = item.file; issue = item.issue; stage = item.stage; log = item.log
        }

        var item: DownloadItem {
            let item = DownloadItem(url: url)
            item.title = title
            // A download cut off by quit continues; yt-dlp picks up its partial file.
            item.status = status == .downloading ? .waiting : status
            item.progress = progress
            item.file = file
            item.issue = issue
            item.stage = stage
            item.log = log
            return item
        }
    }

    /// Writes the history. Called after every change to the list and on quit.
    func save() {
        guard let history else { return }
        do {
            try FileManager.default.createDirectory(at: history.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items.map(Saved.init)).write(to: history, options: .atomic)
        } catch {
            print("AntHill: could not save the history: \(error.localizedDescription)")
        }
    }

    /// The browser whose YouTube sign-in yt-dlp borrows; nil downloads signed out.
    var browser: YTMusic.Browser? {
        didSet { defaults.set(browser?.rawValue, forKey: "music.browser") }
    }

    var hasFinished: Bool { items.contains { $0.status == .done } }
    var hasFailed: Bool { items.contains(where: \.failed) }

    /// The first problem the person can fix once, from failed songs or the playlist sheet.
    var issue: YTMusic.Issue? {
        playlist?.issue ?? items.first { $0.failed && $0.issue != nil }?.issue
    }

    /// Browsers on this Mac that yt-dlp can read, the default browser first.
    var installedBrowsers: [YTMusic.Browser] {
        let workspace = NSWorkspace.shared
        let defaultID = workspace.urlForApplication(toOpen: URL(string: "https://youtube.com")!)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        return YTMusic.Browser.allCases
            .filter { workspace.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
            .sorted { a, _ in a.bundleID == defaultID }
    }

    /// Queues a link. A playlist link opens the playlist sheet instead.
    /// Returns false and adds nothing when the text is not a link.
    @discardableResult
    func add(_ text: String) -> Bool {
        guard YTMusic.isLink(text) else { return false }
        let url = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if YTMusic.playlistID(url) != nil {
            loadPlaylist(PlaylistPick(url: url))
        } else {
            items.append(DownloadItem(url: url))
            startNext()
        }
        return true
    }

    /// Queues the chosen songs of the playlist sheet, in playlist order, and closes it.
    func downloadPlaylist() {
        guard let pick = playlist else { return }
        for entry in pick.entries where pick.chosen.contains(entry.id) {
            let item = DownloadItem(url: YTMusic.videoLink(id: entry.id))
            item.title = entry.title
            items.append(item)
        }
        closePlaylist()
        startNext()
    }

    func closePlaylist() {
        playlist?.process?.terminate()
        playlist = nil
    }

    /// Puts failed songs back in the queue; with an issue, only the songs it stopped.
    func retryFailed(_ issue: YTMusic.Issue? = nil) {
        for item in items where item.failed && (issue == nil || item.issue == issue) { retry(item) }
        if let pick = playlist, pick.issue != nil, issue == nil || pick.issue == issue { loadPlaylist(PlaylistPick(url: pick.url)) }
    }

    func retry(_ item: DownloadItem) {
        guard item.failed else { return }
        item.status = .waiting
        item.issue = nil
        item.lastError = nil
        item.progress = 0
        item.stage = .start
        startNext()
    }

    /// Sign-in fix: borrow the browser's YouTube cookies, then retry what sign-in stopped.
    func useBrowser(_ browser: YTMusic.Browser) {
        self.browser = browser
        showsFix = false
        retryFailed(.signIn)
        retryFailed(.cookieAccess)
    }

    /// Opens System Settings at Full Disk Access, which Safari's cookies need.
    func openFullDiskAccess() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    /// Missing-tool fix: brew install yt-dlp ffmpeg, then retry. Without Homebrew, opens brew.sh.
    func installTools() {
        guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: FileManager.default.isExecutableFile) else {
            NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["install", "yt-dlp", "ffmpeg"]
        process.environment = Self.environment
        process.terminationHandler = { _ in
            Task { @MainActor in
                self.installing = false
                self.showsFix = false
                self.retryFailed(.missingTool)
            }
        }
        do {
            try process.run()
            installing = true
        } catch {
            NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
        }
    }

    /// Menu bar quick action: queues the link on the clipboard without showing the window.
    /// Beeps when the clipboard holds no link.
    func addFromClipboard() {
        if !add(NSPasteboard.general.string(forType: .string) ?? "") { NSSound.beep() }
    }

    /// Items added by seed data for snapshots: no process behind them.
    func insertSample(_ item: DownloadItem) { items.append(item) }

    func togglePause(_ item: DownloadItem) {
        switch item.status {
        case .downloading:
            // shortcut: SIGSTOP stops yt-dlp, not an ffmpeg child mid-conversion; fine for the download phase.
            item.process?.suspend()
            item.status = .paused
            startNext()
        case .waiting:
            item.status = .paused
        case .paused:
            if let process = item.process {
                process.resume()
                item.status = .downloading
            } else {
                item.status = .waiting
                startNext()
            }
        default: break
        }
    }

    func remove(_ item: DownloadItem) {
        items.removeAll { $0.id == item.id }
        stop(item)
        startNext()
    }

    func clearFinished() {
        items.removeAll { $0.status == .done }
        save()
    }

    /// Stops every running yt-dlp and saves the history, for quit.
    func stopAll() {
        save()
        items.forEach(stop)
    }

    /// Finder with the file selected; the folder when the file is gone (Music.app moves it).
    func reveal(_ item: DownloadItem) {
        if let file = item.file, FileManager.default.fileExists(atPath: file) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: folder, isDirectory: true))
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true)
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }

    private func stop(_ item: DownloadItem) {
        guard let process = item.process, process.isRunning else { return }
        item.process = nil
        // A stopped process holds SIGTERM until it runs again.
        process.resume()
        process.terminate()
    }

    /// Every change to the list ends here, so this is where the history is saved.
    private func startNext() {
        save()
        guard startsDownloads, !items.contains(where: { $0.status == .downloading }),
              let next = items.first(where: { $0.status == .waiting }) else { return }
        start(next)
    }

    private func loadPlaylist(_ pick: PlaylistPick) {
        closePlaylist()
        playlist = pick
        guard startsDownloads else { return }
        do {
            pick.process = try Self.launch(YTMusic.playlistArguments(url: pick.url, browser: browser)) { line in
                if let entry = YTMusic.parseEntry(line) {
                    pick.entries.append(entry)
                    pick.chosen.insert(entry.id)
                } else if case .error(let message) = YTMusic.parse(line) {
                    pick.lastError = message
                }
            } exited: { code in
                pick.loading = false
                pick.process = nil
                guard code != 0 || pick.entries.isEmpty else { return }
                pick.error = pick.lastError.map(YTMusic.plainError) ?? "yt-dlp found no songs (code \(code))."
                pick.issue = pick.lastError.flatMap(YTMusic.issue(in:))
            }
        } catch {
            pick.loading = false
            pick.error = error.localizedDescription
            pick.issue = (error as? LaunchError) == .missingTool ? .missingTool : nil
        }
    }

    private func start(_ item: DownloadItem) {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let arguments = YTMusic.arguments(url: item.url, folder: folder,
                                          temp: FileManager.default.temporaryDirectory.appending(path: "yt-music").path,
                                          browser: browser)
        item.log.append("$ yt-dlp " + arguments.joined(separator: " "))
        do {
            item.process = try Self.launch(arguments) { self.handle($0, for: item) } exited: { self.finished(item, code: $0) }
            item.status = .downloading
            item.stage = .info
        } catch {
            item.status = .failed(error.localizedDescription)
            item.issue = (error as? LaunchError) == .missingTool ? .missingTool : nil
            startNext()
        }
    }

    private enum LaunchError: LocalizedError {
        case missingTool

        var errorDescription: String? { MusicQueue.installHint }
    }

    /// Apps start without the login shell PATH; yt-dlp needs ffmpeg from Homebrew.
    private static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }

    /// Runs yt-dlp and hands each output line, then the exit code, to the main thread.
    private static func launch(_ arguments: [String], line: @escaping @MainActor (String) -> Void,
                               exited: @escaping @MainActor (Int32) -> Void) throws -> Process {
        guard let tool = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"].first(where: FileManager.default.isExecutableFile) else {
            throw LaunchError.missingTool
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let lines = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let found = lines.append(handle.availableData)
            guard !found.isEmpty else { return }
            Task { @MainActor in found.forEach(line) }
        }
        process.terminationHandler = { process in
            let code = process.terminationStatus
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                exited(code)
            }
        }
        try process.run()
        return process
    }

    private func handle(_ line: String, for item: DownloadItem) {
        let parsed = YTMusic.parse(line)
        if case .percent = parsed {} else {
            item.log.append(line)
            // shortcut: keeps the last 2000 lines; enough for one song, raise it if long logs get cut.
            if item.log.count > 2000 { item.log.removeFirst(item.log.count - 2000) }
        }
        switch parsed {
        case .title(let title):
            item.title = title
            item.stage = max(item.stage, .download)
        case .percent(let value): item.progress = value
        case .file(let path):
            item.file = path
            item.stage = max(item.stage, .move)
        case .error(let message): item.lastError = message
        case .stage(let stage): item.stage = max(item.stage, stage)
        case nil: break
        }
    }

    private func finished(_ item: DownloadItem, code: Int32) {
        // Removed items had their process cleared on purpose.
        guard item.process != nil else { return }
        item.process = nil
        item.log.append(code == 0 ? "Finished." : "yt-dlp stopped with code \(code).")
        if code == 0 {
            item.status = .done
            item.progress = 1
        } else {
            item.status = .failed(item.lastError.map(YTMusic.plainError) ?? "yt-dlp stopped with code \(code)")
            item.issue = item.lastError.flatMap(YTMusic.issue(in:))
        }
        startNext()
    }
}

/// Splits pipe data into lines; called from the pipe's background queue.
private nonisolated final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.withLock {
            pending.append(data)
            var lines: [String] = []
            while let end = pending.firstIndex(of: 0x0A) {
                lines.append(String(decoding: pending[..<end], as: UTF8.self))
                pending.removeSubrange(...end)
            }
            return lines
        }
    }
}
