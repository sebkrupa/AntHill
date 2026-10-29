import AppKit
import AntHillKit

/// The Music.app library on the YT-Music Library tab: its tracks, the task the model runs
/// on them, and the changes it proposes. Nothing changes until the person applies them.
@Observable
final class MusicLibrary {
    private(set) var tracks: [Library.Track] = []
    var loading = false
    /// Why the tracks could not be read, in plain words.
    var error: String?
    /// True when macOS keeps AntHill from controlling Music; the page offers the setting.
    var needsAccess = false
    /// The checked tasks; Run asks about all of them in one pass.
    var tasks: Set<Library.Task> = Set(Library.Task.allCases)
    /// The tracks the task runs on; none selected runs on all.
    var selection: Set<Library.Track.ID> = []
    /// Questions answered and asked in the current run; nil when no run goes on.
    private(set) var progress: (done: Int, total: Int)?
    /// The proposed changes; the review sheet shows while this is set.
    var changes: [Library.Change]?
    /// The changes the person keeps checked in the review sheet.
    var chosen: Set<Library.Change.ID> = []
    /// What the last run did to each track, for the first and last columns of the list.
    var notes: [Library.Track.ID: Note] = [:]
    private var run: Task<Void, Never>?

    var running: Bool { progress != nil }
    /// The task menu's title: the one checked task, or how many are checked.
    var tasksTitle: String {
        switch tasks.count {
        case 0: "No Tasks"
        case 1: tasks.first!.title
        case Library.Task.allCases.count: "All Tasks"
        default: "\(tasks.count) Tasks"
        }
    }
    var scope: [Library.Track] { selection.isEmpty ? tracks : tracks.filter { selection.contains($0.id) } }

    /// Reads every file track from Music.app. The first time, macOS asks to allow AntHill to control Music.
    /// shortcut: NSAppleScript runs on the main thread, so a library of tens of thousands of songs pauses the window for a moment.
    func load() {
        // Test runs never touch the real Music library.
        guard !Store.isOverridden, !loading else { return }
        loading = true
        error = nil
        needsAccess = false
        defer { loading = false }
        do {
            let result = try Self.music("""
                tell library playlist 1 to return {persistent ID of every file track, name of every file track, \
                artist of every file track, album of every file track, duration of every file track}
                """)
            func column(_ index: Int) -> [NSAppleEventDescriptor] {
                guard let list = result.atIndex(index), list.numberOfItems > 0 else { return [] }
                return (1...list.numberOfItems).compactMap(list.atIndex)
            }
            let ids = column(1), names = column(2), artists = column(3), albums = column(4), durations = column(5)
            tracks = ids.indices.map { i in
                Library.Track(id: ids[i].stringValue ?? "", name: names[i].stringValue ?? "",
                              artist: artists[i].stringValue ?? "", album: albums[i].stringValue ?? "",
                              duration: durations[i].doubleValue)
            }
            selection.formIntersection(tracks.map(\.id))
        } catch {
            self.error = error.localizedDescription
            needsAccess = error is AccessError
        }
    }

    /// Asks the model about every track for all checked tasks at once, a few questions in parallel,
    /// then opens the review sheet.
    func start(with llama: LlamaConnection) {
        guard !running, !tasks.isEmpty else { return }
        let scope = scope
        let questions = Library.questions(tasks, for: scope)
        progress = (0, questions.count)
        error = nil
        run = Task {
            var found: [Library.Change] = []
            var failures = 0, answers = 0
            var answered: Set<Library.Track.ID> = []
            await withTaskGroup(of: ([Library.Track.ID], Result<[Library.Change], Error>).self) { group in
                var pending = questions[...]
                func next() {
                    guard let question = pending.popFirst() else { return }
                    group.addTask {
                        let ids = question.tracks.map(\.id)
                        do { return (ids, .success(Library.changes(question: question, reply: try await llama.ask(system: question.system, user: question.user)))) }
                        catch { return (ids, .failure(error)) }
                    }
                }
                // llama.cpp answers several requests at once when it has slots; more just wait in its queue.
                for _ in 0..<4 { next() }
                for await (ids, result) in group {
                    switch result {
                    case .success(let changes): found += changes; answers += 1; answered.formUnion(ids)
                    case .failure(let error):
                        failures += 1
                        // The first questions all failed: the server is away, so stop instead of failing every song.
                        if answers == 0, failures == min(3, questions.count) {
                            self.error = "The model did not answer: \(error.localizedDescription)"
                            group.cancelAll()
                        }
                    }
                    progress?.done += 1
                    if !group.isCancelled, !Task.isCancelled { next() }
                }
            }
            if failures > 0, self.error == nil { self.error = "The model did not answer for \(failures) songs. Run again to retry them." }
            let merged = Library.merged(found)
            for id in answered.subtracting(merged.map(\.id)) where notes[id]?.cleaned != true {
                notes[id] = Note(cleaned: false, log: "Checked: nothing to change")
            }
            progress = nil
            run = nil
            chosen = Set(merged.map(\.id))
            changes = merged
        }
    }

