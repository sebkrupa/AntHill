import Foundation
import Testing
@testable import AntHillKit

private func folder() throws -> String {
    let path = FileManager.default.temporaryDirectory.appending(path: "filesfer-\(UUID().uuidString)").path
    for file in ["IMG_1.JPG", "notes.txt", "sub/IMG_2.jpg", "sub/deep/clip.mov", ".hidden.jpg", ".DS_Store", ".git/x.jpg"] {
        let full = (path as NSString).appendingPathComponent(file)
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: full))
    }
    try FileManager.default.createDirectory(atPath: path + "/empty", withIntermediateDirectories: true)
    return path
}

private func job(_ from: String, _ selection: Filesfer.Selection = .whole, _ pattern: String = "") -> Filesfer.Job {
    var job = Filesfer.Job()
    job.from = from
    job.to = "/tmp/out"
    job.selection = selection
    job.pattern = pattern
    return job
}

@Test func wholeFolderTakesHiddenFilesButNoClutter() throws {
    let from = try folder()
    let plan = try Filesfer.plan(job(from))
    #expect(Set(plan.files) == ["IMG_1.JPG", "notes.txt", "sub/IMG_2.jpg", "sub/deep/clip.mov", ".hidden.jpg", ".git/x.jpg"])
    #expect(plan.folders.contains("empty"))
    #expect(plan.destination == "/tmp/out/" + (from as NSString).lastPathComponent)
    #expect(plan.bytes == 6)
}

@Test func filtersSearchSubfoldersIgnoreCaseAndSkipHidden() throws {
    let from = try folder()
    #expect(Set(try Filesfer.plan(job(from, .extensions, "jpg, .MOV")).files) == ["IMG_1.JPG", "sub/IMG_2.jpg", "sub/deep/clip.mov"])
    #expect(try Filesfer.plan(job(from, .regex, "^img_\\d")).files.sorted() == ["IMG_1.JPG", "sub/IMG_2.jpg"])
    #expect(try Filesfer.plan(job(from, .names, "Notes.txt\nclip.mov")).files.sorted() == ["notes.txt", "sub/deep/clip.mov"])
    #expect(try Filesfer.plan(job(from, .extensions, "jpg")).folders.isEmpty)
}

@Test func aFileLandsStraightInWhere() throws {
    let from = try folder() + "/notes.txt"
    let plan = try Filesfer.plan(job(from))
    #expect(plan.files == ["notes.txt"] && plan.destination == "/tmp/out" && plan.source.hasSuffix(plan.source.split(separator: "/").last!))
}

@Test func refusesJobsThatWriteIntoThemselves() {
    var bad = job("/Users/me/Photos")
    bad.to = "/Users/me/Photos/Backup"
    #expect(Filesfer.problem(bad, fromIsFolder: true)?.contains("inside FROM") == true)
    bad.to = "/Users/me/Photos/"
    #expect(Filesfer.problem(bad, fromIsFolder: true)?.contains("same folder") == true)
    bad.to = "/Users/me"
    #expect(Filesfer.problem(bad, fromIsFolder: true)?.contains("already in WHERE") == true)
    bad.operation = .zip
    #expect(Filesfer.problem(bad, fromIsFolder: true) == nil)
    var regex = job("/Users/me/Photos", .regex, "([")
    #expect(Filesfer.problem(regex, fromIsFolder: true) == "The regex is not valid.")
    regex.pattern = " "
    #expect(Filesfer.problem(regex, fromIsFolder: true)?.hasPrefix("Type what to match") == true)
    #expect(Filesfer.problem(regex, fromIsFolder: false) == nil)
}

@Test func freeNamesCountUpLikeFinder() {
    let taken: Set = ["/d/photo.jpg", "/d/photo 2.jpg", "/d/README"]
    #expect(Filesfer.freeName(for: "/d/photo.jpg", exists: taken.contains) == "/d/photo 3.jpg")
    #expect(Filesfer.freeName(for: "/d/README", exists: taken.contains) == "/d/README 2")
    #expect(Filesfer.freeName(for: "/d/new.txt", exists: taken.contains) == "/d/new.txt")
}

