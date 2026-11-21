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

    /// A colour that switches between a light-mode and a dark-mode value.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum Theme {
    static let accent = Color(hex: 0xD85A30)
    static let accentText = Color.dyn(0x993C1D, 0xF0997B)
    static let kcalBG = Color.dyn(0xFAECE7, 0x4A1B0C)
    static let kcalFG = Color.dyn(0x712B13, 0xF5C4B3)
    static let kcalLabel = Color.dyn(0x993C1D, 0xF0997B)
    static let costBG = Color.dyn(0xFAEEDA, 0x412402)
    static let costFG = Color.dyn(0x633806, 0xFAC775)
    static let costLabel = Color.dyn(0x854F0B, 0xEF9F27)
    static let tile = Color.dyn(0xF1EFE8, 0x2C2C2A)
    static let card = Color(.secondarySystemBackground)
    static let photoBG = Color(hex: 0x4A1B0C)
}

enum Keys {
    static let photoSide = "photoSide"
    static let shrinkMonths = "shrinkMonths"
    static let shrinkSide = "shrinkSide"
    static let aiModel = "aiModel"
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

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.accentText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.accent.opacity(0.5), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
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
            Text(value).font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(fg)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(bg))
    }
}
