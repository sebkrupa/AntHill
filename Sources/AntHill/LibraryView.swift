import SwiftUI
import AntHillKit

/// YT-Music > Library: the Music.app songs, a task for the local model, and Run.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var choosingTasks = false
    @State private var sortOrder = [KeyPathComparator(\Row.name)]

    private var library: MusicLibrary { model.library }

    var body: some View {
        @Bindable var library = library
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Button { choosingTasks.toggle() } label: {
                    Label(library.tasksTitle, systemImage: "chevron.down")
                        .labelStyle(TrailingIcon())
                }
                .fixedSize()
                .disabled(library.running)
                .help("The checks Run does, all in one pass")
                .popover(isPresented: $choosingTasks, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ForEach(Library.Task.allCases) { task in
                            Toggle(task.title, isOn: Binding(
                                get: { library.tasks.contains(task) },
                                set: { if $0 { library.tasks.insert(task) } else { library.tasks.remove(task) } }
                            ))
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(Space.md)
                    .noInitialFocus()
                }
                if let progress = library.progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 160)
                    Text("\(progress.done) of \(progress.total)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Stop", systemImage: "stop.fill") { library.stop() }
                } else {
                    Button("Run", systemImage: "play.fill") { library.start(with: model.llama) }
                        .buttonStyle(.borderedProminent)
                        .disabled(library.tracks.isEmpty || library.tasks.isEmpty || !model.llama.available)
                        .help("Ask \(model.llama.model ?? "the model") about every song for all checked tasks, then review the changes")
                    Text(library.selection.isEmpty ? "All \(library.tracks.count) songs" : "\(library.selection.count) selected songs")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reload", systemImage: "arrow.clockwise") { library.load() }
                    .labelStyle(.iconOnly)
                    .help("Read the songs from Music again")
                    .disabled(library.running || library.loading)
            }
            .font(.callout)
            .padding(Space.margin)
            .gridArea("header")
            if !model.llama.available {
                HStack(spacing: Space.sm) {
                    Label("Corrections and cleanups need a local model. Connect llama.cpp in Settings to run them.",
                          systemImage: "cpu")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Model Settings…") {
                        model.settingsTab = .models
                        openSettings()
                    }
                }
                .font(.callout)
                .padding([.horizontal, .bottom], Space.margin)
            }
            if let error = library.error, !library.tracks.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom], Space.margin)
            }
            Divider()
            Table(rows, selection: $library.selection, sortOrder: $sortOrder) {
                TableColumn("Cleaned", value: \.cleaned) { row in
                    if row.cleaned == 1 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help("Cleaned")
                            .accessibilityLabel("Cleaned")
                    }
                }
                .width(56)
                TableColumn("Name", value: \.name)
                TableColumn("Artist", value: \.artist)
                TableColumn("Album", value: \.album)
                TableColumn("Log", value: \.log) { row in
                    Text(row.log)
                        .foregroundStyle(.secondary)
                        .help(row.log)
                }
            }
            .overlay { empty }
        }
        .task { if library.tracks.isEmpty { library.load() } }
        .sheet(isPresented: Binding(get: { library.changes != nil }, set: { if !$0, library.changes != nil { library.discard() } })) {
            ReviewSheet()
        }
    }

    /// Title first, then the icon, like a pull-down button.
    struct TrailingIcon: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: Space.xs) {
                configuration.title
                configuration.icon.imageScale(.small)
            }
        }
    }

    /// One song in the list with what the last run did to it, sortable by every column.
    nonisolated struct Row: Identifiable, Sendable {
        let track: Library.Track
        let note: MusicLibrary.Note?
        var id: String { track.id }
        var name: String { track.name }
        var artist: String { track.artist }
        var album: String { track.album }
        var cleaned: Int { note?.cleaned == true ? 1 : 0 }
        var log: String { note?.log ?? "" }
    }

    private var rows: [Row] {
        library.tracks.map { Row(track: $0, note: library.notes[$0.id]) }.sorted(using: sortOrder)
    }

    @ViewBuilder private var empty: some View {
        if library.loading {
            ProgressView("Reading Music…")
        } else if library.tracks.isEmpty, let error = library.error {
            ContentUnavailableView {
                Label("Can’t Read Music", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                if library.needsAccess { Button("Open Automation Settings") { library.openAutomationSettings() } }
                Button("Try Again") { library.load() }
            }
        } else if library.tracks.isEmpty {
            ContentUnavailableView("No Songs", systemImage: "music.note.list",
                                   description: Text("Music has no downloaded songs yet."))
        }
    }
}

/// The model's proposed changes as checkboxes. Apply does the checked ones in Music.
struct ReviewSheet: View {
    @Environment(AppModel.self) private var model

    private var library: MusicLibrary { model.library }

    var body: some View {
        let changes = library.changes ?? []
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(library.tasksTitle).font(.headline)
                Text(changes.isEmpty ? "The model found nothing to change." : "\(library.chosen.count) of \(changes.count) changes chosen")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !changes.isEmpty {
                List(changes) { change in
                    Toggle(isOn: Binding(
                        get: { library.chosen.contains(change.id) },
                        set: { if $0 { library.chosen.insert(change.id) } else { library.chosen.remove(change.id) } }
                    )) {
                        ChangeRow(change: change)
                    }
                    .toggleStyle(.checkbox)
                }
                .fitsContent(max: 420)
            }
            HStack {
                Spacer()
                if changes.isEmpty {
                    Button("Done") { library.changes = nil }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", role: .cancel) { library.discard() }
                        .keyboardShortcut(.cancelAction)
                    Button("Apply \(library.chosen.count) Changes") { library.apply() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(library.chosen.isEmpty)
                }
            }
        }
        .padding(Space.margin)
        .frame(width: 640)
        .gridArea("review")
        .noInitialFocus()
    }
}

/// One proposed change: the song as it is, and what the model wants.
struct ChangeRow: View {
    let change: Library.Change

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(change.track.name).lineLimit(1)
            let details = [change.track.artist, change.track.album].filter { !$0.isEmpty }.joined(separator: " – ")
            if !details.isEmpty {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            switch change.kind {
            case .edit(let name, let artist, let album):
                Label([name, artist, album].filter { !$0.isEmpty }.joined(separator: " – "), systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(.tint)
            case .trash(let kept):
                Label("Move to Trash, keep “\(kept.name)”", systemImage: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, Space.xs)
    }
}
