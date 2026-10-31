// Outgoing.swift — tab "Xuất kho": tìm RSI, tích chọn dòng, xuất kho.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Tab "Xuất kho": tìm RSI, tích chọn dòng, xuất kho (đóng) từng dòng hoặc tất cả
//
// Làm theo web DESM (script đã gửi 2026-10-28):
//   Tìm dòng còn xuất được: POST /getDesmOutGoingCreationList.do  (popup "Creation" của Outgoing Control, menu 376)
//   Lưu xuất kho:           POST /saveDesmRsiOutSave.do  với updateList = JSON [{RSI_HEADER_ID, RSI_LINE_ID, HANDOVER_DATE "yyyy/MM/dd",
//                            HANDOVER_QTY, MATERIAL_CODE, PROJECT_NO, RECEIVER_NAME}]
//   Phản hồi: result.error == null là thành công; error == "QTY" kèm RSI_LINE_ID + HANDOVER_AVAILABLE_QTY là vượt số lượng; còn lại là thông báo lỗi.
// CHƯA kiểm chứng: tên các trường trả về của getDesmOutGoingCreationList (suy từ cột lưới trong script; log mới chỉ có kết quả rỗng),
// và máy chủ có đòi thêm gì ngoài các tham số trên cho lệnh lưu (ajaxSetup.js chưa xem). Đây là thao tác GHI lên DESM thật.

func desmFormEnc(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
}

