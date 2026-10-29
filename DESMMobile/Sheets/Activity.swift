// Activity.swift — hoạt động gần đây (mục "Thêm").

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Hoạt động gần đây (mục "Thêm")
//
// Gom các hoạt động đọc được từ DESM trong 1/3/7 ngày: Packing List mới tải lên, phiếu RSI mới tạo, RSI đã bàn giao,
// phiếu MRF trả hàng mới tạo, MRF đã trả. Dùng đúng các truy vấn đã có ở `fetchDocs` / `fetchPackingHistory`.
// Nhãn "MỚI" = chưa thấy ở lần mở trước (danh sách đã thấy lưu ở UserDefaults `desmActivitySeen`; lần mở đầu tiên không gắn nhãn).
// Đổi vị trí / xác nhận kiện lấy từ `/getIdsmOsSummaryList.do` (LOC_UPDATE_DATE, LOC_UPDATED_BY, CONFIRM_DATE, CONFIRMED_BY): chỉ có lần cập nhật CUỐI của mỗi kiện,
// không phải toàn bộ Edit Log (chưa bắt được API Edit Log).
// "Phiếu mới tạo" suy từ ngày yêu cầu (REQUEST_DATE / RETURN_REQ_DATE) nên chỉ chính xác theo ngày, không theo giờ.

enum DesmActivityKind: String {
    case packingUpload, rsiNew, rsiHandover, mrfNew, mrfReturn, locationUpdate, pkgConfirm
    var label: String {
        switch self {
        case .packingUpload: return "Tải Packing List"
        case .rsiNew: return "RSI mới"
        case .rsiHandover: return "RSI bàn giao"
        case .mrfNew: return "MRF mới"
        case .mrfReturn: return "MRF đã trả"
        case .locationUpdate: return "Đổi vị trí"
        case .pkgConfirm: return "Xác nhận kiện"
        }
    }
    var symbol: String {
        switch self {
        case .packingUpload: return "doc.badge.arrow.up"
        case .rsiNew: return "doc.badge.plus"
        case .rsiHandover: return "shippingbox.and.arrow.backward"
        case .mrfNew: return "arrow.uturn.backward.circle"
        case .mrfReturn: return "checkmark.circle"
        case .locationUpdate: return "mappin.and.ellipse"
        case .pkgConfirm: return "checkmark.seal"
        }
    }
    var color: Color {
        switch self {
        case .packingUpload: return .blue
        case .rsiNew, .rsiHandover: return .orange
        case .mrfNew, .mrfReturn: return .purple
        case .locationUpdate: return .teal
        case .pkgConfirm: return .green
        }
    }
    /// 1 = Packing List, 2 = RSI, 3 = MRF, 4 = Kiện (vị trí/xác nhận) (khớp bộ lọc trong màn hình)
    var group: Int {
        switch self {
        case .packingUpload: return 1
        case .rsiNew, .rsiHandover: return 2
        case .mrfNew, .mrfReturn: return 3
        case .locationUpdate, .pkgConfirm: return 4
        }
    }
}

struct DesmActivity: Identifiable {
    let id: String
    let kind: DesmActivityKind
    let title: String
    let detail: String
    let date: String
    var isNew = false
}

