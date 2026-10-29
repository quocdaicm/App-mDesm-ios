// MrfReturn.swift — tab "Trả hàng" (MRF).

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Tab "Trả hàng" (MRF): tìm MRF, tích chọn dòng còn phải trả
//
// Làm theo popup "Return Creation" của web (desmReturnCreationPopUp.js, 2026-10-28):
//   Tìm:  POST /getDesmReturnCreationList.do  (PROJECT_NO, PACKAGE_NO, MRF_NO, MATERIAL_CODE, REQUEST_START_DATE, ATTRIBUTE10, REQUEST_END_DATE, TYPE, CATEGORY)
//         trả MRF_NO, MRF_NAME, SUBCONTRACTOR, RETURN_REQ_DATE, MATERIAL_CODE, PACKAGE_NO, DESCRIPTION, REQ_RETURN_QTY, RETURN_AVAILABLE_QTY, MRF_HEADER_ID, MRF_LINE_ID, RSI_LINE_ID...
//   Lưu:  POST /saveDesmMrfReturnSave.do  updateList=[{MRF_HEADER_ID, MRF_LINE_ID, MATERIAL_CODE, PROJECT_NO, RETURN_DATE(yyyy/MM/dd), RETURN_QTY, RSI_LINE_ID}]
//         lỗi số lượng: {error:"QTY", MRF_LINE_ID, RETURN_AVAILABLE_QTY}. Phần lưu CHƯA thử trên DESM thật.

struct DesmMrfLine: Identifiable {
    let id: String
    var mrfNo = "", mrfName = "", status = "", returnType = "", reqDate = "", rsiNo = "", code = "", desc = "", pkg = "", loc = "", unit = ""
    var req = 0.0, done = 0.0, balance = 0.0
    var headerId: Any = NSNull()
    var lineId: Any = NSNull()
    var rsiLineId: Any = NSNull()
    var valid = true
}

final class DesmMrfReturnVM: ObservableObject {
    @Published var mrfNo = ""
    @Published var mrfName = ""
    @Published var pkg = ""
    @Published var code = ""
    @Published var onlyOpen = true
    @Published var saving = false
    @Published var notice: String? = nil
    var project = ""
    @Published var lines: [DesmMrfLine] = []
    @Published var selected = Set<String>()
    @Published var qty: [String: String] = [:]
    @Published var date = Date()
    @Published var loading = false
    @Published var searched = false
    @Published var error: String? = nil

    var groups: [(String, [DesmMrfLine])] {
        var order: [String] = []; var map: [String: [DesmMrfLine]] = [:]
        for l in lines { if map[l.mrfNo] == nil { order.append(l.mrfNo) }; map[l.mrfNo, default: []].append(l) }
        return order.map { ($0, map[$0] ?? []) }
    }
    var allSelected: Bool { !lines.isEmpty && selected.count == lines.filter { $0.valid }.count }

