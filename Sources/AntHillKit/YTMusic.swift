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
    public enum Stage: Int, CaseIterable, Comparable, Sendable {
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

    /// yt-dlp arguments: best audio as m4a, cover and tags, artist and title from
    /// "Artist - Title", no link, description, or channel name in the file.
    /// Downloads into `temp` so Music.app never grabs a half-converted file.
    public static func arguments(url: String, folder: String, temp: String) -> [String] {
        [
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
            "--", url,
        ]
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
