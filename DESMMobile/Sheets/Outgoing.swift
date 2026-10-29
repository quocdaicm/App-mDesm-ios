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

struct DesmOutLine: Identifiable {
    let id: String
    var rsiNo = "", rsiName = "", subcon = "", reqDate = "", pkg = "", plist = "", desc = "", code = "", pending = "", project = ""
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
    var project = ""

    var groups: [(String, [DesmOutLine])] {
        var order: [String] = []; var map: [String: [DesmOutLine]] = [:]
        for l in lines { if map[l.rsiNo] == nil { order.append(l.rsiNo) }; map[l.rsiNo, default: []].append(l) }
        return order.map { ($0, map[$0] ?? []) }
    }
    var allSelected: Bool { !lines.isEmpty && selected.count == lines.filter { $0.valid }.count }

    func reset() { rsiNo = ""; rsiName = ""; pkg = ""; code = "" }

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

    func search(_ model: BrowserModel) {
        loading = true; error = nil; notice = nil
        Task { @MainActor in
            let pj: String
            do { pj = try await model.desmProjectNo() }
            catch { self.loading = false; self.error = error.localizedDescription; return }
            self.project = pj
            let e = desmFormEnc
            let body = "PROJECT_NO=\(e(pj))&PACKING_LIST_NO=&PACKAGE_NO=\(e(self.pkg))&RSI_NO=\(e(self.rsiNo))&MATERIAL_CODE=\(e(self.code))&REQUEST_START_DATE=&ATTRIBUTE10=&REQUEST_END_DATE=&DESCRIPTION=&DRAWING_NO=&TAG_NO=&RSI_NAME=\(e(self.rsiName))&TYPE=&CATEGORY=&SUBCON=&PENDING=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
            defer { self.loading = false; self.searched = true }
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
                l.project = Self.str(r, "PROJECT_NO")
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
            let q = Double((qty[l.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
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

    func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).frame(width: 96, alignment: .leading)
            TextField("", text: text)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .submitLabel(.search).onSubmit { vm.search(model) }
        }
    }

    func pill(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(.white).background(color, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    var searchCard: some View {
        VStack(spacing: 8) {
            if showForm {
                field("RSI No.", $vm.rsiNo)
                field("RSI Name", $vm.rsiName)
                field("Package No.", $vm.pkg)
                field("Material Code", $vm.code)
            }
            HStack(spacing: 8) {
                pill(showForm ? "Ẩn" : "Bộ lọc", showForm ? "chevron.up.2" : "chevron.down.2", Color(red: 0.07, green: 0.70, blue: 0.62)) {
                    withAnimation { showForm.toggle() }
                }
                pill("Đặt lại", "arrow.counterclockwise", Color(red: 0.42, green: 0.53, blue: 0.72)) { vm.reset() }
                pill("Tìm", "magnifyingglass", Color.tabBlue) { vm.search(model); withAnimation { showForm = false } }
            }
        }
        .padding(12)
        .background(Color(red: 0.95, green: 0.97, blue: 1.0))
    }

    func lineRow(_ l: DesmOutLine) -> some View {
        let on = vm.selected.contains(l.id)
        return HStack(alignment: .top, spacing: 10) {
            Button { vm.toggle(l) } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24)).foregroundStyle(l.valid ? Color.tabBlue : Color.gray)
            }.buttonStyle(.plain).disabled(!l.valid)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(l.code.isEmpty ? "(không có mã)" : l.code).font(.system(size: 14, weight: .bold))
                    if l.pending.uppercased() == "Y" {
                        Text("Chưa duyệt").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(.orange).background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                if !l.desc.isEmpty { Text(l.desc).font(.system(size: 13)).lineLimit(3) }
                if !l.pkg.isEmpty { Label(l.pkg, systemImage: "shippingbox").font(.system(size: 12)) }
                HStack(spacing: 10) {
                    Text("Yêu cầu \(DesmOutgoingVM.fmt(l.req))")
                    Text("Còn xuất được \(DesmOutgoingVM.fmt(l.avail))").foregroundStyle(l.avail > 0 ? Color.tabBlue : Color.red)
                }.font(.system(size: 12, weight: .medium))
                if !l.plist.isEmpty { Text(l.plist).font(.system(size: 11)).foregroundStyle(.secondary) }
                if !l.valid { Text("Thiếu RSI_LINE_ID/RSI_HEADER_ID trong dữ liệu — không thể xuất dòng này.").font(.system(size: 11)).foregroundStyle(.red) }
            }
            Spacer(minLength: 4)
            if on {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SL xuất").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("0", text: Binding(get: { vm.qty[l.id] ?? "" }, set: { vm.qty[l.id] = $0 }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.red)
                        .frame(width: 78).padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color(red: 1, green: 1, blue: 0.88), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { vm.toggle(l) }
    }

    var bottomBar: some View {
        VStack(spacing: 8) {
            HStack {
                DatePicker("Ngày xuất", selection: $vm.date, displayedComponents: .date).font(.system(size: 14, weight: .semibold))
            }
            TextField("Người nhận / ghi chú (tuỳ chọn)", text: $vm.receiver)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            Button { confirm = true } label: {
                HStack {
                    if vm.saving { ProgressView().tint(.white) }
                    Text("Xuất kho \(vm.selected.count) dòng").font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white).background(Color(red: 0.16, green: 0.65, blue: 0.40), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain).disabled(vm.saving)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    var body: some View {
        NavigationStack {
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
                    Text(vm.searched ? "Không có dòng nào còn xuất được theo điều kiện này (phiếu có thể đã xuất hết)."
                                     : "Nhập số RSI (hoặc để trống) rồi bấm Tìm.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    HStack {
                        Button { vm.setAll(!vm.allSelected) } label: {
                            Label(vm.allSelected ? "Bỏ chọn tất cả" : "Chọn tất cả (\(vm.lines.filter { $0.valid }.count))",
                                  systemImage: vm.allSelected ? "square" : "checkmark.square")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Spacer()
                        Text("\(vm.selected.count) đã chọn").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    List {
                        ForEach(vm.groups, id: \.0) { g in
                            Section {
                                ForEach(g.1) { l in lineRow(l) }
                            } header: {
                                let first = g.1.first
                                let allOn = g.1.allSatisfy { vm.selected.contains($0.id) || !$0.valid }
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.0).font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                                        Text([first?.rsiName, first?.subcon, first?.reqDate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(allOn ? "Bỏ chọn phiếu" : "Chọn cả phiếu") { vm.setGroup(g.1, on: !allOn) }
                                        .font(.system(size: 12, weight: .semibold)).textCase(nil)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
                if !vm.selected.isEmpty { bottomBar }
            }
            .navigationTitle("Xuất kho")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
            }
        }
        .desmAlert(isPresented: $confirm, icon: "exclamationmark.triangle.fill", title: "Xác nhận xuất kho",
                   message: "Ghi xuất kho \(vm.selected.count) dòng lên DESM. Thao tác này không tự hoàn tác được.",
                   actions: [DesmDialogAction(title: "Xuất kho", kind: .destructive) { vm.save(model) },
                             DesmDialogAction(title: "Huỷ", kind: .cancel)])
        .onAppear { if !vm.searched { vm.search(model) } }
    }
}