    func reset() { mrfNo = ""; mrfName = ""; pkg = ""; code = "" }
    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }

    func pick(_ l: DesmMrfLine) { selected.insert(l.id); if (qty[l.id] ?? "").isEmpty { qty[l.id] = Self.fmt(l.balance) } }
    func toggle(_ l: DesmMrfLine) { guard l.valid else { return }; if selected.contains(l.id) { selected.remove(l.id) } else { pick(l) } }
    func setGroup(_ items: [DesmMrfLine], on: Bool) { for l in items where l.valid { if on { pick(l) } else { selected.remove(l.id) } } }
    func setAll(_ on: Bool) { setGroup(lines, on: on) }

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
        loading = true; error = nil
        model.desmQuery("/getInitDefailProject.do", body: "") { rows, err in
            guard let rows = rows else { self.loading = false; self.error = err; return }
            guard let pj = rows.first?["SEGMENT1"] as? String, !pj.isEmpty else {
                self.loading = false; self.error = "Chưa có dự án mặc định trong DESM."; return
            }
            self.project = pj
            let e = desmFormEnc
            let body = "PROJECT_NO=\(e(pj))&PACKAGE_NO=\(e(self.pkg))&MRF_NO=\(e(self.mrfNo))&MATERIAL_CODE=\(e(self.code))&REQUEST_START_DATE=&ATTRIBUTE10=&REQUEST_END_DATE=&TYPE=&CATEGORY="
            model.desmQuery("/getDesmReturnCreationList.do", body: body) { list, err2 in
                self.loading = false; self.searched = true
                guard let list = list else { self.error = err2; self.lines = []; return }
                var out: [DesmMrfLine] = []
                for (i, r) in list.enumerated() {
                    let lid = r["MRF_LINE_ID"], hid = r["MRF_HEADER_ID"]
                    let ok = lid != nil && !(lid is NSNull) && hid != nil && !(hid is NSNull)
                    var l = DesmMrfLine(id: ok ? Self.str(r, "MRF_LINE_ID") + "-" + Self.str(r, "RSI_LINE_ID") : "row\(i)")
                    l.mrfNo = Self.str(r, "MRF_NO"); l.mrfName = Self.str(r, "MRF_NAME"); l.status = Self.str(r, "SUBCONTRACTOR")
                    l.returnType = Self.str(r, "TYPE"); l.reqDate = Self.str(r, "RETURN_REQ_DATE")
                    l.code = Self.str(r, "MATERIAL_CODE"); l.desc = Self.str(r, "DESCRIPTION"); l.pkg = Self.str(r, "PACKAGE_NO")
                    l.loc = Self.str(r, "CATEGORY")
                    l.req = Self.num(r, "REQ_RETURN_QTY"); l.balance = Self.num(r, "RETURN_AVAILABLE_QTY")
                    l.headerId = hid ?? NSNull(); l.lineId = lid ?? NSNull(); l.rsiLineId = r["RSI_LINE_ID"] ?? NSNull()
                    l.valid = ok
                    if self.onlyOpen && l.balance <= 0 { continue }
                    if !self.mrfName.isEmpty && !l.mrfName.localizedCaseInsensitiveContains(self.mrfName) { continue }
                    out.append(l)
                }
                out.sort { $0.reqDate > $1.reqDate }
                self.lines = out
                self.selected = self.selected.intersection(Set(out.map { $0.id }))
            }
        }
    }

    func save(_ model: BrowserModel) {
        let chosen = lines.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
        let day = f.string(from: date)
        var list: [[String: Any]] = []
        for l in chosen {
            let q = Double((qty[l.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
            if q <= 0 { error = "Số lượng trả của \(l.code) phải lớn hơn 0."; return }
            if q > l.balance + 0.0005 { error = "\(l.code): số lượng trả \(Self.fmt(q)) vượt quá số còn trả được \(Self.fmt(l.balance))."; return }
            list.append(["MRF_HEADER_ID": l.headerId, "MRF_LINE_ID": l.lineId, "MATERIAL_CODE": l.code, "PROJECT_NO": project,
                         "RETURN_DATE": day, "RETURN_QTY": q, "RSI_LINE_ID": l.rsiLineId])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list), let json = String(data: data, encoding: .utf8) else {
            error = "Không tạo được dữ liệu gửi đi."; return
        }
        saving = true; error = nil; notice = nil
        model.desmWrite("/saveDesmMrfReturnSave.do", updateList: json, label: "Trả hàng MRF") { res, err in
            self.saving = false
            if res == nil { self.error = err; return }
            guard let r = res as? [String: Any] else { self.error = "Phản hồi không rõ. Hãy kiểm tra trên web trước khi thử lại."; return }
            let e = r["error"]
            if e == nil || e is NSNull {
                self.notice = "Đã trả hàng \(chosen.count) dòng."
                self.selected.removeAll(); self.qty.removeAll()
                self.search(model)
            } else if (e as? String) == "QTY" {
                let id = Self.str(r, "MRF_LINE_ID")
                let av = Self.str(r, "RETURN_AVAILABLE_QTY")
                let name = chosen.first { Self.str(["x": $0.lineId], "x") == id }?.code ?? id
                self.error = "Vượt số lượng được trả ở dòng \(name). Còn trả được: \(av). Hãy tải lại danh sách để kiểm tra."
            } else {
                self.error = "\(e ?? "Lỗi không rõ")"
            }
        }
    }
}

struct DesmMrfReturnSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void
    @StateObject private var vm = DesmMrfReturnVM()
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
                field("MRF No.", $vm.mrfNo)
                field("MRF Name", $vm.mrfName)
                field("Package No.", $vm.pkg)
                field("Material Code", $vm.code)
                Toggle("Chỉ dòng còn phải trả", isOn: $vm.onlyOpen).font(.system(size: 13, weight: .semibold))
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

    func lineRow(_ l: DesmMrfLine) -> some View {
        let on = vm.selected.contains(l.id)
        return HStack(alignment: .top, spacing: 10) {
            Button { vm.toggle(l) } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24)).foregroundStyle(l.valid ? Color.tabBlue : Color.gray)
            }.buttonStyle(.plain).disabled(!l.valid)
            VStack(alignment: .leading, spacing: 3) {
                Text(l.code.isEmpty ? "(không có mã)" : l.code).font(.system(size: 14, weight: .bold))
                if !l.desc.isEmpty { Text(l.desc).font(.system(size: 13)).lineLimit(3) }
                if !l.pkg.isEmpty { Label(l.pkg, systemImage: "shippingbox").font(.system(size: 12)) }
                HStack(spacing: 10) {
                    Text("Cần trả \(DesmMrfReturnVM.fmt(l.req))\(l.unit.isEmpty ? "" : " " + l.unit)")
                    Text("còn trả được \(DesmMrfReturnVM.fmt(l.balance))").foregroundStyle(l.balance > 0 ? Color.red : Color.green)
                }.font(.system(size: 12, weight: .medium))
                HStack(spacing: 10) {
                    if !l.rsiNo.isEmpty { Text(l.rsiNo) }
                    if !l.loc.isEmpty { Text(l.loc) }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if on {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SL trả").font(.system(size: 10)).foregroundStyle(.secondary)
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
            DatePicker("Ngày trả", selection: $vm.date, displayedComponents: .date).font(.system(size: 14, weight: .semibold))
            Button { vm.error = nil; confirm = true } label: {
                Text(vm.saving ? "Đang gửi…" : "Trả hàng \(vm.selected.count) dòng").font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white).background(Color(red: 0.16, green: 0.65, blue: 0.40), in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).disabled(vm.saving)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchCard
                Divider()
                if let n = vm.notice {
                    Text(n).font(.system(size: 13, weight: .semibold)).foregroundStyle(.green).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.10))
                }
                if let e = vm.error {
                    Text(e).font(.system(size: 13)).foregroundStyle(.red).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                }
                if vm.loading && vm.lines.isEmpty {
                    Spacer(); ProgressView("Đang tìm…"); Spacer()
                } else if vm.lines.isEmpty {
                    Spacer()
                    Text(vm.searched ? "Không có dòng nào còn trả được." : "Nhập số MRF (hoặc để trống) rồi bấm Tìm.")
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
                                        Text([first?.mrfName, first?.status, first?.returnType, first?.reqDate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
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
            .navigationTitle("Trả hàng MRF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
            }
        }
        .desmAlert(isPresented: $confirm, icon: "exclamationmark.triangle.fill", title: "Xác nhận trả hàng",
                   message: "Ghi trả hàng \(vm.selected.count) dòng lên DESM. Thao tác này không tự hoàn tác được.",
                   actions: [DesmDialogAction(title: "Trả hàng", kind: .destructive) { vm.save(model) },
                             DesmDialogAction(title: "Huỷ", kind: .cancel)])
        .onAppear { if !vm.searched { vm.search(model) } }
    }
}
