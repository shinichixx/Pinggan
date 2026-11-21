import SwiftUI

// MARK: - Main Settings page: one row per group, details on sub-pages

struct SettingsView: View {
    @ObservedObject private var backup = BackupService.shared
    @ObservedObject private var store = MealStore.shared
    @ObservedObject private var pantry = Pantry.shared
    @AppStorage(Keys.aiMode) private var aiMode = AIMode.onDevice.rawValue
    @AppStorage(Keys.aiModel) private var model = ClaudeClient.defaultModel
    @AppStorage(Keys.photoSide) private var photoSide = 1280
    @AppStorage(Keys.shrinkMonths) private var shrinkMonths = 6
    @State private var bytes: Int64 = 0

    var body: some View {
        let device = OnDeviceAI.status
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PageHeader(title: "Settings", subtitle: "Pinggan \(appVersion)") { EmptyView() }
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        link(icon: "sparkles", color: Theme.coral, title: "Food AI",
                             summary: aiMode == AIMode.claude.rawValue ? "Claude" : "On-device · \(device.ready ? "ready" : "not ready")") {
                            FoodAISettings()
                        }
                        divider
                        link(icon: "key.fill", color: Color(hex: 0xD97757), title: "Claude",
                             summary: (ClaudeClient.hasKey ? "Key saved" : "No key") + " · " + (model.contains("haiku") ? "Haiku 5.5" : "Sonnet 5.5")) {
                            ClaudeSettings()
                        }
                        divider
                        link(icon: "leaf.fill", color: Color(hex: 0x5DB58F), title: "My food",
                             summary: "\(pantry.products.count) products · \(pantry.dishes.count) remembered dishes") {
                            MyFoodSettings()
                        }
                    }
                    .creamCard(padding: 0)

                    VStack(spacing: 0) {
                        link(icon: "photo.fill", color: Theme.peach, title: "Storage",
                             summary: "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) · \(photoSide) px · " +
                                (shrinkMonths == 0 ? "never shrink" : "shrink after \(shrinkMonths) months")) {
                            StorageSettings()
                        }
                        divider
                        link(icon: "icloud.and.arrow.up.fill", color: Color(hex: 0x378ADD), title: "Backup",
                             summary: backupSummary) {
                            BackupSettings()
                        }
                    }
                    .creamCard(padding: 0)

                    VStack(spacing: 0) {
                        NavigationLink {
                            AboutSettings()
                        } label: {
                            HStack(spacing: 12) {
                                Image("AppIconPreview").resizable().frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                rowText("About Pinggan", "Version \(appVersion) · \(store.meals.count) meals")
                                Spacer()
                                chevron
                            }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .creamCard(padding: 0)
                }
                .padding(.horizontal, 20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            Task.detached(priority: .utility) {
                let b = ImageStore.folderBytes()
                await MainActor.run { bytes = b }
            }
        }
    }

    private var backupSummary: String {
        guard let d = backup.lastBackup else { return "No backup saved yet" }
        return "Last saved \(Fmt.dayShort.string(from: d))"
    }

    private var divider: some View { Divider().overlay(Theme.line).padding(.leading, 56) }
    private var chevron: some View { Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.brown3) }

    private func rowText(_ title: String, _ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15.5, weight: .semibold, design: .rounded)).foregroundStyle(Theme.brown)
            Text(summary).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.brown2).lineLimit(1)
        }
    }

    private func link<D: View>(icon: String, color: Color, title: String, summary: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color))
                rowText(title, summary)
                Spacer()
                chevron
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

var appVersion: String {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(v) (build \(b))"
}

// MARK: - Sub-page frame

/// Gradient page with a back button and title, and a cream form underneath.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    RoundNavButton(icon: "chevron.left") { dismiss() }
                    Text(title).font(.q(24, .bold)).foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 4)
                Form { content }
                    .scrollContentBackground(.hidden)
                    .contentMargins(.top, 8, for: .scrollContent)
                    .foregroundStyle(Theme.brown)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private func footerText(_ t: String) -> some View {
    Text(t).foregroundStyle(Theme.brown2)
}

