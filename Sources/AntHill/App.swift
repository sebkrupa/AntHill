import AppKit
import SwiftUI
import AntHillKit

// AntHill
//   AntHill                      the app
//   APP_STORE=<file> AntHill     test run: settings go to a separate defaults suite
//   APP_SNAPSHOT=<dir> AntHill   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 AntHill           fill the YT-Music queue with sample items (tools/snap.sh)
//   AntHill --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> AntHill      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 AntHill           draw the 8 pt grid and the layout probes over the window

@main
struct AntHillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("AntHill", id: "main") {
            ContentView()
                .environment(model)
                .onAppear { AppDelegate.model = model }
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 720)
        // Closing to the menu bar must not make the next launch start without a window.
        .defaultLaunchBehavior(.presented)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await model.updates.check(userAsked: true) } }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            SidebarCommands()
            ToolbarCommands()
            CommandMenu("YT-Music") {
                Button("Clear Finished") { model.music.clearFinished() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(!model.music.hasFinished)
                Button("Change Download Folder…") { model.music.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button((model.music.issue?.fixTitle ?? "Fix Problem") + "…") {
                    model.sidebar = .ytMusic
                    model.music.showsFix = true
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(model.music.issue == nil)
                Button("Retry Failed") { model.music.retryFailed() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!model.music.hasFailed)
                Divider()
                Button("Show Downloads") {
                    model.sidebar = .ytMusic
                    model.musicPage = .downloads
                }
                .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Show Library") {
                    model.sidebar = .ytMusic
                    model.musicPage = .library
                }
                .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Run \(model.library.tasksTitle)") {
                    model.sidebar = .ytMusic
                    model.musicPage = .library
                    model.library.start(with: model.llama)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.llama.available || model.library.running || model.library.tracks.isEmpty || model.library.tasks.isEmpty)
                Menu("Library Tasks") {
                    ForEach(Library.Task.allCases) { task in
                        Toggle(task.title, isOn: Binding(
                            get: { model.library.tasks.contains(task) },
                            set: { if $0 { model.library.tasks.insert(task) } else { model.library.tasks.remove(task) } }
                        ))
                    }
                }
                .disabled(model.library.running)
                Button("Stop Library Task") { model.library.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.library.running)
            }
            CommandMenu("Shop Check") {
                Button("Check Again") {
                    model.sidebar = .shopCheck
                    model.shopChecks.checkAgain()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(model.shopChecks.selected == nil || model.shopChecks.running != nil)
                Button("Remove Report") {
                    if let id = model.shopChecks.selection { model.shopChecks.remove(id) }
                }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(model.shopChecks.selected == nil)
                Button("Clear History…") {
                    model.sidebar = .shopCheck
                    model.shopChecks.confirmsClear = true
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.shopChecks.reports.isEmpty)
            }
            CommandMenu("Network") {
                Button(model.network.paused ? "Resume Updates" : "Pause Updates") {
                    model.sidebar = .network
                    model.network.paused.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Refresh Now") {
                    model.sidebar = .network
                    Task { await model.network.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
            }
        }

        // The menu bar icon stays while the window is closed; Quit lives here.
        MenuBarExtra("AntHill", systemImage: "ant.fill") {
            MenuBarContent()
                .environment(model)
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app so quit can stop running downloads.
    static var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            // The closing window is still visible now; look on the next turn of the run loop.
            Task { @MainActor in self.leaveDockIfNoWindow() }
        }
    }

    /// Closing the window keeps the app running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// With no window left, the app leaves the Dock and lives only in the menu bar.
    /// Checked after a window closes, never while one is opening, or the new window loses focus.
    private func leaveDockIfNoWindow() {
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        Self.model?.music.stopAll()
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}
