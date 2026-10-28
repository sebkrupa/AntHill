import Foundation

/// yt-dlp rules for the YT-Music module, ported from
/// the Scripts repo, SoftwareAndSupplement/Alfred/workflow/yt-download/music.sh and notify.sh.
public enum YTMusic {
    /// One line of yt-dlp output the app cares about.
    public enum Line: Equatable, Sendable {
        case title(String)
        case percent(Double)
        case file(String)
        case error(String)
        /// yt-dlp or ffmpeg started a later stage.
        case stage(Stage)
    }

    /// The stages of one download, in the order yt-dlp runs them.
    public enum Stage: Int, CaseIterable, Comparable, Codable, Sendable {
        case start, info, download, convert, tags, cover, move

        public var title: String {
            switch self {
            case .start: "Start yt-dlp"
            case .info: "Read video info"
            case .download: "Download audio"
            case .convert: "Convert to m4a"
            case .tags: "Write artist and title"
            case .cover: "Add cover art"
            case .move: "Save to the download folder"
            }
        }

        public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    /// yt-dlp's post-processor tags and the stage each one starts.
    static let stages: [(String, Stage)] = [
        ("[ExtractAudio]", .convert),
        ("[Metadata]", .tags),
        ("[EmbedThumbnail]", .cover),
        ("[MoveFiles]", .move),
    ]

