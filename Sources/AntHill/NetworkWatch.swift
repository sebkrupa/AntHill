import Foundation
import AntHillKit

/// Network Monitor: the network connections of one app, read with lsof every 2 seconds while the page shows.
@Observable
final class NetworkWatch {
    /// The app to watch, as picked or typed; part of the name is enough.
    var name: String {
        didSet { defaults.set(name, forKey: "network.app") }
    }
    /// Every connection lsof saw last time.
    private(set) var all: [Network.Connection] = []
    private(set) var updated: Date?
    var paused = false
    var error: String?
    private var loop: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        name = defaults.string(forKey: "network.app") ?? ""
    }

    var connections: [Network.Connection] { Network.connections(all, of: name) }
    var apps: [String] { Network.apps(all) }

    /// Reads now, then every 2 seconds until `stop`. Test runs keep their sample data.
    func start() {
        guard loop == nil, !Store.isOverridden else { return }
        loop = Task {
            while !Task.isCancelled {
                if !paused { await refresh() }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func refresh() async {
        do {
            all = Network.parse(try await Self.lsof())
            updated = .now
            error = nil
        } catch {
            self.error = "lsof failed: \(error.localizedDescription)"
        }
    }

    func insertSample(_ connections: [Network.Connection]) {
        all = connections
        updated = .now
    }

    private nonisolated static func lsof() async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/lsof")
            process.arguments = Network.arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            // Read before waiting: a full pipe would block lsof forever.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