extension BrowserModel {
    /// POST updateList (chuỗi JSON) tới một endpoint lưu của DESM. Trả về phần JSON phản hồi.
    /// Mọi lệnh đi qua đây đều được ghi vào "Nhật ký thao tác ghi" (WriteAudit.swift): dữ liệu gửi, phản hồi và kết luận.
    func desmWrite(_ path: String, updateList: String, label: String = "", done outer: @escaping (Any?, String) -> Void) {
        let aid = WriteAuditStore.begin(label: label.isEmpty ? path : label, path: path, payload: updateList)
        func done(_ res: Any?, _ err: String) {
            if res == nil {
                // "Hãy mở DESM…" / chưa có trang = lệnh chưa đi; các lỗi khác = đã đi nhưng không có phản hồi hợp lệ (có thể đã lưu)
                let notSent = err.hasPrefix("Hãy mở DESM") || err.hasPrefix("Chưa có trang DESM")
                WriteAuditStore.finish(id: aid, status: notSent ? "notsent" : "unknown", error: err)
            } else {
                let dict = res as? [String: Any]
                let e = dict?["error"]
                let failed = dict == nil || !(e == nil || e is NSNull)
                var text = ""
                if let r = res, JSONSerialization.isValidJSONObject(r), let d = try? JSONSerialization.data(withJSONObject: r) { text = String(data: d, encoding: .utf8) ?? "" }
                WriteAuditStore.finish(id: aid, status: dict == nil ? "unknown" : (failed ? "rejected" : "ok"), response: text,
                                       error: failed ? (e.map { "\($0)" } ?? "Phản hồi không rõ") : "")
            }
            outer(res, err)
        }
        guard let webView = webView else { done(nil, "Chưa có trang DESM để gửi lệnh."); return }
        let js = #"""
        if (!/(^|\.)doosanenerbility\.com$/i.test(location.hostname)) return JSON.stringify({ err: 'Hãy mở DESM và đăng nhập trước.' });
        try {
          const r = await fetch(path, { method: 'POST', credentials: 'include', cache: 'no-store',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest' },
            body: 'updateList=' + encodeURIComponent(updateList) });
          const t = await r.text(); let s;
          try { s = JSON.parse(t); } catch (e) { return JSON.stringify({ err: 'HTTP ' + r.status + ': phản hồi không phải JSON. Hãy kiểm tra trên web xem đã lưu chưa trước khi thử lại.' }); }
          return JSON.stringify({ res: s });
        } catch (e) { return JSON.stringify({ err: String(e && e.message || e) }); }
        """#
        webView.callAsyncJavaScript(js, arguments: ["path": path, "updateList": updateList], in: nil, in: .page) { result in
            switch result {
            case .failure(let e): done(nil, "Không gửi được: \(e.localizedDescription)")
            case .success(let v):
                guard let text = v as? String, let data = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { done(nil, "Không đọc được phản hồi. Hãy kiểm tra trên web trước khi thử lại."); return }
                if let err = obj["err"] as? String { done(nil, err); return }
                done(obj["res"] ?? [String: Any](), "")
            }
        }
    }
}

/// Thông tin đầu phiếu RSI (Remarks, người yêu cầu/kiểm tra/xác nhận/duyệt + giờ) — lấy từ dòng đầu của getDesmRsiViewList.
/// Tên trường CHƯA kiểm chứng: dò theo mẫu tên (…REQUEST…BY, …CHECK…BY, …CONFIRM…BY, …APPROV…BY, …DATE, REMARK) nên có trường nào hiện trường đó.
struct DesmRsiInfo {
    var remarks = ""
    var stages: [(label: String, by: String, date: String)] = []
    var extra: [(String, String)] = []
    var isEmpty: Bool { remarks.isEmpty && stages.isEmpty && extra.isEmpty }

    /// "2026/10/30 13:33:05" / "2026-10-30T13:33" / "2026/10/30" -> "13:33 30/10/26"; không nhận ra thì giữ nguyên.
    static func prettyDate(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard let re = try? NSRegularExpression(pattern: #"^(\d{4})[/-](\d{1,2})[/-](\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?"#),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return t }
        func g(_ i: Int) -> String? { Range(m.range(at: i), in: t).map { String(t[$0]) } }
        guard let y = g(1), let mo = g(2), let d = g(3) else { return t }
        let date = String(format: "%02d/%02d/%@", Int(d) ?? 0, Int(mo) ?? 0, String(y.suffix(2)))
        if let hh = g(4), let mm = g(5) { return String(format: "%02d:%@ ", Int(hh) ?? 0, mm) + date }
        return date
    }

    static func parse(_ r: [String: Any]) -> DesmRsiInfo {
        func val(_ k: String) -> String {
            if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = r[k] as? NSNumber { return n.stringValue }
            return ""
        }
        var info = DesmRsiInfo()
        let keys = r.keys.sorted()
        for k in ["RSI_REMARKS", "RSI_REMARK", "HEADER_REMARK", "REMARK", "REMARKS"] where info.remarks.isEmpty { info.remarks = val(k) }
        let stages: [(String, [String])] = [("Requested", ["REQUEST", "PREPARED", "CREATED"]), ("Checked", ["CHECK"]),
                                            ("Confirmed", ["CONFIRM"]), ("Approved", ["APPROV"])]
        for (label, stems) in stages {
            func has(_ k: String) -> Bool { stems.contains { k.contains($0) } }
            let by = keys.first { k in
                let u = k.uppercased(); return has(u) && (u.hasSuffix("_BY") || u.contains("_BY_") || u.hasSuffix("BY")) && !val(k).isEmpty
            }.map { val($0) } ?? ""
            let date = keys.first { k in
                let u = k.uppercased()
                return has(u) && u.contains("DATE") && !u.contains("START") && !u.contains("END") && !u.contains("HANDOVER") && !val(k).isEmpty
            }.map { prettyDate(val($0)) } ?? ""
            if !by.isEmpty || !date.isEmpty { info.stages.append((label, by, date)) }
        }
        for k in keys where k.uppercased().contains("CCB") && !val(k).isEmpty { info.extra.append((k, val(k))) }
        return info
    }
}

/// Một hạng mục trong màn RSI Detail: dòng của phiếu (getDesmRsiViewList, gồm cả dòng đã đóng) ghép với dòng còn xuất được
/// (getDesmOutGoingCreationList). Dòng có `out` còn số lượng thì tích được để OUT.G; dòng đã xuất đủ chỉ để xem.
struct DesmRsiItem: Identifiable {
    let id: String
    var pkg = "", desc = "", code = "", unit = ""
    var req = 0.0, done = 0.0
    var out: DesmOutLine? = nil
    /// Còn xuất được và có đủ ID để gửi lệnh
    var tickable: Bool { guard let o = out else { return false }; return o.valid && o.avail > 0 }
    /// Đã xuất đủ: máy chủ không còn dòng chờ xuất, hoặc số đã xuất >= số yêu cầu
    var isClosed: Bool {
        if let o = out, o.avail <= 0 { return true }
        return req > 0 && done >= req - 0.0005
    }
}

struct DesmOutLine: Identifiable {
    let id: String
    var rsiNo = "", rsiName = "", subcon = "", reqDate = "", pkg = "", plist = "", desc = "", code = "", pending = "", project = "", status = ""
    var req = 0.0, avail = 0.0
    var headerId: Any = NSNull()
    var lineId: Any = NSNull()
    var valid = true
}

final class DesmOutgoingVM: ObservableObject {
    @Published var rsiNo = ""
    @Published var rsiName = ""
    @Published var pkg = ""
    @Published var code = ""
    @Published var subconF = ""          // lọc nhà thầu khi tìm
    @Published var fPkg = ""             // lọc ngay trong phiếu (không gọi máy chủ)
    @Published var fCode = ""
    @Published var showOpts = false
    @Published var lines: [DesmOutLine] = []
    @Published var selected = Set<String>()
    @Published var qty: [String: String] = [:]
    @Published var date = Date()
    @Published var receiver = ""
    @Published var loading = false
    @Published var saving = false
    @Published var searched = false
    @Published var error: String? = nil
    @Published var notice: String? = nil
    @Published var infos: [String: DesmRsiInfo] = [:]   // thông tin đầu phiếu theo số RSI (tải khi mở phiếu)
    @Published var viewRows: [String: [[String: Any]]] = [:]   // TẤT CẢ dòng của phiếu (kể cả đã đóng) theo số RSI
    @Published var viewLoading = Set<String>()
    @Published var viewFailed = Set<String>()
    var project = ""

    /// Tải đầu phiếu + toàn bộ dòng của phiếu (getDesmRsiViewList, cùng truy vấn đã dùng ở DocDetail), kể cả dòng đã xuất đủ.
    /// `force` = tải lại (sau khi OUT.G). Lỗi thì đánh dấu `viewFailed`, không ảnh hưởng xuất kho.
    func loadInfo(_ model: BrowserModel, rsi: String, force: Bool = false) {
        if rsi.isEmpty { return }
        if !force && infos[rsi] != nil { return }
        if viewLoading.contains(rsi) { return }
        viewLoading.insert(rsi); viewFailed.remove(rsi)
        Task { @MainActor in
            defer { self.viewLoading.remove(rsi) }
            guard let pj = try? await model.desmProjectNo() else { self.viewFailed.insert(rsi); return }
            let e = desmFormEnc
            let body = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(e(pj))&RSI_NO=\(e(rsi))&RSI_NAME=&SUBCONTRACTOR=&ATTRIBUTE10=&MATERIAL_CODE=&START_REQUEST_DATE=&END_REQUEST_DATE=&BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&PACKAGE_NO=&ITEM_DESC=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
            guard let rows = try? await model.desmQueryAsync("/getDesmRsiViewList.do", body: body) else { self.viewFailed.insert(rsi); return }
            let mine = rows.filter { Self.str($0, "RSI_NO").uppercased() == rsi.uppercased() }
            self.viewRows[rsi] = mine
            self.infos[rsi] = mine.first.map { DesmRsiInfo.parse($0) } ?? DesmRsiInfo()
        }
    }

    /// Ghép dòng của phiếu với dòng còn xuất được: theo RSI_LINE_ID, không có thì theo Package No + Material Code.
    /// Dòng chờ xuất không ghép được với dòng nào của phiếu vẫn được thêm vào cuối để không bỏ sót.
    func items(for rsi: String) -> [DesmRsiItem] {
        let key = rsi.uppercased()
        let outs = lines.filter { $0.rsiNo.uppercased() == key }
        func nz(_ t: String) -> String { t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased() }
        var used = Set<Int>()
        var result: [DesmRsiItem] = []
        for (i, r) in (viewRows[rsi] ?? []).enumerated() {
            let lid = Self.str(r, "RSI_LINE_ID")
            var hit: Int? = nil
            if !lid.isEmpty { hit = outs.indices.first { !used.contains($0) && outs[$0].id == lid } }
            if hit == nil {
                let k = nz(Self.str(r, "PACKAGE_NO")) + "|" + nz(Self.str(r, "MATERIAL_CODE"))
                hit = outs.indices.first { !used.contains($0) && nz(outs[$0].pkg) + "|" + nz(outs[$0].code) == k }
            }
            var it = DesmRsiItem(id: "v\(i)")
            it.pkg = Self.str(r, "PACKAGE_NO"); it.desc = Self.str(r, "DESCRIPTION"); it.code = Self.str(r, "MATERIAL_CODE")
            it.unit = Self.str(r, "UNIT"); it.req = Self.num(r, "REQ_QTY"); it.done = Self.num(r, "HANDOVER_QTY")
            if let h = hit { used.insert(h); it.out = outs[h] }
            result.append(it)
        }
        for (i, o) in outs.enumerated() where !used.contains(i) {
            var it = DesmRsiItem(id: "o\(o.id)")
            it.pkg = o.pkg; it.desc = o.desc; it.code = o.code; it.req = o.req; it.done = max(0, o.req - o.avail); it.out = o
            result.append(it)
        }
        return result
    }

    /// Đầu phiếu lấy từ dòng của phiếu khi không còn dòng chờ xuất nào (phiếu đã đóng hết).
    func headerLine(_ rsi: String) -> DesmOutLine {
        var l = DesmOutLine(id: "hdr")
        l.rsiNo = rsi
        if let r = viewRows[rsi]?.first {
            l.rsiName = Self.str(r, "RSI_NAME"); l.subcon = Self.str(r, "SUBCONTRACTOR"); l.status = Self.str(r, "STATUS")
            l.reqDate = Self.str(r, "REQUEST_DATE")
        }
        return l
    }

    /// Đổi RSI_HEADER_ID (số sau `RSI!!!` trong QR) thành số RSI bằng getDesmRsiList.do (API của màn RSI Creation, kết quả là mảng).
    /// Trả nil nếu lỗi hoặc không thấy; khi đó dùng đường tải toàn bộ danh sách chờ xuất.
    func resolveRsiNo(_ model: BrowserModel, headerId: String) async -> String? {
        guard let pj = try? await model.desmProjectNo() else { return nil }
        let e = desmFormEnc
        let body = "STATUS=&CLOSED_CODE=&RSI_NO=&RSI_NAME=&DESCRIPTION=&PROJECT_NO=\(e(pj))&START_REQUEST_DATE=&END_REQUEST_DATE=&MATERIAL_TYPE=&SUBCONTRACTOR="
        guard let rows = try? await model.desmQueryAsync("/getDesmRsiList.do", body: body) else { return nil }
        let hit = rows.first { Self.str($0, "RSI_HEADER_ID") == headerId }
        let no = hit.map { Self.str($0, "RSI_NO") } ?? ""
        return no.isEmpty ? nil : no.uppercased()
    }

    var groups: [(String, [DesmOutLine])] {
        var order: [String] = []; var map: [String: [DesmOutLine]] = [:]
        for l in lines { if map[l.rsiNo] == nil { order.append(l.rsiNo) }; map[l.rsiNo, default: []].append(l) }
        return order.map { ($0, map[$0] ?? []) }
    }
    var allSelected: Bool { !lines.isEmpty && selected.count == lines.filter { $0.valid }.count }

    func reset() { rsiNo = ""; rsiName = ""; pkg = ""; code = ""; subconF = "" }

    func toggle(_ l: DesmOutLine) {
        guard l.valid else { return }
        if selected.contains(l.id) { selected.remove(l.id) }
        else { selected.insert(l.id); if (qty[l.id] ?? "").isEmpty { qty[l.id] = Self.fmt(l.avail) } }
    }
    func setGroup(_ items: [DesmOutLine], on: Bool) {
        for l in items where l.valid {
            if on { selected.insert(l.id); if (qty[l.id] ?? "").isEmpty { qty[l.id] = Self.fmt(l.avail) } }
            else { selected.remove(l.id) }
        }
    }
    func setAll(_ on: Bool) { setGroup(lines, on: on) }

    static func dayText(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
        return f.string(from: d)
    }

    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }

    static func str(_ r: [String: Any], _ k: String) -> String {
        if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = r[k] as? NSNumber { return n.stringValue }
        return ""
    }
    static func num(_ r: [String: Any], _ k: String) -> Double {
        if let n = r[k] as? NSNumber { return n.doubleValue }
        if let s = r[k] as? String { return Double(s) ?? 0 }
        return 0
    }

    func search(_ model: BrowserModel, done: (() -> Void)? = nil) {
        loading = true; error = nil; notice = nil
        Task { @MainActor in
            let pj: String
            do { pj = try await model.desmProjectNo() }
            catch { self.loading = false; self.error = error.localizedDescription; done?(); return }
            self.project = pj
            let e = desmFormEnc
            let body = "PROJECT_NO=\(e(pj))&PACKING_LIST_NO=&PACKAGE_NO=\(e(self.pkg))&RSI_NO=\(e(self.rsiNo))&MATERIAL_CODE=\(e(self.code))&REQUEST_START_DATE=&ATTRIBUTE10=&REQUEST_END_DATE=&DESCRIPTION=&DRAWING_NO=&TAG_NO=&RSI_NAME=\(e(self.rsiName))&TYPE=&CATEGORY=&SUBCON=\(e(self.subconF))&PENDING=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
            defer { self.loading = false; self.searched = true; done?() }
            let list: [[String: Any]]
            do { list = try await model.desmQueryAsync("/getDesmOutGoingCreationList.do", body: body) }
            catch { self.error = error.localizedDescription; self.lines = []; return }
            var out: [DesmOutLine] = []
            for (i, r) in list.enumerated() {
                let lineId = r["RSI_LINE_ID"]
                let hasIds = lineId != nil && !(lineId is NSNull) && r["RSI_HEADER_ID"] != nil && !(r["RSI_HEADER_ID"] is NSNull)
                var l = DesmOutLine(id: hasIds ? Self.str(r, "RSI_LINE_ID") : "row\(i)")
                l.rsiNo = Self.str(r, "RSI_NO"); l.rsiName = Self.str(r, "RSI_NAME"); l.subcon = Self.str(r, "SUBCONTRACTOR")
                l.reqDate = Self.str(r, "REQUEST_DATE"); l.pkg = Self.str(r, "PACKAGE_NO"); l.plist = Self.str(r, "PACKING_LIST_NO")
                l.desc = Self.str(r, "DESCRIPTION"); l.code = Self.str(r, "MATERIAL_CODE"); l.pending = Self.str(r, "PENDING")
                l.project = Self.str(r, "PROJECT_NO"); l.status = Self.str(r, "STATUS")
                l.req = Self.num(r, "REQ_QTY"); l.avail = Self.num(r, "HANDOVER_AVAILABLE_QTY")
                l.headerId = r["RSI_HEADER_ID"] ?? NSNull(); l.lineId = lineId ?? NSNull()
                l.valid = hasIds
                out.append(l)
            }
            self.lines = out
            let ids = Set(out.map { $0.id })
            self.selected = self.selected.intersection(ids)
        }
    }

    /// Kiểm tra và gửi lệnh xuất kho cho các dòng đã tích.
    func save(_ model: BrowserModel) {
        let chosen = lines.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
        let day = f.string(from: date)
        var list: [[String: Any]] = []
        for l in chosen {
            let q = Double((qty[l.id] ?? Self.fmt(l.avail)).replacingOccurrences(of: ",", with: ".")) ?? 0
            if q <= 0 { error = "Số lượng xuất của \(l.code) phải lớn hơn 0."; return }
            if q > l.avail + 0.0005 { error = "\(l.code): số lượng xuất \(Self.fmt(q)) vượt quá số còn xuất được \(Self.fmt(l.avail))."; return }
            list.append(["RSI_HEADER_ID": l.headerId, "RSI_LINE_ID": l.lineId, "HANDOVER_DATE": day, "HANDOVER_QTY": q,
                         "MATERIAL_CODE": l.code, "PROJECT_NO": l.project.isEmpty ? project : l.project,
                         "RECEIVER_NAME": receiver.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list), let json = String(data: data, encoding: .utf8) else {
            error = "Không tạo được dữ liệu gửi đi."; return
        }
        saving = true; error = nil; notice = nil
        model.desmWrite("/saveDesmRsiOutSave.do", updateList: json, label: "Xuất kho (RSI)") { res, err in
            self.saving = false
            if res == nil { self.error = err; return }
            guard let r = res as? [String: Any] else { self.error = "Phản hồi không rõ. Hãy kiểm tra trên web trước khi thử lại."; return }
            let e = r["error"]
            if e == nil || e is NSNull {
                self.notice = "Đã xuất kho \(chosen.count) dòng."
                self.selected.removeAll(); self.qty.removeAll()
                self.search(model)
                for rsi in Set(chosen.map { $0.rsiNo }) { self.loadInfo(model, rsi: rsi, force: true) }   // cập nhật số đã xuất/đã đóng
            } else if (e as? String) == "QTY" {
                let id = Self.str(r, "RSI_LINE_ID")
                let av = Self.str(r, "HANDOVER_AVAILABLE_QTY")
                let name = chosen.first { Self.str(["x": $0.lineId], "x") == id }?.code ?? id
                self.error = "Vượt số lượng được xuất ở dòng \(name). Còn xuất được: \(av). Chưa có dòng nào được lưu nếu máy chủ báo lỗi; hãy tải lại danh sách để kiểm tra."
            } else {
                self.error = "\(e ?? "Lỗi không rõ")"
            }
        }
    }
}

struct DesmOutgoingSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void
    @StateObject private var vm = DesmOutgoingVM()
    @State private var showForm = true
    @State private var confirm = false
    @State private var path: [String] = []
    private let headBlue = Color(red: 0.33, green: 0.65, blue: 0.98)
    private let bg = Color(red: 0.95, green: 0.97, blue: 0.99)

    func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 14, weight: .bold)).frame(width: 110, alignment: .leading)
            TextField("", text: text)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.35)))
                .submitLabel(.search).onSubmit { vm.search(model); withAnimation { showForm = false } }
        }
    }

    func pill(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .foregroundStyle(.white).background(color, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    // MARK: Bước 1 — tìm số RSI, ra danh sách phiếu
    var searchCard: some View {
        VStack(spacing: 8) {
            if showForm {
                field("RSI No.", $vm.rsiNo)
                field("RSI Name", $vm.rsiName)
                field("Subcontractor", $vm.subconF)
                field("Package No.", $vm.pkg)
            }
            HStack(spacing: 8) {
                pill(showForm ? "Hide" : "Filter", showForm ? "chevron.up.2" : "chevron.down.2", Color(red: 0.07, green: 0.70, blue: 0.62)) {
                    withAnimation { showForm.toggle() }
                }
                pill("Reset", "arrow.counterclockwise", Color(red: 0.42, green: 0.53, blue: 0.72)) { vm.reset() }
                pill("Search", "magnifyingglass", Color(red: 0.12, green: 0.56, blue: 1.0)) { vm.search(model); withAnimation { showForm = false } }
            }
        }
        .padding(12)
        .background(bg)
    }

    func voucherCard(_ g: (String, [DesmOutLine])) -> some View {
        let f = g.1.first
        let left = g.1.reduce(0.0) { $0 + $1.avail }
        return Button { path.append(g.0) } label: {
            HStack(spacing: 0) {
                Rectangle().fill(headBlue).frame(width: 5)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(g.0).font(.system(size: 17, weight: .bold)).underline()
                        Spacer()
                        Text(f?.status ?? "").font(.system(size: 14))
                    }
                    HStack {
                        Text(f?.rsiName ?? "").font(.system(size: 15))
                        Spacer()
                        Text(f?.subcon ?? "").font(.system(size: 15))
                    }
                    HStack {
                        Text("\(g.1.count) dòng · còn xuất \(DesmOutgoingVM.fmt(left))").font(.system(size: 13)).foregroundStyle(.secondary)
                        Spacer()
                        Text(f?.reqDate ?? "").font(.system(size: 15))
                    }
                }
                .padding(12).foregroundStyle(.primary)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }.buttonStyle(.plain)
    }

    var rootView: some View {
        VStack(spacing: 0) {
            searchCard
            Divider()
            if let e = vm.error {
                Text(e).font(.system(size: 13)).foregroundStyle(.red).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
            }
            if let n = vm.notice {
                Text(n).font(.system(size: 13, weight: .semibold)).foregroundStyle(.green).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.10))
            }
            if vm.loading && vm.lines.isEmpty {
                Spacer(); ProgressView("Đang tìm…"); Spacer()
            } else if vm.lines.isEmpty {
                Spacer()
                Text(vm.searched ? "Không có phiếu nào còn hàng chờ xuất theo điều kiện này (có thể đã xuất hết)."
                                 : "Nhập số RSI (hoặc tên RSI) rồi bấm Search. Để trống sẽ tìm toàn bộ và có thể mất ~10 giây.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.groups, id: \.0) { g in voucherCard(g) }
                    }.padding(12)
                }
                .background(bg)
            }
        }
    }

    // MARK: Bước 2 — mở phiếu: tích dòng, chỉnh số lượng, bấm OUT.G
    func matches(_ l: DesmRsiItem) -> Bool {
        let p = vm.fPkg.trimmingCharacters(in: .whitespaces).lowercased()
        let c = vm.fCode.trimmingCharacters(in: .whitespaces).lowercased()
        if !p.isEmpty && !l.pkg.lowercased().contains(p) { return false }
        if !c.isEmpty && !(l.code.lowercased().contains(c) || l.desc.lowercased().contains(c)) { return false }
        return true
    }

    func header(_ f: DesmOutLine?, info: DesmRsiInfo? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(f?.rsiNo ?? "").font(.system(size: 22, weight: .semibold))
                Text(f?.subcon ?? "").font(.system(size: 20))
                Spacer(minLength: 4)
                Text(f?.status ?? "").font(.system(size: 18))
            }
            HStack {
                Text(f?.rsiName ?? "").font(.system(size: 20))
                Spacer()
                Text(f?.reqDate ?? "").font(.system(size: 18))
            }
            if vm.showOpts, let info = info, !info.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REMARKS").font(.system(size: 15, weight: .bold))
                    Text(info.remarks.isEmpty ? " " : info.remarks)
                        .font(.system(size: 15)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading).padding(8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    ForEach(Array(info.stages.enumerated()), id: \.offset) { _, st in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(st.label) by :").font(.system(size: 14))
                            Text(st.by.isEmpty ? "-" : st.by).font(.system(size: 14, weight: .semibold))
                            Spacer(minLength: 4)
                            Text(st.date).font(.system(size: 13))
                        }
                    }
                    ForEach(Array(info.extra.enumerated()), id: \.offset) { _, kv in
                        Text("\(kv.0) : \(kv.1)").font(.system(size: 13))
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
            }
            if vm.showOpts {
                VStack(spacing: 8) {
                    DatePicker("Ngày xuất", selection: $vm.date, displayedComponents: .date)
                        .font(.system(size: 14, weight: .semibold))
                    TextField("Người nhận / ghi chú (tuỳ chọn)", text: $vm.receiver)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.black)
                }
                .padding(10).background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Text(vm.showOpts ? "" : "Ngày xuất: " + DesmOutgoingVM.dayText(vm.date)).font(.system(size: 13)).opacity(0.9)
                Spacer()
                Button { withAnimation { vm.showOpts.toggle() } } label: {
                    Image(systemName: vm.showOpts ? "chevron.up" : "chevron.down")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(headBlue)
                        .frame(width: 56, height: 34).background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headBlue)
    }

    func filterBar(_ shown: [DesmOutLine]) -> some View {
        let valid = shown.filter { $0.valid }
        let allOn = !valid.isEmpty && valid.allSatisfy { vm.selected.contains($0.id) }
        return HStack(spacing: 8) {
            Text("PKG.").font(.system(size: 14, weight: .bold))
            TextField("", text: $vm.fPkg).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(.horizontal, 8).padding(.vertical, 8).frame(maxWidth: .infinity)
                .background(Color(red: 0.95, green: 0.96, blue: 0.98), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
            Text("MÃ").font(.system(size: 14, weight: .bold))
            TextField("", text: $vm.fCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(.horizontal, 8).padding(.vertical, 8).frame(maxWidth: .infinity)
                .background(Color(red: 0.95, green: 0.96, blue: 0.98), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
            Button { vm.setGroup(shown, on: !allOn) } label: {
                HStack(spacing: 4) {
                    Image(systemName: allOn ? "checkmark.square.fill" : "square").font(.system(size: 22)).foregroundStyle(Color.tabBlue)
                    Text("ALL").font(.system(size: 15, weight: .bold)).foregroundStyle(.primary)
                }
            }.buttonStyle(.plain)
            Button { if !vm.selected.isEmpty { confirm = true } } label: {
                HStack(spacing: 4) {
                    if vm.saving { ProgressView().tint(.white) }
                    Text(vm.selected.isEmpty ? "OUT.G" : "OUT.G (\(vm.selected.count))").font(.system(size: 16, weight: .bold))
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .foregroundStyle(.white)
                .background(vm.selected.isEmpty ? Color.gray : Color(red: 0.12, green: 0.56, blue: 1.0), in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(vm.saving || vm.selected.isEmpty)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white)
    }

    func card(_ l: DesmOutLine) -> some View {
        let on = vm.selected.contains(l.id)
        let done = max(0, l.req - l.avail)
        return HStack(spacing: 0) {
            Rectangle().fill(l.valid ? headBlue : Color.gray).frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(l.pkg.isEmpty ? "(không có package)" : l.pkg).font(.system(size: 17, weight: .bold)).underline()
                    Spacer()
                    Button { vm.toggle(l) } label: {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.system(size: 26)).foregroundStyle(l.valid ? Color.tabBlue : Color.gray)
                    }.buttonStyle(.plain).disabled(!l.valid)
                }
                HStack(alignment: .top) {
                    Text(l.desc).font(.system(size: 16)).lineLimit(4)
                    Spacer(minLength: 6)
                    TextField("0", text: Binding(get: { vm.qty[l.id] ?? DesmOutgoingVM.fmt(l.avail) }, set: { vm.qty[l.id] = $0 }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.center)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 70).padding(.vertical, 6)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4)))
                }
                HStack(spacing: 4) {
                    Text(l.code).font(.system(size: 16))
                    Spacer(minLength: 4)
                    Text(String(format: "%.3f", l.avail)).font(.system(size: 17, weight: .bold)).foregroundStyle(.red)
                    Text("/").font(.system(size: 17, weight: .bold))
                    Text(String(format: "%.3f", done)).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.tabBlue)
                }
                HStack(spacing: 8) {
                    Text("đỏ = còn xuất được · xanh = đã xuất").font(.system(size: 10)).foregroundStyle(.secondary)
                    if l.pending.uppercased() == "Y" {
                        Text("Chưa duyệt").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(.orange).background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                if !l.valid { Text("Thiếu RSI_LINE_ID/RSI_HEADER_ID — không thể xuất dòng này.").font(.system(size: 11)).foregroundStyle(.red) }
            }
            .padding(12)
        }
        .background(on ? Color(red: 0.90, green: 0.95, blue: 1.0) : Color.white, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .onTapGesture { vm.toggle(l) }
    }

    /// Thẻ hạng mục đã xuất đủ (hoặc chưa xuất được): chỉ để xem, không có ô tích.
    func closedCard(_ it: DesmRsiItem) -> some View {
        let done = it.isClosed
        let tint: Color = done ? .green : .orange
        return HStack(spacing: 0) {
            Rectangle().fill(tint).frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(it.pkg.isEmpty ? "(không có package)" : it.pkg).font(.system(size: 17, weight: .bold)).underline()
                Text(it.desc).font(.system(size: 16)).lineLimit(4)
                HStack(spacing: 4) {
                    Text(it.code).font(.system(size: 16))
                    Spacer(minLength: 4)
                    Text("\(DesmOutgoingVM.fmt(it.req)) / \(DesmOutgoingVM.fmt(it.done)) \(it.unit)").font(.system(size: 17, weight: .bold))
                }
                HStack(spacing: 8) {
                    Text(done ? "Đã đóng (xuất đủ)" : "Chưa đóng · chưa có trong danh sách chờ xuất")
                        .font(.system(size: 11, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(tint).background(tint.opacity(0.15), in: Capsule())
                    Text("yêu cầu / đã xuất").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }

    /// Dải trạng thái của cả phiếu: đã đóng hết hay còn dòng chờ xuất (OUT.G).
    func stateBanner(_ items: [DesmRsiItem]) -> some View {
        let total = items.count
        let open = items.filter { $0.tickable }.count
        let closed = items.filter { $0.isClosed }.count
        let known = vm.searched && vm.error == nil && !vm.loading
        let text: String, tint: Color
        if total == 0 { text = ""; tint = .gray }
        else if !known { text = "Đang kiểm tra dòng chờ xuất…"; tint = .gray }
        else if open > 0 { text = "CHƯA ĐÓNG HẾT · còn \(open)/\(total) dòng chờ xuất (tích rồi bấm OUT.G)"; tint = .orange }
        else if closed == total { text = "ĐÃ ĐÓNG · \(total)/\(total) dòng đã xuất đủ"; tint = .green }
        else { text = "Chưa đóng hết nhưng chưa có dòng nào xuất được (\(closed)/\(total) dòng đã đóng)"; tint = .orange }
        return Group {
            if !text.isEmpty {
                Text(text).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.12))
            }
        }
    }

    func detail(_ rsi: String) -> some View {
        let items = vm.items(for: rsi)
        let shown = items.filter { matches($0) }
        let head = vm.lines.first { $0.rsiNo.uppercased() == rsi.uppercased() } ?? vm.headerLine(rsi)
        let tickLines = shown.compactMap { $0.out }.filter { $0.avail > 0 }
        return VStack(spacing: 0) {
            header(head, info: vm.infos[rsi])
            stateBanner(items)
            filterBar(tickLines)
            Divider()
            if let e = vm.error {
                Text(e).font(.system(size: 13)).foregroundStyle(.red).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
            }
            if let n = vm.notice {
                Text(n).font(.system(size: 13, weight: .semibold)).foregroundStyle(.green).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.10))
            }
            if items.isEmpty {
                Spacer()
                if vm.loading || vm.viewLoading.contains(rsi) { ProgressView("Đang tải…") }
                else {
                    VStack(spacing: 10) {
                        Text(vm.viewFailed.contains(rsi) ? "Không tải được hạng mục của phiếu \(rsi)." : "Phiếu \(rsi) không có hạng mục nào.")
                            .font(.callout).multilineTextAlignment(.center)
                        Button("Tải lại") { vm.loadInfo(model, rsi: rsi, force: true); vm.search(model) }.buttonStyle(.borderedProminent)
                        Button("Xem chi tiết (chỉ xem)") { path.append(Self.closedPrefix + rsi) }
                        Button("Về danh sách") { path.removeAll() }
                    }.padding(24)
                }
                Spacer()
            } else {
                Text("\(shown.count) / \(items.count) hạng mục").font(.system(size: 13)).foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6).background(bg)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(shown) { it in
                            if it.tickable, let o = it.out { card(o) } else { closedCard(it) }
                        }
                        if shown.isEmpty { Text("Không có dòng khớp bộ lọc.").font(.footnote).foregroundStyle(.secondary).padding(20) }
                    }.padding(12)
                }
                .background(bg)
            }
        }
        .navigationTitle("RSI Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.loadInfo(model, rsi: rsi) }
    }

    /// Phiếu RSI vừa quét: đổi mã QR (RSI_HEADER_ID) thành số RSI, tìm theo số RSI (nhanh) rồi mở thẳng màn RSI Detail.
    /// Đổi mã qua getDesmRsiList.do (đã kiểm chứng: RSI2026006488 ↔ RSI_HEADER_ID 86167); không đổi được thì tải toàn bộ
    /// danh sách chờ xuất (chậm ~9 s) và so RSI_HEADER_ID.
    private static let closedPrefix = "closed:"

    private func consumeScan() {
        guard let r0 = model.pendingRsiScan, r0.kind == .rsi else { return }
        model.pendingRsiScan = nil
        vm.reset()
        path.removeAll()
        withAnimation { showForm = false }
        Task { @MainActor in
            var r = r0
            if !r.isNo {
                vm.loading = true
                if let no = await vm.resolveRsiNo(model, headerId: r.value) { r = QRRsi(value: no, raw: r0.raw, isNo: true) }
            }
            let rr = r
            vm.rsiNo = rr.isNo ? rr.value : ""
            vm.search(model) {
                let hit = vm.lines.first { l in
                    rr.isNo ? l.rsiNo.uppercased() == rr.value
                            : DesmOutgoingVM.str(["x": l.headerId], "x") == rr.value
                }
                if let h = hit {
                    vm.rsiNo = h.rsiNo
                    path = [h.rsiNo]
                } else if vm.error == nil {
                    if rr.isNo {
                        // Phiếu không còn dòng chờ xuất (đã đóng hết): vẫn mở màn RSI Detail đầy đủ để xem từng dòng đã đóng/chưa đóng
                        path = [rr.value]
                    } else {
                        vm.error = "Không đổi được mã \(rr.value) sang số RSI (kiểm tra mạng/phiên đăng nhập rồi quét lại)."
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            rootView
                .navigationTitle("Xuất kho")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                }
                .navigationDestination(for: String.self) { rsi in
                    if rsi.hasPrefix(Self.closedPrefix) {
                        DesmDocDetailView(model: model, kind: .rsi, group: DesmDocGroup(id: String(rsi.dropFirst(Self.closedPrefix.count))))
                    } else { detail(rsi) }
                }
        }
        .onAppear { consumeScan() }
        .onChange(of: model.pendingRsiScan) { _ in consumeScan() }
        .onChange(of: path) { _ in
            // Đổi phiếu: bỏ chọn/số lượng đã gõ/bộ lọc để không xuất nhầm dòng của phiếu khác
            vm.selected.removeAll(); vm.qty.removeAll(); vm.fPkg = ""; vm.fCode = ""; vm.error = nil; vm.notice = nil
        }
        .desmAlert(isPresented: $confirm, icon: "exclamationmark.triangle.fill", title: "Xác nhận xuất kho (OUT.G)",
                   message: "Ghi xuất kho \(vm.selected.count) dòng lên DESM ngày \(DesmOutgoingVM.dayText(vm.date)). Thao tác này không tự hoàn tác được.",
                   actions: [DesmDialogAction(title: "Xuất kho", kind: .destructive) { vm.save(model) },
                             DesmDialogAction(title: "Huỷ", kind: .cancel)])
        // Không tự tìm khi mở tab: log API (2026-10-30) cho thấy getDesmOutGoingCreationList với bộ lọc TRỐNG mất ~9 s ở máy chủ
        // (dù chỉ trả 7,6 KB), còn khi có bộ lọc thì ~0,4 s. Người dùng nhập RSI No / Name rồi bấm Search.
    }
}
