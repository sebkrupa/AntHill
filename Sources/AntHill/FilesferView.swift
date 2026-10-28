import AppKit
import SwiftUI
import AntHillKit

/// Filesfer: saved jobs that copy, move, or zip files to another folder. Run one, or Run All.
struct FilesferView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var transfers = model.transfers
        List(transfers.jobs, selection: $transfers.selection) { job in
            JobRow(job: job)
                .contextMenu {
                    if transfers.isBusy(job.id) {
                        Button("Stop") { transfers.stop(job.id) }
                    } else {
                        Button("Run") { transfers.run(job.id) }
                    }
                    Button("Edit…") { transfers.edit(job.id) }
                    Button("Delete") { transfers.remove(job.id) }
                }
        }
        .contextMenu(forSelectionType: Filesfer.Job.ID.self) { _ in } primaryAction: { ids in
            if let id = ids.first { transfers.edit(id) }
        }
        .onDeleteCommand {
            if let id = transfers.selection { transfers.remove(id) }
        }
        .overlay {
            if transfers.jobs.isEmpty {
                ContentUnavailableView {
                    Label("No Transfer Jobs", systemImage: Module.filesfer.symbol)
                } description: {
                    Text("A job copies, moves, or zips files to another folder, by hand or on a schedule.")
                } actions: {
                    Button("New Job") { transfers.newJob() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !transfers.rsync.modern {
                Label("Install Homebrew rsync to see the time left: brew install rsync", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(Space.md)
            }
        }
        .navigationTitle(Module.filesfer.title)
        .toolbar {
            ToolbarItem {
                Button("New Job", systemImage: "plus") { transfers.newJob() }
                    .help("New Job (⌘N)")
            }
            ToolbarItem {
                if transfers.running {
                    Button("Stop All", systemImage: "stop.fill") { transfers.stopAll() }
                        .labelStyle(.titleAndIcon)
                } else {
                    Button("Run All", systemImage: "play.fill") { transfers.runAll() }
                        .labelStyle(.titleAndIcon)
                        .disabled(transfers.jobs.isEmpty)
                }
            }
        }
        .sheet(item: $transfers.editing) { JobSheet(job: $0) }
    }
}

extension Filesfer.Operation {
    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .cut: "scissors"
        case .zip: "doc.zipper"
        }
    }
}

struct JobRow: View {
    @Environment(AppModel.self) private var model
    let job: Filesfer.Job