private func statusColor(_ s: String) -> Color {
    let bad = ["couldn't", "failed", "didn't", "not found", "paused", "unavailable"]
    return bad.contains { s.lowercased().contains($0) } ? Color(hex: 0xC0392B) : Theme.brown2
}

// MARK: - Food AI

struct FoodAISettings: View {
    @AppStorage(Keys.aiMode) private var aiMode = AIMode.onDevice.rawValue

    var body: some View {
        let device = OnDeviceAI.status
        SettingsPage(title: "Food AI") {
            Section {
                Picker("Food AI", selection: $aiMode) {
                    Text("On-device · free").tag(AIMode.onDevice.rawValue)
                    Text("Claude · accurate").tag(AIMode.claude.rawValue)
                }
                HStack(alignment: .top) {
                    Text("Apple Intelligence")
                    Spacer()
                    Text(device.message)
                        .foregroundStyle(device.ready ? Color(hex: 0x3B9C6B) : Color(hex: 0xC0392B))
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                footerText("On-device AI runs on your iPhone with Apple Intelligence: free, private and works offline, but its names and numbers are rougher. Claude is more accurate for local dishes and needs API credit.")
            }
            .listRowBackground(Theme.cream)
        }
    }
}

// MARK: - Claude

struct ClaudeSettings: View {
    @AppStorage(Keys.aiModel) private var model = ClaudeClient.defaultModel
    @State private var key = Keychain.get(ClaudeClient.keychainKey) ?? ""
    @State private var testing = false
    @State private var testResult: String?

    private var keyMasked: String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count > 12 else { return k.isEmpty ? "Not set" : "Set" }
        return String(k.prefix(7)) + "••••" + String(k.suffix(4))
    }

    var body: some View {
        let usage = Usage.thisMonth
        SettingsPage(title: "Claude") {
            Section {
                HStack {
                    Text("Paste new key")
                    SecureField("", text: $key, prompt: Text("sk-ant-…").foregroundStyle(Theme.brown3))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .onChange(of: key) {
                    Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: ClaudeClient.keychainKey)
                    testResult = nil
                }
                HStack {
                    Text("Key")
                    Spacer()
                    Text(keyMasked).foregroundStyle(Theme.brown2)
                }
                Button {
                    Task {
                        testing = true
                        do {
                            try await ClaudeClient.test()
                            testResult = "Key works."
                        } catch {
                            testResult = error.localizedDescription
                        }
                        testing = false
                    }
                } label: {
                    HStack {
                        Text("Test key").foregroundStyle(Theme.coral)
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(key.isEmpty || testing)
                if let testResult {
                    Text(testResult).font(.footnote)
                        .foregroundStyle(testResult == "Key works." ? Color(hex: 0x3B9C6B) : Color(hex: 0xC0392B))
                }
            } footer: {
                footerText("Create a key at platform.claude.com under API keys, and add credit under Billing. The key stays in this iPhone's Keychain and is only sent to Anthropic.")
            }
            .listRowBackground(Theme.cream)

            Section {
                Picker("Model", selection: $model) {
                    Text("Sonnet 5.5 · most accurate").tag(ClaudeClient.defaultModel)
                    Text("Haiku 5.5 · cheaper").tag(ClaudeClient.cheapModel)
                }
                HStack {
                    Text("This month")
                    Spacer()
                    Text("\(usage.photos) photos · ≈ \(Fmt.rm(usage.rm))").foregroundStyle(Theme.brown2)
                }
            } footer: {
                footerText("Only used when Food AI is set to Claude. The cost shown is a rough estimate.")
            }
            .listRowBackground(Theme.cream)
        }
    }
}

// MARK: - My food

struct MyFoodSettings: View {
    @ObservedObject private var pantry = Pantry.shared
    @State private var confirmForget = false

    var body: some View {
        SettingsPage(title: "My food") {
            Section {
                if pantry.products.isEmpty {
                    Text("Scan a food label with the camera's “Food label” option and the product is saved here.")
                        .foregroundStyle(Theme.brown2)
                }
                ForEach(pantry.products) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.displayName).font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("\(Fmt.kcal(p.kcal)) per \(p.serving)\(p.barcode.map { " · \($0)" } ?? "")")
                            .font(.caption).foregroundStyle(Theme.brown2)
                    }
                }
                .onDelete { idx in
                    idx.map { pantry.products[$0] }.forEach { pantry.delete($0) }
                }
            } header: {
                Text("Saved products").foregroundStyle(Theme.brown2)
            }
            .listRowBackground(Theme.cream)

            Section {
                if pantry.dishes.isEmpty {
                    Text("Dishes you correct are remembered here, so the AI gets them right next time.")
                        .foregroundStyle(Theme.brown2)
                }
                ForEach(pantry.dishes.values.sorted(by: { $0.name < $1.name }), id: \.name) { d in
                    HStack {
                        Text(d.name)
                        Spacer()
                        Text(Fmt.kcal(d.kcal)).foregroundStyle(Theme.brown2)
                    }
                }
                if !pantry.dishes.isEmpty {
                    Button("Forget remembered dishes", role: .destructive) { confirmForget = true }
                }
            } header: {
                Text("Remembered dishes").foregroundStyle(Theme.brown2)
            }
            .listRowBackground(Theme.cream)
        }
        .confirmationDialog("Forget all remembered dishes?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) { pantry.clearDishes() }
        }
    }
}

