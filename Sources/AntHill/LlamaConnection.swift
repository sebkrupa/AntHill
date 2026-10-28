import Foundation
import AntHillKit

/// The local llama.cpp server (llama-server) and the model AntHill asks.
/// Settings > Models edits it; the YT-Music Library tab shows while the model is available.
@Observable
final class LlamaConnection {
    enum Status: Equatable {
        case unknown, checking, connected
        case failed(String)
    }

    var address: String {
        didSet { defaults.set(address, forKey: "llama.address") }
    }
    var model: String? {
        didSet { defaults.set(model, forKey: "llama.model") }
    }
    /// The models the server offers, from the last check.
    var models: [String] = []
    var status: Status = .unknown
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        address = defaults.string(forKey: "llama.address") ?? Llama.defaultAddress
        model = defaults.string(forKey: "llama.model")
    }

    /// True when the server answered and offers the chosen model.
    var available: Bool { status == .connected && model.map(models.contains) == true }

    /// Asks the server for its models. A single model is chosen for you.
    func refresh() async {
        guard let base = Llama.base(address) else {
            status = .failed("Type the server address, like \(Llama.defaultAddress).")
            return
        }
        status = .checking
        do {
            let (data, response) = try await URLSession.shared.data(from: base.appending(path: "models"))
            try Self.check(response)
            models = try Llama.models(from: data)
            if model.map(models.contains) != true, models.count == 1 { model = models[0] }
            status = .connected
        } catch {
            models = []
            status = .failed("No llama.cpp server at \(address). Start llama-server, then check again.")
        }
    }

    /// One question to the model; its answer text.
    func ask(system: String, user: String) async throws -> String {
        guard let base = Llama.base(address), let model else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Llama.chatBody(model: model, system: system, user: user)
        // A local model on a laptop can take a while per answer.
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
        return try Llama.reply(from: data)
    }

    private static func check(_ response: URLResponse) throws {
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            throw URLError(.badServerResponse)
        }
    }
}