    var body: some View {
        let transfers = model.transfers
        HStack(spacing: Space.md) {
            Image(systemName: job.operation.symbol)
                .foregroundStyle(.tint)
                .frame(width: Space.xl)
                .help(job.operation.title)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(job.title).lineLimit(1)
                Text("\(job.from) → \(job.to)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("\(job.from) → \(job.to)")
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                state
            }
            Spacer(minLength: Space.sm)
            if transfers.isBusy(job.id) {
                Button("Stop", systemImage: "stop.fill") { transfers.stop(job.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Stop this job")
            } else {
                Button("Run", systemImage: "play.fill") { transfers.run(job.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Run this job now")
            }
        }
        .padding(.vertical, Space.xs)
    }

    /// "Copy · 142 files · 3.2 GB · Next: today 22:00"
    private var details: String {
        var parts = [job.operation.title]
        if let preview = model.transfers.previews[job.id] { parts.append(preview) }
        if let next = job.nextRun { parts.append("Next: " + Self.when(next)) }
        return parts.joined(separator: " · ")
    }

    static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if date <= .now { return "now" }
        if Calendar.current.isDateInToday(date) { return "today \(time)" }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow \(time)" }
        return date.formatted(.dateTime.weekday(.wide).day().month()) + " \(time)"
    }

    @ViewBuilder private var state: some View {
        let transfers = model.transfers
        if let run = transfers.current, run.id == job.id {
            if let fraction = run.fraction {
                ProgressView(value: fraction).controlSize(.small)
            } else {
                ProgressView().progressViewStyle(.linear).controlSize(.small)
            }
            Text(Transfers.progressText(run)).font(.caption).foregroundStyle(.secondary)
        } else if transfers.isBusy(job.id) {
            Text("Waiting").font(.caption).foregroundStyle(.secondary)
        } else if let volume = transfers.waitingForDisk[job.id] {
            Label("Waiting for \(volume)", systemImage: "externaldrive.badge.questionmark")
                .font(.caption).foregroundStyle(.secondary)
        } else if let last = job.last {
            if let error = last.error {
                HStack(spacing: Space.sm) {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(1).help(error)
                    if last.permission {
                        Button("Open Privacy Settings") { transfers.openPrivacySettings() }
                            .controlSize(.small)
                    }
                }
            } else {
                Label("Done \(last.date.formatted(date: .abbreviated, time: .shortened)) · \(last.files) \(last.files == 1 ? "file" : "files") · "
                      + Duration.seconds(last.seconds.rounded()).formatted(.units(width: .narrow)),
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }
}

/// New Job and Edit: FROM, WHERE, what to do, which files, and when.
struct JobSheet: View {
    @Environment(AppModel.self) private var model
    @State var job: Filesfer.Job

    private var fromIsFolder: Bool {
        var folder: ObjCBool = true
        return !FileManager.default.fileExists(atPath: job.from, isDirectory: &folder) || folder.boolValue
    }

    private var problem: String? { Filesfer.problem(job, fromIsFolder: fromIsFolder) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $job.name, prompt: Text(job.defaultName))
                    path("From", job.from, prompt: "A file or a folder") { choose(files: true) { job.from = $0 } }
                    path("Where", job.to, prompt: "A folder") { choose(files: false) { job.to = $0 } }
                }
                Section {
                    Picker("Operation", selection: $job.operation) {
                        ForEach(Filesfer.Operation.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("If a file exists", selection: $job.conflict) {
                        ForEach(Filesfer.Conflict.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text(job.conflict == .keepBoth ? "A changed file is copied as “name 2”. The same file is skipped."
                         : "A file with the same name is replaced.")
                        .foregroundStyle(.secondary)
                }
                if fromIsFolder {
                    Section("Files") {
                        Picker("Take", selection: $job.selection) {
                            ForEach(Filesfer.Selection.allCases) { Text($0.title).tag($0) }
                        }
                        if job.selection != .whole {
                            TextField(job.selection.title, text: $job.pattern, prompt: Text(job.selection.prompt))
                        }
                    }
                }
                Section("Schedule") {
                    Picker("Run", selection: $job.schedule.kind) {
                        ForEach(Filesfer.Schedule.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    switch job.schedule.kind {
                    case .off: EmptyView()
                    case .hours:
                        Stepper("Every \(job.schedule.hours) hours", value: $job.schedule.hours, in: 1...168)
                    case .daily, .weekly:
                        if job.schedule.kind == .weekly { weekdays }
                        DatePicker("At", selection: time, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent()
            HStack(spacing: Space.sm) {
                // Empty paths need no red text; the disabled Save says enough.
                if let problem, !job.from.isEmpty, !job.to.isEmpty {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.transfers.editing = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { model.transfers.commit(job) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
            .padding(Space.margin)
        }
        .frame(width: 520)
        .noInitialFocus()
    }

    private func path(_ title: String, _ value: String, prompt: String, choose: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: Space.sm) {
                Text(value.isEmpty ? prompt : value)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(value)
                Button("Choose…", action: choose)
            }
        }
    }

    private var weekdays: some View {
        let calendar = Calendar.current
        // Weekdays in the order of the person's calendar, Monday first in Poland.
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return LabeledContent("On") {
            HStack(spacing: Space.xs) {
                ForEach(order, id: \.self) { day in
                    Toggle(calendar.veryShortWeekdaySymbols[day - 1], isOn: Binding(
                        get: { job.schedule.weekdays.contains(day) },
                        set: { if $0 { job.schedule.weekdays.insert(day) } else { job.schedule.weekdays.remove(day) } }
                    ))
                    .toggleStyle(.button)
                    .help(calendar.weekdaySymbols[day - 1])
                }
            }
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: job.schedule.hour, minute: job.schedule.minute, second: 0, of: .now) ?? .now },
            set: {
                job.schedule.hour = Calendar.current.component(.hour, from: $0)
                job.schedule.minute = Calendar.current.component(.minute, from: $0)
            }
        )
    }

    private func choose(files: Bool, _ done: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = files
        panel.canCreateDirectories = !files
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { done(url.path) }
    }
}
