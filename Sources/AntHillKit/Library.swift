import Foundation

/// The Music.app library tasks a local model runs: what it is asked, and how its answers become changes.
public enum Library {
    /// One file track in Music.app.
    public struct Track: Identifiable, Hashable, Sendable {
        /// Music.app's persistent ID.
        public let id: String
        public var name: String
        public var artist: String
        public var album: String
        /// Seconds.
        public var duration: Double

        public init(id: String, name: String, artist: String, album: String, duration: Double) {
            self.id = id; self.name = name; self.artist = artist; self.album = album; self.duration = duration
        }
    }

    public enum Task: String, CaseIterable, Identifiable, Sendable {
        case removeDuplicates, correctNames, organizeUnknown

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .removeDuplicates: "Remove Duplicates"
            case .correctNames: "Correct Names and Albums"
            case .organizeUnknown: "Organize Unknown Artists"
            }
        }

        var system: String {
            switch self {
            case .removeDuplicates: """
                You clean an Apple Music library. The user sends songs that may be the same recording, as JSON.
                Remove only true duplicates: the same song by the same artist in the same version.
                Live, remix, acoustic, cover, and edit versions are different songs: keep them.
                Of each set of duplicates keep one: the one with the most complete artist and album, then the longest duration.
                Answer only JSON: {"remove": ["<id>", ...]}. Answer {"remove": []} when nothing is a duplicate.
                """
            case .correctNames: """
                You fix the tags of one song in an Apple Music library. Many songs come from YouTube video titles.
                name: the song title only. Remove video words like (Official Video), (Official Audio), [HD], (Lyrics), (Visualizer), and "Remastered 2004".
                Keep words that name a different version: Live, Remix, Acoustic, Edit, feat.
                artist: the performing artist. When the name is "Artist - Title", move the artist out of the name.
                album: the album the song first came out on, only when you are sure. Otherwise keep the current album.
                Never guess. When a tag is already right, return it unchanged.
                Answer only JSON: {"name": "...", "artist": "...", "album": "..."}.
                """
            case .organizeUnknown: """
                You fix one song in an Apple Music library that has no artist.
                Find the artist from the name, for example "Artist - Title". Then name is the title only, without the artist.
                Fill album only when you are sure which album the song first came out on. Otherwise keep the current album.
                When you can't tell the artist, return the song unchanged with artist "".
                Answer only JSON: {"name": "...", "artist": "...", "album": "..."}.
                """
            }
        }
    }

    /// A change the model proposes for one track. The person reviews it before it is applied.
    public struct Change: Identifiable, Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case edit(name: String, artist: String, album: String)
            /// Move the file to the Trash and drop the track from Music; `keeping` is the copy that stays.
            case trash(keeping: Track)
        }

        public let track: Track
        public let kind: Kind
        public var id: String { track.id }

        public init(track: Track, kind: Kind) { self.track = track; self.kind = kind }
    }

    /// One question for the model: the tracks it looks at together, and the instructions.
    public struct Question: Sendable {
        public let tracks: [Track]
        public let system: String
        public let user: String
    }

    /// The questions a task asks about `tracks`. Every track the task applies to is checked.
    public static func questions(_ task: Task, for tracks: [Track]) -> [Question] {
        switch task {
        case .removeDuplicates:
            // Only songs that could be the same recording go to the model together.
            return duplicateCandidates(tracks).map { group in
                Question(tracks: group, system: task.system, user: json(group.map {
                    ["id": $0.id, "name": $0.name, "artist": $0.artist, "album": $0.album, "seconds": Int($0.duration)]
                }))
            }
        case .correctNames, .organizeUnknown:
            return tracks.filter { task == .correctNames || isUnknown($0.artist) }.map { track in
                Question(tracks: [track], system: task.system,
                         user: json(["name": track.name, "artist": track.artist, "album": track.album]))
            }
        }
    }

    /// The changes in the model's answer to `question`. Answers that are not the asked JSON give none.
    public static func changes(_ task: Task, question: Question, reply: String) -> [Change] {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"),
              let object = try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) as? [String: Any]
        else { return [] }
        switch task {
        case .removeDuplicates:
            let remove = Set(object["remove"] as? [String] ?? [])
            // Something must stay: an answer that removes the whole group is ignored.
            guard let kept = question.tracks.first(where: { !remove.contains($0.id) }) else { return [] }
            return question.tracks.filter { remove.contains($0.id) }.map { Change(track: $0, kind: .trash(keeping: kept)) }
        case .correctNames, .organizeUnknown:
            guard let track = question.tracks.first else { return [] }
            func value(_ key: String, _ current: String) -> String {
                let text = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return text.isEmpty ? current : text
            }
            let name = value("name", track.name), artist = value("artist", track.artist), album = value("album", track.album)
            guard (name, artist, album) != (track.name, track.artist, track.album) else { return [] }
            return [Change(track: track, kind: .edit(name: name, artist: artist, album: album))]
        }
    }

    public static func isUnknown(_ artist: String) -> Bool {
        ["", "unknown", "unknown artist", "various artists"].contains(artist.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Groups of two or more tracks with the same artist and title once brackets, case, and punctuation are gone.
    /// "Daft Punk - One More Time (Official Video)" with no artist meets "One More Time" by Daft Punk.
    static func duplicateCandidates(_ tracks: [Track]) -> [[Track]] {
        func key(_ track: Track) -> String {
            let full = isUnknown(track.artist) || track.name.lowercased().hasPrefix(track.artist.lowercased())
                ? track.name : track.artist + " " + track.name
            let plain = full.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: "", options: .regularExpression)
            return String(plain.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
        }
        return Dictionary(grouping: tracks, by: key).values.filter { $0.count > 1 }
            .map { $0.sorted { $0.id < $1.id } }.sorted { $0[0].name < $1[0].name }
    }

    static func json(_ value: Any) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
    }

    /// Text as an AppleScript string literal.
    public static func appleScript(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
