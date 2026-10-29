// DesmSource.swift — mã nguồn trang đang mở (mục "Thêm").

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Mã nguồn trang đang mở (mục "Thêm")
//
// Đang ở trang DESM nào thì mở mục này: app tự quét danh sách file JS, CSS mà trang (và các khung iframe cùng domain) đang dùng,
// kèm HTML đã dựng của trang và nhật ký API đã ghi. Tích chọn thứ cần rồi bấm Tải: app tự tải bằng phiên đăng nhập hiện có và gộp thành một file để chia sẻ,
// không cần tự tìm link. API chỉ có khi đã bật "Ghi API" (bật ngay trong màn này) rồi thao tác trên trang (Search, mở chi tiết…).
// Mặc định chọn: HTML + CSS/JS của DESM (không gồm thư viện .min / ext như jQuery, Bootstrap; bật công tắc nếu cần).
// CHƯA kiểm chứng trên máy thật.

struct DesmRes: Identifiable, Hashable {
    enum Kind: String { case js, css }
    let url: String
    let kind: Kind
    var id: String { url }
    var path: String { URL(string: url)?.path ?? url }
    var label: String {
        let u = URL(string: url)
        let name = (u?.path ?? url).split(separator: "/").suffix(2).joined(separator: "/")
        return name.isEmpty ? url : name
    }
    /// Thư viện bên thứ ba (jQuery, Bootstrap, font…) — thường không cần cho việc sửa giao diện/logic DESM.
    var vendor: Bool {
        let p = path.lowercased()
        return p.contains(".min.") || p.contains("/ext/") || p.contains("/jquery") || p.contains("/node_modules/") || p.contains("/webfonts/") || p.contains("fontawesome")
    }
}

