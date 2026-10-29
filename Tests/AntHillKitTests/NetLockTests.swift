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

@Test func startWithABlockListPassesBlock() {
    let command = NetLock.startCommand(script: script, mode: .block, apps: ["/Applications/Firefox.app"], log: "/tmp/l")
    #expect(command.hasSuffix("--no-monitor --block '/Applications/Firefox.app' >'/tmp/l' 2>&1 </dev/null &"))
    #expect(!command.contains("--allow"))
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

@Test func stopKillsALockThatIgnoresTermAndRestoresTheNetwork() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let fake = dir.appending(path: "netlock").path
    try """
    [ "$1" = restore ] && { touch "$0.restored"; exit 0; }
    trap '' TERM
    while :; do sleep 0.2; done
    """.write(toFile: fake, atomically: true, encoding: .utf8)
    let lock = Process()
    lock.executableURL = URL(filePath: "/bin/bash")
    lock.arguments = [fake, "--no-monitor"]
    try lock.run()
    defer { lock.terminate() }
    Thread.sleep(forTimeInterval: 0.3)

    let stop = Process()
    stop.executableURL = URL(filePath: "/bin/sh")
    stop.arguments = ["-c", NetLock.stopCommand(script: fake)]
    try stop.run()
    let deadline = Date.now.addingTimeInterval(15)
    while stop.isRunning && Date.now < deadline { Thread.sleep(forTimeInterval: 0.2) }
    #expect(!stop.isRunning)
    lock.waitUntilExit()
    #expect(lock.terminationReason == .uncaughtSignal)
    #expect(FileManager.default.fileExists(atPath: fake + ".restored"))
}

@Test func aLockStartedWithTermIgnoredStillStopsOnTerm() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let fake = dir.appending(path: "netlock").path
    try """
    [ "$1" = restore ] && { touch "$0.restored"; exit 0; }
    trap 'touch "$0.stopped"; exit 143' TERM
    while :; do sleep 0.2 & wait $!; done
    """.write(toFile: fake, atomically: true, encoding: .utf8)
    // Like the administrator prompt: the shell that starts the lock has SIGTERM ignored and blocked.
    let start = Process()
    start.executableURL = URL(filePath: "/usr/bin/perl")
    start.arguments = ["-MPOSIX", "-e", #"sigprocmask(SIG_BLOCK, POSIX::SigSet->new(SIGTERM)); $SIG{TERM} = "IGNORE"; exec "/bin/sh", "-c", $ARGV[0]"#,
                       NetLock.startCommand(script: fake, mode: .block, apps: ["/Applications/A.app"], log: "/dev/null")]
    try start.run()
    start.waitUntilExit()
    Thread.sleep(forTimeInterval: 0.5)

    let stop = Process()
    stop.executableURL = URL(filePath: "/bin/sh")
    stop.arguments = ["-c", NetLock.stopCommand(script: fake)]
    let began = Date.now
    try stop.run()
    stop.waitUntilExit()
    #expect(Date.now.timeIntervalSince(began) < 3)
    #expect(FileManager.default.fileExists(atPath: fake + ".stopped"))
    #expect(!FileManager.default.fileExists(atPath: fake + ".restored"))
}

@Test func appleScriptEscapesQuotesAndBackslashes() {
    #expect(NetLock.appleScript(#"echo "a\b""#) == #"do shell script "echo \"a\\b\"" with administrator privileges"#)
}

@Test func onlyAppBundlesWithoutCommasCanBeAllowed() {
    #expect(NetLock.canAllow("/Applications/Firefox.app"))
    #expect(!NetLock.canAllow("/Applications/A, B.app"))
    #expect(!NetLock.canAllow("/usr/bin/curl"))
}
