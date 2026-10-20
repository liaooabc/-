import Foundation

/// 1.5.0 / v4.13.3 / 2026.39 / "Version 4.13.3" 这种才算版本号，"Download" 这类标题不算
private func looksLikeVersion(_ s: String) -> Bool {
    var t = s.trimmingCharacters(in: .whitespaces)
    for prefix in ["Version ", "version ", "v"] where t.hasPrefix(prefix) {
        t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        break
    }
    guard t.count >= 1, t.count <= 24 else { return false }
    if t.contains(" ") { return false }
    guard let first = t.first, first.isNumber else { return false }
    return t.contains(where: { $0.isNumber })
}

// MARK: - Sparkle appcast

final class AppcastParser: NSObject, XMLParserDelegate {
    struct Item {
        var title: String?
        var shortVersion: String?
        var buildVersion: String?
        var minSystem: String?
        var link: String?
        var enclosure: String?
        var pubDate: String?
        var notes: String?
        var notesLink: String?

        /// 对外展示、用来比较的版本号。营销版本号优先，其次 title（老式 appcast 把版本写在 title 里），
        /// 最后才是构建号——构建号跟 CFBundleShortVersionString 不是一套编号，不能混比。
        var marketingVersion: String? {
            if let v = shortVersion, !v.isEmpty { return v }
            if let t = title, looksLikeVersion(t) {
                // 去掉 "Version " 前缀再拿去比较
                var s = t.trimmingCharacters(in: .whitespaces)
                for p in ["Version ", "version "] where s.hasPrefix(p) {
                    s = String(s.dropFirst(p.count))
                    break
                }
                return s
            }
            return nil
        }
    }

    /// 1.5.0 / v4.13.3 / 2026.39 这种才算版本号，"Download" 这类标题不算
    private(set) var items: [Item] = []
    private var current: Item?
    private var buffer = ""
    private var inItem = false

    func parse(_ data: Data) -> [Item] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let el = elementName.lowercased()
        if el == "item" {
            inItem = true
            current = Item()
        }
        if el == "enclosure", inItem {
            current?.enclosure = attributeDict["url"]
            if current?.buildVersion == nil {
                current?.buildVersion = attributeDict["sparkle:version"] ?? attributeDict["version"]
            }
        }
        if inItem { buffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let el = elementName.lowercased()
        guard inItem else { return }
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "sparkle:shortversionstring":
            if !text.isEmpty { current?.shortVersion = text }
        case "title":
            if !text.isEmpty { current?.title = text }
        case "sparkle:version":
            if !text.isEmpty { current?.buildVersion = text }
        case "sparkle:minimumsystemversion":
            if !text.isEmpty { current?.minSystem = text }
        case "link":
            if !text.isEmpty { current?.link = text }
        case "pubdate":
            if !text.isEmpty { current?.pubDate = text }
        case "description":
            if current?.notes == nil, !text.isEmpty { current?.notes = text }
        case "sparkle:releasenoteslink":
            if !text.isEmpty { current?.notesLink = text }
        case "item":
            if let c = current { items.append(c) }
            current = nil
            inItem = false
        default:
            break
        }
        buffer = ""
    }
}

/// 更新说明常是 HTML，去掉标签、实体和多余空白，只留能读的字
func plainNotes(_ raw: String?, limit: Int = 240) -> String? {
    guard var s = raw else { return nil }
    s = s.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: "(?s)<br\\s*/?>", with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
    let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
                    "&quot;": "\"", "&#39;": "'", "&mdash;": "—", "&hellip;": "…"]
    for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
    s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
    // 很多更新说明以·、•、- 开头，显示在行首很怪，去掉
    while let f = s.first, "·•-–—*>\u{2022}\u{00B7}\u{25CF}\u{3000} ".contains(f) {
        s.removeFirst()
    }
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    if s.count > limit { s = String(s.prefix(limit)) + "…" }
    return s
}

/// appcast 的 pubDate 是 RFC822 格式
func parseRFC822(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    if let d = f.date(from: s) { return d }
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return f.date(from: s)
}

func parseISO8601(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f = ISO8601DateFormatter()
    return f.date(from: s)
}

// MARK: - 网络

enum Net {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 25
        c.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]
        return URLSession(configuration: c)
    }()

    /// raw.githubusercontent.com 在国内时通时不通，用 jsDelivr 做镜像兜底
    private static func jsdelivrMirror(_ urlString: String) -> String? {
        guard let url = URL(string: urlString), url.host == "raw.githubusercontent.com" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 3 else { return nil }
        let owner = parts[0], repo = parts[1], branch = parts[2]
        let rest = parts.dropFirst(3).joined(separator: "/")
        guard !rest.isEmpty else { return nil }
        return "https://cdn.jsdelivr.net/gh/\(owner)/\(repo)@\(branch)/\(rest)"
    }

    private static func fetchText(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }

    static func text(_ urlString: String, retry: Bool = true) async -> String? {
        if let s = await fetchText(urlString) { return s }
        guard retry else { return nil }
        if let alt = jsdelivrMirror(urlString), let s = await fetchText(alt) { return s }
        try? await Task.sleep(nanoseconds: 500_000_000)
        return await fetchText(urlString)
    }

    static func json(_ urlString: String, retry: Bool = true) async -> Any? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        } catch {
            if retry {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return await json(urlString, retry: false)
            }
            return nil
        }
    }
}

