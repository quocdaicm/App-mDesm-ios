// NetLogStore.swift — nhật ký API lưu thành file trong máy.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Nhật ký API lưu thành file trong máy
//
// Trang gửi từng request/phản hồi (message "desmNet") khi người dùng bật "Ghi lại các request API"; app nối vào file JSON-lines
// trong thư mục Caches (tối đa ~40 MB, quá thì bỏ nửa cũ). API dữ liệu được lưu đủ phản hồi (tới 400 000 ký tự mỗi request);
// script/css/ảnh/font chỉ ghi một dòng. Mật khẩu/token đã được che từ phía trang. Xuất ra 3 dạng: text, json, tóm tắt endpoint.
enum NetLogStore {
    static let q = DispatchQueue(label: "desm.netlog")
    static let maxBytes = 40_000_000
    static let staticPattern = #"\.(js|css|png|jpe?g|gif|svg|ico|woff2?|ttf|otf|map)$"#

    static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("desm-netlog.jsonl")
    }

    static func append(_ obj: [String: Any]) {
        q.async {
            guard JSONSerialization.isValidJSONObject(obj), var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
            data.append(0x0A)
            let u = fileURL
            if let h = try? FileHandle(forWritingTo: u) {
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
                try? h.close()
                let size = ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.intValue ?? 0
                if size > maxBytes { trimHalf(u) }
            } else {
                try? data.write(to: u)
            }
        }
    }

    static func trimHalf(_ u: URL) {
        guard let all = try? Data(contentsOf: u) else { return }
        guard let nl = all[(all.startIndex + all.count / 2)...].firstIndex(of: 0x0A) else { return }
        try? Data(all[(nl + 1)...]).write(to: u)
    }

    static func clear() {
        q.sync { try? FileManager.default.removeItem(at: fileURL) }
    }

    static func entries() -> [[String: Any]] {
        q.sync { () -> [[String: Any]] in
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            var out: [[String: Any]] = []
            for line in data.split(separator: 0x0A) {
                if let o = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] { out.append(o) }
            }
            return out
        }
    }

    static func str(_ e: [String: Any], _ k: String) -> String { (e[k] as? String) ?? "" }
    static func num(_ e: [String: Any], _ k: String) -> Int { (e[k] as? NSNumber)?.intValue ?? 0 }
    static func cut(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n)) + "…[\(s.count) ký tự]" : s }

    static func exportText(_ es: [[String: Any]]) -> String {
        var parts: [String] = []
        for (i, e) in es.enumerated() {
            let body = str(e, "body"), resp = str(e, "resp")
            let bodyText = body.isEmpty ? "(rỗng)" : body
            let respText = resp.isEmpty ? "(rỗng)" : resp
            var s = "#\(i + 1) \(str(e, "t")) [\(str(e, "via"))] \(str(e, "method")) \(str(e, "url"))\n"
            s += "   màn hình: \(str(e, "page"))\n"
            s += "   body: \(bodyText)\n"
            s += "   -> HTTP \(num(e, "status")) (\(num(e, "ms")) ms) \(str(e, "ct")) \(num(e, "len")) ký tự\n"
            s += "   phản hồi: \(respText)"
            parts.append(s)
        }
        return parts.joined(separator: "\n\n")
    }

    static func exportJSON(_ es: [[String: Any]]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: es, options: [.withoutEscapingSlashes]) else { return "[]" }
        return String(decoding: d, as: UTF8.self)
    }

    /// Mô tả cấu trúc JSON phản hồi (tên trường), để biết app cần đọc trường nào.
    static func shape(_ resp: String) -> String {
        guard let d = resp.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) else {
            return resp.isEmpty ? "(rỗng)" : "(không phải JSON hoặc bị cắt) " + cut(resp, 300)
        }
        func keys(_ o: Any) -> String {
            if let m = o as? [String: Any] { return "{" + m.keys.sorted().joined(separator: ", ") + "}" }
            return "\(type(of: o))"
        }
        if let m = j as? [String: Any] {
            var s = keys(m)
            for (k, v) in m.sorted(by: { $0.key < $1.key }) {
                if let a = v as? [Any] { s += "\n      \(k)[\(a.count)] mỗi phần tử: " + (a.first.map(keys) ?? "(trống)") }
            }
            return s
        }
        if let a = j as? [Any] { return "[\(a.count)] mỗi phần tử: " + (a.first.map(keys) ?? "(trống)") }
        return "\(type(of: j))"
    }

    static func exportSummary(_ es: [[String: Any]]) -> String {
        struct G {
            var method = "", name = ""
            var count = 0, totalMs = 0, maxLen = 0
            var statuses = Set<Int>(), pages = Set<String>()
            var query = "", body = "", resp = ""
        }
        var groups: [String: G] = [:]
        var order: [String] = []
        var staticCount = 0
        for e in es {
            let url = str(e, "url"), method = str(e, "method").uppercased()
            let comps = URLComponents(string: url)
            let path = comps?.path ?? url
            if str(e, "resp").isEmpty, path.range(of: staticPattern, options: [.regularExpression, .caseInsensitive]) != nil { staticCount += 1; continue }
            let name = (comps?.host ?? "") + path
            let key = method + " " + name
            if groups[key] == nil { groups[key] = G(method: method, name: name); order.append(key) }
            var g = groups[key]!
            g.count += 1; g.totalMs += num(e, "ms"); g.statuses.insert(num(e, "status"))
            let page = str(e, "page"); if !page.isEmpty { g.pages.insert(page) }
            if g.query.isEmpty, let q = comps?.query { g.query = q }
            if g.body.isEmpty { g.body = str(e, "body") }
            let len = num(e, "len")
            if len >= g.maxLen || g.resp.isEmpty { g.maxLen = len; g.resp = str(e, "resp") }
            groups[key] = g
        }
        var out = "TÓM TẮT API: \(order.count) endpoint (bỏ qua \(staticCount) tài nguyên tĩnh js/css/ảnh/font), \(es.count) request\n"
        for key in order {
            guard let g = groups[key] else { continue }
            out += "\n== \(g.method) \(g.name) ==\n"
            out += "  số lần gọi: \(g.count) | HTTP: \(g.statuses.sorted().map(String.init).joined(separator: ",")) | TB \(g.totalMs / max(g.count, 1)) ms | phản hồi lớn nhất: \(g.maxLen) ký tự\n"
            out += "  màn hình: \(g.pages.sorted().prefix(4).joined(separator: " ; "))\n"
            if !g.query.isEmpty { out += "  query mẫu: \(cut(g.query, 600))\n" }
            if !g.body.isEmpty { out += "  body mẫu: \(cut(g.body, 800))\n" }
            out += "  cấu trúc phản hồi: \(shape(g.resp))\n"
        }
        return out
    }
}
