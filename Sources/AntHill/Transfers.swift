import AppKit
import AntHillKit
import UserNotifications

/// Filesfer: saved transfer jobs, run one at a time with rsync, by hand or on a schedule.
@Observable
final class Transfers {
    /// The job running now and how far it is.
    struct Run {
        let id: Filesfer.Job.ID
        let scheduled: Bool
        var phase = "Listing files"
        /// nil while the step has no percent (listing, zipping).
        var fraction: Double?
        /// Seconds left; nil until the pace is known.
        var remaining: TimeInterval?
        var phaseStarted = Date()
    }

    private(set) var jobs: [Filesfer.Job] = []
    var selection: Filesfer.Job.ID?
    /// The job in the edit sheet; a new job until it is saved.
    var editing: Filesfer.Job?
    private(set) var current: Run?
    /// Jobs waiting their turn, and whether a schedule started them.
    private(set) var queue: [(id: Filesfer.Job.ID, scheduled: Bool)] = []
    /// Scheduled jobs whose drive is not connected, with the drive's name.
    private(set) var waitingForDisk: [Filesfer.Job.ID: String] = [:]
    /// "142 files · 3.2 GB" per job, or why its files can't be read.
    private(set) var previews: [Filesfer.Job.ID: String] = [:]
    /// Homebrew rsync 3 reports one percent for the whole job; the macOS rsync (openrsync) only names each file.
    let rsync: (path: String, modern: Bool) = ["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"]
        .first(where: FileManager.default.isExecutableFile).map { ($0, true) } ?? ("/usr/bin/rsync", false)
    private let history: URL?
    private var process: Process?
    private var stopping = false
    private var rsyncError: String?
    private var filesDone = 0

    init(history: URL? = nil) {
        self.history = history
        if let history, let data = try? Data(contentsOf: history),
           let saved = try? JSONDecoder().decode([Filesfer.Job].self, from: data) {
            jobs = saved
        }
        jobs.forEach(preview)
        // Test runs never start a job on their own.
        if !Store.isOverridden { watchSchedules() }
    }

    var running: Bool { current != nil || !queue.isEmpty }

    func isBusy(_ id: Filesfer.Job.ID) -> Bool { current?.id == id || queue.contains { $0.id == id } }

    func job(_ id: Filesfer.Job.ID?) -> Filesfer.Job? { jobs.first { $0.id == id } }

    /// The menu bar line: "Photos → Backup 45% · 3m left".
    var status: String? {
        guard let current, let job = job(current.id) else { return nil }
        return "\(job.title) " + Self.progressText(current)
    }

