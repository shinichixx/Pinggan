import Foundation
import UIKit
import Vision
import CoreImage
import FoundationModels

// MARK: - Pantry: saved products and dishes you corrected

struct Product: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var barcode: String?
    var name: String
    var brand: String
    /// Serving as printed, e.g. "30 g" or "1 bottle (250 ml)". The numbers below are for one serving.
    var serving: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var lastUsed: Date

    init(barcode: String? = nil, name: String = "", brand: String = "", serving: String = "1 serving",
         kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        id = UUID()
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.serving = serving
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        lastUsed = Date()
    }

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        let b = brand.trimmingCharacters(in: .whitespaces)
        if b.isEmpty { return n.isEmpty ? "Product" : n }
        if n.isEmpty { return b }
        return n.lowercased().contains(b.lowercased()) ? n : "\(b) \(n)"
    }
}

struct RememberedDish: Codable, Sendable {
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

private struct PantryFile: Codable {
    var products: [Product]
    var dishes: [String: RememberedDish]
}

@MainActor
final class Pantry: ObservableObject {
    static let shared = Pantry()

    @Published private(set) var products: [Product] = []
    @Published private(set) var dishes: [String: RememberedDish] = [:]

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: Paths.pantry),
              let file = try? JSON.decoder.decode(PantryFile.self, from: data) else { return }
        products = file.products
        dishes = file.dishes
    }

    private func save() {
        let file = PantryFile(products: products, dishes: dishes)
        if let data = try? JSON.encoder.encode(file) {
            try? data.write(to: Paths.pantry, options: .atomic)
        }
        BackupService.shared.scheduleBackup()
    }

    nonisolated static func norm(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func product(barcode: String) -> Product? {
        products.first { $0.barcode == barcode }
    }

    func upsert(_ p: Product) {
        var p = p
        p.lastUsed = Date()
        if let i = products.firstIndex(where: { $0.id == p.id || ($0.barcode != nil && $0.barcode == p.barcode) }) {
            p.id = products[i].id
            products[i] = p
        } else {
            products.append(p)
        }
        products.sort { $0.lastUsed > $1.lastUsed }
        save()
    }

    func delete(_ p: Product) {
        products.removeAll { $0.id == p.id }
        save()
    }

    /// Remembers your corrected name and numbers, so the same dish comes up right next time.
    func remember(_ d: Dish) {
        let key = Self.norm(d.name)
        guard !key.isEmpty, d.kcal > 0 else { return }
        dishes[key] = RememberedDish(name: d.name, kcal: d.kcal, protein: d.protein, carbs: d.carbs, fat: d.fat)
        save()
    }

    func clearDishes() {
        dishes = [:]
        save()
    }

    nonisolated static func apply(_ memory: [String: RememberedDish], to dish: inout Dish) {
        guard let r = memory[norm(dish.name)] else { return }
        dish.name = r.name
        dish.kcal = r.kcal
        dish.protein = r.protein
        dish.carbs = r.carbs
        dish.fat = r.fat
    }
}

// MARK: - What the AI found in a photo

struct FoundDish {
    var dish: Dish
    var box: [Double]?
    var lifted: CIImage?
    var preview: UIImage?
}

enum AIMode: String, CaseIterable {
    case onDevice, claude
}

enum FoodAI {
    static var mode: AIMode {
        AIMode(rawValue: UserDefaults.standard.string(forKey: Keys.aiMode) ?? "") ?? .onDevice
    }

    static func analyse(_ image: UIImage, singleDish: Bool) async throws -> [FoundDish] {
        var found: [FoundDish]
        switch mode {
        case .claude:
            let base = ImageStore.normalized(image, maxSide: 1024)
            let ai = try await ClaudeClient.analysePhoto(image, singleDish: singleDish)
            found = ai.map { a in
                FoundDish(dish: Dish(name: a.name, kcal: a.kcal ?? 0, protein: a.protein_g ?? 0, carbs: a.carbs_g ?? 0, fat: a.fat_g ?? 0),
                          box: a.box, lifted: nil, preview: ImageStore.crop(base, box: a.box, maxSide: 160))
            }
        case .onDevice:
            found = try await OnDeviceAI.analyse(image, singleDish: singleDish)
        }
        let memory = await MainActor.run { Pantry.shared.dishes }
        for i in found.indices { Pantry.apply(memory, to: &found[i].dish) }
        return found
    }

