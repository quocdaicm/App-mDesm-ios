// PackingHistory.swift — lịch sử tải lên Packing List (mục "Thêm").

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Lịch sử tải lên Packing List (mục "Thêm")
//
// Tương ứng khung "Packing List Upload History (Last 3 days)" ở trang chủ DESM (home.do).
// Nguồn dữ liệu (theo nhật ký API 2026-10-28):
//   POST /getInitDefailProject.do                      -> results[0].SEGMENT1 = mã dự án mặc định (vd. T25026)
//   POST /dashboard/getHomeSummary.do  PROJECT_NO=..&DAY_TERM=3 -> results[] gồm INVOICE_NO, SHIPMENT_NO, ORGINAL_FILE,
//        RESULT (SUCCESSFUL / FILE FORMAT ERROR ...), CREATION_DATE, LAST_UPDATED_BY, PROJECT_NAME, ATT_ID
// Gọi bằng fetch trong trang DESM nên dùng sẵn phiên đăng nhập. CHƯA kiểm chứng: DAY_TERM khác 3 (1, 7) có được máy chủ chấp nhận không.

struct PackingUploadRecord: Identifiable, Hashable {
    let id: String
    let invoice: String
    let shipment: String
    let file: String
    let result: String
    let created: String
    let user: String
    let project: String
    let attId: String
    var isSuccess: Bool { result.uppercased() == "SUCCESSFUL" }
}

