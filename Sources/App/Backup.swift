import Foundation
import SwiftUI
import UIKit
import AppleArchive
import System
import UserNotifications

/// Backup = one file (Apple Archive) with meals, products and photos, saved wherever you choose
/// with iOS's "save a file" screen. Picking a folder doesn't work on this iPhone, so nothing here needs it.
@MainActor
final class BackupService: ObservableObject {
    static let shared = BackupService()

    @Published var status = ""
    @Published var lastBackup: Date? = UserDefaults.standard.object(forKey: Keys.lastBackup) as? Date
    @Published var working = false

    /// Kept so other code can say "something changed"; backups are saved by you, not automatically.
    func scheduleBackup() {}

    var isDue: Bool {
        guard !MealStore.shared.meals.isEmpty else { return false }
        guard let last = lastBackup else { return true }
        return Date().timeIntervalSince(last) > 7 * 86_400
    }

    var daysSince: Int? {
        guard let last = lastBackup else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    // MARK: Save

    func saveBackup() {
        guard !working else { return }
        working = true
        status = "Packing your meals…"
        MealStore.shared.persistNow(triggerBackup: false)
        Task {
            let result = await Task.detached(priority: .userInitiated) { BackupService.makeArchive() }.value
            switch result {
            case .failure(let error):
                working = false
                status = "The backup file couldn't be made: \(error.localizedDescription)"
            case .success(let file):
                status = ""
                FilePicker.shared.export(file) { [weak self] saved in
                    guard let self else { return }
                    self.working = false
                    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
                    if saved != nil {
                        let now = Date()
                        self.lastBackup = now
                        UserDefaults.standard.set(now, forKey: Keys.lastBackup)
                        self.status = "Backup saved."
                    } else {
                        self.status = "Not saved."
                    }
                }
            }
        }
    }

    /// Archives Documents/Pinggan (meals.json, pantry.json, Images) into one .aar file in the temporary folder.
    nonisolated static func makeArchive() -> Result<URL, Error> {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let out = work.appendingPathComponent("Pinggan-backup-\(Fmt.stamp.string(from: Date())).aar")
            guard let fileStream = ArchiveByteStream.fileStream(path: FilePath(out.path), mode: .writeOnly,
                                                                options: [.create], permissions: FilePermissions(rawValue: 0o644)),
                  let compressStream = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: fileStream),
                  let encodeStream = ArchiveStream.encodeStream(writingTo: compressStream),
                  let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DEV,DAT,MOD,FLG,MTM,BTM,CTM") else {
                return .failure(CocoaError(.fileWriteUnknown))
            }
            var failure: Error?
            do {
                try encodeStream.writeDirectoryContents(archiveFrom: FilePath(Paths.root.path), keySet: keySet)
            } catch {
                failure = error
            }
            try? encodeStream.close()
            try? compressStream.close()
            try? fileStream.close()
            if let failure { return .failure(failure) }
            return .success(out)
        } catch {
            return .failure(error)
        }
    }

    // MARK: Restore

    /// Replaces everything on this iPhone with the backup file.
    func restore(fromFile file: URL) async -> String {
        MealStore.shared.persistNow(triggerBackup: false)
        let result = await Task.detached(priority: .userInitiated) { () -> String in
            let fm = FileManager.default
            let ok = file.startAccessingSecurityScopedResource()
            defer { if ok { file.stopAccessingSecurityScopedResource() } }
            let dest = fm.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: dest) }
            do {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                guard let readStream = ArchiveByteStream.fileStream(path: FilePath(file.path), mode: .readOnly,
                                                                    options: [], permissions: FilePermissions(rawValue: 0o644)),
                      let decompressStream = ArchiveByteStream.decompressionStream(readingFrom: readStream),
                      let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream),
                      let extractStream = ArchiveStream.extractStream(extractingTo: FilePath(dest.path),
                                                                      flags: [.ignoreOperationNotPermitted]) else {
                    return "That file couldn't be opened. Pick a Pinggan backup (.aar) file."
                }
                var failure: Error?
                do {
                    _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
                } catch {
                    failure = error
                }
                try? extractStream.close()
                try? decodeStream.close()
                try? decompressStream.close()
                try? readStream.close()
                if let failure { return "That backup couldn't be read: \(failure.localizedDescription)" }
            } catch {
                return "That backup couldn't be read: \(error.localizedDescription)"
            }
            return BackupService.install(from: dest)
        }.value
        ImageStore.clearCache()
        MealStore.shared.load()
        Pantry.shared.load()
        return result
    }

    /// Copies an unpacked backup (meals.json, pantry.json, Images) into the app.
    nonisolated static func install(from dir: URL) -> String {
        let fm = FileManager.default
        let json = dir.appendingPathComponent("meals.json")
        guard let data = try? Data(contentsOf: json) else { return "No Pinggan meals were found in that file." }
        guard let meals = try? JSON.decoder.decode([Meal].self, from: data) else { return "That backup couldn't be read." }
        let srcImages = dir.appendingPathComponent("Images", isDirectory: true)
        let items = (try? fm.contentsOfDirectory(at: srcImages, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var copied = 0
        for u in items {
            let target = Paths.images.appendingPathComponent(u.lastPathComponent)
            let a = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            let b = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
            if a == b { continue }
            try? fm.removeItem(at: target)
            if (try? fm.copyItem(at: u, to: target)) != nil { copied += 1 }
        }
        if let pantry = try? Data(contentsOf: dir.appendingPathComponent("pantry.json")) {
            try? pantry.write(to: Paths.pantry, options: .atomic)
        }
        do {
            try data.write(to: Paths.data, options: .atomic)
        } catch {
            return "Restore failed: \(error.localizedDescription)"
        }
        return "Restored \(meals.count) meals and \(copied) photos."
    }
}

// MARK: - Weekly reminder

enum BackupReminder {
    static let enabledKey = "backupReminderOn"
    static let weekdayKey = "backupReminderWeekday"    // 1 = Sunday … 7 = Saturday
    static let minutesKey = "backupReminderMinutes"    // minutes after midnight
    private static let id = "pinggan-weekly-backup"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var weekday: Int { UserDefaults.standard.integer(forKey: weekdayKey) }
    static var minutes: Int { UserDefaults.standard.integer(forKey: minutesKey) }

    static func apply() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "Back up Pinggan"
        content.body = "Save this week's meals and photos to iCloud Drive."
        content.sound = .default
        var when = DateComponents()
        when.weekday = max(1, min(7, weekday))
        when.hour = minutes / 60
        when.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

// MARK: - File pickers (UIKit, opened straight from the app)

@MainActor
final class FilePicker: NSObject, UIDocumentPickerDelegate {
    static let shared = FilePicker()
    private var completion: ((URL?) -> Void)?

    /// "Save a file" screen.
    func export(_ url: URL, _ completion: @escaping (URL?) -> Void) {
        present(UIDocumentPickerViewController(forExporting: [url], asCopy: true), completion)
    }

    /// Pick one file; it's copied into the app first.
    func pickFile(_ completion: @escaping (URL?) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        present(picker, completion)
    }

    private func present(_ picker: UIDocumentPickerViewController, _ completion: @escaping (URL?) -> Void) {
        guard let top = Self.topViewController() else { completion(nil); return }
        self.completion = completion
        picker.delegate = self
        top.present(picker, animated: true)
    }

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let first = urls.first
        Task { @MainActor in self.finish(first) }
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor in self.finish(nil) }
    }

    private func finish(_ url: URL?) {
        let c = completion
        completion = nil
        c?(url)
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

@MainActor
enum Maintenance {
    static var running = false

    /// Re-saves photos of meals older than the chosen number of months at the smaller size.
    static func shrinkOldPhotos() {
        let ud = UserDefaults.standard
        let months = ud.integer(forKey: Keys.shrinkMonths)
        guard months > 0, !running else { return }
        let side = CGFloat(max(320, ud.integer(forKey: Keys.shrinkSide)))
        guard let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) else { return }
        let targets = MealStore.shared.meals.filter { $0.date < cutoff && !$0.photoShrunk && $0.photo != nil }
        guard !targets.isEmpty else { return }
        running = true
        let jobs = targets.compactMap { m -> (UUID, String)? in
            guard let p = m.photo else { return nil }
            return (m.id, p)
        }
        Task.detached(priority: .background) {
            var done: [UUID] = []
            for (id, name) in jobs where ImageStore.shrink(name, maxSide: side) { done.append(id) }
            let finished = done
            await MainActor.run {
                MealStore.shared.markShrunk(finished)
                Maintenance.running = false
            }
        }
    }
}

