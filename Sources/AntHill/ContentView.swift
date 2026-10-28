import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(Module.allCases, selection: $model.sidebar) { module in
                Label(module.title, systemImage: module.symbol)
                    .help(module.title)
                    .tag(module)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 212)
        } detail: {
            ModuleView(module: model.sidebar ?? .ytMusic)
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }
}

/// One view per module. Add a case here when you add one to `Module`.
struct ModuleView: View {
    let module: Module

    var body: some View {
        switch module {
        case .ytMusic: MusicView()
        case .shopCheck: ShopCheckView()
        case .network: NetworkView()
        case .filesfer: FilesferView()
        }
    }
}
