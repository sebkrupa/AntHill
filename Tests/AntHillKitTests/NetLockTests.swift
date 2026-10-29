import Foundation
import Testing
@testable import AntHillKit

private let script = "/Applications/AntHill.app/Contents/Resources/netlock"

@Test func quotesSingleQuotes() {
    #expect(NetLock.quote("it's") == "'it'\\''s'")
}

@Test func startStopsFirstThenRunsInBackground() {
    let command = NetLock.startCommand(script: script, apps: ["/Applications/Firefox.app", "/Applications/Bob's App.app"], log: "/tmp/l")
    #expect(command.hasPrefix(NetLock.stopCommand(script: script) + "; "))
    #expect(command.hasSuffix("/bin/bash '\(script)' --no-monitor --allow '/Applications/Firefox.app' --allow '/Applications/Bob'\\''s App.app' >'/tmp/l' 2>&1 </dev/null &"))
}

@Test func startWithoutAppsBlocksEverything() {
    #expect(NetLock.startCommand(script: script, apps: [], log: "/tmp/l").contains("--no-monitor >'/tmp/l'"))
}

@Test func patternMatchesTheLockButNotTheShellThatStartsIt() throws {
    let regex = try NSRegularExpression(pattern: NetLock.pattern(script: script))
    func matches(_ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
    #expect(matches("/bin/bash \(script) --no-monitor --allow /Applications/Firefox.app"))
    #expect(!matches("/bin/sh -c " + NetLock.startCommand(script: script, apps: [], log: "/tmp/l")))
    #expect(!matches("/bin/bash \(script)x --no-monitor"))
}

@Test func appleScriptEscapesQuotesAndBackslashes() {
    #expect(NetLock.appleScript(#"echo "a\b""#) == #"do shell script "echo \"a\\b\"" with administrator privileges"#)
}

@Test func onlyAppBundlesWithoutCommasCanBeAllowed() {
    #expect(NetLock.canAllow("/Applications/Firefox.app"))
    #expect(!NetLock.canAllow("/Applications/A, B.app"))
    #expect(!NetLock.canAllow("/usr/bin/curl"))
}
