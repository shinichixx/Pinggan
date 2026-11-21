import SwiftUI
import UIKit

struct RecapTheme: Identifiable {
    let id: Int
    let colors: [Color]
    let title: Color
    let accent: Color

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topTrailing, endPoint: .bottomLeading)
    }

    static let all: [RecapTheme] = [
        RecapTheme(id: 0, colors: [Color(hex: 0xFFD794), Color(hex: 0xFDB487), Color(hex: 0xFB8C74), Color(hex: 0xF7655F)],
                   title: .white, accent: Color(hex: 0xFFF1D8)),
        RecapTheme(id: 1, colors: [Color(hex: 0xFFF1D8), Color(hex: 0xFFD7B5), Color(hex: 0xFDB487)],
                   title: Color(hex: 0x6A3D2C), accent: Color(hex: 0xE2603F)),
        RecapTheme(id: 2, colors: [Color(hex: 0xE3F2C4), Color(hex: 0x9FD8A8), Color(hex: 0x5DB58F)],
                   title: Color(hex: 0x1F4D3A), accent: Color(hex: 0x2E7D5B)),
        RecapTheme(id: 3, colors: [Color(hex: 0xF0997B), Color(hex: 0x8A5BA8), Color(hex: 0x3C3489)],
                   title: .white, accent: Color(hex: 0xFFD9C6)),
        RecapTheme(id: 4, colors: [Color(hex: 0x7A5A4A), Color(hex: 0x3E3330), Color(hex: 0x2C2C2A)],
                   title: .white, accent: Color(hex: 0xF0997B))
    ]
}

/// The shareable month card: your month drawn on a plate, like the app icon. 360 pt wide, rendered at 3× (1080 px).
struct RecapCard: View {
    let month: Date
    let meals: [Meal]
    let theme: RecapTheme
    let showNumbers: Bool
    let story: Bool

    private let width: CGFloat = 360
    private var height: CGFloat { story ? 640 : 450 }
    private var plate: CGFloat { story ? 318 : 262 }
    private var grid: CGFloat { (plate * 0.66).rounded() }

