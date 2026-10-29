// WipCompletion.swift — WIP Completion (mục "Thêm").

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - WIP Completion (mục "Thêm")
//
// Làm theo popup "WIP Creation" của web (plWipCreationPopup.js, 2026-10-28):
//   Tìm:  POST /material/getPlWipCreationList.do   (đã kiểm chứng bằng log: trả WIP_AVAILABLE_QTY, WIP_DATE, WIP_QTY, SHOP_UNIT, SHOP_BLDG, RSI_LINE_ID, RSI_HEADER_ID...)
//   Lưu:  POST /material/savePlWipQuantity.do  updateList = JSON [{PROJECT_NO, RSI_HEADER_ID, RSI_LINE_ID, WIP_DATE, WIP_QTY, SHOP_UNIT, SHOP_BLDG, MATERIAL_CODE}]
//   Bắt buộc mỗi dòng: WIP date, WIP qty, C.Unit và BLDG (web có nút batch gán Unit/Bldg cho các dòng đã chọn).
//   Phản hồi: error rỗng/null là thành công; error == "QTY" kèm RSI_LINE_ID là vượt số lượng WIP khả dụng.
// CHƯA kiểm chứng: lệnh lưu với máy chủ thật (thao tác GHI).

struct DesmWipLine: Identifiable {
    let id: String
    var rsiNo = "", rsiName = "", subcon = "", reqDate = "", pkg = "", desc = "", code = "", tag = "", unit = "", project = ""
    var shopUnit = "", shopBldg = ""
    var avail = 0.0, handover = 0.0, totWip = 0.0
    var headerId: Any = NSNull()
    var lineId: Any = NSNull()
    var valid = true
}

final class DesmWipVM: ObservableObject {
    @Published var rsiNo = ""
    @Published var rsiName = ""
    @Published var pkg = ""
    @Published var code = ""
    @Published var lines: [DesmWipLine] = []
    @Published var selected = Set<String>()
    @Published var qty: [String: String] = [:]
    @Published var unitIn: [String: String] = [:]
    @Published var bldgIn: [String: String] = [:]
    @Published var date = Date()
    @Published var batchUnit = ""
    @Published var batchBldg = ""
    @Published var loading = false
    @Published var saving = false
    @Published var searched = false
    @Published var error: String? = nil
    @Published var notice: String? = nil
    var project = ""

    var groups: [(String, [DesmWipLine])] {
        var order: [String] = []; var map: [String: [DesmWipLine]] = [:]
        for l in lines { if map[l.rsiNo] == nil { order.append(l.rsiNo) }; map[l.rsiNo, default: []].append(l) }
        return order.map { ($0, map[$0] ?? []) }
    }
    var allSelected: Bool { !lines.isEmpty && selected.count == lines.filter { $0.valid }.count }

