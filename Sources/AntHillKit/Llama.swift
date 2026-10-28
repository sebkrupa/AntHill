import Foundation

/// The llama.cpp server API (llama-server), which speaks the OpenAI chat format.
public enum Llama {
    public static let defaultAddress = "http://127.0.0.1:8080"

    /// "127.0.0.1:8080/v1/" -> http://127.0.0.1:8080/v1, the base every call adds a path to.
    public static func base(_ address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/v1") { text.removeLast(3) }
        if !text.contains("://") { text = "http://" + text }
        guard let url = URL(string: text + "/v1"), url.host != nil else { return nil }
        return url
    }

    /// The model names in a GET /v1/models answer.
    public static func models(from data: Data) throws -> [String] {
        struct List: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        return try JSONDecoder().decode(List.self, from: data).data.map(\.id)
    }

    /// A POST /v1/chat/completions body that asks for one JSON object back.
    public static func chatBody(model: String, system: String, user: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "temperature": 0,
            "response_format": ["type": "json_object"],
        ] as [String: Any])
    }

    /// The text of the first answer in a chat completion.
    public static func reply(from data: Data) throws -> String {
        struct Completion: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            let choices: [Choice]
        }
        return try JSONDecoder().decode(Completion.self, from: data).choices.first?.message.content ?? ""
    }
}
