import ServiceManagement
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
            case .models: ModelSettings()
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
    case general, models, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .models: "Models"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .models: "cpu"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle("Open at login", isOn: $opensAtLogin)
                .onChange(of: opensAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        opensAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        } header: {
            Text("Startup")
        } footer: {
            Text("Filesfer schedules run while AntHill is open. Closing the window keeps it open in the menu bar.")
                .foregroundStyle(.secondary)
        }
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

/// The local llama.cpp server and the model the YT-Music Library tab asks.
struct ModelSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var llama = model.llama
        Section {
            TextField("Server address", text: $llama.address, prompt: Text(Llama.defaultAddress))
                .onSubmit { Task { await llama.refresh() } }
            LabeledContent("Status") {
                HStack(spacing: Space.sm) {
                    status
                    Button("Check Again") { Task { await llama.refresh() } }
                        .disabled(llama.status == .checking)
                }
            }
            Picker("Model", selection: $llama.model) {
                Text("None").tag(String?.none)
                // The saved model stays listed while the server is away.
                ForEach(Set(llama.models + [llama.model].compactMap { $0 }).sorted(), id: \.self) { Text($0).tag(Optional($0)) }
            }
            .disabled(llama.models.isEmpty)
        } header: {
            Text("llama.cpp")
        } footer: {
            Text("Start the server with llama-server -m model.gguf --port 8080. With a model chosen, YT-Music shows a Library tab.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var status: some View {
        switch model.llama.status {
        case .unknown: Text("Not checked").foregroundStyle(.secondary)
        case .checking: ProgressView().controlSize(.small)
        case .connected:
            Label(model.llama.available ? "Connected" : "Connected, choose a model", systemImage: "checkmark.circle.fill")
                .foregroundStyle(model.llama.available ? .green : .orange)
        case .failed(let message):
            Label("Not connected", systemImage: "xmark.circle.fill").foregroundStyle(.red).help(message)
        }
    }
}
