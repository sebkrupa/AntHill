import Foundation
import Testing
@testable import AntHillKit

@Test("Server address to API base", arguments: [
    ("http://127.0.0.1:8080", "http://127.0.0.1:8080/v1"),
    ("127.0.0.1:8080/", "http://127.0.0.1:8080/v1"),
    ("http://mac.local:8080/v1/", "http://mac.local:8080/v1"),
])
func llamaBase(_ address: String, _ base: String) {
    #expect(Llama.base(address)?.absoluteString == base)
}

@Test func llamaRejectsEmptyAddress() {
    #expect(Llama.base("  ") == nil)
}

@Test func llamaDecodesModelsAndReply() throws {
    #expect(try Llama.models(from: Data(#"{"object":"list","data":[{"id":"qwen3-8b"},{"id":"gemma-3"}]}"#.utf8)) == ["qwen3-8b", "gemma-3"])
    #expect(try Llama.reply(from: Data(#"{"choices":[{"message":{"role":"assistant","content":"{\"a\":1}"}}]}"#.utf8)) == #"{"a":1}"#)
}

private let daft = Library.Track(id: "A", name: "One More Time", artist: "Daft Punk", album: "Discovery", duration: 320)
private let daftVideo = Library.Track(id: "B", name: "Daft Punk - One More Time (Official Video)", artist: "", album: "", duration: 322)
private let other = Library.Track(id: "C", name: "Dreams", artist: "Fleetwood Mac", album: "Rumours", duration: 257)

@Test func groupsPossibleDuplicates() {
    #expect(Library.duplicateCandidates([daft, daftVideo, other]) == [[daft, daftVideo]])
}

@Test func duplicateAnswerTrashesOnlyListedTracks() throws {
    let question = try #require(Library.questions(.removeDuplicates, for: [daft, daftVideo, other]).first)
    #expect(Library.changes(question: question, reply: #"{"remove": ["B"]}"#)
        == [.init(track: daftVideo, kind: .trash(keeping: daft))])
    #expect(Library.changes(question: question, reply: #"{"remove": ["A", "B"]}"#).isEmpty)
    #expect(Library.changes(question: question, reply: "no idea").isEmpty)
}

@Test func correctNamesProposesOnlyRealEdits() throws {
    let question = try #require(Library.questions(.correctNames, for: [daftVideo]).first)
    let reply = "```json\n{\"name\": \"One More Time\", \"artist\": \"Daft Punk\", \"album\": \"\"}\n```"
    #expect(Library.changes(question: question, reply: reply)
        == [.init(track: daftVideo, kind: .edit(name: "One More Time", artist: "Daft Punk", album: ""))])
    let same = #"{"name": "Daft Punk - One More Time (Official Video)", "artist": "", "album": ""}"#
    #expect(Library.changes(question: question, reply: same).isEmpty)
}

@Test func organizeUnknownAsksOnlyAboutTracksWithoutArtist() {
    let unknown = Library.Track(id: "D", name: "Teardrop", artist: "Unknown Artist", album: "", duration: 330)
    #expect(Library.questions(.organizeUnknown, for: [daft, daftVideo, unknown]).map { $0.tracks[0].id } == ["B", "D"])
    #expect(Library.questions(.correctNames, for: [daft, daftVideo, unknown]).count == 3)
}

@Test func allTasksAskOnceAboutEverySong() {
    let all = Library.questions(Set(Library.Task.allCases), for: [daft, daftVideo, other])
    #expect(all.map(\.task) == [.removeDuplicates, .correctNames, .correctNames, .correctNames])
    #expect(Library.questions([.organizeUnknown], for: [daft, daftVideo, other]).map { $0.tracks[0].id } == ["B"])
    #expect(Library.questions([], for: [daft]).isEmpty)
}

@Test func mergedDropsEditsOfTrashedSongs() {
    let trash = Library.Change(track: daftVideo, kind: .trash(keeping: daft))
    let edit = Library.Change(track: daftVideo, kind: .edit(name: "One More Time", artist: "Daft Punk", album: ""))
    let keep = Library.Change(track: other, kind: .edit(name: "Dreams", artist: "Fleetwood Mac", album: "Rumours 2"))
    #expect(Library.merged([edit, trash, keep]) == [trash, keep])
}

@Test func changeLogSaysWhatChangedToWhat() {
    #expect(Library.Change(track: daftVideo, kind: .edit(name: "One More Time", artist: "Daft Punk", album: "")).log
        == "Name: “Daft Punk - One More Time (Official Video)” → “One More Time”; Artist: none → “Daft Punk”")
    #expect(Library.Change(track: daftVideo, kind: .trash(keeping: daft)).log == "Duplicate of “One More Time”: moved to Trash")
}

@Test func escapesAppleScriptStrings() {
    #expect(Library.appleScript(#"Say "Hi" \ Bye"#) == #""Say \"Hi\" \\ Bye""#)
}
