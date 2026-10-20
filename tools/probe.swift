import Foundation

// 命令行探针：复用 App 内的扫描与检测逻辑，直接打印结果，用来验证判断是否正确。
let apps = Scanner.scan()
FileHandle.standardError.write("扫描到 \(apps.count) 个 App\n".data(using: .utf8)!)

func line(_ s: String) { print(s) }

let sem = DispatchSemaphore(value: 0)
var results: [(InstalledApp, CheckResult)] = []
let lock = NSLock()

Task {
    var buffer: [(InstalledApp, CheckResult)] = []
    var index = 0
    let batch = 8
    while index < apps.count {
        let end = min(index + batch, apps.count)
        let slice = Array(apps[index..<end])
        await withTaskGroup(of: (InstalledApp, CheckResult).self) { group in
            for app in slice {
                group.addTask { (app, await Checker.check(app)) }
            }
            for await pair in group {
                buffer.append(pair)
            }
        }
        index = end
        FileHandle.standardError.write("  进度 \(index)/\(apps.count)\n".data(using: .utf8)!)
    }
    lock.lock(); results = buffer; lock.unlock()
    sem.signal()
}

sem.wait()

let updates = results.filter { $0.1.status == .updateAvailable }
let upToDate = results.filter { $0.1.status == .upToDate }
let unknown = results.filter { $0.1.status == .unknown }

line("")
line("=== 有新版本（\(updates.count)）===")
for (app, r) in updates.sorted(by: { $0.0.name < $1.0.name }) {
    line(String(format: "%-24@ %-12@ → %-12@ [%@] %@",
                app.name as NSString, app.version as NSString,
                (r.latest ?? "?") as NSString, (r.source ?? "-") as NSString,
                (r.note ?? "") as NSString))
}

line("")
line("=== 已是最新（\(upToDate.count)）===")
for (app, r) in upToDate.sorted(by: { $0.0.name < $1.0.name }) {
    line(String(format: "%-24@ %-14@ [%@] %@",
                app.name as NSString, app.version as NSString,
                (r.source ?? "-") as NSString, (r.note ?? "") as NSString))
}

line("")
line("=== 无检测源（\(unknown.count)）===")
line(unknown.map { $0.0.name }.joined(separator: "、"))

line("")
line("=== 重点核对 ===")
for name in ["WeChat", "QQ", "Obsidian", "IINA", "Atd", "Chrome"] {
    if let (app, r) = results.first(where: { $0.0.name.contains(name) }) {
        line("\(app.name): 本机 \(app.version) / 状态 \(r.status.rawValue) / 最新 \(r.latest ?? "?") / 源 \(r.source ?? "-") / \(r.downloadURL ?? "-")")
    }
}
