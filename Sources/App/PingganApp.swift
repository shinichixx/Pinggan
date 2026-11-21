import SwiftUI

@main
struct PingganApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            Keys.photoSide: 1280,
            Keys.shrinkMonths: 6,
            Keys.shrinkSide: 800,
            Keys.aiModel: ClaudeClient.defaultModel
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(tab: $tab) { add = AddRequest() }
        }
        .fullScreenCover(item: $add) { req in
            AddMealView(request: req)
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
        HStack(alignment: .bottom, spacing: 0) {
            item(.today, "sun.max", "Today")
            item(.calendar, "calendar", "Calendar")
            Button(action: onCamera) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Theme.accent))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 6, y: 3)
            }
            .offset(y: -8)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Add a meal")
            item(.stats, "chart.pie", "Stats")
            item(.settings, "gearshape", "Settings")
        }
        .padding(.top, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func item(_ t: AppTab, _ icon: String, _ label: String) -> some View {
        Button { tab = t } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(tab == t ? Theme.accentText : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let problem = store.problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
                }

                HStack(spacing: 10) {
                    StatCard(title: "Calories", value: Fmt.kcal(meals.reduce(0) { $0 + $1.kcal }),
                             bg: Theme.kcalBG, label: Theme.kcalLabel, fg: Theme.kcalFG)
                    StatCard(title: "Spent on me", value: Fmt.rm(meals.reduce(0) { $0 + $1.cost }),
                             bg: Theme.costBG, label: Theme.costLabel, fg: Theme.costFG)
                }

                if meals.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "fork.knife.circle").font(.system(size: 40)).foregroundStyle(Theme.accent)
                        Text(isToday ? "Nothing logged yet today" : "Nothing logged this day").font(.headline)
                        Text("Tap the camera button to snap your food.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }

                ForEach(meals) { m in
                    NavigationLink(value: m.id) { MealRow(meal: m) }
                        .buttonStyle(.plain)
                }

                Button {
                    onAdd(AddRequest(type: nextMissing, day: day))
                } label: {
                    Label("Add \(nextMissing.title.lowercased())", systemImage: "plus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
            .padding()
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

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(Fmt.dayLong.string(from: day)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !isToday {
                Button("Today") { day = Date() }.font(.subheadline.weight(.medium))
            }
            Button { shift(-1) } label: { Image(systemName: "chevron.left").font(.title3) }
            Button { shift(1) } label: { Image(systemName: "chevron.right").font(.title3) }
                .disabled(isToday)
        }
        .padding(.top, 8)
    }

    private func shift(_ n: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: n, to: day) else { return }
        if d > Date() && !Calendar.current.isDateInToday(d) { return }
        day = d
    }
}
