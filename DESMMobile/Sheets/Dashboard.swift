// Dashboard.swift — màn "Tổng quan" (Thêm > Tổng quan): số liệu nhanh gom từ các API DESM đã dùng ở nơi khác.
// Kiện hàng: /getIdsmOsSummaryList.do (chưa có vị trí, chưa xác nhận, cập nhật hôm nay, theo Packing List).
// Phiếu: fetchDocsAsync (RSI/MRF chưa đóng) + fetchActivityAsync 1 ngày (RSI mới, MRF mới, MRF đã trả).
// Tàu sắp đến: fetchVesselsAsync (arrivingSoon). Thông báo: fetchNoticesAsync (so với NOTICE_ID đã xem).
// Mỗi phần tải riêng, phần nào lỗi chỉ báo lỗi ở phần đó. CHƯA kiểm chứng trên máy thật.

import SwiftUI

struct DesmDashboardSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    enum Load<T> { case idle, loading, failed(String), done(T) }
    struct ListRow: Identifiable { let id: String; var total = 0; var noLoc = 0; var unconfirmed = 0 }
    struct PkgSummary { var total = 0, noLoc = 0, unconfirmed = 0, locToday = 0, confirmToday = 0; var lists: [ListRow] = [] }
    struct DocSummary { var rsiOpen = 0, mrfOpen = 0, rsiNew = 0, mrfNew = 0, mrfReturned = 0; var partial: [String] = [] }
    struct NoticeSummary { var fresh = 0, total = 0, latest = "" }

    @State private var pkg: Load<PkgSummary> = .idle
    @State private var docs: Load<DocSummary> = .idle
    @State private var ships: Load<[DesmVessel]> = .idle
    @State private var notices: Load<NoticeSummary> = .idle
    @State private var updated: Date? = nil
    @State private var started = false

    // MARK: Tải dữ liệu (mỗi phần độc lập)

    @MainActor func loadPkg() async {
        pkg = .loading
        do {
            let P = BrowserModel.enc(try await model.desmProjectNo())
            let body = "PROJECT_NO=\(P)&PACKAGE_LIST_NO=&PACKAGE_NO=&DESCRIPTION=&IS_CONFIRM_MATERIAL=&RECEIPTED=&ATTRIBUTE10=&REMARK=&VENDOR=&LOCATION=&START_RECEIPT_DATE=&END_RECEIPT_DATE=&MRR_VISUAL_CHECK=All&MRR_RECEIVED=&START_MRR_RECEIVED_DATE=&END_MRR_RECEIVED_DATE=&CUSTOMS_YN=&MIR_CATEGORY=&PACKAGE_STATUS="
            let rows = try await model.desmQueryAsync("/getIdsmOsSummaryList.do", body: body)
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
            let today = f.string(from: Date())
            var s = PkgSummary(); var by: [String: ListRow] = [:]
            for r in rows {
                if BrowserModel.fstr(r, "PACKAGE_NO").isEmpty { continue }
                var list = BrowserModel.fstr(r, "PACKAGE_LIST_NO"); if list.isEmpty { list = "(không rõ)" }
                let noLoc = BrowserModel.fstr(r, "STORAGE_LOCATION").isEmpty
                let cd = BrowserModel.fstr(r, "CONFIRM_DATE"), ld = BrowserModel.fstr(r, "LOC_UPDATE_DATE")
                s.total += 1
                if noLoc { s.noLoc += 1 }
                if cd.isEmpty { s.unconfirmed += 1 }
                if ld.hasPrefix(today) { s.locToday += 1 }
                if cd.hasPrefix(today) { s.confirmToday += 1 }
                var row = by[list] ?? ListRow(id: list)
                row.total += 1; if noLoc { row.noLoc += 1 }; if cd.isEmpty { row.unconfirmed += 1 }
                by[list] = row
            }
            s.lists = by.values.sorted { ($0.noLoc, $0.total) > ($1.noLoc, $1.total) }
            pkg = .done(s)
        } catch { pkg = .failed(error.localizedDescription) }
    }

    @MainActor func loadDocs() async {
        docs = .loading
        var s = DocSummary()
        do { s.rsiOpen = try await model.fetchDocsAsync(kind: .rsi, days: 7).open.count } catch { s.partial.append("RSI: " + error.localizedDescription) }
        do { s.mrfOpen = try await model.fetchDocsAsync(kind: .mrf, days: 7).open.count } catch { s.partial.append("MRF: " + error.localizedDescription) }
        let a = await model.fetchActivityAsync(days: 1, only: [.rsiNew, .mrfNew, .mrfReturn])
        s.rsiNew = a.items.filter { $0.kind == .rsiNew }.count
        s.mrfNew = a.items.filter { $0.kind == .mrfNew }.count
        s.mrfReturned = a.items.filter { $0.kind == .mrfReturn }.count
        s.partial += a.errors
        if s.partial.count >= 3 { docs = .failed(s.partial.joined(separator: " | ")) } else { docs = .done(s) }
    }

    @MainActor func loadShips() async {
        ships = .loading
        do { ships = .done(try await model.fetchVesselsAsync().filter { $0.arrivingSoon }.sorted { ($0.tEnd ?? .distantFuture) < ($1.tEnd ?? .distantFuture) }) }
        catch { ships = .failed(error.localizedDescription) }
    }

    @MainActor func loadNotices() async {
        notices = .loading
        do {
            let r = try await model.fetchNoticesAsync()
            let seen = DesmNoticeSeen.load()
            let fresh = seen == nil ? 0 : r.list.filter { !(seen!.contains($0.id)) }.count
            notices = .done(NoticeSummary(fresh: fresh, total: r.list.count, latest: r.list.first?.title ?? ""))
        } catch { notices = .failed(error.localizedDescription) }
    }

    @MainActor func reload() async {
        updated = Date()
        async let a: Void = loadPkg()
        async let b: Void = loadDocs()
        async let c: Void = loadShips()
        async let d: Void = loadNotices()
        _ = await (a, b, c, d)
        updated = Date()
    }

    // MARK: Giao diện

    func num(_ title: String, _ n: Int, _ color: Color = .primary) -> some View {
        HStack { Text(title); Spacer(); Text("\(n)").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundColor(color) }
    }

    @ViewBuilder func state<T, V: View>(_ l: Load<T>, @ViewBuilder _ content: (T) -> V) -> some View {
        switch l {
        case .idle, .loading: HStack { ProgressView(); Text("Đang tải…").foregroundColor(.secondary) }
        case .failed(let m): Text("Không tải được: " + m).font(.footnote).foregroundColor(.orange)
        case .done(let v): content(v)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Kiện hàng") {
                    state(pkg) { s in
                        num("Tổng số kiện", s.total)
                        num("Chưa có vị trí", s.noLoc, s.noLoc > 0 ? .red : .green)
                        num("Chưa xác nhận", s.unconfirmed, s.unconfirmed > 0 ? .orange : .green)
                        num("Cập nhật vị trí hôm nay", s.locToday)
                        num("Xác nhận hôm nay", s.confirmToday)
                        if s.total > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: Double(s.total - s.noLoc), total: Double(s.total))
                                Text("Đã có vị trí: \(s.total - s.noLoc)/\(s.total) (\(Int((Double(s.total - s.noLoc) / Double(s.total) * 100).rounded()))%)")
                                    .font(.footnote).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                if case .done(let s) = pkg, !s.lists.isEmpty {
                    Section("Theo Packing List (chưa có vị trí nhiều nhất)") {
                        ForEach(s.lists.prefix(8)) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(r.id).font(.system(size: 14, weight: .semibold)); Spacer()
                                    Text("\(r.noLoc) chưa vị trí / \(r.total)").font(.footnote).foregroundColor(r.noLoc > 0 ? .red : .secondary) }
                                ProgressView(value: Double(r.total - r.noLoc), total: Double(max(r.total, 1)))
                            }
                        }
                    }
                }
                Section("Phiếu RSI / MRF") {
                    state(docs) { d in
                        num("RSI chưa đóng", d.rsiOpen, d.rsiOpen > 0 ? .orange : .green)
                        num("MRF trả hàng chưa đóng", d.mrfOpen, d.mrfOpen > 0 ? .orange : .green)
                        num("RSI mới (24 giờ)", d.rsiNew)
                        num("MRF mới (24 giờ)", d.mrfNew)
                        num("MRF đã trả (24 giờ)", d.mrfReturned)
                        if !d.partial.isEmpty { Text("Một số nguồn không tải được: " + d.partial.joined(separator: " | ")).font(.footnote).foregroundColor(.orange) }
                    }
                }
                Section("Tàu sắp đến (7 ngày)") {
                    state(ships) { v in
                        if v.isEmpty { Text("Không có tàu nào sắp đến.").foregroundColor(.secondary) }
                        ForEach(v.prefix(6)) { x in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(x.vessel.isEmpty ? x.invoice : x.vessel).font(.system(size: 14, weight: .semibold))
                                Text([x.invoice, x.pod, x.eta.isEmpty ? "" : "ETA " + x.eta].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.footnote).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Section("Thông báo DESM") {
                    state(notices) { n in
                        num("Thông báo mới chưa mở", n.fresh, n.fresh > 0 ? .red : .primary)
                        if !n.latest.isEmpty { Text("Mới nhất: " + n.latest).font(.footnote).foregroundColor(.secondary).lineLimit(2) }
                    }
                }
                if let u = updated {
                    Section { Text("Cập nhật lúc " + u.formatted(date: .omitted, time: .shortened) + " · kéo xuống để làm mới").font(.footnote).foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Tổng quan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") } }
            }
            .refreshable { await reload() }
            .task { if !started { started = true; await reload() } }
        }
    }
}
