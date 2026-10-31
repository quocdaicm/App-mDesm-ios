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
    @Published var fPkg = ""             // lọc ngay trong phiếu (không gọi máy chủ)
    @Published var fCode = ""
    @Published var showOpts = false
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
    static func dayText(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
        return f.string(from: d)
    }

    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }

    /// Đổi MRF_HEADER_ID (số sau `MRF!!!` trong QR) thành số MRF bằng getMrfSummaryList.do (bộ lọc trống).
    /// Trả nil nếu lỗi/không thấy (khi đó dùng đường tải toàn bộ danh sách còn phải trả). Trường MRF_HEADER_ID của API này CHƯA kiểm chứng.
    func resolveMrfNo(_ model: BrowserModel, headerId: String) async -> String? {
        guard let pj = try? await model.desmProjectNo() else { return nil }
        let e = desmFormEnc
        let body = "PROJECT_NO=\(e(pj))&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&MATERIAL_CODE=&RSI_START_REQUEST_DATE=&RSI_END_REQUEST_DATE=&ZIM_ATTRIBUTE10=&RSI_BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&MRF_NO=&MRF_NAME=&PACKAGE_NO=&ITEM_DESC=&RETURN_TYPE=&MRF_BALANCE_QTY="
        guard let rows = try? await model.desmQueryAsync("/getMrfSummaryList.do", body: body) else { return nil }
        let hit = rows.first { Self.str($0, "MRF_HEADER_ID") == headerId }
        let no = hit.map { Self.str($0, "MRF_NO") } ?? ""
        return no.isEmpty ? nil : no.uppercased()
    }

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

    func search(_ model: BrowserModel, done: (() -> Void)? = nil) {
        loading = true; error = nil
        Task { @MainActor in
            let pj: String
            do { pj = try await model.desmProjectNo() }
            catch { self.loading = false; self.error = error.localizedDescription; done?(); return }
            self.project = pj
            let e = desmFormEnc
            let body = "PROJECT_NO=\(e(pj))&PACKAGE_NO=\(e(self.pkg))&MRF_NO=\(e(self.mrfNo))&MATERIAL_CODE=\(e(self.code))&REQUEST_START_DATE=&ATTRIBUTE10=&REQUEST_END_DATE=&TYPE=&CATEGORY="
            defer { self.loading = false; self.searched = true; done?() }
            let list: [[String: Any]]
            do { list = try await model.desmQueryAsync("/getDesmReturnCreationList.do", body: body) }
            catch { self.error = error.localizedDescription; self.lines = []; return }
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

    func save(_ model: BrowserModel) {
        let chosen = lines.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
        let day = f.string(from: date)
        var list: [[String: Any]] = []
        for l in chosen {
            let q = Double((qty[l.id] ?? Self.fmt(l.balance)).replacingOccurrences(of: ",", with: ".")) ?? 0
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

    // MARK: Bước 1 — tìm số MRF, ra danh sách phiếu
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

    func voucherCard(_ g: (String, [DesmMrfLine])) -> some View {
        let f = g.1.first
        let left = g.1.reduce(0.0) { $0 + $1.balance }
        return Button { path.append(g.0) } label: {
            HStack(spacing: 0) {
                Rectangle().fill(headBlue).frame(width: 5)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(g.0).font(.system(size: 17, weight: .bold)).underline()
                        Spacer()
                        Text(f?.returnType ?? "").font(.system(size: 14))
                    }
                    HStack {
                        Text(f?.mrfName ?? "").font(.system(size: 15))
                        Spacer()
                        Text(f?.status ?? "").font(.system(size: 15))
                    }
                    HStack {
                        Text("\(g.1.count) dòng · còn trả \(DesmMrfReturnVM.fmt(left))").font(.system(size: 13)).foregroundStyle(.secondary)
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
                Text(vm.searched ? "Không có phiếu MRF nào còn hàng phải trả theo điều kiện này."
                                 : "Nhập số MRF (hoặc để trống) rồi bấm Search.")
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

    // MARK: Bước 2 — mở phiếu: tích dòng, chỉnh số lượng, bấm RETURN
    func matches(_ l: DesmMrfLine) -> Bool {
        let p = vm.fPkg.trimmingCharacters(in: .whitespaces).lowercased()
        let c = vm.fCode.trimmingCharacters(in: .whitespaces).lowercased()
        if !p.isEmpty && !l.pkg.lowercased().contains(p) { return false }
        if !c.isEmpty && !(l.code.lowercased().contains(c) || l.desc.lowercased().contains(c)) { return false }
        return true
    }

    func header(_ f: DesmMrfLine?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(f?.mrfNo ?? "").font(.system(size: 22, weight: .semibold))
                Text(f?.status ?? "").font(.system(size: 20))
                Spacer(minLength: 4)
                Text(f?.returnType ?? "").font(.system(size: 18))
            }
            HStack {
                Text(f?.mrfName ?? "").font(.system(size: 20))
                Spacer()
                Text(f?.reqDate ?? "").font(.system(size: 18))
            }
            if vm.showOpts {
                DatePicker("Ngày trả", selection: $vm.date, displayedComponents: .date)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(10).background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Text(vm.showOpts ? "" : "Ngày trả: " + DesmMrfReturnVM.dayText(vm.date)).font(.system(size: 13)).opacity(0.9)
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

    func filterBar(_ shown: [DesmMrfLine]) -> some View {
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
            Button { if !vm.selected.isEmpty { vm.error = nil; confirm = true } } label: {
                HStack(spacing: 4) {
                    if vm.saving { ProgressView().tint(.white) }
                    Text(vm.selected.isEmpty ? "RETURN" : "RETURN (\(vm.selected.count))").font(.system(size: 15, weight: .bold))
                }
                .padding(.horizontal, 10).padding(.vertical, 11)
                .foregroundStyle(.white)
                .background(vm.selected.isEmpty ? Color.gray : Color(red: 0.12, green: 0.56, blue: 1.0), in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(vm.saving || vm.selected.isEmpty)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white)
    }

    func card(_ l: DesmMrfLine) -> some View {
        let on = vm.selected.contains(l.id)
        let done = max(0, l.req - l.balance)
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
                    TextField("0", text: Binding(get: { vm.qty[l.id] ?? DesmMrfReturnVM.fmt(l.balance) }, set: { vm.qty[l.id] = $0 }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.center)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 70).padding(.vertical, 6)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4)))
                }
                HStack(spacing: 4) {
                    Text(l.code).font(.system(size: 16))
                    Spacer(minLength: 4)
                    Text(String(format: "%.3f", l.balance)).font(.system(size: 17, weight: .bold)).foregroundStyle(.red)
                    Text("/").font(.system(size: 17, weight: .bold))
                    Text(String(format: "%.3f", done)).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.tabBlue)
                }
                HStack(spacing: 8) {
                    Text("đỏ = còn trả được · xanh = đã trả").font(.system(size: 10)).foregroundStyle(.secondary)
                    if !l.rsiNo.isEmpty { Text(l.rsiNo).font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                if !l.valid { Text("Thiếu MRF_LINE_ID/MRF_HEADER_ID — không thể trả dòng này.").font(.system(size: 11)).foregroundStyle(.red) }
            }
            .padding(12)
        }
        .background(on ? Color(red: 0.90, green: 0.95, blue: 1.0) : Color.white, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .onTapGesture { vm.toggle(l) }
    }

    func detail(_ mrf: String) -> some View {
        let all = vm.lines.filter { $0.mrfNo == mrf }
        let shown = all.filter { matches($0) }
        return VStack(spacing: 0) {
            header(all.first)
            filterBar(shown)
            Divider()
            if let e = vm.error {
                Text(e).font(.system(size: 13)).foregroundStyle(.red).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
            }
            if let n = vm.notice {
                Text(n).font(.system(size: 13, weight: .semibold)).foregroundStyle(.green).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.10))
            }
            if all.isEmpty {
                Spacer()
                if vm.loading { ProgressView("Đang tải…") }
                else {
                    VStack(spacing: 10) {
                        Text("Phiếu \(mrf) không còn dòng nào phải trả (đã trả hết).").font(.callout).multilineTextAlignment(.center)
                        Button("Về danh sách") { path.removeAll() }.buttonStyle(.borderedProminent)
                    }.padding(24)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(shown) { l in card(l) }
                        if shown.isEmpty { Text("Không có dòng khớp bộ lọc.").font(.footnote).foregroundStyle(.secondary).padding(20) }
                    }.padding(12)
                }
                .background(bg)
            }
        }
        .navigationTitle("MRF Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let closedPrefix = "closed:"

    /// Phiếu MRF vừa quét: đổi mã QR (MRF_HEADER_ID) thành số MRF, tìm rồi mở thẳng màn MRF Detail.
    /// Phiếu không còn dòng phải trả (đã trả hết) → mở màn xem chi tiết phiếu (chỉ xem).
    private func consumeScan() {
        guard let r0 = model.pendingRsiScan, r0.kind == .mrf else { return }
        model.pendingRsiScan = nil
        vm.mrfNo = ""; vm.mrfName = ""; vm.pkg = ""; vm.code = ""; vm.onlyOpen = true
        path.removeAll()
        withAnimation { showForm = false }
        Task { @MainActor in
            var r = r0
            if !r.isNo {
                vm.loading = true
                if let no = await vm.resolveMrfNo(model, headerId: r.value) { r = QRRsi(value: no, raw: r0.raw, isNo: true, kind: .mrf) }
            }
            let rr = r
            vm.mrfNo = rr.isNo ? rr.value : ""
            vm.search(model) {
                let hit = vm.lines.first { l in
                    rr.isNo ? l.mrfNo.uppercased() == rr.value
                            : DesmMrfReturnVM.str(["x": l.headerId], "x") == rr.value
                }
                if let h = hit {
                    vm.mrfNo = h.mrfNo
                    path = [h.mrfNo]
                } else if vm.error == nil {
                    if rr.isNo {
                        vm.notice = "Phiếu \(rr.value) không còn dòng phải trả, đang mở chi tiết để xem."
                        path = [Self.closedPrefix + rr.value]
                    } else {
                        vm.error = "Không đổi được mã \(rr.value) sang số MRF (kiểm tra mạng/phiên đăng nhập rồi quét lại)."
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            rootView
                .navigationTitle("Trả hàng MRF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                }
                .navigationDestination(for: String.self) { mrf in
                    if mrf.hasPrefix(Self.closedPrefix) {
                        DesmDocDetailView(model: model, kind: .mrf, group: DesmDocGroup(id: String(mrf.dropFirst(Self.closedPrefix.count))))
                    } else { detail(mrf) }
                }
        }
        .onChange(of: model.pendingRsiScan) { _ in consumeScan() }
        .onChange(of: path) { _ in
            // Đổi phiếu: bỏ chọn/số lượng đã gõ/bộ lọc để không trả nhầm dòng của phiếu khác
            vm.selected.removeAll(); vm.qty.removeAll(); vm.fPkg = ""; vm.fCode = ""; vm.error = nil; vm.notice = nil
        }
        .desmAlert(isPresented: $confirm, icon: "exclamationmark.triangle.fill", title: "Xác nhận trả hàng (RETURN)",
                   message: "Ghi trả hàng \(vm.selected.count) dòng lên DESM ngày \(DesmMrfReturnVM.dayText(vm.date)). Thao tác này không tự hoàn tác được.",
                   actions: [DesmDialogAction(title: "Trả hàng", kind: .destructive) { vm.save(model) },
                             DesmDialogAction(title: "Huỷ", kind: .cancel)])
        .onAppear {
            if model.pendingRsiScan?.kind == .mrf { consumeScan() }
            else if !vm.searched { vm.search(model) }
        }
    }
}
