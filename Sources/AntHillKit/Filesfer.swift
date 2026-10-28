import Foundation

/// Filesfer rules: which files a transfer job takes, where they land, the rsync command, and schedules.
public enum Filesfer {
    public enum Operation: String, Codable, CaseIterable, Identifiable, Sendable {
        case copy, cut, zip

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .copy: "Copy"
            case .cut: "Cut"
            case .zip: "Zip and Copy"
            }
        }
    }

    /// What happens when a file with the same name, but other content, is already in WHERE.
    public enum Conflict: String, Codable, CaseIterable, Identifiable, Sendable {
        case keepBoth, overwrite

        public var id: String { rawValue }
        public var title: String { self == .keepBoth ? "Keep Both" : "Overwrite" }
    }

    /// Which files of a FROM folder the job takes.
    public enum Selection: String, Codable, CaseIterable, Identifiable, Sendable {
        case whole, regex, names, extensions

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .whole: "Whole Folder"
            case .regex: "Regex"
            case .names: "File Names"
            case .extensions: "Extensions"
            }
        }

        public var prompt: String {
            switch self {
            case .whole: ""
            case .regex: "^IMG_\\d+\\.jpe?g$"
            case .names: "notes.txt, budget.xlsx"
            case .extensions: "jpg, heic, mov"
            }
        }
    }

    public struct Schedule: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
            case off, hours, daily, weekly

            public var id: String { rawValue }

            public var title: String {
                switch self {
                case .off: "Off"
                case .hours: "Every N Hours"
                case .daily: "Daily"
                case .weekly: "Weekly"
                }
            }
        }

        public var kind: Kind = .off
        public var hours = 6
        public var hour = 22
        public var minute = 0
        /// Calendar weekdays: 1 is Sunday, 7 is Saturday.
        public var weekdays: Set<Int> = [2, 3, 4, 5, 6]

        public init() {}

        /// The first scheduled time after `date`; nil when the schedule is off.
        public func next(after date: Date, calendar: Calendar = .current) -> Date? {
            switch kind {
            case .off: return nil
            case .hours: return date.addingTimeInterval(Double(max(hours, 1)) * 3600)
            case .daily:
                return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime)
            case .weekly:
                return weekdays.compactMap {
                    calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, weekday: $0), matchingPolicy: .nextTime)
                }.min()
            }
        }
    }

    /// How the last run of a job ended.
    public struct Outcome: Codable, Hashable, Sendable {
        public var date: Date
        /// nil when the run worked.
        public var error: String?
        /// The error came from macOS privacy protection; the row offers Privacy Settings.
        public var permission = false
        public var files: Int
        public var seconds: Double

        public init(date: Date, error: String? = nil, permission: Bool = false, files: Int, seconds: Double) {
            self.date = date; self.error = error; self.permission = permission; self.files = files; self.seconds = seconds
        }
    }

    public struct Job: Codable, Identifiable, Hashable, Sendable {
        public var id = UUID()
        public var name = ""
        /// A file or a folder.
        public var from = ""
        /// A folder.
        public var to = ""
        public var operation = Operation.copy
        public var conflict = Conflict.keepBoth
        public var selection = Selection.whole
        public var pattern = ""
        public var schedule = Schedule()
        /// The schedule counts from here: when it last fired or was set.
        public var anchor = Date()
        public var last: Outcome?

        public init() {}

        /// "Photos → Backup", used while the person has not named the job.
        public var defaultName: String {
            from.isEmpty || to.isEmpty ? "New Job"
                : "\((from as NSString).lastPathComponent) → \((to as NSString).lastPathComponent)"
        }

        public var title: String { name.isEmpty ? defaultName : name }

        public var nextRun: Date? { schedule.next(after: anchor) }

        /// A scheduled time passed since the anchor. Missed runs count once.
        public func isDue(_ now: Date) -> Bool { nextRun.map { $0 <= now } ?? false }
    }

    /// The files one run takes, as paths relative to `source`.
    public struct Plan: Sendable {
        public var source: String
        /// Where `source`'s files land: WHERE/<FROM name> for a folder, WHERE for a file.
        public var destination: String
        public var files: [String]
        /// Folders to create even when empty (Whole Folder only).
        public var folders: [String] = []
        public var bytes: Int64

        public init(source: String, destination: String, files: [String], folders: [String] = [], bytes: Int64) {
            self.source = source; self.destination = destination; self.files = files; self.folders = folders; self.bytes = bytes
        }
    }

    public struct Failure: LocalizedError {
        public let errorDescription: String?
        public init(_ message: String) { errorDescription = message }
    }

    /// macOS clutter that Whole Folder leaves out.
    public static func isJunk(_ name: String) -> Bool {
        name.hasPrefix("._") || [".DS_Store", ".Spotlight-V100", ".Trashes", ".fseventsd", ".TemporaryItems"].contains(name)
    }

    /// Tells if a file name matches the filter. Names and extensions ignore case and accept a comma or line list.
    public static func matcher(_ selection: Selection, _ pattern: String) throws -> @Sendable (String) -> Bool {
        let items = pattern.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        switch selection {
        case .whole: return { _ in true }
        case .regex:
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            return { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        case .names:
            let names = Set(items)
            return { names.contains($0.lowercased()) }
        case .extensions:
            let extensions = Set(items.map { $0.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
            return { extensions.contains(($0 as NSString).pathExtension.lowercased()) }
        }
    }

    private static func standard(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Why the job cannot be saved, or nil when it can.
    public static func problem(_ job: Job, fromIsFolder: Bool) -> String? {
        if job.from.isEmpty { return "Choose what to transfer." }
        if job.to.isEmpty { return "Choose where it goes." }
        let from = standard(job.from), to = standard(job.to)
        if from == to { return "FROM and WHERE are the same folder." }
        if to.hasPrefix(from + "/") { return "WHERE is inside FROM, so the job would copy into itself." }
        // Copy or cut into the folder that already holds FROM would write the files onto themselves.
        if job.operation != .zip && (from as NSString).deletingLastPathComponent == to { return "FROM is already in WHERE." }
        if job.schedule.kind == .weekly && job.schedule.weekdays.isEmpty { return "Pick at least one day." }
        if fromIsFolder && job.selection != .whole {
            if job.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Type what to match, like \(job.selection.prompt)." }
            do { _ = try matcher(job.selection, job.pattern) } catch { return "The regex is not valid." }
        }
        return nil
    }

    /// Lists what the job takes from disk now. Filters search all subfolders and never match hidden files.
    public static func plan(_ job: Job) throws -> Plan {
        let manager = FileManager.default
        var isFolder: ObjCBool = false
        guard manager.fileExists(atPath: job.from, isDirectory: &isFolder) else {
            throw Failure("\((job.from as NSString).lastPathComponent) is not there any more.")
        }
        let name = (job.from as NSString).lastPathComponent
        guard isFolder.boolValue else {
            let size = (try? manager.attributesOfItem(atPath: job.from)[.size] as? Int64) ?? 0
            return Plan(source: (job.from as NSString).deletingLastPathComponent, destination: job.to, files: [name], bytes: size)
        }
        let whole = job.selection == .whole
        let matches = try matcher(job.selection, job.pattern)
        var plan = Plan(source: job.from, destination: (job.to as NSString).appendingPathComponent(name), files: [], bytes: 0)
        guard let walk = manager.enumerator(atPath: job.from) else { throw Failure("Can't read \(name).") }
        while let path = walk.nextObject() as? String {
            let file = (path as NSString).lastPathComponent
            let folder = walk.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            if isJunk(file) || (!whole && file.hasPrefix(".")) {
                if folder { walk.skipDescendants() }
                continue
            }
            if folder {
                if whole { plan.folders.append(path) }
            } else if whole || matches(file) {
                plan.files.append(path)
                plan.bytes += (walk.fileAttributes?[.size] as? Int64) ?? 0
            }
        }
        return plan
    }

    /// Files whose name is taken in the destination by a file with other content (size or date).
    /// The same file already there is no clash: rsync skips it.
    public static func clashes(_ plan: Plan) -> Set<String> {
        let manager = FileManager.default
        return Set(plan.files.filter { path in
            guard let there = try? manager.attributesOfItem(atPath: (plan.destination as NSString).appendingPathComponent(path)),
                  let here = try? manager.attributesOfItem(atPath: (plan.source as NSString).appendingPathComponent(path)) else { return false }
            let a = here[.modificationDate] as? Date ?? .distantPast, b = there[.modificationDate] as? Date ?? .distantPast
            return here[.size] as? Int64 != there[.size] as? Int64 || abs(a.timeIntervalSince(b)) >= 1
        })
    }

    /// The first free name in Finder style: "photo.jpg" -> "photo 2.jpg", "photo 3.jpg"…
    public static func freeName(for path: String, exists: (String) -> Bool) -> String {
        guard exists(path) else { return path }
        let folder = (path as NSString).deletingLastPathComponent
        let file = (path as NSString).lastPathComponent
        let ext = (file as NSString).pathExtension, base = (file as NSString).deletingPathExtension
        for number in 2... {
            let candidate = (folder as NSString).appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            if !exists(candidate) { return candidate }
        }
        return path
    }

    /// "Photos 2026-10-28.zip"; a file loses its extension: "report 2026-10-28.zip".
    public static func zipName(from: String, isFolder: Bool, date: Date) -> String {
        let name = (from as NSString).lastPathComponent
        return "\(isFolder ? name : (name as NSString).deletingPathExtension) \(date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())).zip"
    }

    /// rsync for the paths listed in `list`. `modern` is rsync 3 (Homebrew), with one progress line for the whole job.
    /// shortcut: -lt keeps links and dates, not owners or permissions, so exFAT drives work; add -p if executables must stay executable.
    public static func rsyncArguments(list: String, source: String, destination: String, cut: Bool, modern: Bool) -> [String] {
        ["-lt", "--files-from=\(list)", "--out-format=%n"]
            + (modern ? ["--info=progress2"] : [])
            + (cut ? ["--remove-source-files"] : [])
            + [source + "/", destination + "/"]
    }

    /// The whole-job percent of an rsync 3 `--info=progress2` line: "  30,000,003  45%  12.34MB/s  0:01:23 …".
    public static func progress(in line: String) -> Double? {
        guard let match = line.firstMatch(of: /^\s*[\d,]+\s+(\d{1,3})%\s/), let value = Double(match.1) else { return nil }
        return min(value, 100) / 100
    }

    /// Seconds left at the current pace; nil until there is enough to go on.
    public static func remaining(fraction: Double, elapsed: TimeInterval) -> TimeInterval? {
        guard fraction > 0.02, fraction < 1, elapsed > 2 else { return nil }
        return elapsed * (1 - fraction) / fraction
    }

    /// After a cut: removes folders that hold nothing but macOS clutter, deepest first.
    /// Returns true when `path` itself was removed.
    @discardableResult
    public static func removeEmptyFolders(_ path: String, includingSelf: Bool) -> Bool {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: path) else { return false }
        var empty = true
        for name in names where !isJunk(name) {
            let child = (path as NSString).appendingPathComponent(name)
            // attributesOfItem does not follow links, so a link to a folder is never walked.
            let folder = (try? manager.attributesOfItem(atPath: child)[.type] as? FileAttributeType) == .typeDirectory
            if !(folder && removeEmptyFolders(child, includingSelf: true)) { empty = false }
        }
        guard empty && includingSelf else { return false }
        return (try? manager.removeItem(atPath: path)) != nil
    }

    /// The volume a job needs that is not connected now, like "Backup" for /Volumes/Backup/…
    public static func missingVolume(_ job: Job, exists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> String? {
        for path in [job.from, job.to] {
            let parts = path.split(separator: "/")
            if parts.count >= 2, parts[0] == "Volumes", !exists("/Volumes/\(parts[1])") { return String(parts[1]) }
        }
        return nil
    }
}
