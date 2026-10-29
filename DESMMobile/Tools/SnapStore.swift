// SnapStore.swift — tự lưu cấu trúc/HTML/CSS từng màn hình.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Tự lưu cấu trúc/HTML/CSS từng màn hình
//
// Mỗi màn hình (theo pathname, kể cả màn trong iframe) lưu một file JSON trong Caches/desm-snap/screens; mỗi file CSS lưu một file ở css/.
// Xuất gộp thành MỘT file văn bản: mục lục, rồi từng màn (cây cấu trúc + HTML), sau cùng toàn bộ CSS.
enum SnapStore {
    static let q = DispatchQueue(label: "desm.snap")
    static var dir: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("desm-snap") }
    static var screensDir: URL { dir.appendingPathComponent("screens") }
    static var cssDir: URL { dir.appendingPathComponent("css") }

    static func safe(_ s: String) -> String {
        var r = ""
        for c in s.unicodeScalars { r.append(CharacterSet.alphanumerics.contains(c) || c == "." || c == "-" ? Character(c) : "_") }
        return String(r.prefix(120))
    }

    static func save(_ d: [String: Any]) {
        q.async {
            guard let path = d["path"] as? String else { return }
            let fm = FileManager.default
            try? fm.createDirectory(at: screensDir, withIntermediateDirectories: true)
            try? fm.createDirectory(at: cssDir, withIntermediateDirectories: true)
            var meta = d
            let files = (d["cssFiles"] as? [[String: Any]]) ?? []
            meta["cssFiles"] = nil
            for f in files {
                guard let url = f["url"] as? String, let text = f["text"] as? String else { continue }
                let p = URLComponents(string: url)?.path ?? url
                let st = (f["status"] as? NSNumber)?.intValue ?? 0
                try? "/* ===== \(url) (HTTP \(st), \(text.count) ký tự) ===== */\n\(text)\n".write(to: cssDir.appendingPathComponent(safe(p) + ".txt"), atomically: true, encoding: .utf8)
            }
            if JSONSerialization.isValidJSONObject(meta), let data = try? JSONSerialization.data(withJSONObject: meta) {
                try? data.write(to: screensDir.appendingPathComponent(safe(path) + ".json"))
            }
        }
    }

    static func clear() { q.sync { try? FileManager.default.removeItem(at: dir) } }

    static func screenFiles() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: screensDir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func count() -> Int { q.sync { screenFiles().count } }

    static func export() -> String? {
        q.sync { () -> String? in
            let files = screenFiles()
            if files.isEmpty { return nil }
            var screens: [[String: Any]] = []
            for f in files {
                if let data = try? Data(contentsOf: f), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { screens.append(o) }
            }
            var out = "DESM — CẤU TRÚC, HTML VÀ CSS TỪNG MÀN HÌNH\n\nMỤC LỤC (\(screens.count) màn hình)\n"
            for (i, s) in screens.enumerated() {
                let html = (s["html"] as? String) ?? ""
                let css = ((s["cssLinks"] as? [String]) ?? []).map { URLComponents(string: $0)?.path ?? $0 }.joined(separator: ", ")
                out += "\(i + 1). \((s["path"] as? String) ?? "?")\((s["search"] as? String) ?? "")  | \((s["title"] as? String) ?? "")  | HTML \(html.count) ký tự | CSS: \(css.isEmpty ? "(không)" : css)\n"
            }
            for (i, s) in screens.enumerated() {
                out += "\n\n########## MÀN \(i + 1): \((s["path"] as? String) ?? "?")\((s["search"] as? String) ?? "") ##########\n"
                out += "Tiêu đề: \((s["title"] as? String) ?? "")  | Ghi lúc: \((s["t"] as? String) ?? "")  | \((s["top"] as? Bool) == true ? "trang chính" : "khung con (iframe)")\n"
                out += "\n--- CÂY CẤU TRÚC ---\n\((s["outline"] as? String) ?? "")\n"
                out += "\n--- HTML ---\n\((s["html"] as? String) ?? "")\n"
            }
            let cssFiles = ((try? FileManager.default.contentsOfDirectory(at: cssDir, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            out += "\n\n########## TOÀN BỘ CSS (\(cssFiles.count) file) ##########\n"
            for f in cssFiles { out += "\n" + ((try? String(contentsOf: f, encoding: .utf8)) ?? "") }
            return out
        }
    }
}