    /// Calories for food typed in by name.
    static func estimate(_ name: String) async throws -> Dish? {
        let memory = await MainActor.run { Pantry.shared.dishes }
        if let r = memory[Pantry.norm(name)] {
            return Dish(name: r.name, kcal: r.kcal, protein: r.protein, carbs: r.carbs, fat: r.fat)
        }
        switch mode {
        case .claude:
            let found = try await ClaudeClient.estimate(name)
            guard !found.isEmpty else { return nil }
            return Dish(name: name,
                        kcal: found.reduce(0) { $0 + ($1.kcal ?? 0) },
                        protein: found.reduce(0) { $0 + ($1.protein_g ?? 0) },
                        carbs: found.reduce(0) { $0 + ($1.carbs_g ?? 0) },
                        fat: found.reduce(0) { $0 + ($1.fat_g ?? 0) })
        case .onDevice:
            return try await OnDeviceAI.estimate(name)
        }
    }

    static var modeTitle: String { mode == .claude ? "Claude" : "On-device AI" }
}

// MARK: - On-device Apple Intelligence (iOS 27 image input)

@Generable
struct FMDish {
    @Guide(description: "Short everyday name of the food or drink. Use Malaysian names where they fit, for example nasi lemak, roti canai, mee goreng, teh tarik.")
    var name: String
    @Guide(description: "Estimated calories in kcal for the whole portion")
    var kcal: Int
    @Guide(description: "Estimated protein in grams")
    var protein: Int
    @Guide(description: "Estimated carbohydrate in grams")
    var carbs: Int
    @Guide(description: "Estimated fat in grams")
    var fat: Int
}

@Generable
struct FMItem {
    @Guide(description: "true if the picture shows food or a drink; false for anything else, such as a hand, cutlery, a phone or an empty plate")
    var isFood: Bool
    var dish: FMDish
}

@Generable
struct FMTable {
    @Guide(description: "Every separate food or drink in the photo. A plate of rice with its side dishes is one item.")
    var dishes: [FMDish]
}

@Generable
struct FMLabel {
    @Guide(description: "Product name if it appears in the text, otherwise an empty string")
    var name: String
    @Guide(description: "Brand if it appears in the text, otherwise an empty string")
    var brand: String
    @Guide(description: "Serving size as printed, for example 30 g or 1 packet (250 ml). Empty if not printed.")
    var serving: String
    @Guide(description: "Energy in kcal for one serving. 0 if the label has no per-serving column.")
    var kcalPerServing: Double
    @Guide(description: "Protein in grams for one serving, 0 if not given")
    var proteinPerServing: Double
    @Guide(description: "Carbohydrate in grams for one serving, 0 if not given")
    var carbsPerServing: Double
    @Guide(description: "Fat in grams for one serving, 0 if not given")
    var fatPerServing: Double
    @Guide(description: "Energy in kcal per 100 g or 100 ml, 0 if not given")
    var kcalPer100: Double
    @Guide(description: "Protein in grams per 100 g or 100 ml, 0 if not given")
    var proteinPer100: Double
    @Guide(description: "Carbohydrate in grams per 100 g or 100 ml, 0 if not given")
    var carbsPer100: Double
    @Guide(description: "Fat in grams per 100 g or 100 ml, 0 if not given")
    var fatPer100: Double
}

extension FMDish {
    var asDish: Dish {
        Dish(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
             kcal: Double(max(0, kcal)), protein: Double(max(0, protein)),
             carbs: Double(max(0, carbs)), fat: Double(max(0, fat)))
    }
}

