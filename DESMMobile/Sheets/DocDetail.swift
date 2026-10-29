// DocDetail.swift — chi tiết một phiếu RSI / MRF.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Chi tiết một phiếu RSI / MRF
//
// Tải lại theo số phiếu (đúng như log: RSI_NO / MRF_NO, không giới hạn ngày) rồi ghép:
//   RSI: getDesmRsiViewList (dòng yêu cầu, tồn) + getDesmRsiOutGoingList (ngày bàn giao), ghép theo Package No + Material Code.
//   MRF: getMrfSummaryList (dòng trả, tồn) + getDesmMrfReturnList (ngày trả), ghép theo MRF_LINE_ID.

struct DesmDocLine: Identifiable {
    let id: Int
    var code = "", desc = "", pkg = "", list = "", loc = "", unit = "", date = "", note = ""
    var req = 0.0, done = 0.0
    var bal: Double? = nil
}

struct DesmDocDetail {
    var header: [(String, String)] = []
    var lines: [DesmDocLine] = []
}

extension BrowserModel {
    static func dstr(_ r: [String: Any], _ k: String) -> String {
        if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = r[k] as? NSNumber { return n.stringValue }
        return ""
    }
    static func dnum(_ r: [String: Any], _ k: String) -> Double {
        if let n = r[k] as? NSNumber { return n.doubleValue }
        if let s = r[k] as? String { return Double(s) ?? 0 }
        return 0
    }

    @MainActor
    func fetchDocDetailAsync(kind: DesmDocKind, no: String) async throws -> DesmDocDetail {
        let pj = try await desmProjectNo()
        func e(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
        }
        let P = e(pj), N = e(no)
        let pathA: String, bodyA: String, pathB: String, bodyB: String
        switch kind {
        case .rsi:
            pathA = "/getDesmRsiViewList.do"
            bodyA = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&RSI_NO=\(N)&RSI_NAME=&SUBCONTRACTOR=&ATTRIBUTE10=&MATERIAL_CODE=&START_REQUEST_DATE=&END_REQUEST_DATE=&BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&PACKAGE_NO=&ITEM_DESC=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
            pathB = "/getDesmRsiOutGoingList.do"
            bodyB = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&START_HANDOVER_DATE=&END_HANDOVER_DATE=&PACKAGE_NO=&SUBCONTRACTOR=&RSI_NO=\(N)&MATERIAL_CODE=&ATTRIBUTE10=&RSI_NAME=&TYPE=&CATEGORY=&SUB_CATEGORY=&COMMENTS=&PACKING_LIST_NO=&PENDING=&RECEIVER_REMARK=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
        case .mrf:
            pathA = "/getMrfSummaryList.do"
            bodyA = "PROJECT_NO=\(P)&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&MATERIAL_CODE=&RSI_START_REQUEST_DATE=&RSI_END_REQUEST_DATE=&ZIM_ATTRIBUTE10=&RSI_BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&MRF_NO=\(N)&MRF_NAME=&PACKAGE_NO=&ITEM_DESC=&RETURN_TYPE=&MRF_BALANCE_QTY="
            pathB = "/getDesmMrfReturnList.do"
            bodyB = "PROJECT_NO=\(P)&START_HANDOVER_DATE=&END_HANDOVER_DATE=&PACKAGE_NO=&SUBCONTRACTOR=&MRF_NO=\(N)&MATERIAL_CODE=&ATTRIBUTE10=&MRF_NAME=&TYPE=&CATEGORY="
        }
        let rowsA = try await desmQueryAsync(pathA, body: bodyA)
        let rowsB = (try? await desmQueryAsync(pathB, body: bodyB)) ?? []   // thiếu ngày bàn giao/trả thì vẫn hiện dòng
        func s(_ r: [String: Any], _ k: String) -> String { Self.dstr(r, k) }
        func n(_ r: [String: Any], _ k: String) -> Double { Self.dnum(r, k) }
        var detail = DesmDocDetail()
        switch kind {
        case .rsi:
            var dates: [String: String] = [:]
            for r in rowsB {
                let k = s(r, "PACKAGE_NO") + "|" + s(r, "MATERIAL_CODE"); let d = s(r, "HANDOVER_DATE")
                if d > (dates[k] ?? "") { dates[k] = d }
            }
            let src = rowsA.isEmpty ? rowsB : rowsA
            if let r = src.first {
                detail.header = [("Tên phiếu", s(r, "RSI_NAME")), ("Trạng thái", s(r, "STATUS")), ("Đơn vị", s(r, "SUBCONTRACTOR")),
                                 ("Ngày yêu cầu", s(r, "REQUEST_DATE")), ("Ngày duyệt", s(r, "RSI_APPROVED_DATE"))]
            }
            for (i, r) in src.enumerated() {
                let k = s(r, "PACKAGE_NO") + "|" + s(r, "MATERIAL_CODE")
                var l = DesmDocLine(id: i)
                l.code = s(r, "MATERIAL_CODE"); l.desc = s(r, "DESCRIPTION"); l.pkg = s(r, "PACKAGE_NO")
                l.list = s(r, "INVOICE_NUM").isEmpty ? s(r, "PACKING_LIST_NO") : s(r, "INVOICE_NUM")
                l.loc = s(r, "LOCATION"); l.unit = s(r, "UNIT"); l.note = s(r, "COMMENTS")
                l.req = n(r, "REQ_QTY"); l.done = n(r, "HANDOVER_QTY")
                if r["BALANCE_QTY"] != nil { l.bal = n(r, "BALANCE_QTY") }
                l.date = dates[k] ?? s(r, "HANDOVER_DATE")
                detail.lines.append(l)
            }
        case .mrf:
            var dates: [String: String] = [:]
            for r in rowsB {
                let k = s(r, "MRF_LINE_ID"); let d = s(r, "RETURN_DATE")
                if d > (dates[k] ?? "") { dates[k] = d }
            }
            let src = rowsA.isEmpty ? rowsB : rowsA
            if let r = src.first {
                detail.header = [("Tên phiếu", s(r, "MRF_NAME")), ("Trạng thái", s(r, "STATUS")), ("Loại trả", s(r, "RETURN_TYPE")),
                                 ("RSI gốc", s(r, "RSI_NO")), ("Đơn vị", s(r, "SUBCONTRACTOR")),
                                 ("Ngày yêu cầu trả", s(r, "RETURN_REQ_DATE")), ("Ngày duyệt", s(r, "APPROVED_DATE"))]
            }
            for (i, r) in src.enumerated() {
                var l = DesmDocLine(id: i)
                l.code = s(r, "MATERIAL_CODE"); l.desc = s(r, "DESCRIPTION"); l.pkg = s(r, "PACKAGE_NO")
                l.list = s(r, "PACKAGE_LIST_NO"); l.loc = s(r, "LOCATION"); l.unit = s(r, "UNIT"); l.note = s(r, "COMMENTS")
                let hasA = r["MRF_REQ_RETURN_QTY"] != nil
                l.req = n(r, hasA ? "MRF_REQ_RETURN_QTY" : "REQ_RETURN_QTY")
                l.done = n(r, hasA ? "MRF_RETURN_QTY" : "RETURN_QTY")
                if r["MRF_BALANCE_QTY"] != nil { l.bal = n(r, "MRF_BALANCE_QTY") }
                l.date = dates[s(r, "MRF_LINE_ID")] ?? s(r, "RETURN_DATE")
                detail.lines.append(l)
            }
        }
        detail.header = detail.header.filter { !$0.1.isEmpty }
        return detail
    }

