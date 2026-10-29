// EditLog.swift — tra Edit Log hạng mục (mục "Thêm").

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Tra Edit Log hạng mục (mục "Thêm")
//
// Nhập Material Code hoặc Package No -> tìm hạng mục bằng /getIdsmOsDetailList.do (Material Code: KEY1='material', VALUE1=<mã>; Package: PACKAGE_NO)
// -> chọn hạng mục -> /getDesmPlDetailEditLogList.do {PROJECT_NO, TRK_ITEM_NAME, MATERIAL_CODE} (như popup "Material record" của web).
// CHƯA kiểm chứng với DESM thật: tên trường trả về lấy theo desmPlDtlEditLogPopUp.js.

struct DesmLogItem: Identifiable, Hashable {
    let id: String
    let project: String
    let trk: String
    let pkg: String
    let material: String
    let desc: String
    let location: String
}

struct DesmLogEntry: Identifiable {
    let id: Int
    let date: String
    let by: String
    let location: String
    let locInfo: String
    let qty: String
    let remarks: String
    let reports: String
    let diffs: [String]
    let hasOlder: Bool
}

extension BrowserModel {
    @MainActor
    func searchLogItemsAsync(byMaterial: Bool, term: String) async throws -> [DesmLogItem] {
        let no = try await desmProjectNo()
        let t = Self.enc(term.trimmingCharacters(in: .whitespacesAndNewlines))
        let pkg = byMaterial ? "" : t
        let key = byMaterial ? "material" : ""
        let val = byMaterial ? t : ""
        let body = "PAGE_NUM=1&PAGE_CNT=300&PROJECT_NO=\(Self.enc(no))&PACKAGE_LIST_NO=&PACKAGE_NO=\(pkg)&DESCRIPTION=&DRAWING_NO=&TAG_NO=&QTY_TYPE=rsi&QTY=&KEY1=\(key)&VALUE1=\(val)&LOCATION=&SEQUENCE=&VENDOR=&ATTRIBUTE10=&TYPE=&CATEGORY=&SUB_CATEGORY=&COMMENTS="
        let list = try await desmQueryAsync("/getIdsmOsDetailList.do", body: body)
        var out: [DesmLogItem] = []
        for (i, r) in list.enumerated() {
            let trk = Self.fstr(r, "TRK_ITEM_NAME"), mat = Self.fstr(r, "MATERIAL_CODE")
            if mat.isEmpty { continue }
            out.append(DesmLogItem(id: "\(i)-\(mat)", project: Self.fstr(r, "PROJECT_NO").isEmpty ? no : Self.fstr(r, "PROJECT_NO"),
                                   trk: trk, pkg: Self.fstr(r, "PACKAGE_NO"), material: mat,
                                   desc: Self.fstr(r, "DESCRIPTION"), location: Self.fstr(r, "LOCATION")))
        }
        return out
    }

    func searchLogItems(byMaterial: Bool, term: String, done: @escaping ([DesmLogItem], String) -> Void) {
        Task { @MainActor in
            do { done(try await self.searchLogItemsAsync(byMaterial: byMaterial, term: term), "") }
            catch { done([], error.localizedDescription) }
        }
    }

    @MainActor
    func fetchEditLogAsync(_ item: DesmLogItem) async throws -> [DesmLogEntry] {
        let body = "PROJECT_NO=\(Self.enc(item.project))&TRK_ITEM_NAME=\(Self.enc(item.trk))&MATERIAL_CODE=\(Self.enc(item.material))"
        var list = try await desmQueryAsync("/getDesmPlDetailEditLogList.do", body: body)
        list.sort { Self.fstr($0, "CREATION_DATE_TXT") > Self.fstr($1, "CREATION_DATE_TXT") }
        let fields: [(String, String)] = [("LOCATION", "Location"), ("IN_QTY", "In Q'ty"), ("REMARKS", "Remarks"), ("DESCRIPTION", "Item"),
                                          ("DRAWING_NO", "DWG"), ("TAG_NO", "TAG"), ("UNIT", "Unit"), ("MATERIAL", "Material"),
                                          ("REPORT_SHORT_QTY", "Short"), ("REPORT_OVER_QTY", "Over"), ("REPORT_DMG_QTY", "DMG"), ("REPORT_MISSING_QTY", "Missing")]
        func norm(_ r: [String: Any], _ k: String) -> String {
            Self.fstr(r, k).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        }
        func num(_ r: [String: Any], _ k: String) -> String {
            let v = Self.fnum(r, k); return v == v.rounded() ? String(Int(v)) : String(format: "%.3g", v)
        }
        var out: [DesmLogEntry] = []
        for (i, r) in list.enumerated() {
            var diffs: [String] = []
            let older: [String: Any]? = i + 1 < list.count ? list[i + 1] : nil
            if let o = older {
                for (k, label) in fields where norm(r, k) != norm(o, k) {
                    diffs.append("\(label): \(norm(o, k).isEmpty ? "-" : norm(o, k)) → \(norm(r, k).isEmpty ? "-" : norm(r, k))")
                }
            }
            var rep: [String] = []
            for (k, label) in [("REPORT_SHORT_QTY", "Short"), ("REPORT_OVER_QTY", "Over"), ("REPORT_DMG_QTY", "DMG"), ("REPORT_MISSING_QTY", "Missing")] where Self.fnum(r, k) > 0 {
                rep.append("\(label) \(num(r, k))")
            }
            let ld = norm(r, "LOC_UPDATE_DATE"), lb = norm(r, "LOC_UPDATED_BY")
            let info = [ld, lb].filter { !$0.isEmpty }.joined(separator: " · ")
            let qty = "In Q'ty \(num(r, "IN_QTY")) \(norm(r, "UNIT"))".trimmingCharacters(in: .whitespaces)
            out.append(DesmLogEntry(id: i, date: norm(r, "CREATION_DATE_TXT"), by: norm(r, "CREATED_BY"), location: norm(r, "LOCATION"),
                                    locInfo: info, qty: qty, remarks: norm(r, "REMARKS"), reports: rep.joined(separator: " · "),
                                    diffs: diffs, hasOlder: older != nil))
        }
        return out
    }

