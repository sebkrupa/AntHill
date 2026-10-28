import Foundation
import AntHillKit

/// eCommerce Security Check: checks a shop address and keeps every report until the person clears them.
@Observable
final class ShopChecks {
    /// Newest first.
    private(set) var reports: [ShopCheck.Report] = []
    var selection: ShopCheck.Report.ID?
    /// The domain being checked and the step it is on; nil while idle.
    private(set) var running: (domain: String, step: String)?
    /// Asks before Clear History removes every report.
    var confirmsClear = false
    /// Self-test turns this off so no real check reaches the network.
    var startsChecks = true
    private let history: URL?

    init(history: URL? = nil) {
        self.history = history
        if let history, let data = try? Data(contentsOf: history),
           let saved = try? JSONDecoder().decode([ShopCheck.Report].self, from: data) {
            reports = saved
        }
        selection = reports.first?.id
    }

    var selected: ShopCheck.Report? { reports.first { $0.id == selection } }

    /// Starts a check of `address`. False when it is no web address or a check is running.
    @discardableResult
    func check(_ address: String) -> Bool {
        guard running == nil, let url = ShopCheck.target(address) else { return false }
        running = (url.host() ?? address, "Starting")
        selection = nil
        guard startsChecks else { return true }
        Task {
            let report = await ShopCheck.run(url, step: { step in
                await MainActor.run { self.running?.step = step }
            })
            running = nil
            add(report)
        }
        return true
    }

    /// Checks the selected shop again; the new report goes on top.
    func checkAgain() {
        if let selected { check(selected.domain) }
    }

    func add(_ report: ShopCheck.Report) {
        reports.insert(report, at: 0)
        selection = report.id
        save()
    }

    func remove(_ id: ShopCheck.Report.ID) {
        reports.removeAll { $0.id == id }
        if selection == id { selection = reports.first?.id }
        save()
    }

    func clearHistory() {
        reports = []
        selection = nil
        save()
    }

    private func save() {
        guard let history else { return }
        do {
            try FileManager.default.createDirectory(at: history.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(reports).write(to: history, options: .atomic)
        } catch {
            print("AntHill: could not save the shop check history: \(error.localizedDescription)")
        }
    }
}