    /// "ERROR: [youtube] abc: Video unavailable" -> "Video unavailable. (youtube, abc)"
    public static func plainError(_ line: String) -> String {
        var text = line.hasPrefix("ERROR: ") ? String(line.dropFirst(7)) : line
        // "[extractor] id: message": keep the message, move the source to the end.
        if text.hasPrefix("["), let close = text.firstIndex(of: "]"), let colon = text[close...].range(of: ": ") {
            let source = text[text.index(after: text.startIndex)..<close]
            let id = text[text.index(after: close)..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
            text = String(text[colon.upperBound...]) + " (" + ([String(source), id].filter { !$0.isEmpty }.joined(separator: ", ")) + ")"
        }
        return text
    }

    /// True for an http(s) link with a host. Anything else is not queued.
    public static func isLink(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// The playlist id of a link with `list=`, like watch?v=x&list=PL... or /playlist?list=PL...
    public static func playlistID(_ text: String) -> String? {
        URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?
            .queryItems?.first { $0.name == "list" }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The link that downloads one song of a playlist.
    public static func videoLink(id: String) -> String { "https://www.youtube.com/watch?v=\(id)" }

    /// One song of a playlist: its video id and title.
    public struct Entry: Equatable, Sendable {
        public let id: String
        public let title: String
        public init(id: String, title: String) { self.id = id; self.title = title }
    }

    /// yt-dlp arguments that list a playlist's songs without downloading them.
    public static func playlistArguments(url: String, browser: Browser?) -> [String] {
        ["--flat-playlist", "--yes-playlist", "--print", "sd:entry %(id)s %(title)s"]
            + cookieArguments(browser) + ["--", url]
    }

    /// "sd:entry abc Artist - Title" -> Entry(id: "abc", title: "Artist - Title")
    public static func parseEntry(_ line: String) -> Entry? {
        guard line.hasPrefix("sd:entry ") else { return nil }
        let rest = line.dropFirst(9)
        let id = rest.prefix { $0 != " " }
        guard !id.isEmpty else { return nil }
        let title = rest.dropFirst(id.count).trimmingCharacters(in: .whitespaces)
        return Entry(id: String(id), title: title.isEmpty ? String(id) : title)
    }

    /// Browsers yt-dlp reads cookies from, to download as the signed-in person.
    public enum Browser: String, CaseIterable, Identifiable, Sendable {
        case safari, chrome, firefox, brave, edge, opera, vivaldi, chromium

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .safari: "Safari"
            case .chrome: "Google Chrome"
            case .firefox: "Firefox"
            case .brave: "Brave"
            case .edge: "Microsoft Edge"
            case .opera: "Opera"
            case .vivaldi: "Vivaldi"
            case .chromium: "Chromium"
            }
        }

        public var bundleID: String {
            switch self {
            case .safari: "com.apple.Safari"
            case .chrome: "com.google.Chrome"
            case .firefox: "org.mozilla.firefox"
            case .brave: "com.brave.Browser"
            case .edge: "com.microsoft.edgemac"
            case .opera: "com.operasoftware.Opera"
            case .vivaldi: "com.vivaldi.Vivaldi"
            case .chromium: "org.chromium.Chromium"
            }
        }
    }

    static func cookieArguments(_ browser: Browser?) -> [String] {
        browser.map { ["--cookies-from-browser", $0.rawValue] } ?? []
    }

    /// A problem the person fixes once for every download, not per song.
    public enum Issue: Equatable, Codable, Sendable {
        /// YouTube wants a signed-in person: age-restricted, private, or "confirm you're not a bot".
        case signIn
        /// macOS kept yt-dlp from reading the browser's cookies (Safari needs Full Disk Access).
        case cookieAccess
        case missingTool
    }

    /// The issue behind a yt-dlp error line, if it is one the person can fix once.
    public static func issue(in error: String) -> Issue? {
        let text = error.lowercased()
        if text.contains("cookies") && (text.contains("operation not permitted") || text.contains("permission denied")) {
            return .cookieAccess
        }
        if text.contains("sign in to confirm") || text.contains("--cookies-from-browser")
            || text.contains("private video") || text.contains("members-only") {
            return .signIn
        }
        return nil
    }

    /// yt-dlp arguments: best audio as m4a, cover and tags, artist and title from
    /// "Artist - Title", no link, description, or channel name in the file.
    /// Downloads into `temp` so Music.app never grabs a half-converted file.
    /// One song only: a playlist link goes through `playlistArguments` first.
    public static func arguments(url: String, folder: String, temp: String, browser: Browser? = nil) -> [String] {
        [
            "--no-playlist",
            "--newline", "--progress",
            "--progress-template", "download:sd:pct %(progress._percent_str)s",
            "--print", "before_dl:sd:title %(title)s",
            "--print", "after_move:sd:file %(filepath)s",
            "--extract-audio", "--audio-format", "m4a", "--audio-quality", "0",
            "--embed-thumbnail", "--embed-metadata",
            "--parse-metadata", "%(title)s:(?P<meta_artist>.+?) - (?P<meta_title>.+)",
            "--parse-metadata", "%(artist,meta_artist|)s:(?P<meta_artist>.*)",
            "--parse-metadata", "%(track,meta_title,title)s:(?P<meta_title>.*)",
            "--parse-metadata", "%(meta_purl|)s:(?P<meta_purl>.*)",
            "--parse-metadata", "%(meta_comment|)s:(?P<meta_comment>.*)",
            "--parse-metadata", "%(meta_description|)s:(?P<meta_description>.*)",
            "--parse-metadata", "%(meta_synopsis|)s:(?P<meta_synopsis>.*)",
            "--paths", "home:\(folder)", "--paths", "temp:\(temp)",
            "--output", "%(title)s.%(ext)s",
        ] + cookieArguments(browser) + ["--", url]
    }

    public static func parse(_ line: String) -> Line? {
        if line.hasPrefix("sd:title ") { return .title(String(line.dropFirst(9))) }
        if line.hasPrefix("sd:file ") { return .file(String(line.dropFirst(8))) }
        if line.hasPrefix("sd:pct ") {
            let digits = line.dropFirst(7).filter { $0.isNumber || $0 == "." }
            return Double(digits).map { .percent(min($0, 100) / 100) }
        }
        if line.hasPrefix("ERROR:") { return .error(line) }
        if let stage = stages.first(where: { line.hasPrefix($0.0) }) { return .stage(stage.1) }
        return nil
    }
}
