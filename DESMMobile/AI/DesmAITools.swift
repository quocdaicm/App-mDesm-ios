// DesmAITools.swift — bộ công cụ CHỈ ĐỌC để AI riêng tự tra dữ liệu DESM (kiện, hạng mục chi tiết, RSI, MRF, WIP, tàu, thông báo…)
// kể cả những màn chưa mở. Dùng phiên đăng nhập DESM sẵn có (desmQueryAsync). KHÔNG có công cụ ghi/sửa/xoá.

import Foundation

struct AITool {
    let name: String
    let description: String
    let parameters: [String: Any]   // JSON Schema (object)
}

struct DesmEndpoint {
    let path: String
    let keys: [String]
    let about: String
}

enum DesmAITools {
    /// Các API đọc đã biết (lấy từ các màn native của app). Khoá để trống = không lọc.
    static let catalog: [DesmEndpoint] = [
        DesmEndpoint(path: "/getDesmRsiViewList.do", keys: ["PAGE_NUM", "PAGE_CNT", "PROJECT_NO", "RSI_NO", "RSI_NAME", "SUBCONTRACTOR", "ATTRIBUTE10", "MATERIAL_CODE", "START_REQUEST_DATE", "END_REQUEST_DATE", "BALANCE_QTY", "TYPE", "CATEGORY", "SUB_CATEGORY", "PACKING_LIST_NO", "PACKAGE_NO", "ITEM_DESC", "MASTER_SHOP_UNIT", "MASTER_SHOP_BLDG", "SHOP_UNIT", "SHOP_BLDG"], about: "RSI (phiếu yêu cầu xuất hàng) đang mở/theo ngày yêu cầu. Lọc: RSI_NO, PACKAGE_NO, MATERIAL_CODE, START_REQUEST_DATE/END_REQUEST_DATE (yyyy/MM/dd)…"),
        DesmEndpoint(path: "/getDesmRsiOutGoingList.do", keys: ["PAGE_NUM", "PAGE_CNT", "PROJECT_NO", "START_HANDOVER_DATE", "END_HANDOVER_DATE", "PACKAGE_NO", "SUBCONTRACTOR", "RSI_NO", "MATERIAL_CODE", "ATTRIBUTE10", "RSI_NAME", "TYPE", "CATEGORY", "SUB_CATEGORY", "COMMENTS", "PACKING_LIST_NO", "PENDING", "RECEIVER_REMARK", "MASTER_SHOP_UNIT", "MASTER_SHOP_BLDG", "SHOP_UNIT", "SHOP_BLDG"], about: "RSI đã bàn giao (xuất hàng). Lọc: RSI_NO, PACKAGE_NO, START_HANDOVER_DATE/END_HANDOVER_DATE…"),
        DesmEndpoint(path: "/getMrfSummaryList.do", keys: ["PROJECT_NO", "RSI_NO", "RSI_NAME", "SUBCONTRACTOR", "MATERIAL_CODE", "RSI_START_REQUEST_DATE", "RSI_END_REQUEST_DATE", "ZIM_ATTRIBUTE10", "RSI_BALANCE_QTY", "TYPE", "CATEGORY", "SUB_CATEGORY", "PACKING_LIST_NO", "MRF_NO", "MRF_NAME", "PACKAGE_NO", "ITEM_DESC", "RETURN_TYPE", "MRF_BALANCE_QTY"], about: "MRF (phiếu trả hàng) tổng hợp. Lọc: MRF_NO, RSI_NO, PACKAGE_NO, MATERIAL_CODE…"),
        DesmEndpoint(path: "/getDesmMrfReturnList.do", keys: ["PROJECT_NO", "START_HANDOVER_DATE", "END_HANDOVER_DATE", "PACKAGE_NO", "SUBCONTRACTOR", "MRF_NO", "MATERIAL_CODE", "ATTRIBUTE10", "MRF_NAME", "TYPE", "CATEGORY"], about: "MRF đã trả. Lọc: MRF_NO, PACKAGE_NO, START_HANDOVER_DATE/END_HANDOVER_DATE…"),
        DesmEndpoint(path: "/getIdsmOsSummaryList.do", keys: ["PROJECT_NO", "PACKAGE_LIST_NO", "PACKAGE_NO", "DESCRIPTION", "IS_CONFIRM_MATERIAL", "RECEIPTED", "ATTRIBUTE10", "REMARK", "VENDOR", "LOCATION", "START_RECEIPT_DATE", "END_RECEIPT_DATE", "MRR_VISUAL_CHECK", "MRR_RECEIVED", "START_MRR_RECEIVED_DATE", "END_MRR_RECEIVED_DATE", "CUSTOMS_YN", "MIR_CATEGORY", "PACKAGE_STATUS"], about: "Danh sách PACKAGE (kiện hàng) kèm vị trí, MRR. Lọc: PACKAGE_NO, PACKAGE_LIST_NO (packing list), DESCRIPTION, LOCATION, VENDOR…"),
        DesmEndpoint(path: "/getIdsmOsDetailList.do", keys: ["PAGE_NUM", "PAGE_CNT", "PROJECT_NO", "PACKAGE_LIST_NO", "PACKAGE_NO", "DESCRIPTION", "DRAWING_NO", "TAG_NO", "QTY_TYPE", "QTY", "KEY1", "VALUE1", "LOCATION", "SEQUENCE", "VENDOR", "ATTRIBUTE10", "TYPE", "CATEGORY", "SUB_CATEGORY", "COMMENTS"], about: "HẠNG MỤC CHI TIẾT (Detail Item) của kiện. Lọc: PACKAGE_NO, PACKAGE_LIST_NO, DESCRIPTION, DRAWING_NO, TAG_NO, LOCATION, KEY1=material|reamrks|size + VALUE1=<giá trị> để tra theo Material Code/ghi chú/kích thước."),
        DesmEndpoint(path: "/getDesmPlDetailEditLogList.do", keys: ["PROJECT_NO", "TRK_ITEM_NAME", "MATERIAL_CODE"], about: "Nhật ký chỉnh sửa (Edit Log) của một hạng mục. Cần TRK_ITEM_NAME và MATERIAL_CODE (lấy từ kết quả hạng mục chi tiết)."),
        DesmEndpoint(path: "/getDesmOutGoingCreationList.do", keys: ["PROJECT_NO", "PACKING_LIST_NO", "PACKAGE_NO", "RSI_NO", "MATERIAL_CODE", "REQUEST_START_DATE", "ATTRIBUTE10", "REQUEST_END_DATE", "DESCRIPTION", "DRAWING_NO", "TAG_NO", "RSI_NAME", "TYPE", "CATEGORY", "SUBCON", "PENDING", "MASTER_SHOP_UNIT", "MASTER_SHOP_BLDG", "SHOP_UNIT", "SHOP_BLDG"], about: "Danh sách hạng mục có thể tạo phiếu xuất (outgoing). Lọc: PACKAGE_NO, RSI_NO, MATERIAL_CODE…"),
        DesmEndpoint(path: "/getDesmReturnCreationList.do", keys: ["PROJECT_NO", "PACKAGE_NO", "MRF_NO", "MATERIAL_CODE", "REQUEST_START_DATE", "ATTRIBUTE10", "REQUEST_END_DATE", "TYPE", "CATEGORY"], about: "Danh sách hạng mục có thể tạo phiếu trả (MRF return). Lọc: PACKAGE_NO, MRF_NO, MATERIAL_CODE…"),
        DesmEndpoint(path: "/material/getPlWipCreationList.do", keys: ["PROJECT_NO", "PACKING_LIST_NO", "PACKAGE_NO", "RSI_NO", "RSI_NAME", "SUBCON", "MATERIAL_CODE", "ATTRIBUTE10", "DESCRIPTION", "DRAWING_NO", "TAG_NO", "TYPE", "CATEGORY", "SUB_CATEGORY", "SHOP_UNIT", "SHOP_BLDG"], about: "WIP Completion (hoàn thành gia công). Lọc: PACKAGE_NO, RSI_NO, MATERIAL_CODE…"),
        DesmEndpoint(path: "/vessel/getVesselFinderList.do", keys: ["PROJECT_NO"], about: "Danh sách tàu/chuyến hàng của dự án."),
        DesmEndpoint(path: "/selectDesmShippingStatusList.do", keys: ["PROJECT_NO", "VOYAGE_NO", "INVOICE_NO", "SHIPPING_STATUS", "DATA_CREATED_YN"], about: "Tình trạng vận chuyển theo chuyến/invoice."),
        DesmEndpoint(path: "/dashboard/getHomeSummary.do", keys: ["PROJECT_NO", "DAY_TERM"], about: "Tóm tắt trang chủ: packing list/invoice/shipment gần đây (DAY_TERM = số ngày)."),
        DesmEndpoint(path: "/getNotice.do", keys: ["jobCode"], about: "Danh sách thông báo DESM (jobCode để trống) hoặc một thông báo theo jobCode."),
        DesmEndpoint(path: "/getNoticeContents.do", keys: ["jobCode"], about: "Nội dung chi tiết một thông báo (jobCode = mã thông báo)."),
        DesmEndpoint(path: "/getRealTimeNotice.do", keys: [], about: "Thông báo thời gian thực."),
    ]