extension BrowserModel {
    /// Quét JS/CSS của trang đang mở (kể cả iframe cùng domain và tài nguyên đã tải qua Performance API).
    func listPageResources(done: @escaping (String, [DesmRes], String) -> Void) {
        guard let webView = webView else { done("", [], "Chưa có trang DESM để quét."); return }
        let js = #"""
        var seen = {}, out = [];
        function add(u, k) {
          try {
            var a = new URL(u, location.href);
            if (a.origin !== location.origin) return;
            var key = k + a.pathname + a.search;
            if (seen[key]) return; seen[key] = 1; out.push({ u: a.href, k: k });
          } catch (e) {}
        }
        function scan(doc, l) {
          [].forEach.call(doc.querySelectorAll('script[src]'), function(s) { add(s.src, 'js'); });
          [].forEach.call(doc.querySelectorAll('link[rel~="stylesheet"][href]'), function(s) { add(s.href, 'css'); });
          if (l > 3) return;
          [].forEach.call(doc.querySelectorAll('iframe,frame'), function(f) { try { if (f.contentDocument) scan(f.contentDocument, l + 1); } catch (e) {} });
        }
        scan(document, 0);
        try {
          performance.getEntriesByType('resource').forEach(function(e) {
            var p = String(e.name).split('?')[0];
            if (/\.js$/i.test(p)) add(e.name, 'js'); else if (/\.css$/i.test(p)) add(e.name, 'css');
          });
        } catch (e) {}
        return JSON.stringify({ page: location.href, items: out });
        """#
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure(let e): done("", [], "Không quét được: \(e.localizedDescription)")
            case .success(let v):
                guard let s = v as? String, let data = s.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { done("", [], "Không đọc được kết quả quét."); return }
                var items: [DesmRes] = []
                for it in (o["items"] as? [[String: Any]] ?? []) {
                    guard let u = it["u"] as? String, let k = it["k"] as? String, let kind = DesmRes.Kind(rawValue: k) else { continue }
                    items.append(DesmRes(url: u, kind: kind))
                }
                done(o["page"] as? String ?? "", items, "")
            }
        }
    }
}

struct DesmSourceSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    @AppStorage("desmNetLogOn") private var netLogOn = false
    @AppStorage("desmSourceVendor") private var includeVendor = false
    @State private var page = ""
    @State private var items: [DesmRes] = []
    @State private var selected: Set<String> = []
    @State private var wantHTML = true
    @State private var wantAPI = false
    @State private var scanning = false
    @State private var loading = false
    @State private var progress = ""
    @State private var message = ""
    @State private var shareItem: ShareItem? = nil

    func shown(_ k: DesmRes.Kind) -> [DesmRes] { items.filter { $0.kind == k && (includeVendor || !$0.vendor) } }

    func scan() {
        scanning = true; message = ""
        model.listPageResources { pg, list, err in
            scanning = false; page = pg; items = list; message = err
            selected = Set(list.filter { !$0.vendor }.map { $0.id })
        }
    }

    func save(_ text: String, name: String, ext: String) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(f.string(from: Date())).\(ext)")
        do { try text.write(to: url, atomically: true, encoding: .utf8); shareItem = ShareItem(url: url) }
        catch { message = "Không lưu được file: \(error.localizedDescription)" }
    }

    func run() {
        let css = shown(.css).filter { selected.contains($0.id) }, js = shown(.js).filter { selected.contains($0.id) }
        let jobs = css + js
        guard wantHTML || wantAPI || !jobs.isEmpty else { message = "Hãy chọn ít nhất một mục."; return }
        loading = true; message = ""
        var out = "DESM — MÃ NGUỒN TRANG ĐANG MỞ\nTrang: \(page)\n"
        var bad = 0
        func finish() {
            loading = false; progress = ""
            save(out, name: "desm-source", ext: "txt")
            if bad > 0 { message = "\(bad) mục không tải được (đã ghi lỗi trong file)." }
        }
        func apiStep() {
            guard wantAPI else { finish(); return }
            progress = "Đang lấy nhật ký API…"
            model.fetchNetLog(format: .json) { text, err in
                if let text = text { out += "\n\n===== NHẬT KÝ API (JSON) =====\n\(text)" }
                else { bad += 1; out += "\n\n===== NHẬT KÝ API =====\nLỖI: \(err.isEmpty ? "chưa ghi request nào — bật Ghi API rồi thao tác trên trang" : err)" }
                finish()
            }
        }
        func fileStep(_ i: Int) {
            if i >= jobs.count { apiStep(); return }
            progress = "Đang tải \(i + 1)/\(jobs.count)…"
            model.fetchResource(jobs[i].url) { f, err in
                if let f = f {
                    out += "\n\n===== \(jobs[i].kind == .css ? "CSS" : "JS") \(f.url) =====\nHTTP \(f.status) · \(f.contentType.isEmpty ? "?" : f.contentType) · \(f.text.count) ký tự\n\n\(f.text)"
                    if f.status >= 400 { bad += 1 }
                } else { bad += 1; out += "\n\n===== \(jobs[i].url) =====\nLỖI: \(err)" }
                fileStep(i + 1)
            }
        }
        if wantHTML {
            progress = "Đang lấy HTML trang…"
            model.fetchHTML(stripValues: false, stripScripts: false) { html, err in
                if let html = html { out += "\n\n===== HTML TRANG (đã dựng, gồm iframe cùng domain) =====\n\(html)" }
                else { bad += 1; out += "\n\n===== HTML TRANG =====\nLỖI: \(err)" }
                fileStep(0)
            }
        } else { fileStep(0) }
    }

    func listSection(_ title: String, _ k: DesmRes.Kind) -> some View {
        let list = shown(k)
        let allSel = !list.isEmpty && list.allSatisfy { selected.contains($0.id) }
        return Section {
            if list.isEmpty { Text("Không thấy file nào.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(list) { r in
                Button {
                    if selected.contains(r.id) { selected.remove(r.id) } else { selected.insert(r.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected.contains(r.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(r.id) ? Color.tabBlue : Color.secondary)
                        Text(r.label).font(.system(size: 13, design: .monospaced)).foregroundStyle(.primary).lineLimit(1)
                    }
                }
            }
        } header: {
            HStack {
                Text("\(title) (\(list.count))")
                Spacer()
                if !list.isEmpty {
                    Button(allSel ? "Bỏ chọn" : "Chọn hết") {
                        if allSel { list.forEach { selected.remove($0.id) } } else { list.forEach { selected.insert($0.id) } }
                    }.font(.system(size: 12, weight: .semibold)).textCase(nil)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !page.isEmpty { Text(page).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3) }
                    Button { run() } label: {
                        HStack { if loading { ProgressView() }; Text(loading ? progress : "Tải mục đã chọn và chia sẻ file…").fontWeight(.semibold) }
                    }.disabled(loading || scanning)
                    if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.orange) }
                } header: { Text("Trang đang mở") }

                Section {
                    Toggle("HTML của trang (đã dựng, gồm iframe)", isOn: $wantHTML)
                    Toggle("Nhật ký API đã ghi", isOn: $wantAPI)
                    Toggle("Ghi lại API khi thao tác trang", isOn: $netLogOn).onChange(of: netLogOn) { model.setNetLog($0) }
                    Toggle("Gồm cả thư viện (.min, ext, jQuery…)", isOn: $includeVendor)
                } header: { Text("Chọn loại") } footer: {
                    Text("API: bật công tắc ghi, thao tác trên trang DESM (Search, mở chi tiết…) rồi quay lại mục này, bật \"Nhật ký API đã ghi\" và tải.")
                }

                if scanning { Section { HStack { ProgressView(); Text("Đang quét file của trang…") } } }
                else {
                    listSection("CSS", .css)
                    listSection("Script JS", .js)
                }
            }
            .navigationTitle("Mã nguồn trang này")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button { scan() } label: { Image(systemName: "arrow.clockwise") }.disabled(scanning || loading) }
            }
            .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
        }
        .onAppear { if items.isEmpty && !scanning { scan() } }
    }
}
