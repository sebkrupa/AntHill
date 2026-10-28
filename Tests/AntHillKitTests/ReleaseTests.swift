import Foundation
import Testing
@testable import AntHillKit

@Test("Compare versions", arguments: [
    ("1.2.0", "1.1.9", true),
    ("1.10.0", "1.9.2", true),
    ("2.0", "1.9.9", true),
    ("1.2.0", "1.2", false),
    ("1.2.0", "1.2.0", false),
    ("1.1.0", "1.2.0", false),
    ("0.1.0", "0.0.0", true),
])
func comparesVersions(_ version: String, _ current: String, newer: Bool) {
    #expect(Release.isNewer(version, than: current) == newer)
}

@Test func decodesGitHubRelease() throws {
    let json = #"{"tag_name": "v1.2.0", "html_url": "https://github.com/sebkrupa/AntHill/releases/tag/v1.2.0", "draft": false}"#
    let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
    #expect(release.version == "1.2.0")
    #expect(release.page.absoluteString.hasSuffix("/v1.2.0"))
}