    func reset() { rsiNo = ""; rsiName = ""; pkg = ""; code = "" }
    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }

    func pick(_ l: DesmWipLine) {
        selected.insert(l.id)
        if (qty[l.id] ?? "").isEmpty { qty[l.id] = Self.fmt(l.avail) }
        if (unitIn[l.id] ?? "").isEmpty { unitIn[l.id] = l.shopUnit }
        if (bldgIn[l.id] ?? "").isEmpty { bldgIn[l.id] = l.shopBldg }
    }
    func toggle(_ l: DesmWipLine) {
        guard l.valid else { return }
        if selected.contains(l.id) { selected.remove(l.id) } else { pick(l) }
    }
    func setGroup(_ items: [DesmWipLine], on: Bool) {
        for l in items where l.valid { if on { pick(l) } else { selected.remove(l.id) } }
    }
    func setAll(_ on: Bool) { setGroup(lines, on: on) }
    /// Gán C.Unit / BLDG cho các dòng đã chọn (giống nút batch của web).
    func applyBatch() {
        let u = batchUnit.trimmingCharacters(in: .whitespacesAndNewlines), b = batchBldg.trimmingCharacters(in: .whitespacesAndNewlines)
        for id in selected { if !u.isEmpty { unitIn[id] = u }; if !b.isEmpty { bldgIn[id] = b } }
    }

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
        model.desmQuery("/getInitDefailProject.do", body: "") { rows, err in
            guard let rows = rows else { self.loading = false; self.error = err; return }
            guard let pj = rows.first?["SEGMENT1"] as? String, !pj.isEmpty else {
                self.loading = false; self.error = "Chưa có dự án mặc định trong DESM."; return
            }
            self.project = pj
            let e = desmFormEnc
            let body = "PROJECT_NO=\(e(pj))&PACKING_LIST_NO=&PACKAGE_NO=\(e(self.pkg))&RSI_NO=\(e(self.rsiNo))&RSI_NAME=\(e(self.rsiName))&SUBCON=&MATERIAL_CODE=\(e(self.code))&ATTRIBUTE10=&DESCRIPTION=&DRAWING_NO=&TAG_NO=&TYPE=&CATEGORY=&SUB_CATEGORY=&SHOP_UNIT=&SHOP_BLDG="
            model.desmQuery("/material/getPlWipCreationList.do", body: body) { list, err2 in
                self.loading = false; self.searched = true
                guard let list = list else { self.error = err2; self.lines = []; return }
                var out: [DesmWipLine] = []
                for (i, r) in list.enumerated() {
                    let lineId = r["RSI_LINE_ID"], headerId = r["RSI_HEADER_ID"]
                    let hasIds = lineId != nil && !(lineId is NSNull) && headerId != nil && !(headerId is NSNull)
                    var l = DesmWipLine(id: hasIds ? Self.str(r, "RSI_LINE_ID") : "row\(i)")
                    l.rsiNo = Self.str(r, "RSI_NO"); l.rsiName = Self.str(r, "RSI_NAME"); l.subcon = Self.str(r, "SUBCONTRACTOR")
                    l.reqDate = Self.str(r, "REQUEST_DATE"); l.pkg = Self.str(r, "PACKAGE_NO"); l.desc = Self.str(r, "DESCRIPTION")
                    l.code = Self.str(r, "MATERIAL_CODE"); l.tag = Self.str(r, "TAG_NO"); l.unit = Self.str(r, "UNIT")
                    l.project = Self.str(r, "PROJECT_NO")
                    l.shopUnit = Self.str(r, "SHOP_UNIT"); l.shopBldg = Self.str(r, "SHOP_BLDG")
                    l.avail = Self.num(r, "WIP_AVAILABLE_QTY"); l.handover = Self.num(r, "TOT_HANDOVER_QTY"); l.totWip = Self.num(r, "TOT_WIP_QTY")
                    l.headerId = headerId ?? NSNull(); l.lineId = lineId ?? NSNull()
                    l.valid = hasIds
                    out.append(l)
                }
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
            let u = (unitIn[l.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let b = (bldgIn[l.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if q <= 0 { error = "Số lượng WIP của \(l.code) phải lớn hơn 0."; return }
            if q > l.avail + 0.0005 { error = "\(l.code): WIP \(Self.fmt(q)) vượt quá số khả dụng \(Self.fmt(l.avail))."; return }
            if u.isEmpty || b.isEmpty { error = "\(l.code): chưa nhập C.Unit/BLDG. Nhập ở ô cuối trang rồi bấm “Áp dụng cho dòng đã chọn”."; return }
            list.append(["PROJECT_NO": l.project.isEmpty ? project : l.project, "RSI_HEADER_ID": l.headerId, "RSI_LINE_ID": l.lineId,
                         "WIP_DATE": day, "WIP_QTY": q, "SHOP_UNIT": u, "SHOP_BLDG": b, "MATERIAL_CODE": l.code])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list), let json = String(data: data, encoding: .utf8) else {
            error = "Không tạo được dữ liệu gửi đi."; return
        }
        saving = true; error = nil; notice = nil
        model.desmWrite("/material/savePlWipQuantity.do", updateList: json, label: "WIP Completion") { res, err in
            self.saving = false
            if res == nil { self.error = err; return }
            guard let r = res as? [String: Any] else { self.error = "Phản hồi không rõ. Hãy kiểm tra trên web trước khi thử lại."; return }
            let e = r["error"]
            if e == nil || e is NSNull {
                self.notice = "Đã hoàn tất WIP \(chosen.count) dòng."
                self.selected.removeAll(); self.qty.removeAll(); self.unitIn.removeAll(); self.bldgIn.removeAll()
                self.search(model)
            } else if (e as? String) == "QTY" {
                self.error = "Vượt số lượng WIP khả dụng ở một dòng (RSI_LINE_ID \(Self.str(r, "RSI_LINE_ID"))). Hãy tải lại danh sách rồi kiểm tra."
            } else {
                self.error = "\(e ?? "Lỗi không rõ")"
            }
        }
    }
}

struct DesmWipSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void
    @StateObject private var vm = DesmWipVM()
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
    func mini(_ title: String, _ binding: Binding<String>, width: CGFloat, keyboard: UIKeyboardType = .default, red: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("", text: binding).keyboardType(keyboard).autocorrectionDisabled().textInputAutocapitalization(.characters)
                .font(.system(size: 14, weight: .bold)).foregroundStyle(red ? Color.red : Color.primary)
                .frame(width: width).padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color(red: 1, green: 1, blue: 0.88), in: RoundedRectangle(cornerRadius: 8))
        }
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

    func lineRow(_ l: DesmWipLine) -> some View {
        let on = vm.selected.contains(l.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Button { vm.toggle(l) } label: {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24)).foregroundStyle(l.valid ? Color.tabBlue : Color.gray)
                }.buttonStyle(.plain).disabled(!l.valid)
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.code.isEmpty ? "(không có mã)" : l.code).font(.system(size: 14, weight: .bold))
                    if !l.desc.isEmpty { Text(l.desc).font(.system(size: 13)).lineLimit(3) }
                    HStack(spacing: 8) {
                        if !l.tag.isEmpty { Text("Tag \(l.tag)") }
                        if !l.pkg.isEmpty { Label(l.pkg, systemImage: "shippingbox") }
                    }.font(.system(size: 12))
                    HStack(spacing: 10) {
                        Text("Đã xuất \(DesmWipVM.fmt(l.handover))")
                        Text("WIP \(DesmWipVM.fmt(l.totWip))")
                        Text("Khả dụng \(DesmWipVM.fmt(l.avail))").foregroundStyle(l.avail > 0 ? Color.tabBlue : Color.red)
                    }.font(.system(size: 12, weight: .medium))
                    if !l.shopUnit.isEmpty || !l.shopBldg.isEmpty {
                        Text("C.Unit \(l.shopUnit) · BLDG \(l.shopBldg)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if !l.valid { Text("Thiếu RSI_LINE_ID/RSI_HEADER_ID — không thể xử lý dòng này.").font(.system(size: 11)).foregroundStyle(.red) }
                }
                Spacer(minLength: 0)
            }
            if on {
                HStack(spacing: 8) {
                    mini("SL WIP", Binding(get: { vm.qty[l.id] ?? "" }, set: { vm.qty[l.id] = $0 }), width: 70, keyboard: .decimalPad, red: true)
                    mini("C.Unit", Binding(get: { vm.unitIn[l.id] ?? "" }, set: { vm.unitIn[l.id] = $0 }), width: 70)
                    mini("BLDG", Binding(get: { vm.bldgIn[l.id] ?? "" }, set: { vm.bldgIn[l.id] = $0 }), width: 70)
                    Spacer(minLength: 0)
                }.padding(.leading, 34)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { vm.toggle(l) }
    }

    var bottomBar: some View {
        VStack(spacing: 8) {
            DatePicker("Ngày WIP", selection: $vm.date, displayedComponents: .date).font(.system(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                mini("C.Unit (gán loạt)", $vm.batchUnit, width: 110)
                mini("BLDG (gán loạt)", $vm.batchBldg, width: 110)
                Button { vm.applyBatch() } label: {
                    Text("Áp dụng cho dòng đã chọn").font(.system(size: 12, weight: .bold)).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(.white).background(Color(red: 0.42, green: 0.53, blue: 0.72), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            Button { confirm = true } label: {
                HStack {
                    if vm.saving { ProgressView().tint(.white) }
                    Text("Completion \(vm.selected.count) dòng").font(.system(size: 16, weight: .bold))
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
                    Text(vm.searched ? "Không có dòng nào theo điều kiện này." : "Nhập số RSI rồi bấm Tìm.")
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
            .navigationTitle("WIP Completion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
            }
        }
        .desmAlert(isPresented: $confirm, icon: "exclamationmark.triangle.fill", title: "Xác nhận Completion",
                   message: "Ghi WIP \(vm.selected.count) dòng lên DESM. Thao tác này không tự hoàn tác được.",
                   actions: [DesmDialogAction(title: "Completion", kind: .destructive) { vm.save(model) },
                             DesmDialogAction(title: "Huỷ", kind: .cancel)])
    }
}
