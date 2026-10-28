import SwiftUI
import AntHillKit

/// Network Monitor: pick an app or type its name; its connections show below and update every 2 seconds.
struct NetworkView: View {
    @Environment(AppModel.self) private var model

    private var watch: NetworkWatch { model.network }

    var body: some View {
        @Bindable var watch = watch
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    Picker("App", selection: $watch.name) {
                        Text("Choose…").tag("")
                        // A typed name that has no connections now still shows as chosen.
                        ForEach(Set(watch.apps + [watch.name]).filter { !$0.isEmpty }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
                                id: \.self) { Text($0).tag($0) }
                    }
                    .fixedSize()
                    TextField("or type an app name, like ollama", text: $watch.name)
                        .textFieldStyle(.roundedBorder)
                    Button(watch.paused ? "Resume" : "Pause", systemImage: watch.paused ? "play.fill" : "pause.fill") {
                        watch.paused.toggle()
                    }
                    .help(watch.paused ? "Update the connections every 2 seconds again" : "Stop updating the connections")
                }
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(watch.error == nil ? .secondary : Color.red)
            }
            .padding(Space.margin)
            .gridArea("header")
            Divider()
            Table(watch.connections) {
                TableColumn("Process") { Text("\($0.command) (\($0.pid))") }
                TableColumn("Protocol") { Text("\($0.proto) \($0.family)") }
                    .width(min: 80, ideal: 96)
                TableColumn("Local Address", value: \.local)
                TableColumn("Remote Address") { Text($0.remote.isEmpty ? "—" : $0.remote) }
                TableColumn("State") { connection in
                    Text(connection.state.isEmpty ? "—" : connection.state)
                        .foregroundStyle(connection.state == "ESTABLISHED" ? Color.green : .secondary)
                }
                .width(min: 80, ideal: 112)
            }
            .overlay { empty }
        }
        .navigationTitle(Module.network.title)
        .onAppear { watch.start() }
        .onDisappear { watch.stop() }
    }

    private var summary: String {
        if let error = watch.error { return error }
        let connections = watch.connections
        let established = connections.filter { $0.state == "ESTABLISHED" }.count
        let listening = connections.filter { $0.state == "LISTEN" }.count
        let time = watch.updated.map { " Updated \($0.formatted(date: .omitted, time: .standard))." } ?? ""
        let state = watch.paused ? " Paused." : ""
        return "\(connections.count) connections: \(established) established, \(listening) listening.\(time)\(state)"
    }

    @ViewBuilder private var empty: some View {
        if watch.name.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView("Choose an App", systemImage: Module.network.symbol,
                                   description: Text("Pick an app from the list or type its name. Its network connections show here."))
        } else if watch.connections.isEmpty {
            ContentUnavailableView("No Connections", systemImage: "network.slash",
                                   description: Text("No app named like “\(watch.name)” has a network connection right now. Apps of other users don’t show."))
        }
    }
}
