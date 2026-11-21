import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var backup = BackupService.shared
    @ObservedObject private var store = MealStore.shared
    @ObservedObject private var pantry = Pantry.shared

    @AppStorage(Keys.aiMode) private var aiMode = AIMode.onDevice.rawValue
    @AppStorage(Keys.aiModel) private var model = ClaudeClient.defaultModel
    @AppStorage(Keys.photoSide) private var photoSide = 1280
    @AppStorage(Keys.shrinkMonths) private var shrinkMonths = 6
    @AppStorage(Keys.shrinkSide) private var shrinkSide = 800

    @State private var key = Keychain.get(ClaudeClient.keychainKey) ?? ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var bytes: Int64 = 0
    @State private var importer: ImporterMode?
    @State private var showImporter = false
    @State private var restoreURL: URL?
    @State private var confirmRestore = false
    @State private var restoreMessage: String?
    @State private var confirmForget = false

    private enum ImporterMode { case backupFolder, restore }

    private var keyMasked: String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count > 12 else { return k.isEmpty ? "Not set" : "Set" }
        return String(k.prefix(7)) + "••••" + String(k.suffix(4))
    }

    var body: some View {
        let usage = Usage.thisMonth
        let device = OnDeviceAI.status
        Form {
            Section {
                Text("Settings").font(.q(34, .bold)).foregroundStyle(.white)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))
            }

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
            } header: {
                sectionHeader("Food AI")
            } footer: {
                Text("On-device AI runs on your iPhone with Apple Intelligence: free, private and works offline, but its names and numbers are rougher. Claude is more accurate for local dishes and needs API credit.")
                    .foregroundStyle(Theme.brown2)
            }
            .listRowBackground(Theme.cream)

            Section {
                SecureField("sk-ant-…", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
                    Text(testResult).font(.footnote).foregroundStyle(testResult == "Key works." ? Color(hex: 0x3B9C6B) : Color(hex: 0xC0392B))
                }
                Picker("Model", selection: $model) {
                    Text("Sonnet 5.5 · most accurate").tag(ClaudeClient.defaultModel)
                    Text("Haiku 5.5 · cheaper").tag(ClaudeClient.cheapModel)
                }
                HStack {
                    Text("This month")
                    Spacer()
                    Text("\(usage.photos) photos · ≈ \(Fmt.rm(usage.rm))").foregroundStyle(Theme.brown2)
                }
            } header: {
                sectionHeader("Claude (optional)")
            } footer: {
                Text("Only used when Food AI is set to Claude. Create a key at platform.claude.com under API keys and add credit under Billing. The key stays in this iPhone's Keychain. The cost shown is a rough estimate.")
                    .foregroundStyle(Theme.brown2)
            }
            .listRowBackground(Theme.cream)

            Section {
                NavigationLink {
                    ProductsView()
                } label: {
                    HStack {
                        Text("Saved products")
                        Spacer()
                        Text("\(pantry.products.count)").foregroundStyle(Theme.brown2)
                    }
                }
                HStack {
                    Text("Remembered dishes")
                    Spacer()
                    Text("\(pantry.dishes.count)").foregroundStyle(Theme.brown2)
                }
                if !pantry.dishes.isEmpty {
                    Button("Forget remembered dishes", role: .destructive) { confirmForget = true }
                }
            } header: {
                sectionHeader("My food")
            } footer: {
                Text("Products come from food labels you scan. Remembered dishes are ones you corrected, so the AI gets them right next time.")
                    .foregroundStyle(Theme.brown2)
            }
            .listRowBackground(Theme.cream)

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
            } header: {
                sectionHeader("Storage")
            } footer: {
                Text("Photos are saved as HEIC. Shrinking runs when you open the app. Cut-outs, thumbnails and meal details are never shrunk.")
                    .foregroundStyle(Theme.brown2)
            }
            .listRowBackground(Theme.cream)

            Section {
                Button {
                    importer = .backupFolder
                    showImporter = true
                } label: {
                    HStack {
                        Text("Backup folder").foregroundStyle(Theme.brown)
                        Spacer()
                        Text(backup.folderName ?? "Choose").foregroundStyle(Theme.brown2)
                    }
                }
                HStack {
                    Text("Last backup")
                    Spacer()
                    Text(backup.lastBackup.map { Fmt.dayShort.string(from: $0) + ", " + Fmt.time.string(from: $0) } ?? "Never")
                        .foregroundStyle(Theme.brown2)
                }
                Button {
                    backup.backupNow()
                } label: {
                    HStack {
                        Text("Back up now").foregroundStyle(Theme.coral)
                        if backup.running { Spacer(); ProgressView() }
                    }
                }
                .disabled(!backup.hasFolder || backup.running)
                Button("Restore from backup…") {
                    importer = .restore
                    showImporter = true
                }
                .foregroundStyle(Theme.coral)
                if !backup.status.isEmpty {
                    Text(backup.status).font(.footnote).foregroundStyle(Theme.brown2)
                }
                if let restoreMessage {
                    Text(restoreMessage).font(.footnote).foregroundStyle(Theme.brown2)
                }
            } header: {
                sectionHeader("Backup")
            } footer: {
                Text("Pick a folder in iCloud Drive so the backup doesn't use space on this iPhone. Pinggan makes a “Pinggan Backup” folder inside it and copies only new photos each time. To restore, pick that “Pinggan Backup” folder.")
                    .foregroundStyle(Theme.brown2)
            }
            .listRowBackground(Theme.cream)

            Section {
                HStack(spacing: 12) {
                    Image("AppIconPreview")
                        .resizable()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pinggan").font(.q(16, .bold))
                        Text("Version \(appVersion) · \(store.meals.count) meals logged").font(.caption).foregroundStyle(Theme.brown2)
                    }
                }
            }
            .listRowBackground(Theme.cream)
        }
        .creamList()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            Task.detached(priority: .utility) {
                let b = ImageStore.folderBytes()
                await MainActor.run { bytes = b }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            switch importer {
            case .backupFolder:
                backup.setFolder(url)
            case .restore:
                restoreURL = url
                confirmRestore = true
            case .none:
                break
            }
        }
        .confirmationDialog("Replace all meals on this iPhone with the backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                guard let url = restoreURL else { return }
                Task {
                    restoreMessage = "Restoring…"
                    restoreMessage = await backup.restore(from: url)
                    bytes = ImageStore.folderBytes()
                }
            }
        } message: {
            Text("The meals now on this iPhone are replaced by the ones in the backup.")
        }
        .confirmationDialog("Forget all remembered dishes?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) { pantry.clearDishes() }
        }
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t).font(.q(12.5, .bold)).foregroundStyle(Theme.brown2)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (build \(b))"
    }
}

struct ProductsView: View {
    @ObservedObject private var pantry = Pantry.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack {
                    RoundNavButton(icon: "chevron.left") { dismiss() }
                    Text("Saved products").font(.q(22, .bold)).foregroundStyle(.white)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            Section {
                if pantry.products.isEmpty {
                    Text("Scan a food label with the camera's “Food label” option and it will be saved here.")
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
            }
            .listRowBackground(Theme.cream)
        }
        .creamList()
        .toolbar(.hidden, for: .navigationBar)
    }
}