enum OnDeviceAI {
    static var status: (ready: Bool, message: String) {
        let a = SystemLanguageModel.default.availability
        if case .available = a { return (true, "Ready, free and offline") }
        if case .unavailable(.appleIntelligenceNotEnabled) = a {
            return (false, "Turn on Apple Intelligence in iPhone Settings › Apple Intelligence & Siri.")
        }
        if case .unavailable(.modelNotReady) = a {
            return (false, "Apple Intelligence is still downloading. Try again in a while.")
        }
        if case .unavailable(.deviceNotEligible) = a {
            return (false, "This iPhone doesn't support Apple Intelligence.")
        }
        return (false, "Apple Intelligence isn't available right now.")
    }

    private static let photoNote = "The photo was taken in Malaysia. Estimate realistic calories for Malaysian portions."

    static func analyse(_ image: UIImage, singleDish: Bool) async throws -> [FoundDish] {
        let st = status
        guard st.ready else { throw AIError.server(st.message) }
        let base = ImageStore.normalized(image, maxSide: 1024)
        guard let cg = base.cgImage else { throw AIError.unreadable }

        if singleDish {
            let item = try await describe(cg)
            let lifted = ImageStore.liftAll(cg)
            return [FoundDish(dish: item.dish.asDish, box: nil, lifted: lifted, preview: lifted.flatMap { ImageStore.uiImage($0) })]
        }

        // Vision separates the plates, then the model names each one.
        let parts = ImageStore.splitInstances(cg)
        if parts.count >= 2 {
            var out: [FoundDish] = []
            for p in parts.prefix(6) {
                let item = try await describe(p.focus)
                if item.isFood {
                    out.append(FoundDish(dish: item.dish.asDish, box: nil, lifted: p.lifted, preview: p.preview))
                }
            }
            if !out.isEmpty { return out }
        }

        // Couldn't separate the plates: ask about the whole photo.
        let table = try await describeTable(cg)
        let dishes = Array(table.dishes.prefix(8))
        if dishes.count == 1 {
            let lifted = ImageStore.liftAll(cg)
            return [FoundDish(dish: dishes[0].asDish, box: nil, lifted: lifted, preview: lifted.flatMap { ImageStore.uiImage($0) })]
        }
        return dishes.map { FoundDish(dish: $0.asDish, box: nil, lifted: nil, preview: nil) }
    }

    private static func describe(_ cg: CGImage) async throws -> FMItem {
        let session = LanguageModelSession()
        let response = try await session.respond(generating: FMItem.self, options: GenerationOptions(samplingMode: .greedy)) {
            "Identify the single food or drink in this picture and estimate its calories, protein, carbohydrate and fat for the portion shown."
            photoNote
            Attachment(cg)
        }
        return response.content
    }

    private static func describeTable(_ cg: CGImage) async throws -> FMTable {
        let session = LanguageModelSession()
        let response = try await session.respond(generating: FMTable.self, options: GenerationOptions(samplingMode: .greedy)) {
            "List all food and drink items in this photo, and estimate the calories, protein, carbohydrate and fat of each portion."
            photoNote
            Attachment(cg)
        }
        return response.content
    }

    static func estimate(_ name: String) async throws -> Dish? {
        let st = status
        guard st.ready else { throw AIError.server(st.message) }
        let session = LanguageModelSession()
        let prompt = "Estimate the calories, protein, carbohydrate and fat of one normal Malaysian portion of: \(name). Give one item for the whole thing."
        let response = try await session.respond(to: prompt, generating: FMDish.self, options: GenerationOptions(samplingMode: .greedy))
        var d = response.content.asDish
        d.name = name
        return d
    }

    static func readLabel(_ text: String) async throws -> FMLabel {
        let session = LanguageModelSession()
        let clipped = String(text.prefix(2500))
        let prompt = """
        Below is the text read from a food or drink's nutrition information panel. Malaysian labels can be in Malay and English: \
        Tenaga = Energy, Karbohidrat = Carbohydrate, Lemak = Fat, Hidangan / Sajian = Serving. \
        If energy is only given in kJ, divide by 4.184 to get kcal. Extract the values.

        \(clipped)
        """
        let response = try await session.respond(to: prompt, generating: FMLabel.self, options: GenerationOptions(samplingMode: .greedy))
        return response.content
    }
}

// MARK: - Labels and barcodes

