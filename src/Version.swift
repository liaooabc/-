import Foundation

/// 版本号比较：把字符串切成「数字段」和「字母段」逐段比。
/// 1.5.0 < 1.5.1、1.10 > 1.9、4.1.15 == 4.1.15
enum Ver {
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = tokens(a)
        let pb = tokens(b)
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let ta = i < pa.count ? pa[i] : .num(0)
            let tb = i < pb.count ? pb[i] : .num(0)
            let r = cmp(ta, tb)
            if r != .orderedSame { return r }
        }
        return .orderedSame
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    private enum Tok {
        case num(Int)
        case txt(String)
    }

    private static func tokens(_ s: String) -> [Tok] {
        var cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        var out: [Tok] = []
        var cur = ""
        var curIsDigit: Bool? = nil

        func flush() {
            guard !cur.isEmpty else { return }
            out.append((curIsDigit ?? false) ? .num(Int(cur) ?? 0) : .txt(cur.lowercased()))
            cur = ""
            curIsDigit = nil
        }

        for ch in cleaned {
            // 分隔符（. - _ 空格）只起断开作用，不进队列
            guard ch.isLetter || ch.isNumber else {
                flush()
                continue
            }
            let isDigit = ch.isNumber
            if let d = curIsDigit, d != isDigit { flush() }
            curIsDigit = isDigit
            cur.append(ch)
        }
        flush()
        return out
    }

    private static func cmp(_ a: Tok, _ b: Tok) -> ComparisonResult {
        switch (a, b) {
        case let (.num(x), .num(y)):
            if x == y { return .orderedSame }
            return x < y ? .orderedAscending : .orderedDescending
        case let (.txt(x), .txt(y)):
            if x == y { return .orderedSame }
            // 带后缀的（beta/rc）比不带后缀的旧
            if x.isEmpty { return .orderedDescending }
            if y.isEmpty { return .orderedAscending }
            return x < y ? .orderedAscending : .orderedDescending
        case (.txt, .num):
            return .orderedAscending
        case (.num, .txt):
            return .orderedDescending
        }
    }
}

/// 系统版本是否满足某个 minimumSystemVersion 要求
func systemSatisfies(_ minimum: String?, osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString) -> Bool {
    guard let minimum, !minimum.isEmpty else { return true }
    let os = osVersion.replacingOccurrences(of: "Version ", with: "")
        .components(separatedBy: " ").first ?? osVersion
    let trimmed = os.components(separatedBy: "(").first ?? os
    return Ver.compare(trimmed, minimum) != .orderedAscending
}
