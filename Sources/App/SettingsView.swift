import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var backup = BackupService.shared
    @ObservedObject private var store = MealStore.shared

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

    private enum ImporterMode { case backupFolder, restore }

    private var keyMasked: String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count > 12 else { return k.isEmpty ? "Not set" : "Set" }
        return String(k.prefix(7)) + "••••" + String(k.suffix(4))
    }

    var body: some View {
        let usage = Usage.thisMonth
        Form {
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
                    Text(keyMasked).foregroundStyle(.secondary)
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
                        Text("Test key")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(key.isEmpty || testing)
                if let testResult {
                    Text(testResult).font(.footnote).foregroundStyle(testResult == "Key works." ? Color.green : Color.red)
                }
                Picker("Model", selection: $model) {
                    Text("Sonnet 5.5 · most accurate").tag(ClaudeClient.defaultModel)
                    Text("Haiku 5.5 · cheaper").tag(ClaudeClient.cheapModel)
                }
                HStack {
                    Text("This month")
                    Spacer()
                    Text("\(usage.photos) photos · ≈ \(Fmt.rm(usage.rm))").foregroundStyle(.secondary)
                }
            } header: {
                Text("Claude AI")
            } footer: {
                Text("Create a key at console.anthropic.com under API keys. It's kept in this iPhone's Keychain and only sent to Anthropic. The cost shown is a rough estimate.")
            }

            Section {
                HStack {
                    Text("Pinggan is using")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).foregroundStyle(.secondary)
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
                .disabled(shrinkMonths == 0)
            } header: {
                Text("Storage")
            } footer: {
                Text("Photos are saved as HEIC. Shrinking runs when you open the app. Cut-outs, thumbnails and meal details are never shrunk.")
            }

            Section {
                Button {
                    importer = .backupFolder
                    showImporter = true
                } label: {
                    HStack {
                        Text("Backup folder").foregroundStyle(Color.primary)
                        Spacer()
                        Text(backup.folderName ?? "Choose").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Last backup")
                    Spacer()
                    Text(backup.lastBackup.map { Fmt.dayShort.string(from: $0) + ", " + Fmt.time.string(from: $0) } ?? "Never")
                        .foregroundStyle(.secondary)
                }
                Button {
                    backup.backupNow()
                } label: {
                    HStack {
                        Text("Back up now")
                        if backup.running { Spacer(); ProgressView() }
                    }
                }
                .disabled(!backup.hasFolder || backup.running)
                Button("Restore from backup…") {
                    importer = .restore
                    showImporter = true
                }
                if !backup.status.isEmpty {
                    Text(backup.status).font(.footnote).foregroundStyle(.secondary)
                }
                if let restoreMessage {
                    Text(restoreMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Pick a folder in iCloud Drive so the backup doesn't use space on this iPhone. Pinggan makes a “Pinggan Backup” folder inside it and copies only new photos each time. To restore, pick that “Pinggan Backup” folder.")
            }

            Section {
                HStack {
                    Text("Meals logged")
                    Spacer()
                    Text("\(store.meals.count)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
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
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (build \(b))"
    }
}