    static func progressText(_ run: Run) -> String {
        guard let fraction = run.fraction else { return "\(run.phase)…" }
        let percent = "\(run.phase) \(Int(fraction * 100))%"
        guard let remaining = run.remaining else { return percent }
        return percent + " · " + Duration.seconds(remaining.rounded())
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)) + " left"
    }

    func newJob() { editing = Filesfer.Job() }

    func edit(_ id: Filesfer.Job.ID) { editing = job(id) }

    /// Saves the job from the edit sheet. A changed schedule counts from now, so it does not fire at once.
    func commit(_ edited: Filesfer.Job) {
        var job = edited
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            if jobs[index].schedule != job.schedule { job.anchor = .now }
            job.last = jobs[index].last
            jobs[index] = job
        } else {
            job.anchor = .now
            jobs.append(job)
        }
        editing = nil
        selection = job.id
        save()
        preview(job)
    }

    func remove(_ id: Filesfer.Job.ID) {
        stop(id)
        jobs.removeAll { $0.id == id }
        previews[id] = nil
        waitingForDisk[id] = nil
        if selection == id { selection = nil }
        save()
    }

    func run(_ id: Filesfer.Job.ID, scheduled: Bool = false) {
        guard !isBusy(id), job(id) != nil else { return }
        queue.append((id, scheduled))
        startNext()
    }

    func runAll() { jobs.forEach { run($0.id) } }

    /// Stops the job if it runs, or takes it out of the line. A stopped cut keeps every file:
    /// rsync removes a source file only after it arrived.
    func stop(_ id: Filesfer.Job.ID) {
        queue.removeAll { $0.id == id }
        guard current?.id == id else { return }
        stopping = true
        process?.terminate()
    }

    func stopAll() {
        queue = []
        if let current { stop(current.id) }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    /// Jobs and their state for snapshots: nothing runs behind them.
    func insertSample(_ samples: [Filesfer.Job], previews: [Filesfer.Job.ID: String], running: Run?, waiting: [Filesfer.Job.ID: String]) {
        jobs = samples
        self.previews = previews
        current = running
        waitingForDisk = waiting
    }

    /// Queues every job whose scheduled time passed, once. A job whose drive is away waits for it.
    func tick(_ now: Date = .now) {
        waitingForDisk = waitingForDisk.filter { id, _ in job(id)?.isDue(now) == true }
        for job in jobs where job.isDue(now) && !isBusy(job.id) {
            if let volume = Filesfer.missingVolume(job) {
                waitingForDisk[job.id] = volume
                continue
            }
            waitingForDisk[job.id] = nil
            if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index].anchor = now }
            save()
            run(job.id, scheduled: true)
        }
    }

    /// Counts the files the job takes now, off the main thread.
    func preview(_ job: Filesfer.Job) {
        guard !job.from.isEmpty else { return }
        Task {
            previews[job.id] = await Task.detached {
                if let volume = Filesfer.missingVolume(job) { return "\(volume) is not connected" }
                do {
                    let plan = try Filesfer.plan(job)
                    let size = ByteCountFormatter.string(fromByteCount: plan.bytes, countStyle: .file)
                    return "\(plan.files.count) \(plan.files.count == 1 ? "file" : "files") · \(size)"
                } catch {
                    return error.localizedDescription
                }
            }.value
        }
    }

    private func save() {
        guard let history else { return }
        do {
            try FileManager.default.createDirectory(at: history.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(jobs).write(to: history, options: .atomic)
        } catch {
            print("AntHill: could not save the Filesfer jobs: \(error.localizedDescription)")
        }
    }

    private func watchSchedules() {
        Task {
            while true {
                tick()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func startNext() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        guard let job = job(next.id) else { return startNext() }
        current = Run(id: job.id, scheduled: next.scheduled)
        stopping = false
        Task {
            let started = Date()
            var outcome: Filesfer.Outcome
            do {
                outcome = .init(date: .now, files: try await perform(job), seconds: Date().timeIntervalSince(started))
            } catch {
                let message = stopping ? "Stopped." : error.localizedDescription
                outcome = .init(date: .now, error: message, permission: message.contains("Operation not permitted"),
                                files: 0, seconds: Date().timeIntervalSince(started))
            }
            if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index].last = outcome }
            save()
            if let error = outcome.error, next.scheduled, !stopping { notify("\(job.title) failed", error) }
            current = nil
            process = nil
            preview(job)
            startNext()
        }
    }

    /// One run: list the files, zip them when asked, rsync, then copy clashing files under a free name.
    /// Returns how many files the job took.
    private func perform(_ job: Filesfer.Job) async throws -> Int {
        if let volume = Filesfer.missingVolume(job) { throw Filesfer.Failure("\(volume) is not connected.") }
        let manager = FileManager.default
        var plan = try await Task.detached { try Filesfer.plan(job) }.value
        guard !plan.files.isEmpty || !plan.folders.isEmpty else { throw Filesfer.Failure("No files match.") }
        let count = plan.files.count
        let isFolder = plan.source == job.from
        let temp = manager.temporaryDirectory.appending(path: "Filesfer-\(UUID().uuidString)").path
        try manager.createDirectory(atPath: temp, withIntermediateDirectories: true)
        defer { try? manager.removeItem(atPath: temp) }
        if job.operation == .zip { plan = try await zip(job, plan, isFolder: isFolder, into: temp) }

        let clashes = job.conflict == .keepBoth ? Filesfer.clashes(plan) : []
        try manager.createDirectory(atPath: plan.destination, withIntermediateDirectories: true)
        let list = (temp as NSString).appendingPathComponent("files.txt")
        try (plan.folders + plan.files.filter { !clashes.contains($0) }).joined(separator: "\n")
            .write(toFile: list, atomically: true, encoding: .utf8)
        let cut = job.operation == .cut
        setPhase(cut ? "Moving" : "Copying", fraction: 0)
        rsyncError = nil
        filesDone = 0
        let total = Double(max(plan.files.count - clashes.count, 1))
        let code = try await launch(rsync.path, Filesfer.rsyncArguments(list: list, source: plan.source, destination: plan.destination,
                                                                         cut: cut, modern: rsync.modern)) { line in
            if let fraction = Filesfer.progress(in: line) {
                self.progress(fraction)
            } else if line.hasPrefix("rsync") || line.hasPrefix("openrsync") {
                // The first error names the file; the last one is only "some files were not transferred".
                if self.rsyncError == nil { self.rsyncError = line }
            } else if !self.rsync.modern, !line.isEmpty, !line.hasSuffix("/") {
                self.filesDone += 1
                self.progress(min(Double(self.filesDone) / total, 1))
            }
        }
        if stopping { throw Filesfer.Failure("Stopped.") }
        guard code == 0 else { throw Filesfer.Failure(rsyncError ?? "rsync stopped with code \(code).") }

        for path in clashes.sorted() {
            let source = (plan.source as NSString).appendingPathComponent(path)
            let target = Filesfer.freeName(for: (plan.destination as NSString).appendingPathComponent(path), exists: manager.fileExists(atPath:))
            if cut { try manager.moveItem(atPath: source, toPath: target) } else { try manager.copyItem(atPath: source, toPath: target) }
        }
        if cut && isFolder { Filesfer.removeEmptyFolders(job.from, includingSelf: false) }
        return count
    }

    /// Zips the job's files into `temp` and returns the plan that copies the zip to WHERE.
    private func zip(_ job: Filesfer.Job, _ plan: Filesfer.Plan, isFolder: Bool, into temp: String) async throws -> Filesfer.Plan {
        setPhase("Zipping")
        var name = Filesfer.zipName(from: job.from, isFolder: isFolder, date: .now)
        if job.conflict == .keepBoth {
            let free = Filesfer.freeName(for: (job.to as NSString).appendingPathComponent(name), exists: FileManager.default.fileExists(atPath:))
            name = (free as NSString).lastPathComponent
        }
        let zip = (temp as NSString).appendingPathComponent(name)
        let code: Int32
        if isFolder && job.selection != .whole {
            // zip reads the list from stdin; paths start with the folder's name, like ditto --keepParent.
            let folder = (job.from as NSString).lastPathComponent
            code = try await launch("/usr/bin/zip", ["-q", "-X", zip, "-@"], in: (job.from as NSString).deletingLastPathComponent,
                                    input: plan.files.map { (folder as NSString).appendingPathComponent($0) }.joined(separator: "\n"))
        } else {
            // ditto keeps macOS metadata, like Finder's Compress.
            code = try await launch("/usr/bin/ditto", ["-c", "-k", "--keepParent", job.from, zip])
        }
        if stopping { throw Filesfer.Failure("Stopped.") }
        guard code == 0 else { throw Filesfer.Failure("Zipping stopped with code \(code).") }
        let size = (try? FileManager.default.attributesOfItem(atPath: zip)[.size] as? Int64) ?? 0
        return Filesfer.Plan(source: temp, destination: job.to, files: [name], bytes: size)
    }

    private func setPhase(_ phase: String, fraction: Double? = nil) {
        current?.phase = phase
        current?.fraction = fraction
        current?.remaining = nil
        current?.phaseStarted = .now
    }

    private func progress(_ fraction: Double) {
        guard var run = current else { return }
        run.fraction = fraction
        run.remaining = Filesfer.remaining(fraction: fraction, elapsed: Date().timeIntervalSince(run.phaseStarted))
        current = run
    }

    /// Runs a tool, hands each output line to the main thread, and returns its exit code.
    private func launch(_ tool: String, _ arguments: [String], in folder: String? = nil, input: String? = nil,
                        line: @escaping @MainActor (String) -> Void = { _ in }) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let folder { process.currentDirectoryURL = URL(fileURLWithPath: folder) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let stdin = Pipe()
        if input != nil { process.standardInput = stdin }
        let lines = LineBuffer(ends: [0x0A, 0x0D])
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let found = lines.append(handle.availableData)
            guard !found.isEmpty else { return }
            Task { @MainActor in found.forEach(line) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let code = process.terminationStatus
                Task { @MainActor in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: code)
                }
            }
            do {
                try process.run()
                self.process = process
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
                return
            }
            if let input {
                let writer = stdin.fileHandleForWriting
                Task.detached {
                    writer.write(Data(input.utf8))
                    try? writer.close()
                }
            }
        }
    }

    private func notify(_ title: String, _ body: String) {
        guard !Store.isOverridden else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
