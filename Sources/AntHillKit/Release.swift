import Foundation

/// A published GitHub release, and the rule that says when it is an update.
public struct Release: Decodable, Equatable, Sendable {
    /// The version without the tag's "v": "1.2.0".
    public let version: String
    /// The release page, with the download and the notes.
    public let page: URL

    /// The newest release. GitHub leaves out drafts and pre-releases.
    public static let latestURL = URL(string: "https://api.github.com/repos/sebkrupa/AntHill/releases/latest")!

    public init(version: String, page: URL) {
        self.version = version
        self.page = page
    }

    enum CodingKeys: String, CodingKey { case tag = "tag_name", page = "html_url" }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = String(try values.decode(String.self, forKey: .tag).trimmingPrefix("v"))
        page = try values.decode(URL.self, forKey: .page)
    }

    /// True when `version` is newer than `current`, number by number: 1.10.0 is newer than 1.9.2, 1.2 equals 1.2.0.
    public static func isNewer(_ version: String, than current: String) -> Bool {
        func numbers(_ text: String) -> [Int] { text.split(separator: ".").map { Int($0) ?? 0 } }
        var new = numbers(version), old = numbers(current)
        let count = max(new.count, old.count)
        new += Array(repeating: 0, count: count - new.count)
        old += Array(repeating: 0, count: count - old.count)
        return old.lexicographicallyPrecedes(new)
    }
}
