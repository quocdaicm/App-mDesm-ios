// Notices.swift — thông báo DESM (mục "Thêm").

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Thông báo DESM (mục "Thêm")
//
// Nguồn: trang chủ DESM (home.js). POST /getNotice.do (jobCode rỗng) -> danh sách: NOTICE_ID, TITLE, ATT_CNT (số file đính kèm),
// LAST_UPDATE_DATE, LAST_UPDATED_BY, FILE_GRP_CD. POST /getNoticeContents.do (jobCode = NOTICE_ID) -> results[0].CONTENTS (văn bản thuần, web nhét vào textarea).
// POST /getRealTimeNotice.do -> thông báo chạy trên đầu trang (TITLE, NOTICE_ID). File đính kèm chưa làm (cần /getIdsmSetupDlgItemScheduleFile.do + /getIdsmAttachDownload.do).
// "Mới" = NOTICE_ID chưa mở lần nào (lưu UserDefaults; lần đầu mở thì coi tất cả là đã xem). CHƯA kiểm chứng trên máy thật.

struct DesmNotice: Identifiable, Hashable {
    let id: String
    var title = "", by = "", date = "", fileGroup = ""
    var attach = 0
    var realtime = false
}

struct DesmAttach: Identifiable, Hashable {
    let id: String
    var name = "", ext = "", size = 0.0
}

struct DesmSharedFile: Identifiable { let id = UUID(); let url: URL }

/// Danh sách NOTICE_ID đã mở (UserDefaults). nil = chưa từng lưu: lần đầu coi mọi thông báo hiện có là đã xem.
enum DesmNoticeSeen {
    static let key = "desmSeenNotices"
    static func load() -> Set<String>? { (UserDefaults.standard.array(forKey: key) as? [String]).map(Set.init) }
    static func save(_ s: Set<String>) { UserDefaults.standard.set(Array(s), forKey: key) }
}

