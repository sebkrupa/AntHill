import AppKit
import AntHillKit

/// One link in the YT-Music queue.
@Observable
final class DownloadItem: Identifiable {
    enum Status: Equatable {
        case waiting, downloading, paused, done
        case failed(String)
    }

    let id = UUID()
    let url: String
    var title: String?
    var status: Status = .waiting
    var progress: Double = 0
    var file: String?
    /// The stage yt-dlp works on now; on failure, the stage that failed.
    var stage: YTMusic.Stage = .start
    /// yt-dlp output, without the progress lines; the Log button shows it.
    var log: [String] = []
    fileprivate var process: Process?
    fileprivate var lastError: String?

    init(url: String) { self.url = url }

    var name: String { title ?? url }
    var canPause: Bool { status == .waiting || status == .downloading || status == .paused }
}

/// The YT-Music queue: runs yt-dlp for one item at a time, in order.
@Observable
final class MusicQueue {
    static let defaultFolder = NSString(string: "~/Music/Music/Media.localized/Automatically Add to Music.localized").expandingTildeInPath
    static let installHint = "yt-dlp not found. Install: brew install yt-dlp ffmpeg"

    private(set) var items: [DownloadItem] = []
    /// Self-test turns this off so no real download starts.
    var startsDownloads = true
    private let defaults: UserDefaults

    var folder: String {
        didSet { defaults.set(folder, forKey: "music.folder") }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        folder = defaults.string(forKey: "music.folder") ?? Self.defaultFolder
    }

    var hasFinished: Bool { items.contains { $0.status == .done } }

    /// Queues a link. Returns false and adds nothing when the text is not a link.
    @discardableResult
    func add(_ text: String) -> Bool {
        guard YTMusic.isLink(text) else { return false }
        items.append(DownloadItem(url: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        startNext()
        return true
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
    }

    /// Stops every running yt-dlp, for quit.
    func stopAll() { items.forEach(stop) }

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

    private func startNext() {
        guard startsDownloads, !items.contains(where: { $0.status == .downloading }),
              let next = items.first(where: { $0.status == .waiting }) else { return }
        start(next)
    }

    private func start(_ item: DownloadItem) {
        guard let tool = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"].first(where: FileManager.default.isExecutableFile) else {
            item.status = .failed(Self.installHint)
            startNext()
            return
        }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = YTMusic.arguments(url: item.url, folder: folder,
                                              temp: FileManager.default.temporaryDirectory.appending(path: "yt-music").path)
        // Apps start without the login shell PATH; yt-dlp needs ffmpeg from Homebrew.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let lines = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let found = lines.append(handle.availableData)
            guard !found.isEmpty else { return }
            Task { @MainActor in found.forEach { self.handle($0, for: item) } }
        }
        process.terminationHandler = { process in
            let code = process.terminationStatus
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                self.finished(item, code: code)
            }
        }
        item.log.append("$ yt-dlp " + (process.arguments ?? []).joined(separator: " "))
        do {
            try process.run()
            item.process = process
            item.status = .downloading
            item.stage = .info
        } catch {
            item.status = .failed("Could not start yt-dlp: \(error.localizedDescription)")
            startNext()
        }
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