    func fetchDocDetail(kind: DesmDocKind, no: String, done: @escaping (DesmDocDetail?, String) -> Void) {
        Task { @MainActor in
            do { done(try await self.fetchDocDetailAsync(kind: kind, no: no), "") }
            catch { done(nil, error.localizedDescription) }
        }
    }
}

struct DesmDocDetailView: View {
    @ObservedObject var model: BrowserModel
    let kind: DesmDocKind
    let group: DesmDocGroup

    @State private var detail: DesmDocDetail? = nil
    @State private var loading = false
    @State private var error: String? = nil

    func load() {
        loading = true; error = nil
        model.fetchDocDetail(kind: kind, no: group.id) { d, err in
            loading = false
            if let d = d { detail = d } else { error = err }
        }
    }
    func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }

    var body: some View {
        Group {
            if let error = error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(.orange)
                    Text(error).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Thử lại") { load() }.buttonStyle(.borderedProminent)
                }.padding(24)
            } else if let d = detail {
                List {
                    Section {
                        ForEach(Array(d.header.enumerated()), id: \.offset) { _, kv in
                            HStack(alignment: .firstTextBaseline) {
                                Text(kv.0).font(.system(size: 13)).foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text(kv.1).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    Section("\(d.lines.count) dòng hàng") {
                        ForEach(d.lines) { l in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(l.code.isEmpty ? "(không có mã)" : l.code).font(.system(size: 14, weight: .bold))
                                if !l.desc.isEmpty { Text(l.desc).font(.system(size: 13)).lineLimit(3) }
                                HStack(spacing: 10) {
                                    Text("\(kind == .rsi ? "Yêu cầu" : "Cần trả") \(fmt(l.req))\(l.unit.isEmpty ? "" : " " + l.unit)")
                                    Text("Đã \(kind.noun) \(fmt(l.done))")
                                    if let b = l.bal { Text("còn \(fmt(b))").foregroundStyle(b > 0 ? Color.red : Color.green) }
                                }.font(.system(size: 12, weight: .medium))
                                if !l.pkg.isEmpty { Label(l.pkg, systemImage: "shippingbox").font(.system(size: 12)) }
                                HStack(spacing: 10) {
                                    if !l.list.isEmpty { Text(l.list) }
                                    if !l.loc.isEmpty { Text(l.loc) }
                                    if !l.date.isEmpty { Text("\(kind == .rsi ? "Bàn giao" : "Trả") \(l.date)") }
                                }.font(.system(size: 11)).foregroundStyle(.secondary)
                                if !l.note.isEmpty { Text(l.note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3) }
                            }.padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ProgressView("Đang tải…")
            }
        }
        .navigationTitle(group.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
            }
        }
        .onAppear { if detail == nil && !loading { load() } }
    }
}
