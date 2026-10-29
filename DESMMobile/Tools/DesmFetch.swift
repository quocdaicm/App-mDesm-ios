// DesmFetch.swift — tải file/API cho AI (mục "Thêm").

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Tải file / API cho AI (mục "Thêm")
//
// Để khi AI khác cần xem mã nguồn của DESM (file .js, .css, trang HTML) hoặc kết quả một API, người dùng chỉ cần dán link/địa chỉ vào đây,
// bấm tải rồi chia sẻ file lại cho AI. Chạy bằng phiên đăng nhập hiện có của trang DESM, chỉ tải được địa chỉ cùng domain.
// Mỗi dòng là một yêu cầu:
//   /resources/scripts/shippingStatus/vesselFinder.js?rv=bJ5Z2O2Jp5            (GET; có thể dán nguyên link https://desm...)
//   POST /vessel/getVesselFinderList.do PROJECT_NO=T25026                       (POST form: sau địa chỉ là phần body)
// Một dòng -> lưu đúng nội dung (đuôi .js/.json/.css/.html/.txt theo loại trả về); nhiều dòng -> gộp thành một file văn bản có tiêu đề từng phần.
// CHƯA kiểm chứng trên máy thật.

extension BrowserModel {
    /// Tải một yêu cầu ("[GET|POST] địa chỉ [body]"). done(kết quả, lỗi): lỗi rỗng = thành công.
    func fetchResource(_ spec: String, done: @escaping (DesmFetched?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang DESM để tải. Hãy mở DESM và đăng nhập trước."); return }
        let js = #"""
        var m = 'GET', u = String(spec || '').trim(), b = null;
        var mm = u.match(/^(GET|POST)\s+(\S+)(?:\s+([\s\S]*))?$/i);
        if (mm) { m = mm[1].toUpperCase(); u = mm[2]; b = mm[3] || ''; }
        var a;
        try { a = new URL(u, location.href); } catch (e) { return JSON.stringify({ err: 'Địa chỉ không hợp lệ' }); }
        if (a.origin !== location.origin) return JSON.stringify({ err: 'Chỉ tải được địa chỉ cùng domain với trang đang mở (' + location.origin + ')' });
        try {
          var o = { method: m, credentials: 'include', cache: 'no-store', headers: {} };
          if (m === 'POST') { o.headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8'; o.headers['X-Requested-With'] = 'XMLHttpRequest'; o.body = b || ''; }
          var r = await fetch(a.href, o);
          var t = await r.text();
          return JSON.stringify({ method: m, url: a.href, status: r.status, ct: (r.headers.get('content-type') || '').split(';')[0], text: t });
        } catch (e) { return JSON.stringify({ err: String(e && e.message || e) }); }
        """#
        webView.callAsyncJavaScript(js, arguments: ["spec": spec], in: nil, in: .page) { result in
            switch result {
            case .failure(let e): done(nil, "Không tải được: \(e.localizedDescription)")
            case .success(let v):
                guard let s = v as? String, let data = s.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { done(nil, "Không đọc được phản hồi."); return }
                if let err = o["err"] as? String { done(nil, err); return }
                done(DesmFetched(method: o["method"] as? String ?? "GET", url: o["url"] as? String ?? spec,
                                 status: (o["status"] as? NSNumber)?.intValue ?? 0,
                                 contentType: o["ct"] as? String ?? "", text: o["text"] as? String ?? ""), "")
            }
        }
    }
}

struct DesmFetched {
    var method: String, url: String, status: Int, contentType: String, text: String
    /// Đuôi file theo loại nội dung (rồi đến đuôi trong địa chỉ).
    var ext: String {
        let c = contentType.lowercased(), p = (URL(string: url)?.path ?? "").lowercased()
        if c.contains("json") || p.hasSuffix(".json") { return "json" }
        if c.contains("javascript") || p.hasSuffix(".js") { return "js" }
        if c.contains("css") || p.hasSuffix(".css") { return "css" }
        if c.contains("html") || p.hasSuffix(".html") || p.hasSuffix(".do") && c.contains("html") { return "html" }
        return "txt"
    }
    var baseName: String {
        let last = (URL(string: url)?.lastPathComponent ?? "").replacingOccurrences(of: ".\(ext)", with: "")
        let clean = last.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return clean.isEmpty ? "desm-fetch" : clean
    }
}

struct DesmFetchSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    static let recentKey = "desmFetchRecent"
    @AppStorage("desmFetchLines") private var lines = ""
    @State private var loading = false
    @State private var progress = ""
    @State private var message = ""
    @State private var shareItem: ShareItem? = nil
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: DesmFetchSheet.recentKey) ?? []

    var specs: [String] {
        lines.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func save(_ text: String, name: String, ext: String) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(f.string(from: Date())).\(ext)")
        do { try text.write(to: url, atomically: true, encoding: .utf8); shareItem = ShareItem(url: url) }
        catch { message = "Không lưu được file: \(error.localizedDescription)" }
    }

    func run() {
        let list = specs
        guard !list.isEmpty else { message = "Hãy dán ít nhất một link hoặc địa chỉ."; return }
        loading = true; message = ""
        var results: [(String, DesmFetched?, String)] = []
        func step(_ i: Int) {
            if i >= list.count {
                loading = false; progress = ""
                // nhớ các dòng đã dùng (tối đa 12)
                var rc = recent
                for s in list.reversed() { rc.removeAll { $0 == s }; rc.insert(s, at: 0) }
                recent = Array(rc.prefix(12)); UserDefaults.standard.set(recent, forKey: DesmFetchSheet.recentKey)
                if list.count == 1 {
                    if let f = results[0].1 { save(f.text, name: f.baseName, ext: f.ext); if f.status >= 400 { message = "HTTP \(f.status) — nội dung có thể là trang lỗi." } }
                    else { message = results[0].2 }
                } else {
                    var out = "DESM — NỘI DUNG ĐÃ TẢI (\(list.count) yêu cầu)\n"
                    for (spec, f, err) in results {
                        if let f = f {
                            out += "\n\n===== \(f.method) \(f.url) =====\nHTTP \(f.status) · \(f.contentType.isEmpty ? "?" : f.contentType) · \(f.text.count) ký tự\n\n\(f.text)"
                        } else {
                            out += "\n\n===== \(spec) =====\nLỖI: \(err)"
                        }
                    }
                    save(out, name: "desm-fetch", ext: "txt")
                    let bad = results.filter { $0.1 == nil }.count
                    if bad > 0 { message = "\(bad)/\(list.count) yêu cầu bị lỗi (đã ghi trong file)." }
                }
                return
            }
            progress = "Đang tải \(i + 1)/\(list.count)…"
            model.fetchResource(list[i]) { f, err in
                results.append((list[i], f, err))
                step(i + 1)
            }
        }
        step(0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $lines)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .frame(minHeight: 140)
                    Button {
                        run()
                    } label: {
                        HStack { if loading { ProgressView() }; Text(loading ? progress : "Tải và chia sẻ file…").fontWeight(.semibold) }
                    }
                    .disabled(loading)
                    if !lines.isEmpty { Button("Xóa ô nhập", role: .destructive) { lines = "" } }
                } header: {
                    Text("Link / địa chỉ cần tải")
                } footer: {
                    Text("Mỗi dòng một yêu cầu. Dán nguyên link https://desm… hoặc chỉ đường dẫn /resources/…js. API dạng POST: POST /đường/dẫn.do PROJECT_NO=T25026. Một dòng lưu đúng file (.js/.json/.css/.html); nhiều dòng gộp thành một file văn bản. Dòng bắt đầu bằng # bị bỏ qua.")
                }
                if !message.isEmpty { Section { Text(message).font(.footnote).foregroundStyle(.orange) } }
                if !recent.isEmpty {
                    Section {
                        ForEach(recent, id: \.self) { s in
                            Button { lines = lines.isEmpty ? s : lines + "\n" + s } label: {
                                Text(s).font(.system(size: 12, design: .monospaced)).lineLimit(2).foregroundStyle(.primary)
                            }
                        }
                        Button("Xóa danh sách gần đây", role: .destructive) { recent = []; UserDefaults.standard.removeObject(forKey: DesmFetchSheet.recentKey) }
                    } header: { Text("Đã dùng gần đây (chạm để thêm lại)") }
                }
                Section {
                    Text("Khi AI cần xem code hoặc API của DESM, nó sẽ gửi bạn link hoặc dòng POST. Dán vào ô trên, bấm Tải, rồi chia sẻ file (Lưu vào Tệp, hoặc gửi thẳng cho AI). Cần đang đăng nhập DESM; file có thể chứa thông tin nội bộ nên hãy xem lại trước khi gửi.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Cách dùng") }
            }
            .navigationTitle("Tải file / API")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } } }
            .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
        }
    }
}
