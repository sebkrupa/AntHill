import SwiftUI
import AntHillKit

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Menu Bar") {
            ForEach(Module.allCases) { module in
                Toggle(isOn: Binding(
                    get: { !model.menuBarHidden.contains(module.rawValue) },
                    set: { shown in
                        if shown { model.menuBarHidden.remove(module.rawValue) } else { model.menuBarHidden.insert(module.rawValue) }
                    }
                )) {
                    Label(module.title, systemImage: module.symbol)
                }
            }
        }
        Section("YT-Music") {
            LabeledContent("Download folder") {
                HStack(spacing: Space.sm) {
                    Text(model.music.folder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(model.music.folder)
                    Button("Change…") { model.music.chooseFolder() }
                }
            }
            @Bindable var music = model.music
            Picker("Use YouTube sign-in from", selection: $music.browser) {
                Text("No Browser").tag(YTMusic.Browser?.none)
                ForEach(model.music.installedBrowsers) { Text($0.title).tag(Optional($0)) }
            }
        }
    }
}
