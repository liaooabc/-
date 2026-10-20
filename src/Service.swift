import AppKit
import Combine
import Foundation

@MainActor
final class UpdateService: ObservableObject {
    @Published private(set) var rows: [AppRow] = []
    @Published private(set) var updateCount: Int = 0
    @Published private(set) var checking: Bool = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastCheck: Date?
    @Published var settings = AppSettings()
    @Published private(set) var appCount: Int = 0

    private var apps: [InstalledApp] = []
    private var results: [String: CheckResult] = [:]
    private var timer: Timer?
    private var didBootstrap = false

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("UpdateRadar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var storeURL: URL { Self.supportDir.appendingPathComponent("state.json") }

    init() {
        load()
    }

    // MARK: - 启动

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        rescan()
        scheduleTimer()
        checkAll()
    }

    func rescan() {
        apps = Scanner.scan()
        appCount = apps.count
        rebuild()
    }

    // MARK: - 检测

    func checkAll() {
        guard !checking else { return }
        if apps.isEmpty { rescan() }
        let targets = apps
            .filter { !settings.ignored.contains($0.id) }
            .sorted { priority($0) > priority($1) }
        guard !targets.isEmpty else { return }

        checking = true
        progress = 0
        let total = Double(targets.count)

        Task { [weak self] in
            guard let self else { return }
            let batchSize = 6
            var index = 0
            while index < targets.count {
                let end = min(index + batchSize, targets.count)
                let slice = Array(targets[index..<end])
                await withTaskGroup(of: CheckResult.self) { group in
                    for app in slice {
                        group.addTask { await Checker.check(app) }
                    }
                    for await result in group {
                        self.results[result.bundleId] = result
                    }
                }
                index = end
                self.progress = Double(index) / total
                self.rebuild()
            }
            self.settings.lastCheck = Date()
            self.lastCheck = self.settings.lastCheck
            self.checking = false
            self.progress = 1
            self.save()
            self.notifyIfNeeded()
        }
    }

    /// 先查有检测源的，用户能更快看到有用结果
    private func priority(_ app: InstalledApp) -> Int {
        if Rules.match(app) != nil { return 3 }
        if app.sparkleFeed != nil { return 2 }
        if app.isAppStore { return 1 }
        return 0
    }

    // MARK: - 数据整合

    private func rebuild() {
        rows = apps.map { app in
            var result = results[app.id]
            if let r = result, let confirmed = settings.dismissed?[app.id], confirmed == (r.latest ?? "") {
                result?.status = .upToDate
                result?.note = "手动确认：商店版本 \(r.latest ?? "-")，本机包标注 \(app.version)，App Store 也认为已最新"
            }
            return AppRow(app: app, result: result)
        }
        updateCount = rows.filter { $0.isUpdate && !settings.ignored.contains($0.id) }.count
    }

    // MARK: - 设置

    func ignore(_ app: InstalledApp) {
        if !settings.ignored.contains(app.id) {
            settings.ignored.append(app.id)
        }
        rebuild()
        save()
    }

    func unignore(_ id: String) {
        settings.ignored.removeAll { $0 == id }
        rebuild()
        save()
    }

    func setInterval(_ hours: Double) {
        settings.intervalHours = hours
        scheduleTimer()
        save()
    }

    func setHideUnknown(_ hide: Bool) {
        settings.hideUnknown = hide
        save()
    }

    /// 用户说「这个已经是最新」：记下当时的商店版本号，商店再涨版本会自动恢复提醒
    func dismiss(_ row: AppRow) {
        var map = settings.dismissed ?? [:]
        map[row.id] = row.latest ?? ""
        settings.dismissed = map
        rebuild()
        save()
    }

    func undismiss(_ id: String) {
        settings.dismissed?[id] = nil
        rebuild()
        save()
    }

    func isDismissed(_ id: String) -> Bool {
        settings.dismissed?[id] != nil
    }

    func setShowCount(_ on: Bool) {
        settings.showCount = on
        save()
    }

    func setNotify(_ on: Bool) {
        settings.notifyOnUpdates = on
        save()
    }

    // MARK: - 通知

    /// 只在「可更新清单发生变化」时提醒，避免每轮都弹
    private func notifyIfNeeded() {
        guard settings.notifyEnabled else { return }
        let updates = rows.filter { $0.isUpdate && !settings.ignored.contains($0.id) }
            .sorted { $0.app.name < $1.app.name }
        let key = updates.map { "\($0.id)@\($0.latest ?? "")" }.joined(separator: "|")

        guard key != (settings.lastNotifiedKey ?? "") else { return }
        settings.lastNotifiedKey = key
        save()

        guard !updates.isEmpty else { return }
        let shown = updates.prefix(3)
            .map { "\($0.app.name) \($0.app.version)→\($0.latest ?? "?")" }
            .joined(separator: "、")
        let body = updates.count > 3 ? "\(shown) 等 \(updates.count) 个" : shown
        Notifier.shared.post(title: "\(updates.count) 个 App 有新版本", body: body, id: "updates")
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: max(0.25, settings.intervalHours) * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - 持久化

    private struct Disk: Codable {
        var settings: AppSettings
        var results: [String: CheckResult]
    }

    private func save() {
        let disk = Disk(settings: settings, results: results)
        guard let data = try? JSONEncoder().encode(disk) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let disk = try? JSONDecoder().decode(Disk.self, from: data) else { return }
        settings = disk.settings
        results = disk.results
        lastCheck = disk.settings.lastCheck
    }

    // MARK: - 动作

    func openUpdate(for row: AppRow) {
        if let s = row.result?.downloadURL, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        } else {
            reveal(row.app)
        }
    }

    func reveal(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    func launch(_ app: InstalledApp) {
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
    }
}