    var body: some View {
        let byDay = Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.date) }
        let days = CalendarMath.gridDays(for: month)
        let rows = days.count / 7
        let cell = (grid / 7).rounded(.down)
        let stats = MonthStats(meals: meals)

        ZStack {
            theme.gradient
            Image(systemName: "leaf")
                .font(.system(size: 120, weight: .light))
                .rotationEffect(.degrees(-20))
                .foregroundStyle(.white.opacity(0.16))
                .position(x: 24, y: story ? 140 : 110)
            Image(systemName: "fork.knife")
                .font(.system(size: 100, weight: .light))
                .rotationEffect(.degrees(18))
                .foregroundStyle(.white.opacity(0.16))
                .position(x: width - 18, y: story ? 420 : 300)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MY MONTH IN PLATES").font(.q(10, .bold)).tracking(2).foregroundStyle(theme.title.opacity(0.9))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Fmt.monthName.string(from: month)).font(.q(story ? 40 : 32, .bold)).foregroundStyle(theme.title)
                        Text(Fmt.year.string(from: month)).font(.q(story ? 19 : 16, .bold)).foregroundStyle(theme.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: story ? 14 : 6)

                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0xFFFCF9), Color(hex: 0xFFF8F2)], center: .center, startRadius: 0, endRadius: plate / 2))
                        .overlay(Circle().stroke(Color(hex: 0xF2DED0), lineWidth: 2).padding(plate * 0.165))
                        .frame(width: plate, height: plate)
                        .shadow(color: Color(hex: 0x963220).opacity(0.32), radius: 15, y: 12)
                        .overlay {
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    ForEach(Array(CalendarMath.weekdayLetters.enumerated()), id: \.offset) { _, l in
                                        Text(l).font(.q(7.5, .bold)).foregroundStyle(Color(hex: 0xC19A86)).frame(width: cell)
                                    }
                                }
                                .padding(.bottom, 2)
                                ForEach(0..<rows, id: \.self) { r in
                                    HStack(spacing: 0) {
                                        ForEach(0..<7, id: \.self) { c in
                                            cellView(days[r * 7 + c], byDay: byDay, size: cell)
                                                .overlay(alignment: .trailing) {
                                                    if c < 6 { Rectangle().fill(Color(hex: 0xF0DDD0)).frame(width: 0.6) }
                                                }
                                        }
                                    }
                                    .overlay(alignment: .bottom) {
                                        if r < rows - 1 { Rectangle().fill(Color(hex: 0xF0DDD0)).frame(height: 0.6) }
                                    }
                                }
                            }
                        }

                    HStack(spacing: 6) {
                        FlipCounter(value: Double(stats.dishCount), size: 17, unit: "dishes", showFire: false)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0xFFFDFB), Color(hex: 0xFBF1EA)], startPoint: .top, endPoint: .bottom))
                            .shadow(color: Color(hex: 0x782814).opacity(0.3), radius: 9, y: 6)
                    )
                    .offset(x: 18, y: -6)
                }

                Spacer(minLength: story ? 14 : 6)

                VStack(spacing: 3) {
                    Text(summaryLine(stats))
                        .font(.q(13, .bold)).foregroundStyle(theme.title).lineLimit(1).minimumScaleFactor(0.7)
                    if showNumbers {
                        Text("\(Fmt.kcal(stats.totalKcal)) · \(Fmt.rm(stats.spent))")
                            .font(.q(12.5, .semibold)).foregroundStyle(theme.title.opacity(0.85))
                    }
                }

                if story {
                    Text("Pinggan")
                        .font(.q(44, .semibold))
                        .foregroundStyle(theme.title == .white ? Color(hex: 0xFFF6EF) : theme.title)
                        .shadow(color: Color(hex: 0x963220).opacity(0.22), radius: 4, y: 2)
                        .padding(.top, 18)
                } else {
                    Text("Pinggan").font(.q(22, .semibold)).foregroundStyle(theme.title).padding(.top, 6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, story ? 28 : 18)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private func summaryLine(_ s: MonthStats) -> String {
        var parts = ["\(s.daysLogged) \(s.daysLogged == 1 ? "day" : "days") at the table"]
        if let t = s.topSpot { parts.append("Top spot \(t.name)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func cellView(_ day: Date?, byDay: [Date: [Meal]], size: CGFloat) -> some View {
        if let day {
            let hero = DayHero(meals: byDay[day] ?? [])
            ZStack(alignment: .topLeading) {
                Color.clear
                if let img = hero.cutout {
                    Image(uiImage: img).resizable().scaledToFit().padding(size * 0.12)
                        .frame(width: size, height: size)
                } else if let img = hero.photo {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: size * 0.8, height: size * 0.8).clipShape(Circle())
                        .frame(width: size, height: size)
                }
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.q(5.5, .bold)).foregroundStyle(Color(hex: 0xC19A86)).padding(1.5)
            }
            .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

struct RecapView: View {
    let month: Date

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MealStore.shared
    @State private var themeIndex = 0
    @State private var showNumbers = false
    @State private var story = true
    @State private var rendered: UIImage?
    @State private var savedNote: String?

    private var title: String { Fmt.monthYear.string(from: month) }

    var body: some View {
        ZStack {
            Color(hex: 0xFFF4EC).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.coral)
                                .frame(width: 36, height: 36)
                        }
                        Spacer()
                        Text("Monthly recap").font(.q(18, .bold)).foregroundStyle(Theme.brown)
                        Spacer()
                        Color.clear.frame(width: 36, height: 36)
                    }

                    Group {
                        if let rendered {
                            Image(uiImage: rendered)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 540)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .shadow(color: Color(hex: 0x3C140A).opacity(0.3), radius: 14, y: 8)
                        } else {
                            ProgressView().frame(height: 300)
                        }
                    }

                    HStack(spacing: 14) {
                        ForEach(RecapTheme.all) { t in
                            Circle()
                                .fill(t.gradient)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(.white, lineWidth: themeIndex == t.id ? 3 : 0))
                                .overlay(Circle().stroke(Theme.coral, lineWidth: themeIndex == t.id ? 2 : 0).padding(-3))
                                .onTapGesture { themeIndex = t.id }
                                .accessibilityLabel("Colour \(t.id + 1)")
                        }
                    }

                    Toggle("Show spend and calories", isOn: $showNumbers)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.brown)
                        .tint(Theme.coral)
                        .creamCard()

                    PillPicker(options: [(true, "Story 9:16"), (false, "Post 4:5")], selection: $story, light: true)

                    if let rendered {
                        HStack(spacing: 10) {
                            ShareLink(item: Image(uiImage: rendered),
                                      preview: SharePreview("Pinggan · \(title)", image: Image(uiImage: rendered))) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(AccentButtonStyle())
                            Button {
                                UIImageWriteToSavedPhotosAlbum(rendered, nil, nil, nil)
                                savedNote = "Saved to Photos"
                            } label: {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(OutlineButtonStyle())
                        }
                    }
                    if let savedNote {
                        Text(savedNote).font(.footnote).foregroundStyle(Theme.brown2)
                    }
                    Text("Each day shows your starred dish, or the biggest one. Star a dish in its meal to choose it.")
                        .font(.footnote).foregroundStyle(Theme.brown2).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { render() }
        .onChange(of: themeIndex) { render() }
        .onChange(of: showNumbers) { render() }
        .onChange(of: story) { render() }
    }

    @MainActor
    private func render() {
        savedNote = nil
        let card = RecapCard(month: month, meals: store.meals(inMonthOf: month), theme: RecapTheme.all[themeIndex],
                             showNumbers: showNumbers, story: story)
            .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: card)
        r.scale = 3
        rendered = r.uiImage
    }
}
