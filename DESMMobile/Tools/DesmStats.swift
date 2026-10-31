// DesmStats.swift — thống kê lỗi 7 ngày gần nhất (hiện ở Cài đặt > Nâng cao > Chẩn đoán giao diện).
// Ghi: kết quả mỗi lệnh gọi API DESM (thành công / lỗi theo loại / phải dùng đường lui qua trang web) và số lần script
// phải "áp lại" CSS hoặc class vì DESM đã xoá chúng. Chỉ lưu SỐ ĐẾM theo ngày + đường dẫn API trong máy (UserDefaults),
// không lưu nội dung dữ liệu, không gửi đi đâu.

import Foundation

/// Chỉ ghi/đọc trên luồng chính (record tự chuyển về luồng chính nếu gọi từ nơi khác).
final class DesmStats: ObservableObject {
    static let shared = DesmStats()

    enum Kind: String, CaseIterable {
        case apiOK, apiExpired, apiNoSession, apiNetwork, apiNotJSON, apiServer, apiOther
        case webFallback          // URLSession lỗi, phải chạy qua trang web
        case reapplyStyle         // DESM xoá thẻ <style> của app, script phải chèn lại
        case reapplyClass         // DESM gỡ class desm-mobile-mode

        var label: String {
            switch self {
            case .apiOK: return "API thành công"
            case .apiExpired: return "Hết phiên đăng nhập"
            case .apiNoSession: return "Chưa có phiên"
            case .apiNetwork: return "Lỗi mạng"
            case .apiNotJSON: return "Phản hồi không phải JSON"
            case .apiServer: return "Máy chủ trả lỗi / dữ liệu lạ"
            case .apiOther: return "Lỗi API khác"
            case .webFallback: return "Phải dùng đường lui qua trang web"
            case .reapplyStyle: return "Phải chèn lại CSS (DESM xoá style)"
            case .reapplyClass: return "Phải gắn lại class giao diện"
            }
        }
        var isFailure: Bool {
            switch self {
            case .apiOK, .webFallback, .reapplyStyle, .reapplyClass: return false
            default: return true
            }
        }
    }

    @Published private(set) var counts: [String: Int] = [:]   // "yyyy-MM-dd|kind|path" -> số lần
    private let storeKey = "desmStatsV1"
    private var lastAt: [String: Date] = [:]
    private let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private init() {
        if let d = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Int] { counts = d }
        prune()
    }

    private func prune() {
        let cutoff = dayFmt.string(from: Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date())
        counts = counts.filter { String($0.key.prefix(10)) >= cutoff }
    }

    /// `minGap`: bỏ qua nếu cùng loại + đường dẫn vừa ghi trong khoảng này (tránh đếm hàng nghìn lần khi DESM xoá style liên tục).
    func record(_ k: Kind, path: String = "", minGap: TimeInterval = 0) {
        if !Thread.isMainThread { DispatchQueue.main.async { self.record(k, path: path, minGap: minGap) }; return }
        let now = Date()
        let id = k.rawValue + "|" + path
        if minGap > 0, let t = lastAt[id], now.timeIntervalSince(t) < minGap { return }
        lastAt[id] = now
        counts[dayFmt.string(from: now) + "|" + id, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: storeKey)
    }

    private func within(_ days: Int) -> [(kind: Kind, path: String, n: Int)] {
        let cutoff = dayFmt.string(from: Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date())
        var out: [(Kind, String, Int)] = []
        for (key, n) in counts {
            let p = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 3, p[0] >= cutoff, let k = Kind(rawValue: p[1]) else { continue }
            out.append((k, p[2], n))
        }
        return out
    }

    func total(_ k: Kind, days: Int = 7) -> Int { within(days).filter { $0.kind == k }.reduce(0) { $0 + $1.n } }
    var failureTotal: Int { Kind.allCases.filter { $0.isFailure }.reduce(0) { $0 + total($1) } }

    /// API hay lỗi nhất: (đường dẫn, số lỗi, số thành công).
    func worstPaths(limit: Int = 5) -> [(path: String, fails: Int, ok: Int)] {
        var m: [String: (Int, Int)] = [:]
        for e in within(7) where !e.path.isEmpty {
            var v = m[e.path] ?? (0, 0)
            if e.kind == .apiOK { v.1 += e.n } else if e.kind.isFailure { v.0 += e.n }
            m[e.path] = v
        }
        return m.filter { $0.value.0 > 0 }.map { (path: $0.key, fails: $0.value.0, ok: $0.value.1) }
            .sorted { $0.fails > $1.fails }.prefix(limit).map { $0 }
    }

    func reset() { counts = [:]; lastAt = [:]; UserDefaults.standard.removeObject(forKey: storeKey) }

    var report: String {
        var t = "Thống kê 7 ngày:"
        for k in Kind.allCases { let n = total(k); if n > 0 { t += "\n  \(k.label): \(n)" } }
        let w = worstPaths()
        if !w.isEmpty { t += "\n  API hay lỗi nhất:"; for e in w { t += "\n    \(e.path): \(e.fails) lỗi / \(e.ok) thành công" } }
        return t
    }
}