    static func defs() -> [AITool] {
        func obj(_ props: [String: Any], required: [String] = []) -> [String: Any] {
            var o: [String: Any] = ["type": "object", "properties": props]
            if !required.isEmpty { o["required"] = required }
            return o
        }
        return [
            AITool(name: "desm_list_endpoints",
                   description: "Liệt kê các API đọc của DESM mà desm_query dùng được (đường dẫn, mô tả, tên tham số lọc). Gọi trước khi tra nếu chưa chắc.",
                   parameters: obj([:])),
            AITool(name: "desm_query",
                   description: "Tra dữ liệu DESM (CHỈ ĐỌC) bằng một API trong danh mục. Dùng cho kiện hàng (/getIdsmOsSummaryList.do), hạng mục chi tiết của kiện (/getIdsmOsDetailList.do), RSI, MRF, WIP, tàu, thông báo… PROJECT_NO tự điền nếu bỏ trống. Kết quả có thể bị cắt: hãy lọc hẹp bằng params (PACKAGE_NO, MATERIAL_CODE, RSI_NO, DESCRIPTION, LOCATION, ngày yyyy/MM/dd…).",
                   parameters: obj([
                       "endpoint": ["type": "string", "description": "Đường dẫn, ví dụ /getIdsmOsDetailList.do"],
                       "params_json": ["type": "string", "description": "Chuỗi JSON object các tham số lọc, ví dụ {\"PACKAGE_NO\":\"ABC123\"}. Để {} nếu không lọc."],
                       "max_rows": ["type": "integer", "description": "Số dòng tối đa trả về (mặc định 100, tối đa 500)."]
                   ], required: ["endpoint"])),
            AITool(name: "desm_recorded_endpoints",
                   description: "Liệt kê các API .do mà app đã ghi lại khi người dùng dùng web (cần bật Ghi API trong Cài đặt nâng cao), kèm mẫu tham số, để tra thêm các mục sâu ngoài danh mục.",
                   parameters: obj([:])),
            AITool(name: "desm_read_open_page",
                   description: "Đọc nội dung trang DESM đang mở trên màn hình (mọi khung, các dòng lưới đã tải, ô lọc).",
                   parameters: obj(["limit": ["type": "integer", "description": "Số ký tự tối đa (mặc định 30000)."]]))
        ]
    }

