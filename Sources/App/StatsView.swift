import SwiftUI
import Charts

struct DayTotal: Identifiable {
    let day: Date
    let kcal: Double
    let cost: Double
    var id: Date { day }
}

struct MonthStats {
    let days: [DayTotal]
    let spent: Double
    let totalKcal: Double
    let avgKcal: Double
    let avgSpend: Double
    let daysLogged: Int
    let mealCount: Int
    let dishCount: Int
    let topSpot: (name: String, visits: Int, spent: Double)?
    let mostEaten: (name: String, count: Int)?
    let priciest: Meal?

    init(meals: [Meal]) {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: meals) { cal.startOfDay(for: $0.date) }
        days = byDay.map { day, ms in
            DayTotal(day: day, kcal: ms.reduce(0) { $0 + $1.kcal }, cost: ms.reduce(0) { $0 + $1.cost })
        }
        .sorted { $0.day < $1.day }
        spent = meals.reduce(0) { $0 + $1.cost }
        totalKcal = meals.reduce(0) { $0 + $1.kcal }
        daysLogged = byDay.count
        avgKcal = daysLogged > 0 ? totalKcal / Double(daysLogged) : 0
        avgSpend = daysLogged > 0 ? spent / Double(daysLogged) : 0
        mealCount = meals.count
        dishCount = meals.reduce(0) { $0 + $1.dishes.count }

        var places: [String: (Int, Double)] = [:]
        for m in meals where !m.place.isEmpty && m.place != "Home" {
            let cur = places[m.place] ?? (0, 0)
            places[m.place] = (cur.0 + 1, cur.1 + m.cost)
        }
        if let best = places.max(by: { $0.value.0 < $1.value.0 }) {
            topSpot = (best.key, best.value.0, best.value.1)
        } else {
            topSpot = nil
        }

        var names: [String: (String, Int)] = [:]
        for d in meals.flatMap({ $0.dishes }) {
            let key = d.name.lowercased().trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let cur = names[key] ?? (d.name, 0)
            names[key] = (cur.0, cur.1 + 1)
        }
        if let best = names.values.max(by: { $0.1 < $1.1 }), best.1 > 1 {
            mostEaten = (best.0, best.1)
        } else {
            mostEaten = nil
        }

        priciest = meals.filter { $0.cost > 0 }.max(by: { $0.cost < $1.cost })
    }
}

struct StatsView: View {
    @ObservedObject private var store = MealStore.shared
    @State private var month = CalendarMath.monthStart(Date())
    @State private var metric = 0

    var body: some View {
        let s = MonthStats(meals: store.meals(inMonthOf: month))
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stats").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(Fmt.monthYear.string(from: month)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { month = CalendarMath.addMonths(-1, to: month) } label: { Image(systemName: "chevron.left").font(.title3) }
                    Button { month = CalendarMath.addMonths(1, to: month) } label: { Image(systemName: "chevron.right").font(.title3) }
                        .disabled(month >= CalendarMath.monthStart(Date()))
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    StatCard(title: "Average per day", value: Fmt.kcal(s.avgKcal),
                             bg: Theme.kcalBG, label: Theme.kcalLabel, fg: Theme.kcalFG)
                    StatCard(title: "Spent this month", value: Fmt.rm(s.spent),
                             bg: Theme.costBG, label: Theme.costLabel, fg: Theme.costFG)
                }

                Picker("Chart", selection: $metric) {
                    Text("Calories").tag(0)
                    Text("Spend").tag(1)
                }
                .pickerStyle(.segmented)

                Chart(s.days) { d in
                    BarMark(x: .value("Day", d.day, unit: .day),
                            y: .value("Amount", metric == 0 ? d.kcal : d.cost))
                        .foregroundStyle(Theme.accent)
                        .cornerRadius(3)
                }
                .chartXScale(domain: CalendarMath.monthStart(month)...CalendarMath.monthEnd(month))
                .frame(height: 170)
                .overlay {
                    if s.days.isEmpty {
                        Text("Nothing logged this month.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 0) {
                    row("Days logged", "\(s.daysLogged)")
                    row("Meals", "\(s.mealCount) · \(s.dishCount) dishes")
                    row("Average spend per day", Fmt.rm(s.avgSpend))
                    if let t = s.topSpot { row("Top spot", "\(t.name) · \(t.visits)× · \(Fmt.rm(t.spent))") }
                    if let e = s.mostEaten { row("Most eaten", "\(e.name) × \(e.count)") }
                    if let p = s.priciest { row("Priciest meal", "\(Fmt.rm(p.cost))\(p.place.isEmpty ? "" : " · " + p.place)", last: true) }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))

                NavigationLink {
                    RecapView(month: month)
                } label: {
                    Label("Monthly recap", systemImage: "square.grid.3x3.fill")
                }
                .buttonStyle(AccentButtonStyle())
            }
            .padding()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ title: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline)
                Spacer(minLength: 12)
                Text(value).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 11)
            if !last { Divider() }
        }
    }
}