// MARK: - Storage

struct StorageSettings: View {
    @AppStorage(Keys.photoSide) private var photoSide = 1280
    @AppStorage(Keys.shrinkMonths) private var shrinkMonths = 6
    @AppStorage(Keys.shrinkSide) private var shrinkSide = 800
    @State private var bytes: Int64 = 0

    var body: some View {
        SettingsPage(title: "Storage") {
            Section {
                HStack {
                    Text("Pinggan is using")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).foregroundStyle(Theme.brown2)
                }
                Picker("New photos", selection: $photoSide) {
                    Text("1024 px").tag(1024)
                    Text("1280 px").tag(1280)
                    Text("1600 px").tag(1600)
                    Text("2000 px").tag(2000)
                }
                Picker("Shrink meals older than", selection: $shrinkMonths) {
                    Text("3 months").tag(3)
                    Text("6 months").tag(6)
                    Text("12 months").tag(12)
                    Text("Never").tag(0)
                }
                Picker("Shrink to", selection: $shrinkSide) {
                    Text("640 px").tag(640)
                    Text("800 px").tag(800)
                    Text("1024 px").tag(1024)
                }
                .disabled(shrinkMonths == 0)
                Button("Shrink old photos now") {
                    Maintenance.shrinkOldPhotos()
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        bytes = ImageStore.folderBytes()
                    }
                }
                .foregroundStyle(Theme.coral)
                .disabled(shrinkMonths == 0)
            } footer: {
                footerText("Photos are saved as HEIC. Shrinking runs when you open the app. Cut-outs, thumbnails and meal details are never shrunk.")
            }
            .listRowBackground(Theme.cream)
        }
        .onAppear { bytes = ImageStore.folderBytes() }
    }
}

// MARK: - Backup

struct BackupSettings: View {
    @ObservedObject private var backup = BackupService.shared
    @ObservedObject private var store = MealStore.shared
    @AppStorage(BackupReminder.enabledKey) private var reminderOn = true
    @AppStorage(BackupReminder.weekdayKey) private var weekday = 1
    @AppStorage(BackupReminder.minutesKey) private var minutes = 21 * 60
    @State private var bytes: Int64 = 0
    @State private var restoreURL: URL?
    @State private var confirmRestore = false
    @State private var message: String?

