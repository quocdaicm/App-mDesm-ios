// DocSheet.swift — RSI chưa đóng / vừa đóng và MRF trả hàng (mục "Thêm").

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - RSI chưa đóng / vừa đóng và MRF trả hàng (mục "Thêm")
//
// Nguồn dữ liệu (nhật ký API 2026-10-28), tất cả POST, dùng phiên đăng nhập của trang:
//   RSI Summary   /getDesmRsiViewList.do   (STATUS, REQ_QTY, HANDOVER_QTY, BALANCE_QTY, REQUEST_DATE, RSI_APPROVED_DATE)
//   Outgoing      /getDesmRsiOutGoingList.do (HANDOVER_DATE, HANDOVER_QTY)
//   MRF Summary   /getMrfSummaryList.do    (STATUS, MRF_REQ_RETURN_QTY, MRF_RETURN_QTY, MRF_BALANCE_QTY, RETURN_REQ_DATE)
//   Return Control /getDesmMrfReturnList.do (RETURN_DATE, RETURN_QTY)
// QUY ƯỚC (suy từ dữ liệu, CHƯA xác nhận với nghiệp vụ DESM): "chưa đóng" = tổng số lượng còn lại (BALANCE_QTY / MRF_BALANCE_QTY) > 0;
// "vừa đóng" = có bàn giao / trả hàng trong N ngày gần đây và không còn số lượng còn lại. Chưa biết hết các giá trị STATUS.
// CHƯA kiểm chứng: máy chủ lọc đúng theo START/END_*_DATE khi để trống số phiếu (đã lọc thêm phía máy khách để an toàn).

enum DesmDocKind: String, Identifiable {
    case rsi, mrf
    var id: String { rawValue }
    var title: String { self == .rsi ? "RSI" : "MRF trả hàng" }
    var noun: String { self == .rsi ? "xuất" : "trả" }
}

struct DesmDocGroup: Identifiable, Hashable {
    let id: String
    var name = ""
    var date = ""
    var closeDate = ""
    var status = ""
    var extra = ""
    var lines = 0
    var qty = 0.0
    var done = 0.0
    var balance: Double? = nil
}

