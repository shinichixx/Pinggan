import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }
}

/// Colours taken from the app icon: coral → peach → butter, cream plates and warm brown text.
enum Theme {
    static let coral = Color(hex: 0xF7655A)
    static let coral2 = Color(hex: 0xFB8A6E)
    static let peach = Color(hex: 0xFDB487)
    static let butter = Color(hex: 0xFFD995)
    static let cream = Color(hex: 0xFFF7F1)
    static let cream2 = Color(hex: 0xFBEDE3)
    static let rim = Color(hex: 0xF2DCCD)
    static let chip = Color(hex: 0xFFE7DA)
    static let brown = Color(hex: 0x6A3D2C)
    static let brown2 = Color(hex: 0x9A6A55)
    static let brown3 = Color(hex: 0xC19A86)
    static let line = Color(hex: 0xF0DDD0)
    static let star = Color(hex: 0xF5A524)
    static let photoBG = Color(hex: 0x4A1B0C)

    static let accent = coral
    static let accentText = coral
    static let tile = cream2
    static let card = cream

    static let page = LinearGradient(
        stops: [
            .init(color: Color(hex: 0xF96B63), location: 0),
            .init(color: Color(hex: 0xFB8D77), location: 0.14),
            .init(color: Color(hex: 0xFDB98C), location: 0.28),
            .init(color: Color(hex: 0xFFE2CE), location: 0.44),
            .init(color: Color(hex: 0xFFF2E9), location: 0.6),
            .init(color: Color(hex: 0xFFF6EF), location: 1)
        ],
        startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.6, y: 1))

    static let button = LinearGradient(colors: [Color(hex: 0xF7655A), Color(hex: 0xFB8D6F), Color(hex: 0xFDA77E)],
                                       startPoint: .leading, endPoint: .trailing)

    static let plateFill = RadialGradient(colors: [Color(hex: 0xFFFDFB), Color(hex: 0xFFF8F2), Color(hex: 0xFBEDE3)],
                                          center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 360)
}

enum QWeight: String {
    case medium = "Medium", semibold = "SemiBold", bold = "Bold"
}

extension Font {
    /// Quicksand, the rounded font of the "Pinggan" lettering on the icon.
    static func q(_ size: CGFloat, _ weight: QWeight = .bold) -> Font {
        .custom("Quicksand-\(weight.rawValue)", size: size)
    }
}

enum Keys {
    static let photoSide = "photoSide"
    static let shrinkMonths = "shrinkMonths"
    static let shrinkSide = "shrinkSide"
    static let aiModel = "aiModel"
    static let aiMode = "aiMode"
    static let backupBookmark = "backupBookmark"
    static let backupFolderName = "backupFolderName"
    static let lastBackup = "lastBackup"
}

enum Fmt {
    static let int: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func num(_ v: Double) -> String { int.string(from: NSNumber(value: v.rounded())) ?? "0" }
    static func kcal(_ v: Double) -> String { num(v) + " kcal" }
    static func rm(_ v: Double) -> String { "RM " + String(format: "%.2f", v) }

    private static func df(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.dateFormat = f
        return d
    }

    static let time = df("h:mm a")
    static let dayLong = df("EEEE, d MMMM")
    static let dayShort = df("EEE d MMM")
    static let monthYear = df("MMMM yyyy")
    static let monthName = df("MMMM")
    static let year = df("yyyy")
    static let stamp = df("yyyy-MM-dd")
    static let monthKey = df("yyyy-MM")

    static func distance(_ m: Double) -> String {
        m < 1000 ? "\(Int(m.rounded())) m" : String(format: "%.1f km", m / 1000)
    }
}

enum CalendarMath {
    /// Weeks start on Monday.
    static var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    static func monthStart(_ d: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }

    static func addMonths(_ n: Int, to d: Date) -> Date {
        cal.date(byAdding: .month, value: n, to: monthStart(d)) ?? d
    }

    static func monthEnd(_ d: Date) -> Date {
        let start = monthStart(d)
        let next = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return cal.date(byAdding: .day, value: -1, to: next) ?? start
    }

    /// Cells for a month grid, Monday first. nil = an empty cell before the 1st or after the last day.
    static func gridDays(for month: Date) -> [Date?] {
        let start = monthStart(month)
        let count = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        let weekday = cal.component(.weekday, from: start)   // 1 = Sunday
        let lead = (weekday + 5) % 7                           // Monday = 0
        var out: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<count { out.append(cal.date(byAdding: .day, value: i, to: start)) }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }

