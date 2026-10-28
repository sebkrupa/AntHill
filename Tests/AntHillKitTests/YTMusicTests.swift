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
