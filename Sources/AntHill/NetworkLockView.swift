import SwiftUI
import AntHillKit

/// Network Lock: an allow list (only these apps keep the network) and a block list (only these
/// apps lose it), a picker for which one the lock uses, and one button that locks.
struct NetworkLockView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()

    private var lock: NetworkLock { model.netLock }

    var body: some View {
        @Bindable var lock = lock
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    Label(lock.status, systemImage: lock.isOn ? "lock.fill" : "lock.open")
                        .font(.title3)
                        .foregroundStyle(lock.isOn ? Palette.accentText : .primary)
                    Spacer()
                    if lock.busy { ProgressView().controlSize(.small) }
                    if lock.isOn {
                        Button("Unlock", systemImage: "lock.open") { lock.unlock() }
                            .disabled(lock.busy)
                        if lock.hasChanges {
                            Button("Apply Changes") { lock.lock() }
                                .buttonStyle(.borderedProminent)
                                .disabled(lock.busy)
                        }
                    } else {
                        Button("Lock Network", systemImage: "lock.fill") { lock.lock() }
                            .buttonStyle(.borderedProminent)
                            .disabled(lock.busy || !lock.canLock)
                    }
                }
                Picker("List", selection: $lock.mode) {
                    Text("Allow List").tag(NetLock.Mode.allow)
                    Text("Block List").tag(NetLock.Mode.block)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: lock.mode) { selection = [] }
                Text(lock.mode == .allow
                     ? "While locked, only the apps below have network, with the apps they start. Everything else is blocked, system services included; only DNS lookups pass. The lock stays on after AntHill quits, until you unlock or restart the Mac."
                     : "While locked, only the apps below lose the network, with the apps they start. Everything else keeps it. The lock stays on after AntHill quits, until you unlock or restart the Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let error = lock.error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .padding(Space.margin)
            .gridArea("header")
            Divider()
            List(selection: $selection) {
                ForEach(lock.apps, id: \.self) { path in
                    Label {
                        Text(URL(filePath: path).deletingPathExtension().lastPathComponent)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: Space.lg, height: Space.lg)
                    }
                    .help(path)
                }
            }
            .onDeleteCommand { lock.remove(selection) }
            .overlay {
                if lock.apps.isEmpty {
                    if lock.mode == .allow {
                        ContentUnavailableView("No Allowed Apps", systemImage: Module.netLock.symbol,
                                               description: Text("Locking now blocks every app. Add the apps that should keep the network."))
                    } else {
                        ContentUnavailableView("No Blocked Apps", systemImage: Module.netLock.symbol,
                                               description: Text("Add the apps that should lose the network, then lock."))
                    }
                }
            }
        }
        .navigationTitle(Module.netLock.title)
        .toolbar {
            ToolbarItem {
                Button("Add App", systemImage: "plus") { lock.chooseApps() }
                    .help("Add App (⌥⌘A)")
            }
            ToolbarItem {
                Button("Remove App", systemImage: "minus") { lock.remove(selection) }
                    .help("Remove the selected apps (Delete)")
                    .disabled(selection.isEmpty)
            }
        }
        .onAppear { lock.refresh() }
    }
}
