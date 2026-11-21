import SwiftUI

@main
struct PingganApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            Keys.photoSide: 1280,
            Keys.shrinkMonths: 6,
            Keys.shrinkSide: 800,
            Keys.aiModel: ClaudeClient.defaultModel,
            Keys.aiMode: AIMode.onDevice.rawValue
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.coral)
                .fontDesign(.rounded)
                .preferredColorScheme(.light)
        }
    }
}

enum AppTab: Hashable {
    case today, calendar, stats, settings
}

struct RootView: View {
    @State private var tab: AppTab = .today
    @State private var add: AddRequest?
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var store = MealStore.shared

    var body: some View {
        Group {
            switch tab {
            case .today: NavigationStack { TodayView(onAdd: { add = $0 }) }
            case .calendar: NavigationStack { CalendarView() }
            case .stats: NavigationStack { StatsView() }
            case .settings: NavigationStack { SettingsView() }
            }
        }
        .contentMargins(.bottom, 90, for: .scrollContent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(tab: $tab) { add = AddRequest() }
        }
        .fullScreenCover(item: $add) { req in
            AddMealView(request: req)
                .fontDesign(.rounded)
        }
        .onChange(of: phase) {
            switch phase {
            case .active:
                Maintenance.shrinkOldPhotos()
            case .background:
                store.persistNow(triggerBackup: false)
                BackupService.shared.backupNow()
            default:
                break
            }
        }
    }
}

struct TabBar: View {
    @Binding var tab: AppTab
    var onCamera: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            item(.today, "sun.max", "Today")
            item(.calendar, "calendar", "Calendar")
            Button(action: onCamera) {
                Circle()
                    .fill(Color(hex: 0xFFF9F4))
                    .overlay(Circle().stroke(Color(hex: 0xF4E2D6), lineWidth: 2.5).padding(9))
                    .overlay(Image(systemName: "camera").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.coral))
                    .frame(width: 66, height: 66)
                    .shadow(color: Color(hex: 0xC85037).opacity(0.38), radius: 11, y: 6)
            }
            .buttonStyle(.plain)
            .offset(y: -22)
            .padding(.horizontal, 6)
            .accessibilityLabel("Add a meal")
            item(.stats, "chart.pie", "Stats")
            item(.settings, "gearshape", "Settings")
        }
        .frame(height: 68)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: 0xFFF8F3).opacity(0.96))
                .shadow(color: Color(hex: 0xA04632).opacity(0.22), radius: 15, y: 8)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private func item(_ t: AppTab, _ icon: String, _ label: String) -> some View {
        Button { tab = t } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 21, weight: .medium))
                Text(label).font(.system(size: 10.5, weight: .bold, design: .rounded))
            }
            .foregroundStyle(tab == t ? Theme.coral : Theme.brown3)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Today

struct TodayView: View {
    var onAdd: (AddRequest) -> Void

    @ObservedObject private var store = MealStore.shared
    @State private var day = Date()

    private var meals: [Meal] { store.meals(on: day) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var title: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return Fmt.dayShort.string(from: day)
    }

    private var nextMissing: MealType {
        let have = Set(meals.map { $0.type })
        return [MealType.breakfast, .lunch, .dinner].first { !have.contains($0) } ?? .snack
    }

    var body: some View {
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageHeader(title: title, subtitle: Fmt.dayLong.string(from: day)) {
                        HStack(spacing: 6) {
                            if !isToday {
                                Button("Today") { day = Date() }
                                    .font(.q(14, .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).frame(height: 36)
                                    .background(Capsule().fill(.white.opacity(0.28)))
                            }
                            RoundNavButton(icon: "chevron.left") { shift(-1) }
                            RoundNavButton(icon: "chevron.right") { shift(1) }
                                .opacity(isToday ? 0.45 : 1)
                                .disabled(isToday)
                        }
                    }

                    if let problem = store.problem {
                        Text(problem).font(.footnote).foregroundStyle(Color(hex: 0xC0392B))
                            .creamCard()
                    }

                    VStack(spacing: 12) {
                        Text(isToday ? "EATEN TODAY" : "EATEN THIS DAY")
                            .font(.q(12, .bold)).tracking(1).foregroundStyle(Theme.brown2)
                        FlipCounter(value: meals.reduce(0) { $0 + $1.kcal })
                        HStack(spacing: 8) {
                            Chip(text: "\(Fmt.rm(meals.reduce(0) { $0 + $1.cost })) on me", icon: "wallet.bifold")
                            Chip(text: "\(meals.count) \(meals.count == 1 ? "meal" : "meals")", icon: "fork.knife")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .plateCard(padding: 18)

                    if meals.isEmpty {
                        VStack(spacing: 6) {
                            Text(isToday ? "Nothing on the plate yet" : "Nothing logged this day").font(.q(17, .bold)).foregroundStyle(Theme.brown)
                            Text("Tap the camera to snap your food.").font(.subheadline).foregroundStyle(Theme.brown2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }

                    ForEach(meals) { m in
                        NavigationLink(value: m.id) { MealRow(meal: m) }
                            .buttonStyle(.plain)
                    }

                    Button {
                        onAdd(AddRequest(type: nextMissing, day: day))
                    } label: {
                        Label("Add \(nextMissing.title.lowercased())", systemImage: "plus")
                            .font(.q(14.5, .bold))
                            .foregroundStyle(Theme.brown2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                                .foregroundStyle(Color(hex: 0xC8785F).opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { MealDetailView(mealID: $0) }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { v in
                guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                if v.translation.width < -60 { shift(1) } else if v.translation.width > 60 { shift(-1) }
            }
        )
    }

    private func shift(_ n: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: n, to: day) else { return }
        if d > Date() && !Calendar.current.isDateInToday(d) { return }
        day = d
    }
}