extension BrowserModel {
    func fetchPackingHistory(days: Int, done: @escaping ([PackingUploadRecord]?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang DESM để lấy dữ liệu."); return }
        let js = #"""
        if (!/(^|\.)doosanenerbility\.com$/i.test(location.hostname)) return JSON.stringify({ err: 'Hãy mở DESM và đăng nhập trước.' });
        const H = { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest' };
        async function post(u, b) {
          const r = await fetch(u, { method: 'POST', credentials: 'include', cache: 'no-store', headers: H, body: b });
          const t = await r.text();
          try { return JSON.parse(t); } catch (e) { throw new Error('HTTP ' + r.status + ': phản hồi không phải JSON (có thể đã hết phiên)'); }
        }
        try {
          const pj = await post('/getInitDefailProject.do', '');
          const no = pj && Array.isArray(pj.results) && pj.results[0] && pj.results[0].SEGMENT1;
          if (!no) return JSON.stringify({ err: 'Chưa có dự án mặc định trong DESM.' });
          const s = await post('/dashboard/getHomeSummary.do', 'PROJECT_NO=' + encodeURIComponent(no) + '&DAY_TERM=' + days);
          if (!s || !Array.isArray(s.results)) return JSON.stringify({ err: 'Máy chủ trả về lỗi.' });
          return JSON.stringify({ list: s.results });
        } catch (e) { return JSON.stringify({ err: String(e && e.message || e) }); }
        """#
        webView.callAsyncJavaScript(js, arguments: ["days": days], in: nil, in: .page) { result in
            switch result {
            case .failure(let e):
                done(nil, "Không tải được: \(e.localizedDescription)")
            case .success(let v):
                guard let text = v as? String, let data = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    done(nil, "Không đọc được phản hồi."); return
                }
                if let err = obj["err"] as? String { done(nil, err); return }
                let rows = obj["list"] as? [[String: Any]] ?? []
                func str(_ r: [String: Any], _ k: String) -> String {
                    if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if let n = r[k] as? NSNumber { return n.stringValue }
                    return ""
                }
                var seen = Set<String>()
                var out: [PackingUploadRecord] = []
                for (i, r) in rows.enumerated() {
                    let att = str(r, "ATT_ID")
                    let key = att.isEmpty ? "row\(i)" : att
                    if !seen.insert(key).inserted { continue }
                    out.append(PackingUploadRecord(
                        id: key, invoice: str(r, "INVOICE_NO"), shipment: str(r, "SHIPMENT_NO"),
                        file: str(r, "ORGINAL_FILE"), result: str(r, "RESULT"),
                        created: str(r, "CREATION_DATE"), user: str(r, "LAST_UPDATED_BY"),
                        project: str(r, "PROJECT_NAME"), attId: att))
                }
                out.sort { $0.created > $1.created }   // "yyyy/MM/dd HH:mm" so sánh chuỗi được
                done(out, "")
            }
        }
    }
}

extension BrowserModel {
    /// Mở màn Kiện hàng và lọc theo Packing List No (bấm một dòng trong Lịch sử Packing List).
    func openPackingList(_ pl: String) {
        guard let d = try? JSONSerialization.data(withJSONObject: ["pl": pl]),
              let js = String(data: d, encoding: .utf8) else { return }
        showToast("Đang mở kiện của \(pl)…")
        webView?.evaluateJavaScript("window.__desmFindPackingList ? window.__desmFindPackingList(\(js)) : 0;", completionHandler: nil)
    }

    /// Tải file xlsx đã upload (theo ATT_ID) bằng phiên đăng nhập của trang, lưu vào thư mục tạm. `done(url, lỗi)`.
    /// CHƯA kiểm chứng: địa chỉ tải của DESM. Script tự dò địa chỉ chứa "download" trong home.do và các script của nó,
    /// rồi thử thêm vài địa chỉ phổ biến; chỉ nhận phản hồi là file (không phải HTML/JSON). Lỗi thì liệt kê các địa chỉ đã thử.
    func downloadPackingFile(attId: String, fileName: String, done: @escaping (URL?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang DESM để tải."); return }
        let js = #"""
        if (!/(^|\.)doosanenerbility\.com$/i.test(location.hostname)) return JSON.stringify({ err: 'Hãy mở DESM và đăng nhập trước.' });
        const tried = [];
        const urls = [];
        function add(u) { u = String(u || '').split('?')[0]; if (u && urls.indexOf(u) < 0) urls.push(u); }
        try {
          const html = await (await fetch('/home.do', { credentials: 'include', cache: 'no-store' })).text();
          const found = (t) => { for (const m of t.matchAll(/["']([^"'\s]*download[^"'\s]*?\.do)(?:\?[^"'\s]*)?["']/gi)) add(m[1].charAt(0) === '/' ? m[1] : '/' + m[1]); };
          found(html);
          const srcs = [];
          for (const m of html.matchAll(/<script[^>]+src=["']([^"']+)["']/gi)) {
            const u = m[1];
            if (/^(https?:)?\/\//i.test(u) && u.indexOf(location.host) < 0) continue;
            if (/jquery|bootstrap|fontawesome|datatables|chart|moment|popper|treegrid|GridE/i.test(u)) continue;
            srcs.push(u);
          }
          for (const u of srcs.slice(0, 12)) {
            try { found(await (await fetch(u, { credentials: 'include' })).text()); } catch (e) {}
          }
        } catch (e) {}
        ['/fileDownload.do', '/common/fileDownload.do', '/downloadFile.do', '/common/downloadFile.do', '/attachFileDownload.do', '/fileDown.do'].forEach(add);
        const names = ['ATT_ID', 'attId'];
        for (const u of urls.slice(0, 14)) {
          for (const n of names) {
            const full = u + '?' + n + '=' + encodeURIComponent(att);
            try {
              const r = await fetch(full, { credentials: 'include', cache: 'no-store' });
              const ct = (r.headers.get('content-type') || '').toLowerCase();
              if (!r.ok) { tried.push(u + ' ' + r.status); continue; }
              const buf = new Uint8Array(await r.arrayBuffer());
              const zip = buf.length > 3 && buf[0] === 0x50 && buf[1] === 0x4B;
              if (!zip && (/text\/html|json|text\/plain/.test(ct) || buf.length < 100)) { tried.push(u + ' không phải file'); continue; }
              let bin = '';
              for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000));
              return JSON.stringify({ b64: btoa(bin) });
            } catch (e) { tried.push(u + ' lỗi'); }
          }
        }
        return JSON.stringify({ err: 'Không tìm được địa chỉ tải file. Đã thử: ' + (tried.slice(0, 6).join('; ') || 'không có') });
        """#
        webView.callAsyncJavaScript(js, arguments: ["att": attId], in: nil, in: .page) { result in
            switch result {
            case .failure(let e):
                done(nil, "Không tải được: \(e.localizedDescription)")
            case .success(let v):
                guard let text = v as? String, let data = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    done(nil, "Không đọc được phản hồi."); return
                }
                if let err = obj["err"] as? String { done(nil, err); return }
                guard let b64 = obj["b64"] as? String, let bytes = Data(base64Encoded: b64), !bytes.isEmpty else {
                    done(nil, "File tải về rỗng."); return
                }
                var name = fileName.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { name = "packing-list-\(attId)" }
                if (name as NSString).pathExtension.isEmpty { name += ".xlsx" }
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("desm-packing-\(UUID().uuidString)", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(name)
                    try bytes.write(to: url)
                    done(url, "")
                } catch { done(nil, "Không lưu được file: \(error.localizedDescription)") }
            }
        }
    }
}

struct PackingHistorySheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void
    var onOpen: (String) -> Void = { _ in }

    @State private var days = 3
    @State private var records: [PackingUploadRecord] = []
    @State private var loading = false
    @State private var error: String? = nil
    @State private var downloadingID: String? = nil
    @State private var shareItem: ShareItem? = nil
    @State private var downloadError: String? = nil

    func download(_ r: PackingUploadRecord) {
        guard downloadingID == nil, !r.attId.isEmpty else { return }
        downloadingID = r.id
        model.downloadPackingFile(attId: r.attId, fileName: r.file) { url, err in
            downloadingID = nil
            if let url = url { shareItem = ShareItem(url: url) } else { downloadError = err }
        }
    }

    func load() {
        loading = true; error = nil
        model.fetchPackingHistory(days: days) { list, err in
            loading = false
            if let list = list { records = list } else { records = []; error = err }
        }
    }

    func badge(_ r: PackingUploadRecord) -> some View {
        Text(r.result.isEmpty ? "—" : r.result)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(r.isSuccess ? Color.green : Color.red)
            .background((r.isSuccess ? Color.green : Color.red).opacity(0.12), in: Capsule())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Khoảng ngày", selection: $days) {
                    Text("1 ngày").tag(1)
                    Text("3 ngày").tag(3)
                    Text("7 ngày").tag(7)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .onChange(of: days) { _ in load() }

                if loading && records.isEmpty {
                    Spacer(); ProgressView("Đang tải…"); Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(.orange)
                        Text(error).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Thử lại") { load() }.buttonStyle(.borderedProminent)
                    }.padding(24)
                    Spacer()
                } else if records.isEmpty {
                    Spacer()
                    Text("Không có lượt tải lên nào trong \(days) ngày gần đây.").font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    List(records) { r in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(r.invoice.isEmpty ? "(không có Invoice)" : r.invoice)
                                    .font(.system(size: 15, weight: .bold))
                                Spacer(minLength: 6)
                                badge(r)
                            }
                            if !r.file.isEmpty || !r.attId.isEmpty {
                                HStack(alignment: .center, spacing: 8) {
                                    Label(r.file.isEmpty ? "Tệp Packing List" : r.file, systemImage: "doc.text").font(.system(size: 13))
                                        .foregroundStyle(.primary).lineLimit(2)
                                    Spacer(minLength: 6)
                                    if !r.attId.isEmpty {
                                        Button { download(r) } label: {
                                            if downloadingID == r.id {
                                                ProgressView().frame(width: 32, height: 32)
                                            } else {
                                                Image(systemName: "arrow.down.circle")
                                                    .font(.system(size: 22)).frame(width: 32, height: 32)
                                            }
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(downloadingID != nil)
                                        .accessibilityLabel("Tải file xlsx")
                                    }
                                }
                            }
                            HStack(spacing: 10) {
                                if !r.shipment.isEmpty { Text("Shipment \(r.shipment)") }
                                if !r.created.isEmpty { Text(r.created) }
                                if !r.user.isEmpty { Text(r.user).lineLimit(1) }
                            }
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture { if !r.invoice.isEmpty { onOpen(r.invoice) } }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lịch sử Packing List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
        }
        .onAppear { if records.isEmpty && !loading { load() } }
        .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
        .desmAlert(isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } }),
                   icon: "exclamationmark.triangle.fill", title: "Không tải được file", message: downloadError,
                   actions: [DesmDialogAction(title: "OK", kind: .primary)])
    }
}
