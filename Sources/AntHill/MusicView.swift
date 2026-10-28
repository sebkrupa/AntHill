import SwiftUI
import AntHillKit

/// YT-Music: paste a link, press Return, watch the queue.
struct MusicView: View {
    @Environment(AppModel.self) private var model
    @State private var link = ""
    @State private var selection: DownloadItem.ID?
    @FocusState private var fieldFocused: Bool

    private var queue: MusicQueue { model.music }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.md) {
                TextField("Paste a YouTube link and press Return", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($fieldFocused)
                    .onSubmit {
                        if queue.add(link) { link = "" }
                        fieldFocused = true
                    }
                HStack(spacing: Space.sm) {
                    Label(queue.folder, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(queue.folder)
                    Button("Change…") { queue.chooseFolder() }
                    Spacer()
                    Button("Clear Finished") { queue.clearFinished() }
                        .disabled(!queue.hasFinished)
                }
                .font(.callout)
            }
            .padding(Space.margin)
            .gridArea("header")
            Divider()
            list
        }
        .navigationTitle(Module.ytMusic.title)
    }

    private var list: some View {
        List(queue.items, selection: $selection) { item in
            DownloadRow(item: item)
                .contextMenu {
                    if item.status == .done { Button("Show in Finder") { queue.reveal(item) } }
                    if item.canPause { Button(item.status == .paused ? "Resume" : "Pause") { queue.togglePause(item) } }
                    Button("Remove") { queue.remove(item) }
                }
        }
        .contextMenu(forSelectionType: DownloadItem.ID.self) { _ in } primaryAction: { ids in
            for item in queue.items where ids.contains(item.id) && item.status == .done { queue.reveal(item) }
        }
        .onDeleteCommand {
            if let item = queue.items.first(where: { $0.id == selection }) { queue.remove(item) }
        }
        .overlay {
            if queue.items.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: Module.ytMusic.symbol,
                                       description: Text("Paste a YouTube link above and press Return."))
            }
        }
    }
}

struct DownloadRow: View {
    @Environment(AppModel.self) private var model
    @State private var showsLog = false
    let item: DownloadItem

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                status
                if item.status == .downloading && item.stage > .download {
                    // ffmpeg reports no percent, so the bar only shows that work goes on.
                    ProgressView().progressViewStyle(.linear).controlSize(.small)
                } else if item.status == .downloading || (item.status == .paused && item.progress > 0) {
                    ProgressView(value: item.progress)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: Space.sm)
            if item.canPause {
                Button(item.status == .paused ? "Resume" : "Pause",
                       systemImage: item.status == .paused ? "play.fill" : "pause.fill") {
                    model.music.togglePause(item)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            Button("Log", systemImage: "doc.text") { showsLog.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show what yt-dlp does")
                .disabled(item.status == .waiting)
                .popover(isPresented: $showsLog, arrowEdge: .bottom) { DownloadLog(item: item) }
            Button("Remove", systemImage: "xmark.circle.fill") { model.music.remove(item) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Space.xs)
    }

    @ViewBuilder private var status: some View {
        switch item.status {
        case .waiting: Text("Waiting").font(.caption).foregroundStyle(.secondary)
        case .downloading:
            Text(item.stage > .download ? "\(item.stage.title)…" : "Downloading \(Int(item.progress * 100))%")
                .font(.caption).foregroundStyle(.secondary)
        case .paused: Text("Paused").font(.caption).foregroundStyle(.secondary)
        case .done: Label("Done", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .failed(let message): Text(message).font(.caption).foregroundStyle(.red).lineLimit(1).help(message)
        }
    }
}

/// The Log popover: the stages as a checklist, the error in plain words, and the raw yt-dlp output.
struct DownloadLog: View {
    let item: DownloadItem
    @State private var showsRaw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(YTMusic.Stage.allCases, id: \.self) { stage in
                        let state = state(of: stage)
                        Label {
                            Text(stage == .download && state == .running
                                 ? "\(stage.title) (\(Int(item.progress * 100))%)" : stage.title)
                                .foregroundStyle(state == .waiting ? .secondary : .primary)
                        } icon: {
                            Image(systemName: state.symbol).foregroundStyle(state.color)
                        }
                    }
                }
                if case .failed(let message) = item.status {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Error").font(.headline)
                        Text(message).textSelection(.enabled)
                    }
                }
                DisclosureGroup("yt-dlp output", isExpanded: $showsRaw) {
                    Text(item.log.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 480, height: showsRaw ? 480 : 340)
    }

    private enum StageState {
        case done, running, failed, waiting

        var symbol: String {
            switch self {
            case .done: "checkmark.circle.fill"
            case .running: "circle.dotted.circle.fill"
            case .failed: "xmark.circle.fill"
            case .waiting: "circle"
            }
        }

        var color: Color {
            switch self {
            case .done: .green
            case .running: .yellow
            case .failed: .red
            case .waiting: .secondary
            }
        }
    }

    private func state(of stage: YTMusic.Stage) -> StageState {
        if item.status == .done { return .done }
        if stage < item.stage { return .done }
        if stage > item.stage { return .waiting }
        switch item.status {
        case .failed: return .failed
        case .downloading, .paused: return .running
        default: return .waiting
        }
    }
}
