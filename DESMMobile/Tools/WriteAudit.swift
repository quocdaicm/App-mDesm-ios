import SwiftUI
import UIKit

// Nhật ký thao tác GHI (Thêm > "Nhật ký thao tác ghi").
// Mỗi lần app gửi lệnh lưu lên DESM (Save hạng mục, sửa dòng MRR, Xuất kho, WIP, Trả hàng MRF) đều ghi lại: thời điểm, địa chỉ, dữ liệu đã gửi,
// (nếu có) giá trị trước khi sửa, phản hồi của máy chủ và kết luận. Mục đích: lỡ lưu sai thì biết chính xác đã gửi gì để sửa lại trên web.
// Lưu trong Application Support (không bị hệ thống dọn như Caches), tối đa 500 bản ghi, chỉ nằm trên máy.
//
// Trạng thái:
//   sending  = đã gửi, chưa có kết quả (nếu app bị tắt giữa chừng thì coi như "không rõ")
//   ok       = máy chủ trả về không có lỗi
//   rejected = máy chủ trả về lỗi (chưa lưu, hoặc lưu một phần với lỗi QTY: kiểm tra lại trên web)
//   unknown  = đã gửi nhưng KHÔNG nhận được phản hồi hợp lệ (mất mạng, hết phiên, không phải JSON): có thể đã lưu hoặc chưa -> kiểm tra trên web
//   notsent  = chưa gửi được (chưa mở DESM / thiếu thư viện của trang)

struct DesmAuditEntry: Identifiable, Codable {
    var id: String
    var time: Date
    var label: String
    var path: String
    var payload: String
    var before: String
    var status: String
    var response: String
    var error: String

    /// Bản ghi "sending" cũ hơn 2 phút = app đã bị tắt/mất kết nối giữa chừng -> không rõ kết quả.
    var effectiveStatus: String {
        status == "sending" && Date().timeIntervalSince(time) > 120 ? "unknown" : status
    }
    var statusTitle: String {
        switch effectiveStatus {
        case "ok": return "Đã lưu"
        case "rejected": return "Máy chủ báo lỗi"
        case "unknown": return "Không rõ kết quả"
        case "notsent": return "Chưa gửi"
        default: return "Đang gửi"
        }
    }
    var statusSymbol: String {
        switch effectiveStatus {
        case "ok": return "checkmark.circle.fill"
        case "rejected": return "xmark.octagon.fill"
        case "unknown": return "questionmark.circle.fill"
        case "notsent": return "minus.circle.fill"
        default: return "arrow.up.circle.fill"
        }
    }
    var statusColor: Color {
        switch effectiveStatus {
        case "ok": return .green
        case "rejected": return .red
        case "unknown": return .orange
        default: return .gray
        }
    }
}