struct LabelScan {
    var barcode: String?
    var product: Product?
    var source: String
}

enum LabelReader {
    static func scan(_ image: UIImage) async -> LabelScan {
        let base = ImageStore.normalized(image, maxSide: 2000)
        guard let cg = base.cgImage else { return LabelScan(barcode: nil, product: nil, source: "") }
        let code = barcode(in: cg)

        if let code {
            let known = await MainActor.run { Pantry.shared.product(barcode: code) }
            if let known { return LabelScan(barcode: code, product: known, source: "Saved product") }
        }

        let text = ocr(cg)
        if looksLikeNutrition(text), var p = await parse(text) {
            p.barcode = code
            return LabelScan(barcode: code, product: p, source: "Read from the label")
        }

        if let code, let p = await OpenFoodFacts.lookup(code) {
            return LabelScan(barcode: code, product: p, source: "Found in Open Food Facts")
        }
        return LabelScan(barcode: code, product: nil, source: "")
    }

    static func barcode(in cg: CGImage) -> String? {
        let req = VNDetectBarcodesRequest()
        req.symbologies = [.ean13, .ean8, .upce, .code128, .itf14]
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        return req.results?.compactMap { $0.payloadStringValue }.first
    }

    static func ocr(_ cg: CGImage) -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func looksLikeNutrition(_ text: String) -> Bool {
        let t = text.lowercased()
        let words = ["kcal", "energy", "tenaga", "protein", "karbohidrat", "carbohydrate", "lemak", "fat", "kj"]
        return words.filter { t.contains($0) }.count >= 2
    }

    static func parse(_ text: String) async -> Product? {
        if OnDeviceAI.status.ready, let l = try? await OnDeviceAI.readLabel(text) {
            var p = Product(name: l.name, brand: l.brand)
            if l.kcalPerServing > 0 {
                p.serving = l.serving.isEmpty ? "1 serving" : l.serving
                p.kcal = l.kcalPerServing
                p.protein = l.proteinPerServing
                p.carbs = l.carbsPerServing
                p.fat = l.fatPerServing
                return p
            }
            if l.kcalPer100 > 0 {
                p.serving = "100 g"
                p.kcal = l.kcalPer100
                p.protein = l.proteinPer100
                p.carbs = l.carbsPer100
                p.fat = l.fatPer100
                return p
            }
        }
        // Without Apple Intelligence: take the first kcal figure printed.
        let pattern = #"(\d+(?:[.,]\d+)?)\s*kcal"#
        if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range(at: 1), in: text),
           let v = Double(text[r].replacingOccurrences(of: ",", with: ".")) {
            return Product(serving: "1 serving", kcal: v)
        }
        return nil
    }
}

enum OpenFoodFacts {
    static func lookup(_ code: String) async -> Product? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,serving_size,nutriments") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("Pinggan/1.1 (personal iOS app)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: req),
              let obj = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any],
              (obj["status"] as? Int) == 1,
              let prod = obj["product"] as? [String: Any] else { return nil }
        let n = prod["nutriments"] as? [String: Any] ?? [:]
        func num(_ k: String) -> Double? {
            if let d = n[k] as? Double { return d }
            if let s = n[k] as? String { return Double(s) }
            return nil
        }
        var p = Product(barcode: code,
                        name: prod["product_name"] as? String ?? "",
                        brand: (prod["brands"] as? String ?? "").components(separatedBy: ",").first ?? "")
        let serving = prod["serving_size"] as? String ?? ""
        if let k = num("energy-kcal_serving"), !serving.isEmpty {
            p.serving = serving
            p.kcal = k
            p.protein = num("proteins_serving") ?? 0
            p.carbs = num("carbohydrates_serving") ?? 0
            p.fat = num("fat_serving") ?? 0
            return p
        }
        if let k = num("energy-kcal_100g") {
            p.serving = "100 g"
            p.kcal = k
            p.protein = num("proteins_100g") ?? 0
            p.carbs = num("carbohydrates_100g") ?? 0
            p.fat = num("fat_100g") ?? 0
            return p
        }
        return nil
    }
}