extension BrowserModel {
    @MainActor
    func fetchActivityAsync(days: Int) async -> (items: [DesmActivity], errors: [String]) {
        let P: String
        do { P = Self.enc(try await desmProjectNo()) } catch { return ([], [error.localizedDescription]) }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
        let now = Date()
        let today = f.string(from: now)
        let cutoff = f.string(from: Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now)
        func num(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }
        func join(_ parts: [String]) -> String { parts.filter { !$0.isEmpty }.joined(separator: " · ") }

        var out: [DesmActivity] = []
        var errs: [String] = []

        // Packing List đã tải lên
        let (plList, plErr): ([PackingUploadRecord]?, String) = await withCheckedContinuation { cont in
            self.fetchPackingHistory(days: days) { list, e in cont.resume(returning: (list, e)) }
        }
        if let list = plList {
            for r in list {
                out.append(DesmActivity(id: "pl-\(r.id)", kind: .packingUpload,
                                        title: r.invoice.isEmpty ? "(không có Invoice)" : r.invoice,
                                        detail: join([r.file, r.result, r.user]), date: r.created))
            }
        } else { errs.append("Packing List: \(plErr)") }

        // RSI mới tạo (theo ngày yêu cầu)
        do {
            let body = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&ATTRIBUTE10=&MATERIAL_CODE=&START_REQUEST_DATE=\(Self.enc(cutoff))&END_REQUEST_DATE=\(Self.enc(today))&BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&PACKAGE_NO=&ITEM_DESC=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
            let rows = try await desmQueryAsync("/getDesmRsiViewList.do", body: body)
            for g in Self.groups(rows, doc: "RSI_NO", name: "RSI_NAME", date: "REQUEST_DATE", status: "STATUS", extra: "SUBCONTRACTOR",
                                 qty: "REQ_QTY", done: "HANDOVER_QTY", bal: "BALANCE_QTY", close: nil) where g.date >= cutoff {
                out.append(DesmActivity(id: "rsi-new-\(g.id)", kind: .rsiNew, title: g.id,
                                        detail: join([g.name, g.extra, "\(g.lines) dòng", "SL \(num(g.qty))", g.status]), date: g.date))
            }
        } catch { errs.append("RSI: \(error.localizedDescription)") }

        // RSI đã bàn giao
        do {
            let body = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&START_HANDOVER_DATE=\(Self.enc(cutoff))&END_HANDOVER_DATE=\(Self.enc(today))&PACKAGE_NO=&SUBCONTRACTOR=&RSI_NO=&MATERIAL_CODE=&ATTRIBUTE10=&RSI_NAME=&TYPE=&CATEGORY=&SUB_CATEGORY=&COMMENTS=&PACKING_LIST_NO=&PENDING=&RECEIVER_REMARK=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
            let rows = try await desmQueryAsync("/getDesmRsiOutGoingList.do", body: body)
            for g in Self.groups(rows, doc: "RSI_NO", name: "RSI_NAME", date: "REQUEST_DATE", status: "", extra: "SUBCONTRACTOR",
                                 qty: "REQ_QTY", done: "HANDOVER_QTY", bal: nil, close: "HANDOVER_DATE") where g.closeDate >= cutoff {
                out.append(DesmActivity(id: "rsi-out-\(g.id)-\(g.closeDate)", kind: .rsiHandover, title: g.id,
                                        detail: join([g.name, g.extra, "Bàn giao SL \(num(g.done))"]), date: g.closeDate))
            }
        } catch { errs.append("RSI bàn giao: \(error.localizedDescription)") }

        // MRF mới tạo (máy chủ không lọc ngày ở truy vấn này nên lọc phía máy khách)
        do {
            let body = "PROJECT_NO=\(P)&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&MATERIAL_CODE=&RSI_START_REQUEST_DATE=&RSI_END_REQUEST_DATE=&ZIM_ATTRIBUTE10=&RSI_BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&MRF_NO=&MRF_NAME=&PACKAGE_NO=&ITEM_DESC=&RETURN_TYPE=&MRF_BALANCE_QTY="
            let rows = try await desmQueryAsync("/getMrfSummaryList.do", body: body)
            for g in Self.groups(rows, doc: "MRF_NO", name: "MRF_NAME", date: "RETURN_REQ_DATE", status: "STATUS", extra: "RETURN_TYPE",
                                 qty: "MRF_REQ_RETURN_QTY", done: "MRF_RETURN_QTY", bal: "MRF_BALANCE_QTY", close: nil) where g.date >= cutoff {
                out.append(DesmActivity(id: "mrf-new-\(g.id)", kind: .mrfNew, title: g.id,
                                        detail: join([g.name, g.extra, "\(g.lines) dòng", "SL \(num(g.qty))", g.status]), date: g.date))
            }
        } catch { errs.append("MRF: \(error.localizedDescription)") }

        // MRF đã trả
        do {
            let body = "PROJECT_NO=\(P)&START_HANDOVER_DATE=\(Self.enc(cutoff))&END_HANDOVER_DATE=\(Self.enc(today))&PACKAGE_NO=&SUBCONTRACTOR=&MRF_NO=&MATERIAL_CODE=&ATTRIBUTE10=&MRF_NAME=&TYPE=&CATEGORY="
            let rows = try await desmQueryAsync("/getDesmMrfReturnList.do", body: body)
            for g in Self.groups(rows, doc: "MRF_NO", name: "MRF_NAME", date: "RETURN_REQ_DATE", status: "", extra: "RETURN_TYPE",
                                 qty: "REQ_RETURN_QTY", done: "RETURN_QTY", bal: nil, close: "RETURN_DATE") where g.closeDate >= cutoff {
                out.append(DesmActivity(id: "mrf-ret-\(g.id)-\(g.closeDate)", kind: .mrfReturn, title: g.id,
                                        detail: join([g.name, g.extra, "Đã trả SL \(num(g.done))"]), date: g.closeDate))
            }
        } catch { errs.append("MRF đã trả: \(error.localizedDescription)") }

        // Đổi vị trí / xác nhận kiện: lấy từ danh sách Package (LOC_UPDATE_DATE, LOC_UPDATED_BY, CONFIRM_DATE, CONFIRMED_BY).
        // Chỉ có LẦN CẬP NHẬT CUỐI của mỗi kiện (không phải toàn bộ lịch sử Edit Log). Máy chủ không lọc theo ngày này nên lọc phía máy khách.
        do {
            let body = "PROJECT_NO=\(P)&PACKAGE_LIST_NO=&PACKAGE_NO=&DESCRIPTION=&IS_CONFIRM_MATERIAL=&RECEIPTED=&ATTRIBUTE10=&REMARK=&VENDOR=&LOCATION=&START_RECEIPT_DATE=&END_RECEIPT_DATE=&MRR_VISUAL_CHECK=All&MRR_RECEIVED=&START_MRR_RECEIVED_DATE=&END_MRR_RECEIVED_DATE=&CUSTOMS_YN=&MIR_CATEGORY=&PACKAGE_STATUS="
            let rows = try await desmQueryAsync("/getIdsmOsSummaryList.do", body: body)
            for r in rows {
                let pkg = Self.fstr(r, "PACKAGE_NO"); if pkg.isEmpty { continue }
                let ld = Self.fstr(r, "LOC_UPDATE_DATE")
                if ld >= cutoff {
                    let loc = Self.fstr(r, "STORAGE_LOCATION")
                    out.append(DesmActivity(id: "loc-\(pkg)-\(ld)-\(loc)", kind: .locationUpdate, title: pkg,
                                            detail: join([loc.isEmpty ? "" : "→ \(loc)", Self.fstr(r, "LOC_UPDATED_BY"), Self.fstr(r, "DESCRIPTION")]), date: ld))
                }
                let cd = Self.fstr(r, "CONFIRM_DATE")
                if cd >= cutoff {
                    out.append(DesmActivity(id: "cfm-\(pkg)-\(cd)", kind: .pkgConfirm, title: pkg,
                                            detail: join([Self.fstr(r, "CONFIRMED_BY"), Self.fstr(r, "DESCRIPTION")]), date: cd))
                }
            }
        } catch { errs.append("Kiện: \(error.localizedDescription)") }

        out.sort { $0.date > $1.date }   // "yyyy/MM/dd[ HH:mm]" so sánh chuỗi được
        return (out, errs)
    }

