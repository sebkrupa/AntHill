import SwiftUI

/// The menu bar menu: one submenu of quick actions per module, then Open and Quit.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(model.menuBarModules) { module in
            Menu {
                ModuleMenu(module: module)
            } label: {
                Label(module.title, systemImage: module.symbol)
            }
        }
        Divider()
        if let release = model.updates.available {
            Button(model.updates.installing ? "Installing AntHill \(release.version)…" : "Install AntHill \(release.version) and Relaunch") { model.updates.install() }
                .disabled(model.updates.installing)
        }
        Button("Open AntHill") {
            // Back in the Dock first, or the window opens behind other apps.
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            // The window exists only after openWindow returns; bring it up on the next turn.
            Task { @MainActor in
                NSApp.activate()
                let window = NSApp.windows.first { $0.identifier?.rawValue == "main" }
                    ?? NSApp.windows.first { $0.canBecomeMain }
                window?.deminiaturize(nil)
                window?.makeKeyAndOrderFront(nil)
            }
        }
        Button("Quit AntHill") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Quick actions per module. Add a case here when you add one to `Module`.
struct ModuleMenu: View {
    @Environment(AppModel.self) private var model
    let module: Module

    var body: some View {
        switch module {
        case .ytMusic:
            Button("Paste Link") { model.music.addFromClipboard() }
        case .shopCheck:
            Button("Check Copied Address") {
                model.sidebar = .shopCheck
                model.shopChecks.check(NSPasteboard.general.string(forType: .string) ?? "")
            }
            .disabled(model.shopChecks.running != nil)
        case .network:
            Button(model.network.paused ? "Resume Updates" : "Pause Updates") { model.network.paused.toggle() }
        case .filesfer:
            if let status = model.transfers.status { Text(status) }
            Button("Run All") { model.transfers.runAll() }
                .disabled(model.transfers.jobs.isEmpty)
            Button("Stop") { model.transfers.stopAll() }
                .disabled(!model.transfers.running)
        case .netLock:
            Text(model.netLock.status)
            Button(model.netLock.isOn ? "Unlock Network" : "Lock Network") { model.netLock.toggle() }
                .disabled(model.netLock.busy)
        }
    }
}
