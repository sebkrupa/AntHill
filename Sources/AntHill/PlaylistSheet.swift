import SwiftUI
import AntHillKit

/// The songs of a pasted playlist link as checkboxes. Download queues the checked ones.
struct PlaylistSheet: View {
    @Environment(AppModel.self) private var model
    let pick: PlaylistPick

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Playlist").font(.headline)
                    Text(pick.loading ? "Reading the playlist…" : "\(pick.chosen.count) of \(pick.entries.count) songs chosen")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !pick.entries.isEmpty {
                    Button("Select All") { pick.chosen = Set(pick.entries.map(\.id)) }
                        .keyboardShortcut("a")
                    Button("Select None") { pick.chosen = [] }
                        .keyboardShortcut("a", modifiers: [.command, .shift])
                }
            }
            if let error = pick.error {
                if let issue = pick.issue {
                    IssueFixView(issue: issue)
                } else {
                    ContentUnavailableView("No Songs", systemImage: "music.note.list", description: Text(error))
                }
            } else if pick.entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    // A wrapping grid: as many columns as fit the sheet.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Space.lg, alignment: .leading)],
                              alignment: .leading, spacing: Space.sm) {
                        ForEach(pick.entries, id: \.id) { entry in
                            Toggle(isOn: Binding(
                                get: { pick.chosen.contains(entry.id) },
                                set: { if $0 { pick.chosen.insert(entry.id) } else { pick.chosen.remove(entry.id) } }
                            )) {
                                Text(entry.title).lineLimit(1).truncationMode(.middle)
                            }
                            .toggleStyle(.checkbox)
                            .help(entry.title)
                        }
                    }
                }
                .fitsContent(max: 420)
            }
            HStack {
                if pick.loading && !pick.entries.isEmpty { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { model.music.closePlaylist() }
                    .keyboardShortcut(.cancelAction)
                Button("Download \(pick.chosen.count) Songs", systemImage: "play.fill") { model.music.downloadPlaylist() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pick.chosen.isEmpty || pick.loading)
            }
        }
        .padding(Space.margin)
        .frame(width: 640)
        .gridArea("playlist")
        .noInitialFocus()
    }
}