    func stop() { run?.cancel() }

    /// Applies the checked changes in Music.app. Duplicates go to the Trash, so they can come back.
    func apply() {
        guard let changes else { return }
        var failed: [String] = []
        // Logs of this apply per track: a kept duplicate can also get a new name.
        var done: [Library.Track.ID: [String]] = [:]
        for change in changes where !chosen.contains(change.id) {
            notes[change.id] = Note(cleaned: false, log: "Not applied: " + change.log)
        }
        for change in changes where chosen.contains(change.id) {
            let track = "(first file track of library playlist 1 whose persistent ID is \(Library.appleScript(change.track.id)))"
            do {
                switch change.kind {
                case .edit(let name, let artist, let album):
                    try Self.music("""
                        set theTrack to \(track)
                        set name of theTrack to \(Library.appleScript(name))
                        set artist of theTrack to \(Library.appleScript(artist))
                        set album of theTrack to \(Library.appleScript(album))
                        """)
                case .trash:
                    // "POSIX path of" inside the tell block goes to Music, which fails; Swift reads the file reference.
                    // A track whose file is already gone has no location: only the track is deleted.
                    if let file = try Self.music("get location of \(track)").fileURLValue {
                        try FileManager.default.trashItem(at: file, resultingItemURL: nil)
                    }
                    try Self.music("delete \(track)")
                }
                done[change.id, default: []].append(change.log)
                if case .trash(let kept) = change.kind { done[kept.id, default: []].append("Removed duplicate “\(change.track.name)”") }
            } catch {
                failed.append("\(change.track.name): \(error.localizedDescription)")
                notes[change.id] = Note(cleaned: false, log: "Failed: " + error.localizedDescription)
            }
        }
        for (id, logs) in done { notes[id] = Note(cleaned: true, log: logs.joined(separator: "; ")) }
        self.changes = nil
        load()
        // The Log column has each reason; the banner names only the first.
        if let first = failed.first {
            error = failed.count == 1 ? "A change failed. \(first)" : "\(failed.count) changes failed; the Log column says why. First: \(first)"
        }
    }

    /// Closes the review sheet without changing Music.
    func discard() {
        chosen = []
        for change in changes ?? [] { notes[change.id] = Note(cleaned: false, log: "Not applied: " + change.log) }
        changes = nil
    }

    struct Note: Equatable, Sendable {
        var cleaned: Bool
        var log: String
    }

    func insertSample(_ tracks: [Library.Track]) { self.tracks = tracks }

    /// Runs AppleScript inside `tell application "Music"`.
    @discardableResult
    private static func music(_ body: String) throws -> NSAppleEventDescriptor {
        var info: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Music\"\n\(body)\nend tell")
        if let result = script?.executeAndReturnError(&info) { return result }
        // -1743: the person has not allowed AntHill to control Music.
        if info?[NSAppleScript.errorNumber] as? Int == -1743 { throw AccessError() }
        throw NSError(domain: "Music", code: 0, userInfo: [NSLocalizedDescriptionKey:
            info?[NSAppleScript.errorMessage] as? String ?? "Music did not answer."])
    }

    struct AccessError: LocalizedError {
        var errorDescription: String? { "AntHill may not control Music. Allow it in System Settings > Privacy & Security > Automation." }
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
}