extension BrowserModel {
    static func fstr(_ r: [String: Any], _ k: String) -> String {
        if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = r[k] as? NSNumber { return n.stringValue }
        return ""
    }
    static func fnum(_ r: [String: Any], _ k: String) -> Double {
        if let n = r[k] as? NSNumber { return n.doubleValue }
        if let s = r[k] as? String { return Double(s) ?? 0 }
        return 0
    }
    static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
    }

    /// Gộp các dòng thành từng phiếu (theo số phiếu).
    static func groups(_ rows: [[String: Any]], doc: String, name: String, date: String, status: String, extra: String,
                               qty: String, done: String, bal: String?, close: String?) -> [DesmDocGroup] {
        var order: [String] = []; var map: [String: DesmDocGroup] = [:]
        for r in rows {
            let id = fstr(r, doc); if id.isEmpty { continue }
            var g: DesmDocGroup
            if let ex = map[id] { g = ex } else { g = DesmDocGroup(id: id); order.append(id) }
            g.lines += 1
            if g.name.isEmpty { g.name = fstr(r, name) }
            if g.date.isEmpty { g.date = fstr(r, date) }
            if g.status.isEmpty { g.status = fstr(r, status) }
            if g.extra.isEmpty { g.extra = fstr(r, extra) }
            g.qty += fnum(r, qty); g.done += fnum(r, done)
            if let b = bal { g.balance = (g.balance ?? 0) + fnum(r, b) }
            if let c = close { let v = fstr(r, c); if v > g.closeDate { g.closeDate = v } }
            map[id] = g
        }
        return order.compactMap { map[$0] }
    }

    /// open = còn số lượng chưa xử lý (mới nhất trước); closed = vừa bàn giao/trả trong `days` ngày và không còn số lượng còn lại.
    @MainActor
    func fetchDocsAsync(kind: DesmDocKind, days: Int) async throws -> (open: [DesmDocGroup], closed: [DesmDocGroup]) {
        let P = Self.enc(try await desmProjectNo())
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
        let cal = Calendar.current; let now = Date()
        let today = f.string(from: now)
        let cutoff = f.string(from: cal.date(byAdding: .day, value: -days, to: now) ?? now)
        let openFrom = f.string(from: cal.date(byAdding: .day, value: -180, to: now) ?? now)
        func d(_ s: String) -> String { Self.enc(s) }

        let pathA: String, bodyA: String, pathB: String, bodyB: String
        switch kind {
        case .rsi:
            pathA = "/getDesmRsiViewList.do"
            bodyA = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&ATTRIBUTE10=&MATERIAL_CODE=&START_REQUEST_DATE=\(d(openFrom))&END_REQUEST_DATE=\(d(today))&BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&PACKAGE_NO=&ITEM_DESC=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
            pathB = "/getDesmRsiOutGoingList.do"
            bodyB = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&START_HANDOVER_DATE=\(d(cutoff))&END_HANDOVER_DATE=\(d(today))&PACKAGE_NO=&SUBCONTRACTOR=&RSI_NO=&MATERIAL_CODE=&ATTRIBUTE10=&RSI_NAME=&TYPE=&CATEGORY=&SUB_CATEGORY=&COMMENTS=&PACKING_LIST_NO=&PENDING=&RECEIVER_REMARK=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
        case .mrf:
            pathA = "/getMrfSummaryList.do"
            bodyA = "PROJECT_NO=\(P)&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&MATERIAL_CODE=&RSI_START_REQUEST_DATE=&RSI_END_REQUEST_DATE=&ZIM_ATTRIBUTE10=&RSI_BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&MRF_NO=&MRF_NAME=&PACKAGE_NO=&ITEM_DESC=&RETURN_TYPE=&MRF_BALANCE_QTY="
            pathB = "/getDesmMrfReturnList.do"
            bodyB = "PROJECT_NO=\(P)&START_HANDOVER_DATE=\(d(cutoff))&END_HANDOVER_DATE=\(d(today))&PACKAGE_NO=&SUBCONTRACTOR=&MRF_NO=&MATERIAL_CODE=&ATTRIBUTE10=&MRF_NAME=&TYPE=&CATEGORY="
        }
        let rowsA = try await desmQueryAsync(pathA, body: bodyA)
        let rowsB = try await desmQueryAsync(pathB, body: bodyB)
        let a: [DesmDocGroup], b: [DesmDocGroup]
        switch kind {
        case .rsi:
            a = Self.groups(rowsA, doc: "RSI_NO", name: "RSI_NAME", date: "REQUEST_DATE", status: "STATUS", extra: "SUBCONTRACTOR",
                            qty: "REQ_QTY", done: "HANDOVER_QTY", bal: "BALANCE_QTY", close: nil)
            b = Self.groups(rowsB, doc: "RSI_NO", name: "RSI_NAME", date: "REQUEST_DATE", status: "", extra: "SUBCONTRACTOR",
                            qty: "REQ_QTY", done: "HANDOVER_QTY", bal: nil, close: "HANDOVER_DATE")
        case .mrf:
            a = Self.groups(rowsA, doc: "MRF_NO", name: "MRF_NAME", date: "RETURN_REQ_DATE", status: "STATUS", extra: "RETURN_TYPE",
                            qty: "MRF_REQ_RETURN_QTY", done: "MRF_RETURN_QTY", bal: "MRF_BALANCE_QTY", close: nil)
            b = Self.groups(rowsB, doc: "MRF_NO", name: "MRF_NAME", date: "RETURN_REQ_DATE", status: "", extra: "RETURN_TYPE",
                            qty: "REQ_RETURN_QTY", done: "RETURN_QTY", bal: nil, close: "RETURN_DATE")
        }
        let open = a.filter { ($0.balance ?? 0) > 0 }.sorted { $0.date > $1.date }
        let byId = Dictionary(a.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        var closed: [DesmDocGroup] = []
        for var g in b where g.closeDate >= cutoff {
            if let m = byId[g.id] {
                if (m.balance ?? 0) > 0 { continue }   // còn số lượng chưa xử lý: thuộc nhóm "chưa đóng"
                g.balance = m.balance; g.status = m.status
            }
            closed.append(g)
        }
        closed.sort { $0.closeDate > $1.closeDate }
        return (open, closed)
    }

    func fetchDocs(kind: DesmDocKind, days: Int, done: @escaping ([DesmDocGroup], [DesmDocGroup], String) -> Void) {
        Task { @MainActor in
            do { let r = try await self.fetchDocsAsync(kind: kind, days: days); done(r.open, r.closed, "") }
            catch { done([], [], error.localizedDescription) }
        }
    }
}