@Test func onlyChangedFilesClash() throws {
    let from = try folder()
    let to = FileManager.default.temporaryDirectory.appending(path: "filesfer-out-\(UUID().uuidString)").path
    let landed = (to as NSString).appendingPathComponent((from as NSString).lastPathComponent)
    try FileManager.default.createDirectory(atPath: landed, withIntermediateDirectories: true)
    try FileManager.default.copyItem(atPath: from + "/notes.txt", toPath: landed + "/notes.txt")
    try Data("other".utf8).write(to: URL(fileURLWithPath: landed + "/IMG_1.JPG"))
    var plan = try Filesfer.plan(job(from))
    plan.destination = landed
    #expect(Filesfer.clashes(plan) == ["IMG_1.JPG"])
}

@Test func rsyncArgumentsAndProgress() {
    #expect(Filesfer.rsyncArguments(list: "/t/l", source: "/a", destination: "/b/a", cut: true, modern: true)
        == ["-lt", "--files-from=/t/l", "--out-format=%n", "--info=progress2", "--remove-source-files", "/a/", "/b/a/"])
    #expect(Filesfer.rsyncArguments(list: "/t/l", source: "/a", destination: "/b", cut: false, modern: false)
        == ["-lt", "--files-from=/t/l", "--out-format=%n", "/a/", "/b/"])
    #expect(Filesfer.progress(in: "     30,000,003  45%  922.91MB/s    0:00:00 (xfr#2, to-chk=0/4)") == 0.45)
    #expect(Filesfer.progress(in: "sub/45% off.txt") == nil)
    #expect(Filesfer.remaining(fraction: 0.25, elapsed: 60) == 180)
    #expect(Filesfer.remaining(fraction: 0.01, elapsed: 60) == nil)
}

@Test func removesOnlyFoldersLeftEmpty() throws {
    let from = try folder()
    for file in ["IMG_1.JPG", "notes.txt", "sub/IMG_2.jpg", "sub/deep/clip.mov"] { try FileManager.default.removeItem(atPath: from + "/" + file) }
    Filesfer.removeEmptyFolders(from, includingSelf: true)
    #expect(!FileManager.default.fileExists(atPath: from + "/sub") && !FileManager.default.fileExists(atPath: from + "/empty"))
    #expect(FileManager.default.fileExists(atPath: from + "/.hidden.jpg") && FileManager.default.fileExists(atPath: from + "/.git/x.jpg"))
}

@Test func schedulesFireOnceForMissedRuns() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 10))!
    var schedule = Filesfer.Schedule()
    schedule.kind = .daily
    #expect(schedule.next(after: monday, calendar: calendar) == calendar.date(bySettingHour: 22, minute: 0, second: 0, of: monday))
    schedule.kind = .weekly
    schedule.weekdays = [1]
    #expect(calendar.component(.weekday, from: schedule.next(after: monday, calendar: calendar)!) == 1)
    schedule.kind = .hours
    schedule.hours = 3
    #expect(schedule.next(after: monday) == monday.addingTimeInterval(3 * 3600))

    var job = Filesfer.Job()
    job.schedule.kind = .daily
    job.anchor = monday.addingTimeInterval(-3 * 86_400)
    #expect(job.isDue(monday))
    job.anchor = monday
    #expect(!job.isDue(monday.addingTimeInterval(60)))
    job.schedule.kind = .off
    #expect(!job.isDue(.distantFuture))
}

@Test func namesAndVolumes() {
    var job = Filesfer.Job()
    job.from = "/Users/me/Photos"
    job.to = "/Volumes/Backup/2026"
    #expect(job.title == "Photos → 2026")
    #expect(Filesfer.missingVolume(job, exists: { _ in false }) == "Backup")
    #expect(Filesfer.missingVolume(job, exists: { _ in true }) == nil)
    let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 0, minute: 30))!
    #expect(Filesfer.zipName(from: "/a/Photos", isFolder: true, date: date) == "Photos 2026-10-28.zip")
    #expect(Filesfer.zipName(from: "/a/report.pdf", isFolder: false, date: date) == "report 2026-10-28.zip")
}