    private var reminderTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            minutes = (c.hour ?? 21) * 60 + (c.minute ?? 0)
        })
    }

    var body: some View {
        SettingsPage(title: "Backup") {
            Section {
                HStack {
                    Text("Last saved backup")
                    Spacer()
                    Text(backup.lastBackup.map { Fmt.dayShort.string(from: $0) + ", " + Fmt.time.string(from: $0) } ?? "Never")
                        .foregroundStyle(Theme.brown2)
                }
                Button {
                    backup.saveBackup()
                } label: {
                    HStack {
                        Label("Save backup to iCloud Drive…", systemImage: "icloud.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.coral)
                        if backup.working { Spacer(); ProgressView() }
                    }
                }
                .disabled(backup.working)
                HStack {
                    Text("Backup size")
                    Spacer()
                    Text("\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) · \(store.meals.count) meals")
                        .foregroundStyle(Theme.brown2)
                }
                if !backup.status.isEmpty {
                    Text(backup.status).font(.footnote).foregroundStyle(statusColor(backup.status))
                }
            } footer: {
                footerText("Saves one file with your meals, products and photos. Choose iCloud Drive › Pinggan; the file is kept even if you delete the app.")
            }
            .listRowBackground(Theme.cream)

            Section {
                Toggle("Weekly reminder", isOn: $reminderOn).tint(Theme.coral)
                if reminderOn {
                    Picker("Remind me on", selection: $weekday) {
                        ForEach(1...7, id: \.self) { d in
                            Text(Calendar.current.weekdaySymbols[d - 1]).tag(d)
                        }
                    }
                    DatePicker("At", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                footerText("Today also shows a small banner when your last backup is over 7 days old.")
            }
            .listRowBackground(Theme.cream)

            Section {
                Button("Restore from backup file…") {
                    FilePicker.shared.pickFile { url in
                        guard let url else { return }
                        restoreURL = url
                        confirmRestore = true
                    }
                }
                .foregroundStyle(Theme.coral)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(statusColor(message))
                }
            } footer: {
                footerText("Pick a saved Pinggan backup (.aar) file. It replaces the meals on this iPhone.")
            }
            .listRowBackground(Theme.cream)
        }
        .onAppear { bytes = ImageStore.folderBytes() }
        .onChange(of: reminderOn) { Task { await BackupReminder.apply() } }
        .onChange(of: weekday) { Task { await BackupReminder.apply() } }
        .onChange(of: minutes) { Task { await BackupReminder.apply() } }
        .confirmationDialog("Replace all meals on this iPhone with the backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                guard let url = restoreURL else { return }
                Task {
                    message = "Restoring…"
                    message = await backup.restore(fromFile: url)
                    bytes = ImageStore.folderBytes()
                }
            }
        } message: {
            Text("The meals now on this iPhone are replaced by the ones in the backup.")
        }
    }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var store = MealStore.shared

    var body: some View {
        SettingsPage(title: "About Pinggan") {
            Section {
                HStack(spacing: 14) {
                    Image("AppIconPreview").resizable().frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pinggan").font(.q(20, .bold))
                        Text("Version \(appVersion)").font(.subheadline).foregroundStyle(Theme.brown2)
                    }
                }
                .padding(.vertical, 4)
                HStack {
                    Text("Meals logged")
                    Spacer()
                    Text("\(store.meals.count)").foregroundStyle(Theme.brown2)
                }
                HStack {
                    Text("Dishes logged")
                    Spacer()
                    Text("\(store.meals.reduce(0) { $0 + $1.dishes.count })").foregroundStyle(Theme.brown2)
                }
            } footer: {
                footerText("Your personal food photo journal. Everything stays on this iPhone unless you back it up.")
            }
            .listRowBackground(Theme.cream)
        }
    }
}