    func fetchEditLog(_ item: DesmLogItem, done: @escaping ([DesmLogEntry], String) -> Void) {
        Task { @MainActor in
            do { done(try await self.fetchEditLogAsync(item), "") }
            catch { done([], error.localizedDescription) }
        }
    }
}

struct DesmEditLogDetailView: View {
    @ObservedObject var model: BrowserModel
    let item: DesmLogItem
    @State private var entries: [DesmLogEntry] = []
    @State private var loading = true
    @State private var error: String? = nil

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.material).font(.system(size: 15, weight: .bold))
                    if !item.desc.isEmpty { Text(item.desc).font(.system(size: 13)) }
                    if !item.pkg.isEmpty { Text(item.pkg).font(.system(size: 12)).foregroundStyle(.secondary) }
                }
            }
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let error = error {
                Text(error).font(.callout).foregroundStyle(.orange)
            } else if entries.isEmpty {
                Text("Hạng mục này chưa có lịch sử chỉnh sửa.").font(.callout).foregroundStyle(.secondary)
            } else {
                Section("\(entries.count) bản ghi (mới nhất trước)") {
                    ForEach(entries) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(e.date.isEmpty ? "—" : e.date).font(.system(size: 14, weight: .bold))
                                Spacer()
                                Text(e.by).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            if e.hasOlder {
                                Text(e.diffs.isEmpty ? "Không đổi so với bản trước" : "Thay đổi — " + e.diffs.joined(separator: " · "))
                                    .font(.system(size: 12, weight: e.diffs.isEmpty ? .regular : .semibold))
                                    .foregroundStyle(e.diffs.isEmpty ? Color.secondary : Color.orange)
                            }
                            Text("📍 " + (e.location.isEmpty ? "—" : e.location) + (e.locInfo.isEmpty ? "" : "   (\(e.locInfo))"))
                                .font(.system(size: 12))
                            Text(e.qty + (e.remarks.isEmpty ? "" : "   Remarks: \(e.remarks)")).font(.system(size: 12)).foregroundStyle(.secondary)
                            if !e.reports.isEmpty { Text(e.reports).font(.system(size: 12)).foregroundStyle(.secondary) }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Edit Log")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard loading else { return }
            if item.trk.isEmpty { loading = false; error = "Thiếu TRK_ITEM_NAME của hạng mục nên chưa xem được Edit Log."; return }
            model.fetchEditLog(item) { list, err in
                loading = false
                if err.isEmpty { entries = list } else { error = err }
            }
        }
    }
}

struct DesmEditLogSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    @State private var byMaterial = true
    @State private var term = ""
    @State private var items: [DesmLogItem] = []
    @State private var loading = false
    @State private var error: String? = nil
    @State private var searched = false

    func search() {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !loading else { return }
        loading = true; error = nil; searched = true
        model.searchLogItems(byMaterial: byMaterial, term: t) { list, err in
            loading = false
            if err.isEmpty { items = list } else { items = []; error = err }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tìm theo", selection: $byMaterial) {
                    Text("Material Code").tag(true)
                    Text("Package No").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 10)
                HStack(spacing: 8) {
                    TextField(byMaterial ? "Vd: OMN-009-001-00002" : "Vd: OM4-DE-IS-0009-002", text: $term)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder).submitLabel(.search).onSubmit { search() }
                    Button("Tìm") { search() }.buttonStyle(.borderedProminent).disabled(loading || term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16)

                if loading {
                    Spacer(); ProgressView("Đang tìm…"); Spacer()
                } else if let error = error {
                    Spacer(); Text(error).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center).padding(24); Spacer()
                } else if items.isEmpty {
                    Spacer()
                    Text(searched ? "Không tìm thấy hạng mục nào." : "Nhập Material Code hoặc Package No rồi bấm Tìm.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    List(items) { it in
                        NavigationLink {
                            DesmEditLogDetailView(model: model, item: it)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(it.material).font(.system(size: 14, weight: .bold))
                                if !it.desc.isEmpty { Text(it.desc).font(.system(size: 12)).lineLimit(2) }
                                Text([it.pkg, it.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tra Edit Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } } }
        }
    }
}
