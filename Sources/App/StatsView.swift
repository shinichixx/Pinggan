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
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader(title: "Stats", subtitle: Fmt.monthYear.string(from: month)) {
                        HStack(spacing: 6) {
                            RoundNavButton(icon: "chevron.left") { month = CalendarMath.addMonths(-1, to: month) }
                            RoundNavButton(icon: "chevron.right") { month = CalendarMath.addMonths(1, to: month) }
                                .opacity(month >= CalendarMath.monthStart(Date()) ? 0.45 : 1)
                                .disabled(month >= CalendarMath.monthStart(Date()))
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AVERAGE PER DAY").font(.q(11.5, .bold)).tracking(1).foregroundStyle(Theme.brown2)
                                FlipCounter(value: s.avgKcal, size: 24)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("SPENT ON ME").font(.q(11.5, .bold)).tracking(1).foregroundStyle(Theme.brown2)
                                Text(Fmt.rm(s.spent)).font(.q(24, .bold)).foregroundStyle(Theme.brown)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        PillPicker(options: [(0, "Calories"), (1, "Spend")], selection: $metric, light: true)
                        Chart(s.days) { d in
                            BarMark(x: .value("Day", d.day, unit: .day),
                                    y: .value("Amount", metric == 0 ? d.kcal : d.cost))
                                .foregroundStyle(LinearGradient(colors: [Theme.coral2, Theme.coral], startPoint: .top, endPoint: .bottom))
                                .cornerRadius(4)
                        }
                        .chartXScale(domain: CalendarMath.monthStart(month)...CalendarMath.monthEnd(month))
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                                AxisValueLabel(format: .dateTime.day()).foregroundStyle(Theme.brown3)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine().foregroundStyle(Theme.line)
                                AxisValueLabel().foregroundStyle(Theme.brown3)
                            }
                        }
                        .frame(height: 150)
                        .overlay {
                            if s.days.isEmpty {
                                Text("Nothing logged this month.").font(.q(14, .bold)).foregroundStyle(Theme.brown2)
                            }
                        }
                    }
                    .plateCard()

                    VStack(spacing: 0) {
                        row("Days logged", "\(s.daysLogged)")
                        row("Meals", "\(s.mealCount) · \(s.dishCount) dishes")
                        row("Average spend per day", Fmt.rm(s.avgSpend))
                        if let t = s.topSpot { row("Top spot", "\(t.name) · \(t.visits)×") }
                        if let e = s.mostEaten { row("Most eaten", "\(e.name) × \(e.count)") }
                        if let p = s.priciest { row("Priciest meal", "\(Fmt.rm(p.cost))\(p.place.isEmpty ? "" : " · " + p.place)") }
                    }
                    .creamCard(padding: 0)

                    NavigationLink {
                        RecapView(month: month)
                    } label: {
                        Label("Monthly recap", systemImage: "square.grid.3x3.fill")
                    }
                    .buttonStyle(AccentButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(Theme.brown)
                Spacer(minLength: 12)
                Text(value).foregroundStyle(Theme.brown2).multilineTextAlignment(.trailing)
            }
            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            Divider().overlay(Theme.line)
        }
    }
}
