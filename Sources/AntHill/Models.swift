import Foundation

/// The modules in the sidebar. Snapshot mode walks through every case.
/// A new module: add a case here and its view in `ModuleView`.
enum Module: String, CaseIterable, Identifiable {
    case ytMusic = "yt-music"
    case shopCheck = "shop-check"
    case network = "network"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ytMusic: "YT-Music"
        case .shopCheck: "eCommerce Security Check"
        case .network: "Network Monitor"
        }
    }

    var symbol: String {
        switch self {
        case .ytMusic: "music.note"
        case .shopCheck: "checkmark.shield"
        case .network: "network"
        }
    }
}

enum MusicPage: String, CaseIterable, Identifiable {
    case downloads, library

    var id: String { rawValue }
    var title: String { self == .downloads ? "Downloads" : "Library" }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    /// Test and snapshot runs keep their settings away from the real ones.
    static let defaults = Store.isOverridden ? UserDefaults(suiteName: "com.sebkrupa.anthill.test")! : .standard

    var sidebar: Module? = Module(rawValue: defaults.string(forKey: "sidebar") ?? "") ?? .ytMusic {
        didSet { Self.defaults.set(sidebar?.rawValue, forKey: "sidebar") }
    }
    /// Settings reopens on the last tab.
    var settingsTab: SettingsTab = SettingsTab(rawValue: defaults.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { Self.defaults.set(settingsTab.rawValue, forKey: "settings.tab") }
    }
    /// Modules left out of the menu bar. Stored as the hidden ones, so new modules show by default.
    var menuBarHidden: Set<String> = Set(defaults.stringArray(forKey: "menuBar.hidden") ?? []) {
        didSet { Self.defaults.set(Array(menuBarHidden), forKey: "menuBar.hidden") }
    }
    let music = MusicQueue(defaults: defaults, history: Store.history)
    let llama = LlamaConnection(defaults: defaults)
    let library = MusicLibrary()
    let shopChecks = ShopChecks(history: Store.shopChecks)
    let network = NetworkWatch(defaults: defaults)
    /// The YT-Music page: the download queue, or the Music library the model works on.
    var musicPage: MusicPage = .downloads
    let updates = Updates(defaults: defaults)

    init() {
        // Test runs must not reach GitHub or show alerts.
        if !Store.isOverridden {
            updates.checkDaily()
            Task { await llama.refresh() }
        }
    }

    var menuBarModules: [Module] { Module.allCases.filter { !menuBarHidden.contains($0.rawValue) } }
}

/// Test, snapshot, and self-test runs set APP_STORE to a path in /tmp.
enum Store {
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    /// The YT-Music history: every download and its log, kept until the person removes it.
    static var history: URL {
        if isOverridden { return URL(fileURLWithPath: ProcessInfo.processInfo.environment["APP_STORE"]!) }
        return URL.applicationSupportDirectory.appending(path: "AntHill/history.json")
    }

    /// The eCommerce Security Check reports, kept until the person clears them.
    static var shopChecks: URL {
        if isOverridden { return URL(fileURLWithPath: ProcessInfo.processInfo.environment["APP_STORE"]! + "-shop-checks.json") }
        return URL.applicationSupportDirectory.appending(path: "AntHill/shop-checks.json")
    }
}
