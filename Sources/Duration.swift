import Foundation

enum Format {
    /// 0:59, 24:00, 1:05:00 — the shortest thing that reads as a clock.
    static func clock(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "25 min", "1h 30m" — for menu labels.
    static func human(_ t: TimeInterval) -> String {
        let m = Int(t.rounded()) / 60
        if m < 60 { return "\(m) min" }
        let (h, rem) = (m / 60, m % 60)
        return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
    }
}

enum Duration {
    /// Accepts "25", "45m", "1h30", "90s", "25:00".
    static func parse(_ raw: String) -> TimeInterval? {
        let s = raw.lowercased().replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }

        if s.contains(":") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
            guard !parts.contains(where: { $0 == nil }) else { return nil }
            let v = parts.compactMap { $0 }
            switch v.count {
            case 2: return v[0] * 60 + v[1]
            case 3: return v[0] * 3600 + v[1] * 60 + v[2]
            default: return nil
            }
        }

        var total: Double = 0
        var num = ""
        var lastUnit: Character?
        for ch in s {
            if ch.isNumber || ch == "." { num.append(ch); continue }
            guard let v = Double(num) else { return nil }
            num = ""
            switch ch {
            case "h": total += v * 3600
            case "m": total += v * 60
            case "s": total += v
            default: return nil
            }
            lastUnit = ch
        }
        if !num.isEmpty {
            guard let v = Double(num) else { return nil }
            // A trailing bare number takes the next unit down: "1h30" is 90 min,
            // "2m30" is two and a half minutes, plain "25" is 25 minutes.
            switch lastUnit {
            case "m", "s": total += v
            default:       total += v * 60
            }
        }
        return total > 0 ? total : nil
    }
}