    func fetchActivity(days: Int, done: @escaping ([DesmActivity], [String]) -> Void) {
        Task { @MainActor in
            let r = await self.fetchActivityAsync(days: days)
            done(r.items, r.errors)
        }
    }
}

struct DesmActivitySheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    static let seenKey = "desmActivitySeen"
    @State private var days = 3
    @State private var filter = 0
    @State private var items: [DesmActivity] = []
    @State private var errors: [String] = []
    @State private var loading = false
    @State private var seenAtOpen: Set<String>? = nil   // nil = lần đầu: chưa có mốc nên không gắn "MỚI"
    @State private var started = false

    var shown: [DesmActivity] { filter == 0 ? items : items.filter { $0.kind.group == filter } }
    var newCount: Int { items.filter { $0.isNew }.count }

    func load() {
        loading = true
        if !started {
            started = true
            if let a = UserDefaults.standard.stringArray(forKey: Self.seenKey) { seenAtOpen = Set(a) }
        }
        model.fetchActivity(days: days) { list, errs in
            loading = false
            errors = errs
            let seen = seenAtOpen
            items = list.map { var a = $0; a.isNew = seen.map { !$0.contains(a.id) } ?? false; return a }
            // Ghi nhớ đã thấy (giữ tối đa 600 mã gần nhất)
            var all = Array(seen ?? [])
            for a in list where !all.contains(a.id) { all.append(a.id) }
            if all.count > 600 { all = Array(all.suffix(600)) }
            UserDefaults.standard.set(all, forKey: Self.seenKey)
        }
    }

    func row(_ a: DesmActivity) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: a.kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(a.kind.color)
                .frame(width: 34, height: 34)
                .background(a.kind.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(a.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    if a.isNew {
                        Text("MỚI").font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(.white).background(Color.red, in: Capsule())
                    }
                    Spacer(minLength: 4)
                    Text(a.kind.label).font(.system(size: 11, weight: .bold)).foregroundStyle(a.kind.color)
                }
                if !a.detail.isEmpty {
                    Text(a.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(a.date).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Khoảng ngày", selection: $days) {
                    Text("1 ngày").tag(1); Text("3 ngày").tag(3); Text("7 ngày").tag(7)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
                .onChange(of: days) { _ in load() }
                Picker("Loại", selection: $filter) {
                    Text("Tất cả").tag(0); Text("Packing").tag(1); Text("RSI").tag(2); Text("MRF").tag(3); Text("Kiện").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.bottom, 8)

                if newCount > 0 {
                    Text("\(newCount) hoạt động mới từ lần xem trước")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                        .padding(.bottom, 6)
                }
                if !errors.isEmpty {
                    Text("Một số nguồn không tải được: " + errors.joined(separator: " | "))
                        .font(.system(size: 11)).foregroundStyle(.orange)
                        .padding(.horizontal, 16).padding(.bottom, 6)
                }

                if loading && items.isEmpty {
                    Spacer(); ProgressView("Đang tải…"); Spacer()
                } else if shown.isEmpty {
                    Spacer()
                    Text("Không có hoạt động nào trong \(days) ngày gần đây.").font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    List(shown) { a in row(a) }.listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Hoạt động")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
        }
        .onAppear { if items.isEmpty && !loading { load() } }
    }
}