    static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]
}

// MARK: - Building blocks

/// The gradient page background with faint leaf and cutlery shapes, like the icon.
struct PageBackground: View {
    var body: some View {
        ZStack {
            Theme.page
            GeometryReader { geo in
                Image(systemName: "leaf")
                    .font(.system(size: 150, weight: .light))
                    .rotationEffect(.degrees(-22))
                    .position(x: 30, y: 120)
                Image(systemName: "fork.knife")
                    .font(.system(size: 110, weight: .light))
                    .rotationEffect(.degrees(16))
                    .position(x: geo.size.width - 20, y: 190)
            }
            .foregroundStyle(.white.opacity(0.16))
        }
        .ignoresSafeArea()
    }
}

struct PlateCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.plateFill)
                    .shadow(color: Color(hex: 0xAA4632).opacity(0.22), radius: 14, y: 10)
            )
    }
}

struct CreamCard: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.cream)
                    .shadow(color: Color(hex: 0xAA5037).opacity(0.13), radius: 10, y: 6)
            )
    }
}

extension View {
    func plateCard(padding: CGFloat = 16) -> some View { modifier(PlateCard(padding: padding)) }
    func creamCard(padding: CGFloat = 14) -> some View { modifier(CreamCard(padding: padding)) }

    /// Lists and forms on the gradient, with cream rows.
    func creamList() -> some View {
        self.scrollContentBackground(.hidden)
            .background(PageBackground())
            .foregroundStyle(Theme.brown)
    }
}

/// Calories shown on flip-counter tiles, like the "1,850 kcal" badge on the icon.
struct FlipCounter: View {
    let value: Double
    var size: CGFloat = 34
    var unit: String = "kcal"
    var showFire = true

    var body: some View {
        let text = Fmt.num(value)
        HStack(spacing: size * 0.09) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                if ch.isNumber {
                    Text(String(ch))
                        .font(.q(size, .bold))
                        .foregroundStyle(Theme.brown)
                        .frame(width: size * 0.88, height: size * 1.35)
                        .background(
                            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                                .fill(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.49),
                                                             .init(color: Color(hex: 0xF6EBE3), location: 0.51), .init(color: Color(hex: 0xF6EBE3), location: 1)],
                                                     startPoint: .top, endPoint: .bottom))
                                .shadow(color: Color(hex: 0x783C28).opacity(0.18), radius: 2, y: 1.5)
                        )
                        .overlay(Rectangle().fill(Color(hex: 0x966450).opacity(0.2)).frame(height: 1))
                } else {
                    Text(String(ch)).font(.q(size * 0.9, .bold)).foregroundStyle(Theme.brown)
                }
            }
            if !unit.isEmpty {
                VStack(spacing: 2) {
                    if showFire { Text("🔥").font(.system(size: size * 0.5)) }
                    Text(unit).font(.q(size * 0.45, .bold)).foregroundStyle(Theme.brown2)
                }
                .padding(.leading, size * 0.12)
            }
        }
    }
}

/// Pill-shaped tag on a cream card.
struct Chip: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
            Text(text).font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Theme.brown)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.chip))
    }
}

/// White title + subtitle at the top of a page, with optional buttons on the right.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.q(34, .bold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
            }
            Spacer()
            trailing
        }
        .padding(.top, 8)
    }
}

struct RoundNavButton: View {
    let icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.28)))
        }
        .buttonStyle(.plain)
    }
}

/// Segmented control drawn as a cream pill on the gradient.
struct PillPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var light = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let on = opt.0 == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = opt.0 }
                } label: {
                    Text(opt.1)
                        .font(.q(13.5, .bold))
                        .lineLimit(1)
                        .foregroundStyle(on ? Theme.coral : (light ? Theme.brown2 : .white))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(on ? Theme.cream : .clear).shadow(color: .black.opacity(on ? 0.08 : 0), radius: 3, y: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(light ? Theme.cream2 : .white.opacity(0.35)))
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.q(16.5, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Theme.button).shadow(color: Theme.coral.opacity(0.35), radius: 9, y: 5))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.q(16.5, .bold))
            .foregroundStyle(Theme.coral)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Theme.cream).shadow(color: Color(hex: 0xAA5037).opacity(0.13), radius: 6, y: 3))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let bg: Color
    let label: Color
    let fg: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(label)
            Text(value).font(.q(21, .bold)).foregroundStyle(fg)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(bg))
    }
}