    // MARK: Thực thi
    @MainActor
    static func run(_ name: String, _ args: [String: Any], model: BrowserModel) async -> String {
        switch name {
        case "desm_list_endpoints":
            return catalog.map { "\($0.path) — \($0.about) | tham số: \($0.keys.joined(separator: ", "))" }.joined(separator: "\n")
        case "desm_recorded_endpoints":
            return recorded()
        case "desm_read_open_page":
            let n = min(max((args["limit"] as? Int) ?? Int((args["limit"] as? String) ?? "") ?? 30000, 2000), 120000)
            let t = await model.fetchScreenTextForAI(limit: n)
            return t.isEmpty ? "Không đọc được trang đang mở (có thể chưa mở DESM hoặc đang ở trang đăng nhập)." : t
        case "desm_query":
            return await query(args, model: model)
        default:
            return "Công cụ không tồn tại: \(name)"
        }
    }

    private static let readPattern = #"^/([A-Za-z0-9_]+/)*(get|select|search|list|find|view|query)[A-Za-z0-9_]*\.do$"#
    private static let writeWords = ["save", "delete", "remove", "update", "insert", "approve", "reject", "submit",
                                     "upload", "reset", "cancel", "execute", "modify", "send", "write"]

    private static func isReadOnly(_ path: String) -> Bool {
        guard path.range(of: readPattern, options: .regularExpression) != nil else { return false }
        let last = (path as NSString).lastPathComponent.lowercased()
        return !writeWords.contains { last.contains($0) }
    }

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
    }

    private static func parseParams(_ args: [String: Any]) -> [String: String] {
        var raw: [String: Any] = [:]
        if let d = args["params"] as? [String: Any] { raw = d }
        else if let s = args["params_json"] as? String, let d = s.data(using: .utf8),
                let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { raw = o }
        var out: [String: String] = [:]
        for (k, v) in raw { out[k] = (v is NSNull) ? "" : "\(v)" }
        return out
    }

    @MainActor
    private static func query(_ args: [String: Any], model: BrowserModel) async -> String {
        guard var path = args["endpoint"] as? String else { return "Thiếu tham số endpoint." }
        path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.hasPrefix("/") { path = "/" + path }
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        let known = catalog.first { $0.path == path }
        guard known != nil || isReadOnly(path) else {
            return "Từ chối: chỉ gọi được API đọc (tên bắt đầu get/select/search/list/find/view/query và không chứa lệnh ghi). Dùng desm_list_endpoints để xem danh mục."
        }
        let maxRows = min(max((args["max_rows"] as? Int) ?? Int("\(args["max_rows"] ?? "")") ?? 100, 1), 500)
        var vals = parseParams(args)
        var order: [String] = known?.keys ?? []
        for k in vals.keys.sorted() where !order.contains(k) { order.append(k) }
        if order.contains("PAGE_NUM"), vals["PAGE_NUM"] == nil { vals["PAGE_NUM"] = "1" }
        if order.contains("PAGE_CNT"), vals["PAGE_CNT"] == nil { vals["PAGE_CNT"] = "1000" }
        if order.contains("PROJECT_NO"), (vals["PROJECT_NO"] ?? "").isEmpty {
            do { vals["PROJECT_NO"] = try await model.desmProjectNo() }
            catch { return "Lỗi: \(error.localizedDescription)" }
        }
        let body = order.map { "\($0)=\(enc(vals[$0] ?? ""))" }.joined(separator: "&")
        do {
            let rows = try await model.desmQueryAsync(path, body: body)
            return format(rows, maxRows: maxRows, charBudget: 24000, path: path)
        } catch {
            return "Lỗi khi gọi \(path): \(error.localizedDescription)"
        }
    }

    private static func clean(_ v: Any) -> String? {
        if v is NSNull { return nil }
        var s = "\(v)"
        if s.contains("<") { s = s.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression) }
        s = s.replacingOccurrences(of: "&nbsp;", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        return s.count > 100 ? String(s.prefix(100)) + "…" : s
    }

    private static func format(_ rows: [[String: Any]], maxRows: Int, charBudget: Int, path: String) -> String {
        var lines: [String] = []
        var used = 0
        for r in rows.prefix(maxRows) {
            var o: [String: String] = [:]
            for (k, v) in r { if let c = clean(v) { o[k] = c } }
            guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]),
                  let s = String(data: d, encoding: .utf8) else { continue }
            if used + s.count > charBudget { break }
            used += s.count + 1
            lines.append(s)
        }
        var head = "\(path): tổng \(rows.count) dòng, trả về \(lines.count)."
        if lines.count < rows.count {
            head += " ĐÃ CẮT — hãy lọc hẹp hơn (ví dụ PACKAGE_NO, MATERIAL_CODE, ngày) hoặc tăng max_rows."
        }
        if rows.isEmpty { head += " Không có dòng nào khớp bộ lọc." }
        return ([head] + lines).joined(separator: "\n")
    }

    private static func recorded() -> String {
        var seen: [String: (method: String, body: String, n: Int)] = [:]
        for e in NetLogStore.entries() {
            let url = NetLogStore.str(e, "url")
            guard let u = URL(string: url), u.path.hasSuffix(".do") else { continue }
            let p = u.path
            let body = NetLogStore.str(e, "body")
            if var x = seen[p] { x.n += 1; seen[p] = x }
            else { seen[p] = (NetLogStore.str(e, "method"), NetLogStore.cut(body, 300), 1) }
        }
        if seen.isEmpty { return "Chưa có API nào được ghi. Người dùng cần bật Cài đặt > Nâng cao > Ghi lại các request API rồi duyệt các màn trên web." }
        return seen.keys.sorted().prefix(120).map { p in
            let x = seen[p]!
            return "\(p) [\(x.method), \(x.n) lần]\(isReadOnly(p) ? "" : " (KHÔNG gọi được: có vẻ là API ghi)") mẫu body: \(x.body)"
        }.joined(separator: "\n")
    }
}
