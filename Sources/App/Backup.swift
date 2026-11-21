import Foundation
import SwiftUI

/// Copies meals.json and the Images folder to a folder you pick in Files (e.g. iCloud Drive › Pinggan).
/// Only new or changed photos are copied each time.
@MainActor
final class BackupService: ObservableObject {
    static let shared = BackupService()

    @Published var status = ""
    @Published var lastBackup: Date? = UserDefaults.standard.object(forKey: Keys.lastBackup) as? Date
    @Published var folderName: String? = UserDefaults.standard.string(forKey: Keys.backupFolderName)
    @Published var running = false

    private var pending: Task<Void, Never>?

    var hasFolder: Bool { UserDefaults.standard.data(forKey: Keys.backupBookmark) != nil }

    func setFolder(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Keys.backupBookmark)
            UserDefaults.standard.set(url.lastPathComponent, forKey: Keys.backupFolderName)
            folderName = url.lastPathComponent
            status = ""
            backupNow()
        } catch {
            status = "That folder couldn't be remembered: \(error.localizedDescription)"
        }
    }

    private func resolveFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Keys.backupBookmark) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, url.startAccessingSecurityScopedResource() {
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: Keys.backupBookmark)
            }
            url.stopAccessingSecurityScopedResource()
        }
        return url
    }

    func scheduleBackup() {
        guard hasFolder else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await self.run()
        }
    }

    func backupNow() {
        guard hasFolder else { return }
        pending?.cancel()
        Task { @MainActor in await self.run() }
    }

    private func run() async {
        guard !running else { return }
        guard let folder = resolveFolder() else {
            status = "Backup folder not found. Choose it again."
            return
        }
        MealStore.shared.persistNow(triggerBackup: false)
        running = true
        let localCount = MealStore.shared.meals.count
        let result = await Task.detached(priority: .utility) {
            BackupService.copy(to: folder, localCount: localCount)
        }.value
        running = false
        if result.ok {
            let now = Date()
            lastBackup = now
            UserDefaults.standard.set(now, forKey: Keys.lastBackup)
        }
        status = result.message
    }

    nonisolated static func copy(to folder: URL, localCount: Int) -> (ok: Bool, message: String) {
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let dest = folder.appendingPathComponent("Pinggan Backup", isDirectory: true)
        let destImages = dest.appendingPathComponent("Images", isDirectory: true)
        let history = dest.appendingPathComponent("History", isDirectory: true)
        do {
            try fm.createDirectory(at: destImages, withIntermediateDirectories: true)
            try fm.createDirectory(at: history, withIntermediateDirectories: true)

            // Safety: if far fewer meals are on the phone than in the backup, something went wrong — don't overwrite.
            let remoteJSON = dest.appendingPathComponent("meals.json")
            if let d = try? Data(contentsOf: remoteJSON),
               let arr = (try? JSONSerialization.jsonObject(with: d)) as? [Any],
               arr.count >= 10, localCount * 2 < arr.count {
                return (false, "Backup paused: the backup has \(arr.count) meals but this iPhone has \(localCount). Restore from the backup if meals are missing.")
            }

            func sizes(_ dir: URL) -> [String: Int] {
                let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                var out: [String: Int] = [:]
                for u in items { out[u.lastPathComponent] = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
                return out
            }
            let local = sizes(Paths.images)
            let remote = sizes(destImages)
            var copied = 0
            for (name, size) in local where remote[name] != size {
                let target = destImages.appendingPathComponent(name)
                if remote[name] != nil { try? fm.removeItem(at: target) }
                try fm.copyItem(at: Paths.images.appendingPathComponent(name), to: target)
                copied += 1
            }
            for name in remote.keys where local[name] == nil {
                try? fm.removeItem(at: destImages.appendingPathComponent(name))
            }

            let data = (try? Data(contentsOf: Paths.data)) ?? Data("[]".utf8)
            try data.write(to: remoteJSON, options: .atomic)
            try data.write(to: history.appendingPathComponent("meals-\(Fmt.stamp.string(from: Date())).json"), options: .atomic)
            let old = ((try? fm.contentsOfDirectory(at: history, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .dropFirst(30)
            for u in old { try? fm.removeItem(at: u) }

            return (true, copied == 0 ? "Backed up" : "Backed up (\(copied) new \(copied == 1 ? "file" : "files"))")
        } catch {
            return (false, "Backup failed: \(error.localizedDescription)")
        }
    }

    /// Replaces everything on this iPhone with the backup in `folder` (the "Pinggan Backup" folder or the folder holding it).
    func restore(from folder: URL) async -> String {
        MealStore.shared.persistNow(triggerBackup: false)
        let result = await Task.detached(priority: .userInitiated) { () -> String in
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            let fm = FileManager.default
            var src = folder
            if !fm.fileExists(atPath: src.appendingPathComponent("meals.json").path) {
                src = folder.appendingPathComponent("Pinggan Backup", isDirectory: true)
            }
            let json = src.appendingPathComponent("meals.json")
            guard let data = try? Data(contentsOf: json) else { return "No Pinggan backup found in that folder." }
            guard let meals = try? JSON.decoder.decode([Meal].self, from: data) else { return "That backup couldn't be read." }
            let srcImages = src.appendingPathComponent("Images", isDirectory: true)
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
            do {
                try data.write(to: Paths.data, options: .atomic)
            } catch {
                return "Restore failed: \(error.localizedDescription)"
            }
            return "Restored \(meals.count) meals and \(copied) photos."
        }.value
        ImageStore.clearCache()
        MealStore.shared.load()
        return result
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
