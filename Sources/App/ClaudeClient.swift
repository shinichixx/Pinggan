import Foundation
import Security
import UIKit

struct AIDish: Decodable {
    var name: String
    var kcal: Double?
    var protein_g: Double?
    var carbs_g: Double?
    var fat_g: Double?
    var box: [Double]?
}

private struct AIReply: Decodable {
    var dishes: [AIDish]
}

enum AIError: LocalizedError {
    case noKey
    case badKey
    case server(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your Claude API key in Settings first."
        case .badKey: return "Your Claude API key was rejected. Check it in Settings."
        case .server(let m): return m
        case .unreadable: return "Claude's answer couldn't be read. Try again."
        }
    }
}

/// Talks to the Claude API (Anthropic) to name dishes and estimate calories.
enum ClaudeClient {
    static let defaultModel = "claude-sonnet-5-5"
    static let cheapModel = "claude-haiku-5-5"
    static let keychainKey = "claude-api-key"

    static var apiKey: String { Keychain.get(keychainKey) ?? "" }
    static var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    static var model: String {
        let m = UserDefaults.standard.string(forKey: Keys.aiModel) ?? ""
        return m.isEmpty ? defaultModel : m
    }

    private static let system = """
    You are a nutrition assistant for a man in Malaysia who logs what he eats. \
    You estimate realistic portion calories for Malaysian food and drinks (mamak, kopitiam, hawker, cafe, fast food, home cooking). \
    You always reply with JSON only, no other text.
    """

    private static let shape = #"{"dishes":[{"name":"","kcal":0,"protein_g":0,"carbs_g":0,"fat_g":0,"box":[0,0,0,0]}]}"#

    static func analysePhoto(_ image: UIImage, singleDish: Bool) async throws -> [AIDish] {
        let small = ImageStore.normalized(image, maxSide: 1024)
        guard let jpg = small.jpegData(compressionQuality: 0.7) else { throw AIError.unreadable }
        var prompt = """
        List every separate food or drink in this photo. Each plate, bowl, cup or glass is usually one item; \
        a plate of rice with its side dishes is one item. For each item give:
        - name: the short everyday name, using Malaysian names where they fit (for example nasi kandar ayam goreng, roti canai, teh tarik ais)
        - kcal: estimated calories for the whole portion you can see
        - protein_g, carbs_g, fat_g: estimated grams
        - box: [x, y, width, height] of the item as fractions from 0 to 1 of the photo, measured from the top-left corner
        If there is no food or drink, return an empty list.
        """
        if singleDish {
            prompt += "\nThis photo shows one dish or drink (it may have sides on the same plate). Return exactly one item."
        }
        prompt += "\nReply with JSON only, exactly in this shape: \(shape)"
        let content: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpg.base64EncodedString()]],
            ["type": "text", "text": prompt]
        ]
        let text = try await send(content: content, maxTokens: 1500, isPhoto: true)
        return try parse(text)
    }

    /// Calories for food typed in by name.
    static func estimate(_ description: String) async throws -> [AIDish] {
        let prompt = """
        Estimate the calories and macros of this food or drink eaten in Malaysia, for one normal portion: "\(description)". \
        If it lists several items, return one entry per item. Leave box out. \
        Reply with JSON only, in this shape: {"dishes":[{"name":"","kcal":0,"protein_g":0,"carbs_g":0,"fat_g":0}]}
        """
        let text = try await send(content: [["type": "text", "text": prompt]], maxTokens: 600, isPhoto: false)
        return try parse(text)
    }

    /// Checks that the key works with a tiny request.
    static func test() async throws {
        _ = try await send(content: [["type": "text", "text": "Reply with the word OK."]], maxTokens: 5, isPhoto: false)
    }

    private static func send(content: [[String: Any]], maxTokens: Int, isPhoto: Bool) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.noKey }
        let model = self.model
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": content]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard code == 200 else {
            if code == 401 { throw AIError.badKey }
            let msg = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? "Claude returned error \(code)."
            throw AIError.server(msg)
        }
        if let u = obj?["usage"] as? [String: Any] {
            Usage.record(input: u["input_tokens"] as? Int ?? 0, output: u["output_tokens"] as? Int ?? 0, model: model, photo: isPhoto)
        }
        let blocks = obj?["content"] as? [[String: Any]] ?? []
        return blocks.compactMap { b -> String? in
            guard (b["type"] as? String) == "text" else { return nil }
            return b["text"] as? String
        }.joined()
    }

    private static func parse(_ text: String) throws -> [AIDish] {
        guard let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}"), s < e else { throw AIError.unreadable }
        let json = String(text[s...e])
        do {
            return try JSONDecoder().decode(AIReply.self, from: Data(json.utf8)).dishes
        } catch {
            throw AIError.unreadable
        }
    }
}

/// Rough running total of what the Claude API has cost this month.
enum Usage {
    static let usdToRM = 4.3

    private static func key(_ s: String, _ d: Date = Date()) -> String { "usage-\(Fmt.monthKey.string(from: d))-\(s)" }

    /// US$ per million tokens (input, output). Estimates only.
    static func prices(_ model: String) -> (Double, Double) {
        if model.contains("haiku") { return (0.1, 0.5) }
        if model.contains("opus") { return (4, 20) }
        return (2, 10)
    }

    static func record(input: Int, output: Int, model: String, photo: Bool) {
        let ud = UserDefaults.standard
        let p = prices(model)
        let usd = Double(input) / 1_000_000 * p.0 + Double(output) / 1_000_000 * p.1
        ud.set(ud.double(forKey: key("usd")) + usd, forKey: key("usd"))
        ud.set(ud.integer(forKey: key("calls")) + 1, forKey: key("calls"))
        if photo { ud.set(ud.integer(forKey: key("photos")) + 1, forKey: key("photos")) }
    }

    static var thisMonth: (photos: Int, calls: Int, rm: Double) {
        let ud = UserDefaults.standard
        return (ud.integer(forKey: key("photos")), ud.integer(forKey: key("calls")), ud.double(forKey: key("usd")) * usdToRM)
    }
}

enum Keychain {
    private static let service = "com.ridhuan.pinggan"

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
