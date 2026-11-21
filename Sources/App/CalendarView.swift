import SwiftUI
import MapKit

struct CalendarView: View {
    @ObservedObject private var store = MealStore.shared
    @State private var month = CalendarMath.monthStart(Date())
    @State private var mode = 0
    @State private var selected = Calendar.current.startOfDay(for: Date())

    private var monthMeals: [Meal] { store.meals(inMonthOf: month) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(Fmt.monthYear.string(from: month)).font(.system(size: 26, weight: .bold, design: .rounded))
                    Spacer()
                    Button { month = CalendarMath.addMonths(-1, to: month) } label: { Image(systemName: "chevron.left").font(.title3) }
                    Button { month = CalendarMath.addMonths(1, to: month) } label: { Image(systemName: "chevron.right").font(.title3) }
                        .disabled(month >= CalendarMath.monthStart(Date()))
                }
                .padding(.top, 8)

                Picker("View", selection: $mode) {
                    Text("Month").tag(0)
                    Text("Photo grid").tag(1)
                    Text("Map").tag(2)
                }
                .pickerStyle(.segmented)

                switch mode {
                case 0: monthGrid
                case 1: photoGrid
                default: mapView
                }
            }
            .padding()
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { MealDetailView(mealID: $0) }
    }

    // MARK: Month

    @ViewBuilder
    private var monthGrid: some View {
        let byDay = Dictionary(grouping: monthMeals) { Calendar.current.startOfDay(for: $0.date) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(Array(CalendarMath.weekdayLetters.enumerated()), id: \.offset) { _, l in
                Text(l).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(CalendarMath.gridDays(for: month).enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(day: day, meals: byDay[day] ?? [], selected: day == selected)
                        .onTapGesture { selected = day }
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }

        let dayMeals = store.meals(on: selected)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Fmt.dayShort.string(from: selected)).font(.headline)
                Spacer()
                if !dayMeals.isEmpty {
                    Text("\(dayMeals.count) \(dayMeals.count == 1 ? "meal" : "meals") · \(Fmt.kcal(dayMeals.reduce(0) { $0 + $1.kcal })) · \(Fmt.rm(dayMeals.reduce(0) { $0 + $1.cost }))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if dayMeals.isEmpty {
                Text("Nothing logged.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(dayMeals) { m in
                NavigationLink(value: m.id) { MealRow(meal: m) }.buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }

    // MARK: Photos

    @ViewBuilder
    private var photoGrid: some View {
        let meals = monthMeals.reversed()
        if meals.isEmpty {
            Text("No photos this month.").font(.subheadline).foregroundStyle(.secondary).padding(.top, 20)
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(Array(meals)) { m in
                NavigationLink(value: m.id) {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .background(Theme.tile)
                        .overlay {
                            if let img = ImageStore.load(m.thumb) {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else if let img = ImageStore.cutoutImage(m.dishes.first?.cutout) {
                                Image(uiImage: img).resizable().scaledToFit().padding(8)
                            } else {
                                Image(systemName: "fork.knife").foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            Text(Fmt.kcal(m.kcal))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(.black.opacity(0.45)))
                                .padding(4)
                        }
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
            let key = entry.key
            let ms = entry.value
            guard let first = ms.first, let la = first.latitude, let lo = first.longitude else { return nil }
            return Pin(id: key, name: first.place.isEmpty ? "Unnamed place" : first.place,
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
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.accent))
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .id(month)
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        if list.isEmpty {
            Text("No places with a location this month.").font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(list) { p in
            HStack {
                Text(p.name).lineLimit(1)
                Spacer()
                Text("\(p.count)× · \(Fmt.rm(p.spent))").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

struct DayCell: View {
    let day: Date
    let meals: [Meal]
    let selected: Bool

    var body: some View {
        let hero = DayHero(meals: meals)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(shape.fill(Theme.tile))
            .overlay {
                if let img = hero.cutout {
                    Image(uiImage: img).resizable().scaledToFit().padding(3)
                } else if let img = hero.photo {
                    Image(uiImage: img).resizable().scaledToFill()
                }
            }
            .clipShape(shape)
            .overlay(alignment: .topLeading) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
            .overlay(alignment: .bottomTrailing) {
                if hero.extra > 0 {
                    Text("+\(hero.extra)").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.accentText).padding(3)
                }
            }
            .overlay(shape.stroke(selected ? Theme.accent : Color.clear, lineWidth: 2))
    }
}
