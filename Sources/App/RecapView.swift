import SwiftUI
import UIKit

struct RecapTheme: Identifiable {
    let id: Int
    let bg: Color
    let fg: Color
    let accent: Color
    let cell: Color
    let sub: Color

    static let all: [RecapTheme] = [
        RecapTheme(id: 0, bg: Color(hex: 0xFBF6EE), fg: Color(hex: 0x2C2C2A), accent: Color(hex: 0xD85A30), cell: Color(hex: 0xEFE7DA), sub: Color(hex: 0x888780)),
        RecapTheme(id: 1, bg: Color(hex: 0xD85A30), fg: .white, accent: Color(hex: 0xFAECE7), cell: Color(hex: 0xE3774F), sub: Color(hex: 0xFAECE7)),
        RecapTheme(id: 2, bg: Color(hex: 0x0F6E56), fg: .white, accent: Color(hex: 0x9FE1CB), cell: Color(hex: 0x1C7F65), sub: Color(hex: 0xC9EEDF)),
        RecapTheme(id: 3, bg: Color(hex: 0x26215C), fg: .white, accent: Color(hex: 0xAFA9EC), cell: Color(hex: 0x37317A), sub: Color(hex: 0xCECBF6)),
        RecapTheme(id: 4, bg: Color(hex: 0x2C2C2A), fg: .white, accent: Color(hex: 0xF0997B), cell: Color(hex: 0x3E3E3B), sub: Color(hex: 0xB4B2A9))
    ]
}

/// The shareable month card. Drawn at 360 pt wide and rendered at 3× (1080 px).
struct RecapCard: View {
    let month: Date
    let meals: [Meal]
    let theme: RecapTheme
    let showNumbers: Bool
    let story: Bool

    private let width: CGFloat = 360
    private var height: CGFloat { story ? 640 : 450 }
    private var pad: CGFloat { story ? 24 : 18 }
    private var gap: CGFloat { story ? 6 : 4 }
    private var cell: CGFloat { ((width - pad * 2 - gap * 6) / 7).rounded(.down) }

    var body: some View {
        let byDay = Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.date) }
        let days = CalendarMath.gridDays(for: month)
        let rows = days.count / 7
        let stats = MonthStats(meals: meals)

        VStack(alignment: .leading, spacing: 0) {
            Text("PINGGAN · MONTH IN PLATES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.monthName.string(from: month))
                    .font(.system(size: story ? 42 : 32, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.fg)
                Text(Fmt.year.string(from: month))
                    .font(.system(size: story ? 20 : 16, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.accent)
            }
            .padding(.top, 2)

            Spacer(minLength: story ? 18 : 8)

            HStack(spacing: gap) {
                ForEach(Array(CalendarMath.weekdayLetters.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.sub).frame(width: cell)
                }
            }
            .padding(.bottom, 4)

            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { c in
                            if let day = days[r * 7 + c] {
                                dayCell(day, meals: byDay[day] ?? [])
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: story ? 18 : 8)

            Text("\(stats.dishCount) dishes · \(stats.daysLogged) days logged")
                .font(.system(size: story ? 15 : 13, weight: .medium, design: .rounded))
                .foregroundStyle(theme.fg)
            if showNumbers {
                Text("\(Fmt.kcal(stats.totalKcal)) · \(Fmt.rm(stats.spent))")
                    .font(.system(size: story ? 13 : 12, design: .rounded))
                    .foregroundStyle(theme.sub)
                    .padding(.top, 2)
            }
            if let t = stats.topSpot {
                Text("Top spot: \(t.name) ×\(t.visits)")
                    .font(.system(size: story ? 13 : 12, design: .rounded))
                    .foregroundStyle(theme.sub)
                    .lineLimit(1)
                    .padding(.top, 2)
            }

            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(hex: 0xD85A30)).frame(width: 20, height: 20)
                    Circle().stroke(Color(hex: 0xFAECE7), lineWidth: 2.5).frame(width: 10, height: 10)
                }
                Text("Pinggan").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(theme.fg)
                Spacer()
            }
            .padding(.top, story ? 14 : 8)
        }
        .padding(pad)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(theme.bg)
    }

    @ViewBuilder
    private func dayCell(_ day: Date, meals: [Meal]) -> some View {
        let hero = DayHero(meals: meals)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        ZStack {
            shape.fill(theme.cell)
            if let img = hero.cutout {
                Image(uiImage: img).resizable().scaledToFit().padding(2)
            } else if let img = hero.photo {
                Image(uiImage: img).resizable().scaledToFill().frame(width: cell, height: cell).clipShape(shape)
            }
        }
        .frame(width: cell, height: cell)
        .overlay(alignment: .topLeading) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(theme.sub)
                .padding(3)
        }
        .overlay(alignment: .bottomTrailing) {
            if hero.extra > 0 {
                Text("+\(hero.extra)").font(.system(size: 8, weight: .bold)).foregroundStyle(theme.accent).padding(3)
            }
        }
    }
}

struct RecapView: View {
    let month: Date

    @ObservedObject private var store = MealStore.shared
    @State private var themeIndex = 0
    @State private var showNumbers = false
    @State private var story = true
    @State private var rendered: UIImage?
    @State private var savedNote: String?

    private var title: String { Fmt.monthYear.string(from: month) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Group {
                    if let rendered {
                        Image(uiImage: rendered)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 520)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    } else {
                        ProgressView().frame(height: 300)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Colour").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(RecapTheme.all) { t in
                            Circle()
                                .fill(t.bg)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(themeIndex == t.id ? Theme.accent : Color.secondary.opacity(0.3),
                                                         lineWidth: themeIndex == t.id ? 3 : 1))
                                .onTapGesture { themeIndex = t.id }
                                .accessibilityLabel("Colour \(t.id + 1)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("Show spend and calories", isOn: $showNumbers)

                Picker("Size", selection: $story) {
                    Text("Story 9:16").tag(true)
                    Text("Post 4:5").tag(false)
                }
                .pickerStyle(.segmented)

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
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }
                }
                if let savedNote {
                    Text(savedNote).font(.footnote).foregroundStyle(.secondary)
                }
                Text("Each day shows your starred dish, or the biggest one. Star a dish in its meal to choose it.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Monthly recap")
        .navigationBarTitleDisplayMode(.inline)
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
