import SwiftUI
import MapKit

struct CalendarView: View {
    @ObservedObject private var store = MealStore.shared
    @State private var month = CalendarMath.monthStart(Date())
    @State private var mode = 0
    @State private var selected = Calendar.current.startOfDay(for: Date())

    private var monthMeals: [Meal] { store.meals(inMonthOf: month) }

    var body: some View {
        let daysLogged = Set(monthMeals.map { Calendar.current.startOfDay(for: $0.date) }).count
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader(title: Fmt.monthName.string(from: month),
                               subtitle: "\(Fmt.year.string(from: month)) · \(daysLogged) \(daysLogged == 1 ? "day" : "days") logged") {
                        HStack(spacing: 6) {
                            RoundNavButton(icon: "chevron.left") { month = CalendarMath.addMonths(-1, to: month) }
                            RoundNavButton(icon: "chevron.right") { month = CalendarMath.addMonths(1, to: month) }
                                .opacity(month >= CalendarMath.monthStart(Date()) ? 0.45 : 1)
                                .disabled(month >= CalendarMath.monthStart(Date()))
                        }
                    }

                    PillPicker(options: [(0, "Month"), (1, "Photo grid"), (2, "Map")], selection: $mode)

                    switch mode {
                    case 0: monthGrid
                    case 1: photoGrid
                    default: mapView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { MealDetailView(mealID: $0) }
    }

    // MARK: Month

    @ViewBuilder
    private var monthGrid: some View {
        let byDay = Dictionary(grouping: monthMeals) { Calendar.current.startOfDay(for: $0.date) }
        let days = CalendarMath.gridDays(for: month)
        let rows = days.count / 7
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(CalendarMath.weekdayLetters.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.q(11, .bold)).foregroundStyle(Theme.brown3).frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 6)
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        Group {
                            if let day = days[r * 7 + c] {
                                DayCell(day: day, meals: byDay[day] ?? [], selected: day == selected)
                                    .onTapGesture { selected = day }
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if c < 6 { Rectangle().fill(Theme.line).frame(width: 1) }
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if r < rows - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
        }
        .plateCard(padding: 12)

        let dayMeals = store.meals(on: selected)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Fmt.dayShort.string(from: selected)).font(.q(16, .bold)).foregroundStyle(Theme.brown)
                Spacer()
                if !dayMeals.isEmpty {
                    Chip(text: "\(dayMeals.count) \(dayMeals.count == 1 ? "meal" : "meals") · \(Fmt.kcal(dayMeals.reduce(0) { $0 + $1.kcal })) · \(Fmt.rm(dayMeals.reduce(0) { $0 + $1.cost }))")
                }
            }
            if dayMeals.isEmpty {
                Text("Nothing logged.").font(.subheadline).foregroundStyle(Theme.brown2)
            }
        }
        .creamCard()

        ForEach(dayMeals) { m in
            NavigationLink(value: m.id) { MealRow(meal: m) }.buttonStyle(.plain)
        }
    }

    // MARK: Photos

    @ViewBuilder
    private var photoGrid: some View {
        let meals = Array(monthMeals.reversed())
        if meals.isEmpty {
            Text("No photos this month.").font(.q(15, .bold)).foregroundStyle(.white).padding(.top, 20)
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(meals) { m in
                NavigationLink(value: m.id) {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .background(Theme.cream)
                        .overlay {
                            if let img = ImageStore.load(m.thumb) {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else if let img = ImageStore.cutoutImage(m.dishes.first?.cutout) {
                                Image(uiImage: img).resizable().scaledToFit().padding(8)
                            } else {
                                Image(systemName: "fork.knife").foregroundStyle(Theme.brown3)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            Text(Fmt.kcal(m.kcal))
                                .font(.q(10.5, .bold))
                                .foregroundStyle(Theme.brown)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.cream.opacity(0.92)))
                                .padding(5)
                        }
                        .shadow(color: Color(hex: 0xAA5037).opacity(0.15), radius: 5, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Map

    private struct Pin: Identifiable {
        let id: String
        let name: String
        let coord: CLLocationCoordinate2D
        let count: Int
        let spent: Double
    }

    private var pins: [Pin] {
        var groups: [String: [Meal]] = [:]
        for m in monthMeals {
            guard let la = m.latitude, let lo = m.longitude else { continue }
            let key = m.place.isEmpty ? String(format: "%.4f,%.4f", la, lo) : m.place
            groups[key, default: []].append(m)
        }
        return groups.compactMap { entry -> Pin? in
            let ms = entry.value
            guard let first = ms.first, let la = first.latitude, let lo = first.longitude else { return nil }
            return Pin(id: entry.key, name: first.place.isEmpty ? "Unnamed place" : first.place,
                       coord: CLLocationCoordinate2D(latitude: la, longitude: lo),
                       count: ms.count, spent: ms.reduce(0) { $0 + $1.cost })
        }
        .sorted { $0.count > $1.count }
    }

    @ViewBuilder
    private var mapView: some View {
        let list = pins
        Map(initialPosition: .automatic) {
            ForEach(list) { p in
                Annotation(p.name, coordinate: p.coord) {
                    Text("\(p.count)")
                        .font(.q(13, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.button))
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .id(month)
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .plateCard(padding: 6)

        VStack(spacing: 0) {
            if list.isEmpty {
                Text("No places with a location this month.").font(.subheadline).foregroundStyle(Theme.brown2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            }
            ForEach(list) { p in
                HStack {
                    Text(p.name).lineLimit(1).foregroundStyle(Theme.brown)
                    Spacer()
                    Text("\(p.count)× · \(Fmt.rm(p.spent))").foregroundStyle(Theme.brown2)
                }
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .padding(.vertical, 10)
                if p.id != list.last?.id { Divider().overlay(Theme.line) }
            }
        }
        .creamCard(padding: 14)
    }
}

struct DayCell: View {
    let day: Date
    let meals: [Meal]
    let selected: Bool

    var body: some View {
        let hero = DayHero(meals: meals)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img = hero.cutout {
                    Image(uiImage: img).resizable().scaledToFit().padding(5)
                } else if let img = hero.photo {
                    Image(uiImage: img).resizable().scaledToFill().padding(4).clipShape(Circle())
                }
            }
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0xFFE6D8))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.coral2, lineWidth: 2))
                }
            }
            .overlay(alignment: .topLeading) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.q(9.5, .bold))
                    .foregroundStyle(Theme.brown3)
                    .padding(3)
            }
            .overlay(alignment: .bottomTrailing) {
                if hero.extra > 0 {
                    Text("+\(hero.extra)").font(.q(8.5, .bold)).foregroundStyle(Theme.coral).padding(3)
                }
            }
            .contentShape(Rectangle())
    }
}
