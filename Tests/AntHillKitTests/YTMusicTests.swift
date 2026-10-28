import Testing
@testable import AntHillKit

@Test("Parse yt-dlp lines", arguments: [
    ("sd:title Daft Punk - One More Time", YTMusic.Line.title("Daft Punk - One More Time")),
    ("sd:pct  42.3%", .percent(0.423)),
    ("sd:pct 100%", .percent(1)),
    ("sd:file /Music/One More Time.m4a", .file("/Music/One More Time.m4a")),
    ("ERROR: [youtube] x: Video unavailable", .error("ERROR: [youtube] x: Video unavailable")),
    ("[ExtractAudio] Destination: a.m4a", .stage(.convert)),
    ("[EmbedThumbnail] ffmpeg: Adding thumbnail", .stage(.cover)),
    ("[MetadataParser] Parsed meta_artist", nil),
])
func parses(_ line: String, expected: YTMusic.Line?) {
    #expect(YTMusic.parse(line) == expected)
}

@Test func plainErrors() {
    #expect(YTMusic.plainError("ERROR: [youtube] abc: Video unavailable") == "Video unavailable (youtube, abc)")
    #expect(YTMusic.plainError("ERROR: Postprocessing: audio conversion failed") == "Postprocessing: audio conversion failed")
}

@Test func ignoresOtherLines() {
    #expect(YTMusic.parse("[youtube] Extracting URL") == nil)
    #expect(YTMusic.parse("sd:pct N/A") == nil)
}

@Test func acceptsOnlyLinks() {
    #expect(YTMusic.isLink("https://www.youtube.com/watch?v=abc"))
    #expect(YTMusic.isLink("  https://youtu.be/abc \n"))
    #expect(!YTMusic.isLink(""))
    #expect(!YTMusic.isLink("hello"))
    #expect(!YTMusic.isLink("file:///etc/passwd"))
}

@Test func linkIsLastArgument() {
    let args = YTMusic.arguments(url: "https://youtu.be/abc", folder: "/out", temp: "/tmp/x")
    #expect(args.last == "https://youtu.be/abc")
    #expect(args.contains("home:/out"))
}

@Test func findsPlaylists() {
    #expect(YTMusic.playlistID("https://www.youtube.com/watch?v=abc&list=PL123") == "PL123")
    #expect(YTMusic.playlistID("https://music.youtube.com/playlist?list=OLAK5") == "OLAK5")
    #expect(YTMusic.playlistID("https://www.youtube.com/watch?v=abc") == nil)
    #expect(YTMusic.playlistID("https://www.youtube.com/watch?v=abc&list=") == nil)
}

@Test func parsesPlaylistEntries() {
    #expect(YTMusic.parseEntry("sd:entry fOT0BUpITw8 Peso Pluma - Bellakeo") == .init(id: "fOT0BUpITw8", title: "Peso Pluma - Bellakeo"))
    #expect(YTMusic.parseEntry("sd:entry abc") == .init(id: "abc", title: "abc"))
    #expect(YTMusic.parseEntry("[youtube:tab] Downloading page") == nil)
    #expect(YTMusic.parseEntry("sd:entry ") == nil)
}

@Test func findsIssues() {
    #expect(YTMusic.issue(in: "ERROR: [youtube] x: Sign in to confirm your age. This video may be inappropriate for some users. Use --cookies-from-browser or --cookies for the authentication.") == .signIn)
    #expect(YTMusic.issue(in: "ERROR: [Errno 1] Operation not permitted: '/Users/a/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'") == .cookieAccess)
    #expect(YTMusic.issue(in: "ERROR: [youtube] x: Video unavailable") == nil)
}

@Test func downloadsOneSongWithCookies() {
    let args = YTMusic.arguments(url: "https://youtu.be/abc", folder: "/out", temp: "/tmp/x", browser: .chrome)
    #expect(args.contains("--no-playlist"))
    #expect(args.suffix(4) == ["--cookies-from-browser", "chrome", "--", "https://youtu.be/abc"])
    #expect(!YTMusic.arguments(url: "u", folder: "/o", temp: "/t").contains("--cookies-from-browser"))
}