// MARK: - 检测器

enum Checker {
    static func check(_ app: InstalledApp) async -> CheckResult {
        let bid = app.id
        let now = Date()

        func failed(_ note: String) -> CheckResult {
            CheckResult(bundleId: bid, status: .failed, latest: nil,
                        downloadURL: nil, note: note, source: "failed", checkedAt: now)
        }

        // 1. 厂商专用规则优先（微信这类没有 appcast 的常用软件）
        if let rule = Rules.match(app) {
            if let r = await rule.run(app) {
                return CheckResult(bundleId: bid, status: r.status, latest: r.latest,
                                   downloadURL: r.url, note: r.note, source: "vendor",
                                   checkedAt: now, releaseDate: r.releaseDate, notes: r.notes)
            }
            // 规则命中但这次没抓到：说明是网络/页面变动问题，不是“没有检测源”
            return failed("官网页面没抓到版本号")
        }

        // 2. Sparkle appcast：34 个 App 走这条路
        if let feed = app.sparkleFeed {
            if let r = await sparkle(feed: feed, current: app.version) {
                return CheckResult(bundleId: bid, status: r.status, latest: r.latest,
                                   downloadURL: r.url, note: nil, source: "sparkle",
                                   checkedAt: now, releaseDate: r.releaseDate, notes: r.notes)
            }
            return failed("更新源没有响应")
        }

        // 3. Mac App Store 上架的应用（不在商店里属于正常情况，算无检测源）
        if let bidReal = app.bundleId, app.isAppStore {
            if let r = await appStore(bundleId: bidReal, current: app.version, installedAt: app.installedAt) {
                return CheckResult(bundleId: bidReal, status: r.status, latest: r.latest,
                                   downloadURL: r.url, note: nil, source: "appstore",
                                   checkedAt: now, releaseDate: r.releaseDate, notes: r.notes)
            }
        }

        return CheckResult(bundleId: bid, status: .unknown, latest: nil,
                           downloadURL: nil, note: nil, source: "manual", checkedAt: now)
    }

    struct Outcome {
        var status: CheckStatus
        var latest: String?
        var url: String?
        var note: String?
        var releaseDate: Date?
        var notes: String?
    }

    static func sparkle(feed: String, current: String) async -> Outcome? {
        guard let body = await Net.text(feed), !body.isEmpty else { return nil }
        let items = AppcastParser().parse(Data(body.utf8))
        guard !items.isEmpty else { return nil }

        // appcast 里条目按新到旧排列，取第一条「本机系统能装」且带可用版本号的
        for it in items {
            guard systemSatisfies(it.minSystem), let latest = it.marketingVersion else { continue }
            let newer = Ver.isNewer(latest, than: current)
            var notes = plainNotes(it.notes)
            if notes == nil, newer, let link = it.notesLink, let html = await Net.text(link) {
                notes = plainNotes(html)
            }
            return Outcome(status: newer ? .updateAvailable : .upToDate,
                           latest: latest,
                           url: it.enclosure ?? it.link ?? feed,
                           note: nil,
                           releaseDate: parseRFC822(it.pubDate),
                           notes: newer ? notes : nil)
        }
        return nil
    }

    static func appStore(bundleId: String, current: String, installedAt: Date?) async -> Outcome? {
        let url = "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=cn"
        guard let obj = await Net.json(url) as? [String: Any],
              let count = obj["resultCount"] as? Int, count > 0,
              let results = obj["results"] as? [[String: Any]],
              let first = results.first,
              let latest = first["version"] as? String else { return nil }
        let page = first["trackViewUrl"] as? String
        let release = parseISO8601(first["currentVersionReleaseDate"] as? String)

        // 有些开发者发版时没同步 Mac 包里的 CFBundleShortVersionString，
        // 导致「商店 1.13、包内写着 1.4」。Apple 比的是构建号，认为已最新；
        // 这里用安装时间兜底：包比商店那次发布还新，就说明拿到的就是最新包。
        if Ver.isNewer(latest, than: current), let installedAt, let release,
           installedAt > release.addingTimeInterval(60 * 60) {
            return Outcome(status: .upToDate, latest: latest, url: page,
                           note: "商店版本是 \(latest)，但本机包内标注 \(current)：开发者没同步 Mac 包的版本号，App Store 也认为已是最新",
                           releaseDate: release)
        }

        let isNewer = Ver.isNewer(latest, than: current)
        return Outcome(status: isNewer ? .updateAvailable : .upToDate,
                       latest: latest, url: page, note: nil,
                       releaseDate: release,
                       notes: isNewer ? plainNotes(first["releaseNotes"] as? String) : nil)
    }
}

