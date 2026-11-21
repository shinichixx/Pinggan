import Foundation
import SwiftUI
import UIKit

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .snack: return "cup.and.saucer"
        case .dinner: return "moon.stars"
        }
    }

    /// Usual hour, used when adding a meal to an earlier day.
    var usualHour: Int {
        switch self {
        case .breakfast: return 8
        case .lunch: return 13
        case .snack: return 16
        case .dinner: return 20
        }
    }

    static func guess(for date: Date) -> MealType {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let mins = (c.hour ?? 12) * 60 + (c.minute ?? 0)
        switch mins {
        case 240..<660: return .breakfast     // 4:00 – 10:59
        case 660..<900: return .lunch         // 11:00 – 14:59
        case 900..<1110: return .snack        // 15:00 – 18:29
        case 1110..<1350: return .dinner      // 18:30 – 22:29
        default: return .snack
        }
    }
}

struct Dish: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// Base file name of the cut-out (base.heic + optional base.mask.png in Images/).
    var cutout: String?
    var favourite: Bool

    init(name: String = "", kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        id = UUID()
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        cutout = nil
        favourite = false
    }

    enum CodingKeys: String, CodingKey { case id, name, kcal, protein, carbs, fat, cutout, favourite }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kcal = try c.decodeIfPresent(Double.self, forKey: .kcal) ?? 0
        protein = try c.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        carbs = try c.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        fat = try c.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        cutout = try c.decodeIfPresent(String.self, forKey: .cutout)
        favourite = try c.decodeIfPresent(Bool.self, forKey: .favourite) ?? false
    }
}

struct Meal: Identifiable, Hashable, Codable {
    var id: UUID
    var date: Date
    var type: MealType
    var place: String
    var latitude: Double?
    var longitude: Double?
    /// What he paid for his own food only.
    var cost: Double
    var photo: String?
    var thumb: String?
    var photoShrunk: Bool
    var dishes: [Dish]
    var note: String

    init(date: Date, type: MealType) {
        id = UUID()
        self.date = date
        self.type = type
        place = ""
        latitude = nil
        longitude = nil
        cost = 0
        photo = nil
        thumb = nil
        photoShrunk = false
        dishes = []
        note = ""
    }

    enum CodingKeys: String, CodingKey {
        case id, date, type, place, latitude, longitude, cost, photo, thumb, photoShrunk, dishes, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        type = (try? c.decode(MealType.self, forKey: .type)) ?? .snack
        place = try c.decodeIfPresent(String.self, forKey: .place) ?? ""
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        photo = try c.decodeIfPresent(String.self, forKey: .photo)
        thumb = try c.decodeIfPresent(String.self, forKey: .thumb)
        photoShrunk = try c.decodeIfPresent(Bool.self, forKey: .photoShrunk) ?? false
        dishes = try c.decodeIfPresent([Dish].self, forKey: .dishes) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    var kcal: Double { dishes.reduce(0) { $0 + $1.kcal } }
    var protein: Double { dishes.reduce(0) { $0 + $1.protein } }
    var carbs: Double { dishes.reduce(0) { $0 + $1.carbs } }
    var fat: Double { dishes.reduce(0) { $0 + $1.fat } }

    var caption: String {
        [type.title, Fmt.time.string(from: date), place].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Files

enum Paths {
    static var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir(docs.appendingPathComponent("Pinggan", isDirectory: true))
    }
    static var images: URL { dir(root.appendingPathComponent("Images", isDirectory: true)) }
    static var data: URL { root.appendingPathComponent("meals.json") }
    static var previous: URL { root.appendingPathComponent("meals.previous.json") }

    private static func dir(_ u: URL) -> URL {
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

enum JSON {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Store

@MainActor
final class MealStore: ObservableObject {
    static let shared = MealStore()

    @Published private(set) var meals: [Meal] = []
    @Published var problem: String?

    /// False when meals.json exists but could not be read: saving would wipe it, so saving is blocked.
    private var healthy = true
    private var saveTask: Task<Void, Never>?

    init() { load() }

    func load() {
        guard FileManager.default.fileExists(atPath: Paths.data.path) else {
            meals = []
            healthy = true
            return
        }
        do {
            let data = try Data(contentsOf: Paths.data)
            meals = try JSON.decoder.decode([Meal].self, from: data).sorted { $0.date < $1.date }
            healthy = true
            problem = nil
        } catch {
            healthy = false
            meals = []
            problem = "Your meals file could not be read, so nothing will be saved until it's fixed. Restore from a backup in Settings."
        }
    }

    func upsert(_ meal: Meal) {
        if let i = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[i] = meal
        } else {
            meals.append(meal)
        }
        meals.sort { $0.date < $1.date }
        persistSoon()
    }

    func delete(_ meal: Meal) {
        ImageStore.delete(meal.photo)
        ImageStore.delete(meal.thumb)
        for d in meal.dishes { ImageStore.deleteCutout(d.cutout) }
        meals.removeAll { $0.id == meal.id }
        persistSoon()
    }

    func markShrunk(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        for i in meals.indices where set.contains(meals[i].id) { meals[i].photoShrunk = true }
        persistSoon()
    }

    func meals(on day: Date) -> [Meal] {
        let cal = Calendar.current
        return meals.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    func meals(inMonthOf d: Date) -> [Meal] {
        let cal = Calendar.current
        return meals.filter { cal.isDate($0.date, equalTo: d, toGranularity: .month) }
    }

    private func persistSoon() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self.persistNow()
        }
    }

    func persistNow(triggerBackup: Bool = true) {
        saveTask?.cancel()
        saveTask = nil
        guard healthy else { return }
        do {
            let data = try JSON.encoder.encode(meals)
            let fm = FileManager.default
            if fm.fileExists(atPath: Paths.data.path) {
                try? fm.removeItem(at: Paths.previous)
                try? fm.copyItem(at: Paths.data, to: Paths.previous)
            }
            try data.write(to: Paths.data, options: .atomic)
            if triggerBackup { BackupService.shared.scheduleBackup() }
        } catch {
            problem = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

/// The dish that represents a day in the calendar and the monthly recap:
/// a starred dish if there is one, otherwise the biggest dish that has a cut-out.
struct DayHero {
    let dish: Dish?
    let meal: Meal?
    let extra: Int

    init(meals: [Meal]) {
        let all: [(Meal, Dish)] = meals.flatMap { m in m.dishes.map { (m, $0) } }
        let withCut = all.filter { $0.1.cutout != nil }
        let pick = withCut.first(where: { $0.1.favourite })
            ?? withCut.max(by: { $0.1.kcal < $1.1.kcal })
            ?? all.first
        dish = pick?.1
        meal = pick?.0 ?? meals.first
        extra = max(0, all.count - 1)
    }

    var cutout: UIImage? { ImageStore.cutoutImage(dish?.cutout) }
    var photo: UIImage? { ImageStore.load(meal?.thumb) }
}