struct DesmDocSheet: View {
    @ObservedObject var model: BrowserModel
    let kind: DesmDocKind
    var onClose: () -> Void

    @State private var tab = 0
    @State private var days = 7
    @State private var openList: [DesmDocGroup] = []
    @State private var closedList: [DesmDocGroup] = []
    @State private var loading = false
    @State private var error: String? = nil

    func load() {
        loading = true; error = nil
        model.fetchDocs(kind: kind, days: days) { o, c, err in
            loading = false
            if err.isEmpty { openList = o; closedList = c } else { openList = []; closedList = []; error = err }
        }
    }

    func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }

    var current: [DesmDocGroup] { tab == 0 ? openList : closedList }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Nhóm", selection: $tab) {
                    Text("Chưa đóng (\(openList.count))").tag(0)
                    Text("Vừa đóng (\(closedList.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 10)
                if tab == 1 {
                    Picker("Trong", selection: $days) {
                        Text("1 ngày").tag(1); Text("3 ngày").tag(3); Text("7 ngày").tag(7); Text("30 ngày").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16).padding(.top, 8)
                    .onChange(of: days) { _ in load() }
                }
                Spacer().frame(height: 8)

                if loading && current.isEmpty && error == nil {
                    Spacer(); ProgressView("Đang tải…"); Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(.orange)
                        Text(error).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Thử lại") { load() }.buttonStyle(.borderedProminent)
                    }.padding(24)
                    Spacer()
                } else if current.isEmpty {
                    Spacer()
                    Text(tab == 0 ? "Không có \(kind.title) nào còn chưa đóng."
                                  : "Không có \(kind.title) nào vừa đóng trong \(days) ngày gần đây.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    List(current) { g in
                        NavigationLink {
                            DesmDocDetailView(model: model, kind: kind, group: g)
                        } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(g.id).font(.system(size: 15, weight: .bold))
                                Spacer(minLength: 6)
                                if !g.status.isEmpty {
                                    Text(g.status).font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .foregroundStyle(Color.tabBlue)
                                        .background(Color.tabBlue.opacity(0.12), in: Capsule())
                                }
                            }
                            if !g.name.isEmpty { Text(g.name).font(.system(size: 13)).lineLimit(2) }
                            HStack(spacing: 10) {
                                Text("\(g.lines) dòng")
                                Text("Đã \(kind.noun) \(fmt(g.done))/\(fmt(g.qty))")
                                if let b = g.balance { Text("còn \(fmt(b))").foregroundStyle(b > 0 ? Color.red : Color.green) }
                            }.font(.system(size: 12, weight: .medium))
                            HStack(spacing: 10) {
                                if !g.date.isEmpty { Text("Yêu cầu \(g.date)") }
                                if !g.closeDate.isEmpty { Text("Đóng \(g.closeDate)") }
                                if !g.extra.isEmpty { Text(g.extra).lineLimit(1) }
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(kind == .rsi ? "RSI" : "MRF trả hàng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
        }
        .onAppear { if openList.isEmpty && closedList.isEmpty && !loading { load() } }
    }
}