// MARK: - 厂商规则

struct VendorRule {
    let matches: (InstalledApp) -> Bool
    let run: (InstalledApp) async -> Checker.Outcome?
}

enum Rules {
    /// 把一个「官方最新版本号」变成检测结果；本机反而更高时给个说明
    static func verdict(_ app: InstalledApp, latest: String, url: String, releaseDate: Date? = nil) -> Checker.Outcome {
        let newer = Ver.isNewer(latest, than: app.version)
        // 只有「本机反而更高」时才需要解释，版本相同或更新都保持沉默
        let note: String? = (!newer && Ver.isNewer(app.version, than: latest))
            ? "官方源当前是 \(latest)，你装的版本更高（可能是内测版）"
            : nil
        return Checker.Outcome(status: newer ? .updateAvailable : .upToDate,
                               latest: latest, url: url, note: note, releaseDate: releaseDate)
    }

    /// 官网页面里抓版本号
    static func pageRegex(app: InstalledApp, page: String, pattern: String,
                          downloadPage: String) async -> Checker.Outcome? {
        guard let html = await Net.text(page) else { return nil }
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = html as NSString
        let found = re.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var versions: [String] = []
        for m in found where m.numberOfRanges > 1 {
            versions.append(ns.substring(with: m.range(at: 1)))
        }
        guard let latest = versions.max(by: { Ver.compare($0, $1) == .orderedAscending }) else { return nil }
        return verdict(app, latest: latest, url: downloadPage)
    }

    /// GitHub Releases 最新 tag
    static func githubRepo(app: InstalledApp, repo: String, downloadPage: String) async -> Checker.Outcome? {
        let url = "https://api.github.com/repos/\(repo)/releases/latest"
        guard let obj = await Net.json(url) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return nil }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return verdict(app, latest: latest, url: downloadPage)
    }

    static let all: [VendorRule] = [
        // 微信
        VendorRule(matches: { $0.bundleId == "com.tencent.xinWeChat" }) { app in
            await pageRegex(app: app,
                            page: "https://mac.weixin.qq.com/",
                            pattern: #"WeChatMac_([0-9]+\.[0-9]+\.?[0-9]*)\.dmg"#,
                            downloadPage: "https://mac.weixin.qq.com/")
        },
        // QQ
        VendorRule(matches: { $0.bundleId == "com.tencent.QQ" || $0.bundleId == "com.tencent.qq" }) { app in
            await pageRegex(app: app,
                            page: "https://im.qq.com/macqq/index.shtml",
                            pattern: #"QQ_v([0-9]+\.[0-9]+\.[0-9]+)-[0-9]+\.dmg"#,
                            downloadPage: "https://im.qq.com/macqq/")
        },
        // Obsidian
        VendorRule(matches: { $0.bundleId == "md.obsidian" }) { app in
            await githubRepo(app: app, repo: "obsidianmd/obsidian-releases",
                             downloadPage: "https://obsidian.md/download")
        },
        // Google Chrome：官方 versionhistory 接口在国内不通，改用 Chrome for Testing 的 stable 版本
        VendorRule(matches: { $0.bundleId == "com.google.Chrome" }) { app in
            guard let obj = await Net.json("https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions.json") as? [String: Any],
                  let channels = obj["channels"] as? [String: Any],
                  let stable = channels["Stable"] as? [String: Any],
                  let latest = stable["version"] as? String else { return nil }
            return verdict(app, latest: latest, url: "https://www.google.com/chrome/")
        },
        // WPS Office
        VendorRule(matches: { $0.bundleId == "com.kingsoft.wpsoffice.mac" }) { app in
            await pageRegex(app: app,
                            page: "https://www.wps.cn/product/wpsmac",
                            pattern: #"(1[0-9]\.[0-9]+\.[0-9]{4,6})"#,
                            downloadPage: "https://www.wps.cn/product/wpsmac")
        },
        // Motrix
        VendorRule(matches: { $0.bundleId == "app.motrix.native" }) { app in
            await githubRepo(app: app, repo: "agalwood/Motrix",
                             downloadPage: "https://motrix.app/")
        },
        // Anki
        VendorRule(matches: { $0.bundleId == "net.ankiweb.anki" }) { app in
            await githubRepo(app: app, repo: "ankitects/anki",
                             downloadPage: "https://apps.ankiweb.net/")
        }
    ]

    static func match(_ app: InstalledApp) -> VendorRule? {
        all.first { $0.matches(app) }
    }
}