extension BrowserModel {
    func fetchNotices(done: @escaping ([DesmNotice], [DesmNotice], String) -> Void) {
        func str(_ r: [String: Any], _ k: String) -> String {
            if let v = r[k] as? String { return v.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = r[k] as? NSNumber { return n.stringValue }
            return ""
        }
        func parse(_ rows: [[String: Any]], rt: Bool) -> [DesmNotice] {
            let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
            return rows.map { r in
                var n = DesmNotice(id: str(r, "NOTICE_ID")); n.realtime = rt
                n.title = str(r, "TITLE"); n.by = str(r, "LAST_UPDATED_BY"); n.fileGroup = str(r, "FILE_GRP_CD")
                if let ms = r["LAST_UPDATE_DATE"] as? NSNumber { n.date = f.string(from: Date(timeIntervalSince1970: ms.doubleValue / 1000)) }
                else { n.date = str(r, "LAST_UPDATE_DATE") }
                n.attach = (r["ATT_CNT"] as? NSNumber)?.intValue ?? 0
                return n
            }
        }
        desmQuery("/getNotice.do", body: "jobCode=") { rows, err in
            guard let rows = rows else { done([], [], err); return }
            let list = parse(rows, rt: false)
            self.desmQuery("/getRealTimeNotice.do", body: "") { rt, _ in
                done(list, parse(rt ?? [], rt: true), "")
            }
        }
    }

    /// Đếm thông báo chưa mở, cập nhật chấm đỏ trên nút "Thêm" và số trên icon app.
    func refreshNoticeBadge() {
        guard inDesm else { return }
        fetchNotices { list, _, err in
            guard err.isEmpty else { return }
            var seen = DesmNoticeSeen.load()
            if seen == nil { seen = Set(list.map { $0.id }); DesmNoticeSeen.save(seen!) }
            self.setUnread(list.filter { !(seen ?? []).contains($0.id) }.count)
        }
    }
    func setUnread(_ n: Int) {
        unreadNotices = n
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.badge]) { ok, _ in
            if ok { c.setBadgeCount(n) { _ in } }
        }
    }

    /// File đính kèm của thông báo: lấy FILE_GRP_CD (từ danh sách, không có thì hỏi lại getNotice theo NOTICE_ID) rồi
    /// POST /getIdsmSetupDlgItemScheduleFile.do FILE_GRP_CD=... -> [{ID, NAME, EXT, FILE_SIZE}].
    func fetchNoticeFiles(_ n: DesmNotice, done: @escaping ([DesmAttach], String) -> Void) {
        func enc(_ x: String) -> String { x.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? x }
        func files(_ group: String) {
            guard !group.isEmpty else { done([], ""); return }
            desmQuery("/getIdsmSetupDlgItemScheduleFile.do", body: "FILE_GRP_CD=" + enc(group)) { rows, err in
                guard let rows = rows else { done([], err); return }
                done(rows.compactMap { r in
                    func s(_ k: String) -> String {
                        if let v = r[k] as? String { return v }
                        if let v = r[k] as? NSNumber { return v.stringValue }
                        return ""
                    }
                    let id = s("ID"); if id.isEmpty { return nil }
                    return DesmAttach(id: id, name: s("NAME"), ext: s("EXT"), size: (r["FILE_SIZE"] as? NSNumber)?.doubleValue ?? Double(s("FILE_SIZE")) ?? 0)
                }, "")
            }
        }
        if !n.fileGroup.isEmpty { files(n.fileGroup); return }
        guard n.attach > 0 else { done([], ""); return }
        desmQuery("/getNotice.do", body: "jobCode=" + enc(n.id)) { rows, err in
            guard let rows = rows else { done([], err); return }
            files((rows.first?["FILE_GRP_CD"] as? String) ?? "")
        }
    }

    /// Tải một file đính kèm: GET /getIdsmAttachDownload.do?code=<ID> bằng phiên đăng nhập, lưu vào thư mục tạm để chia sẻ/mở.
    func downloadAttachment(_ a: DesmAttach, done: @escaping (URL?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang DESM để tải."); return }
        let js = #"""
        try {
          const r = await fetch('/getIdsmAttachDownload.do?code=' + encodeURIComponent(code), { credentials: 'include', cache: 'no-store' });
          if (!r.ok) return JSON.stringify({ err: 'HTTP ' + r.status });
          const ct = (r.headers.get('content-type') || '').toLowerCase();
          const buf = new Uint8Array(await r.arrayBuffer());
          if (/text\/html|json/.test(ct) && buf.length < 4000) return JSON.stringify({ err: 'Máy chủ không trả file (có thể đã hết phiên hoặc không có quyền).' });
          let bin = '';
          for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000));
          return JSON.stringify({ b64: btoa(bin) });
        } catch (e) { return JSON.stringify({ err: String(e && e.message || e) }); }
        """#
        webView.callAsyncJavaScript(js, arguments: ["code": a.id], in: nil, in: .page) { result in
            switch result {
            case .failure(let e): done(nil, "Không tải được: \(e.localizedDescription)")
            case .success(let v):
                guard let text = v as? String, let d = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { done(nil, "Không đọc được phản hồi."); return }
                if let err = obj["err"] as? String { done(nil, err); return }
                guard let b64 = obj["b64"] as? String, let bytes = Data(base64Encoded: b64), !bytes.isEmpty else { done(nil, "File tải về rỗng."); return }
                var name = a.name.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { name = "dinh-kem-" + a.id }
                if (name as NSString).pathExtension.isEmpty, !a.ext.isEmpty { name += "." + a.ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("desm-notice-\(UUID().uuidString)", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(name)
                    try bytes.write(to: url)
                    done(url, "")
                } catch { done(nil, "Không lưu được file: \(error.localizedDescription)") }
            }
        }
    }

    func fetchNoticeContent(_ id: String, done: @escaping (String, String) -> Void) {
        desmQuery("/getNoticeContents.do", body: "jobCode=" + (id.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? id)) { rows, err in
            guard let rows = rows else { done("", err); return }
            done((rows.first?["CONTENTS"] as? String) ?? "", rows.isEmpty ? "Thông báo không có nội dung." : "")
        }
    }
}

struct DesmNoticeSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    @State private var notices: [DesmNotice] = []
    @State private var live: [DesmNotice] = []
    @State private var loading = false
    @State private var error = ""
    @State private var seen: Set<String> = []
    @State private var files: [DesmAttach] = []
    @State private var filesMsg = ""
    @State private var downloading: String? = nil
    @State private var shared: DesmSharedFile? = nil
    @State private var opened: DesmNotice? = nil
    @State private var content = ""
    @State private var contentErr = ""
    @State private var contentLoading = false

    func load() {
        loading = true; error = ""
        model.fetchNotices { list, rt, err in
            loading = false; error = err
            notices = list; live = rt
            if let saved = DesmNoticeSeen.load() { seen = saved }
            else { seen = Set(list.map { $0.id }); DesmNoticeSeen.save(seen) }   // lần đầu: coi mọi thông báo hiện có là đã xem
            model.setUnread(list.filter { !seen.contains($0.id) }.count)
        }
    }

    func show(_ n: DesmNotice) {
        opened = n; content = ""; contentErr = ""; contentLoading = true
        files = []; filesMsg = ""; downloading = nil
        seen.insert(n.id); DesmNoticeSeen.save(seen)
        model.setUnread(notices.filter { !seen.contains($0.id) }.count)
        model.fetchNoticeContent(n.id) { text, err in
            contentLoading = false; content = text; contentErr = err
        }
        if n.attach > 0 || !n.fileGroup.isEmpty {
            model.fetchNoticeFiles(n) { list, err in files = list; filesMsg = err }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !live.isEmpty {
                    Section("Thông báo khẩn") {
                        ForEach(live) { n in
                            Button { show(n) } label: {
                                Label(n.title, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.system(size: 14, weight: .semibold))
                            }
                        }
                    }
                }
                Section(notices.isEmpty ? "" : "Thông báo (\(notices.count))") {
                    ForEach(notices) { n in
                        Button { show(n) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    if !seen.contains(n.id) {
                                        Text("Mới").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.red, in: Capsule())
                                    }
                                    Text(n.title).font(.system(size: 14, weight: seen.contains(n.id) ? .regular : .bold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                    if n.attach > 0 { Image(systemName: "paperclip").font(.system(size: 11)).foregroundStyle(.secondary) }
                                }
                                Text([n.date, n.by].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
                if !loading && error.isEmpty && notices.isEmpty { Text("Chưa có thông báo.").foregroundStyle(.secondary) }
            }
            .overlay { if loading && notices.isEmpty { ProgressView("Đang tải…") } }
            .navigationTitle("Thông báo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading) }
            }
            .sheet(item: $opened) { n in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(n.title).font(.system(size: 17, weight: .bold))
                            Text([n.date, n.by].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(.secondary)
                            Divider()
                            if contentLoading { ProgressView() }
                            else if !contentErr.isEmpty { Text(contentErr).foregroundStyle(.orange) }
                            else { Text(content.isEmpty ? "(Không có nội dung)" : content).font(.system(size: 15)).textSelection(.enabled) }
                            if !files.isEmpty || !filesMsg.isEmpty {
                                Divider()
                                Text("Đính kèm").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                                if !filesMsg.isEmpty { Text(filesMsg).font(.system(size: 12)).foregroundStyle(.orange) }
                                ForEach(files) { f in
                                    Button {
                                        guard downloading == nil else { return }
                                        downloading = f.id; filesMsg = ""
                                        model.downloadAttachment(f) { url, err in
                                            downloading = nil
                                            if let url = url { shared = DesmSharedFile(url: url) } else { filesMsg = err }
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "doc.fill").foregroundStyle(Color.tabBlue)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(f.name.isEmpty ? "(file \(f.id))" : f.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                                if f.size > 0 { Text(ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file)).font(.system(size: 11)).foregroundStyle(.secondary) }
                                            }
                                            Spacer()
                                            if downloading == f.id { ProgressView() } else { Image(systemName: "arrow.down.circle").foregroundStyle(Color.tabBlue) }
                                        }
                                        .padding(10).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle("Chi tiết").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Xong") { opened = nil } } }
                    .sheet(item: $shared) { f in ShareSheet(url: f.url) }
                }
            }
        }
        .onAppear { if notices.isEmpty && !loading { load() } }
    }
}