enum WriteAuditStore {
    static let changed = Notification.Name("desmAuditChanged")
    private static let q = DispatchQueue(label: "desm.audit")
    private static let maxEntries = 500
    private static let maxPayload = 200_000, maxResponse = 6_000
    private static var cache: [DesmAuditEntry]? = nil

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("desm-write-audit.json")
    }
    private static func clip(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n)) + "…(đã cắt)" : s }

    // Gọi bên trong q
    private static func load() -> [DesmAuditEntry] {
        if let c = cache { return c }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let list = (try? Data(contentsOf: fileURL)).flatMap { try? dec.decode([DesmAuditEntry].self, from: $0) } ?? []
        cache = list
        return list
    }
    private static func save(_ list: [DesmAuditEntry]) {
        cache = list
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(list) { try? data.write(to: fileURL, options: .atomic) }
        DispatchQueue.main.async { NotificationCenter.default.post(name: changed, object: nil) }
    }

    /// Ghi nhận một lệnh sắp gửi. Trả về id để gọi `finish` khi có kết quả.
    @discardableResult
    static func begin(id: String = UUID().uuidString, label: String, path: String, payload: String, before: String = "") -> String {
        let e = DesmAuditEntry(id: id, time: Date(), label: label, path: path, payload: clip(payload, maxPayload),
                               before: clip(before, maxPayload), status: "sending", response: "", error: "")
        q.sync {   // đồng bộ: bản ghi phải nằm trên đĩa TRƯỚC khi lệnh đi, kể cả khi app bị tắt ngay sau đó
            var list = load(); list.append(e)
            if list.count > maxEntries { list.removeFirst(list.count - maxEntries) }
            save(list)
        }
        return id
    }

    static func finish(id: String, status: String, response: String = "", error: String = "") {
        q.async {
            var list = load()
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].status = status; list[i].response = clip(response, maxResponse); list[i].error = error
            save(list)
        }
    }

    /// Dùng cho message `desmAudit` từ JS trong trang (op = begin | end).
    static func handle(_ d: [String: Any]) {
        func s(_ k: String) -> String { (d[k] as? String) ?? "" }
        guard !s("id").isEmpty else { return }
        if s("op") == "begin" {
            begin(id: s("id"), label: s("label"), path: s("path"), payload: s("payload"), before: s("before"))
        } else if s("op") == "end" {
            finish(id: s("id"), status: s("status").isEmpty ? "unknown" : s("status"), response: s("resp"), error: s("err"))
        }
    }

    static func all() -> [DesmAuditEntry] { q.sync { load() }.reversed() }   // mới nhất trước
    static func clear() { q.sync { save([]) } }

    /// Xuất toàn bộ nhật ký ra file văn bản (để gửi/lưu lại).
    static func exportFile() -> URL? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var out = "NHẬT KÝ THAO TÁC GHI — DESM Mobile\nXuất lúc \(f.string(from: Date()))\n"
        for e in all() {
            out += "\n==================================================\n"
            out += "\(f.string(from: e.time)) · \(e.label) · \(e.statusTitle)\n\(e.path)\n"
            if !e.error.isEmpty { out += "Lỗi: \(e.error)\n" }
            out += "\n-- Đã gửi --\n\(DesmAuditView.pretty(e.payload))\n"
            if !e.before.isEmpty { out += "\n-- Trước khi sửa --\n\(DesmAuditView.pretty(e.before))\n" }
            if !e.response.isEmpty { out += "\n-- Phản hồi --\n\(DesmAuditView.pretty(e.response))\n" }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("desm-write-log.txt")
        do { try out.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}

// MARK: - Màn hình xem nhật ký

struct DesmAuditView: View {
    var onClose: () -> Void
    @State private var entries: [DesmAuditEntry] = []
    @State private var share: ShareItem? = nil
    @State private var confirmClear = false

    static func pretty(_ s: String) -> String {
        guard let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d),
              let p = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let t = String(data: p, encoding: .utf8) else { return s }
        return t
    }
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm:ss"; return f }()

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("Chưa có thao tác ghi nào. Mỗi lần lưu lên DESM từ app (Save hạng mục, sửa MRR, Xuất kho, WIP, Trả hàng) sẽ hiện ở đây.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Section(footer: Text("Dòng cam \"Không rõ kết quả\": lệnh đã đi nhưng không nhận được phản hồi hợp lệ — hãy mở web DESM kiểm tra xem đã lưu chưa trước khi lưu lại.")) {
                        ForEach(entries) { e in
                            NavigationLink { DesmAuditDetail(entry: e) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: e.statusSymbol).foregroundStyle(e.statusColor).font(.system(size: 20))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.label).font(.system(size: 15, weight: .semibold))
                                        Text("\(e.statusTitle) · \(Self.fmt.string(from: e.time))").font(.caption).foregroundStyle(.secondary)
                                        if !e.error.isEmpty { Text(e.error).font(.caption2).foregroundStyle(.red).lineLimit(2) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Nhật ký thao tác ghi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Xong") { onClose() } }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { if let u = WriteAuditStore.exportFile() { share = ShareItem(url: u) } } label: { Image(systemName: "square.and.arrow.up") }
                        .disabled(entries.isEmpty)
                    Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }
                        .disabled(entries.isEmpty)
                }
            }
            .confirmationDialog("Xoá toàn bộ nhật ký thao tác ghi trên máy này?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Xoá hết", role: .destructive) { WriteAuditStore.clear(); entries = [] }
                Button("Huỷ", role: .cancel) {}
            }
            .sheet(item: $share) { ShareSheet(url: $0.url) }
        }
        .onAppear { entries = WriteAuditStore.all() }
        .onReceive(NotificationCenter.default.publisher(for: WriteAuditStore.changed)) { _ in entries = WriteAuditStore.all() }
    }
}

struct DesmAuditDetail: View {
    let entry: DesmAuditEntry
    @State private var copied = ""

    private func block(_ title: String, _ text: String, copyKey: String) -> some View {
        Section(header: Text(title)) {
            Text(DesmAuditView.pretty(text)).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            Button(copied == copyKey ? "Đã sao chép ✓" : "Sao chép") {
                UIPasteboard.general.string = DesmAuditView.pretty(text); copied = copyKey
            }.font(.footnote)
        }
    }

    var body: some View {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return List {
            Section {
                HStack { Image(systemName: entry.statusSymbol).foregroundStyle(entry.statusColor); Text(entry.statusTitle).font(.headline) }
                Text(entry.label); Text(f.string(from: entry.time)).foregroundStyle(.secondary)
                Text(entry.path).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                if !entry.error.isEmpty { Text(entry.error).foregroundStyle(.red) }
                if entry.effectiveStatus == "unknown" {
                    Text("Chưa biết lệnh này đã được lưu hay chưa. Hãy kiểm tra trên web DESM; chỉ lưu lại khi chắc chắn chưa có.").font(.footnote).foregroundStyle(.orange)
                }
            }
            block("Đã gửi lên DESM", entry.payload, copyKey: "p")
            if !entry.before.isEmpty { block("Giá trị trước khi sửa (để khôi phục trên web)", entry.before, copyKey: "b") }
            if !entry.response.isEmpty { block("Phản hồi của máy chủ", entry.response, copyKey: "r") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Chi tiết")
        .navigationBarTitleDisplayMode(.inline)
    }
}
