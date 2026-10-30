// DesmAITools.swift — công cụ CHỈ ĐỌC cho AI riêng: danh mục API DESM, truy vấn có tham số, đọc màn đang mở.
// An toàn: chỉ cho gọi các endpoint "get/select" nằm trong danh mục dưới đây (không có save/delete/update). Chưa build/chưa thử trên máy thật.

import Foundation
import WebKit

struct DesmEndpoint {
    let path: String
    let desc: String
    let keys: [String]
    var defaults: [String: String] = [:]
}

enum DesmAITools {
    // MARK: Danh mục endpoint (tham số lấy từ các màn native của app)
    static let catalog: [DesmEndpoint] = [
        DesmEndpoint(path: "/getIdsmOsSummaryList.do",
                     desc: "Danh sách KIỆN HÀNG (Package). Có STORAGE_LOCATION (vị trí kho), trạng thái, ngày nhận, người cập nhật vị trí (LOC_UPDATED_BY, LOC_UPDATE_DATE), xác nhận (CONFIRM_DATE, CONFIRMED_BY), DESCRIPTION. Lọc theo PACKAGE_NO (số kiện, vd 0009-001), PACKAGE_LIST_NO, DESCRIPTION, VENDOR, LOCATION, START_RECEIPT_DATE/END_RECEIPT_DATE (yyyy/MM/dd), PACKAGE_STATUS.",
                     keys: ["PROJECT_NO", "PACKAGE_LIST_NO", "PACKAGE_NO", "DESCRIPTION", "IS_CONFIRM_MATERIAL", "RECEIPTED", "ATTRIBUTE10", "REMARK", "VENDOR", "LOCATION", "START_RECEIPT_DATE", "END_RECEIPT_DATE", "MRR_VISUAL_CHECK", "MRR_RECEIVED", "START_MRR_RECEIVED_DATE", "END_MRR_RECEIVED_DATE", "CUSTOMS_YN", "MIR_CATEGORY", "PACKAGE_STATUS"],
                     defaults: ["MRR_VISUAL_CHECK": "All"]),
        DesmEndpoint(path: "/getIdsmOsDetailList.do",
                     desc: "HẠNG MỤC CHI TIẾT (Detail Item List) của kiện: MATERIAL_CODE, DESCRIPTION, LOCATION (vị trí từng hạng mục), UNIT, IN_QTY, REMAIN_QTY, REMARKS, TRK_ITEM_NAME... Lọc theo PACKAGE_NO, DESCRIPTION, DRAWING_NO, TAG_NO, VENDOR. Tìm theo mã vật tư: KEY1=material và VALUE1=<Material Code>.",
                     keys: ["PAGE_NUM", "PAGE_CNT", "PROJECT_NO", "PACKAGE_LIST_NO", "PACKAGE_NO", "DESCRIPTION", "DRAWING_NO", "TAG_NO", "QTY_TYPE", "QTY", "KEY1", "VALUE1", "LOCATION", "SEQUENCE", "VENDOR", "ATTRIBUTE10", "TYPE", "CATEGORY", "SUB_CATEGORY", "COMMENTS"],
                     defaults: ["PAGE_NUM": "1", "PAGE_CNT": "300", "QTY_TYPE": "rsi"]),
        DesmEndpoint(path: "/getDesmPlDetailEditLogList.do",
                     desc: "LỊCH SỬ CHỈNH SỬA (Edit Log) của MỘT hạng mục: đổi vị trí, số lượng, ghi chú... Bắt buộc TRK_ITEM_NAME và MATERIAL_CODE (lấy từ kết quả /getIdsmOsDetailList.do).",
                     keys: ["PROJECT_NO", "TRK_ITEM_NAME", "MATERIAL_CODE"]),
        DesmEndpoint(path: "/getDesmRsiViewList.do",
                     desc: "RSI (phiếu yêu cầu vật tư) theo ngày yêu cầu START_REQUEST_DATE/END_REQUEST_DATE (yyyy/MM/dd). Lọc RSI_NO, RSI_NAME, SUBCONTRACTOR, MATERIAL_CODE, PACKAGE_NO, ITEM_DESC. Có REQ_QTY, HANDOVER_QTY, BALANCE_QTY, STATUS.",
                     keys: ["PAGE_NUM", "PAGE_CNT", "PROJECT_NO", "RSI_NO", "RSI_NAME", "SUBCONTRACTOR", "ATTRIBUTE10", "MATERIAL_CODE", "START_REQUEST_DATE", "END_REQUEST_DATE", "BALANCE_QTY", "TYPE", "CATEGORY", "SUB_CATEGORY", "PACKING_LIST_NO", "PACKAGE_NO", "ITEM_DESC", "MASTER_SHOP_UNIT", "MASTER_SHOP_BLDG", "SHOP_UNIT", "SHOP_BLDG"],
                     defaults: ["PAGE_NUM": "1", "PAGE_CNT": "1000"]),
        DesmEndpoint(path: "/getDesmRsiOutGoingList.do",
                     desc: "RSI ĐÃ BÀN GIAO (Outgoing) theo ngày bàn giao START_HANDOVER_DATE/END_HANDOVER_DATE (yyyy/MM/dd). Lọc RSI_NO, PACKAGE_NO, SUBCONTRACTOR, MATERIAL_CODE, RSI_NAME.",
                     keys: ["PAGE_NUM", "PAGE_CNT", "PROJECT_NO", "START_HANDOVER_DATE", "END_HANDOVER_DATE", "PACKAGE_NO", "SUBCONTRACTOR", "RSI_NO", "MATERIAL_CODE", "ATTRIBUTE10", "RSI_NAME", "TYPE", "CATEGORY", "SUB_CATEGORY", "COMMENTS", "PACKING_LIST_NO", "PENDING", "RECEIVER_REMARK", "MASTER_SHOP_UNIT", "MASTER_SHOP_BLDG", "SHOP_UNIT", "SHOP_BLDG"],
                     defaults: ["PAGE_NUM": "1", "PAGE_CNT": "1000"]),
        DesmEndpoint(path: "/getMrfSummaryList.do",
                     desc: "MRF (phiếu trả vật tư) đã tạo. Lọc MRF_NO, MRF_NAME, RSI_NO, PACKAGE_NO, SUBCONTRACTOR, MATERIAL_CODE. Có MRF_REQ_RETURN_QTY, MRF_RETURN_QTY, MRF_BALANCE_QTY, STATUS, RETURN_REQ_DATE.",
                     keys: ["PROJECT_NO", "RSI_NO", "RSI_NAME", "SUBCONTRACTOR", "MATERIAL_CODE", "RSI_START_REQUEST_DATE", "RSI_END_REQUEST_DATE", "ZIM_ATTRIBUTE10", "RSI_BALANCE_QTY", "TYPE", "CATEGORY", "SUB_CATEGORY", "PACKING_LIST_NO", "MRF_NO", "MRF_NAME", "PACKAGE_NO", "ITEM_DESC", "RETURN_TYPE", "MRF_BALANCE_QTY"]),
        DesmEndpoint(path: "/getDesmMrfReturnList.do",
                     desc: "MRF ĐÃ TRẢ theo ngày START_HANDOVER_DATE/END_HANDOVER_DATE (yyyy/MM/dd). Lọc MRF_NO, MRF_NAME, PACKAGE_NO, SUBCONTRACTOR, MATERIAL_CODE.",
                     keys: ["PROJECT_NO", "START_HANDOVER_DATE", "END_HANDOVER_DATE", "PACKAGE_NO", "SUBCONTRACTOR", "MRF_NO", "MATERIAL_CODE", "ATTRIBUTE10", "MRF_NAME", "TYPE", "CATEGORY"]),
        DesmEndpoint(path: "/vessel/getVesselFinderList.do",
                     desc: "Danh sách TÀU / lô hàng của dự án (vị trí, tình trạng vận chuyển).",
                     keys: ["PROJECT_NO"]),
        DesmEndpoint(path: "/getNotice.do",
                     desc: "Danh sách THÔNG BÁO của DESM (để jobCode trống).",
                     keys: ["jobCode"]),
    ]

    static func catalogText(filter: String) -> String {
        let f = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = "Chỉ đọc. Gọi bằng desm_query(endpoint, params_json, max_rows). PROJECT_NO tự điền nếu bỏ trống. Ngày dạng yyyy/MM/dd. Tham số bỏ trống = không lọc.\n"
        for e in catalog {
            if !f.isEmpty && !(e.path.lowercased().contains(f) || e.desc.lowercased().contains(f)) { continue }
            let ks = e.keys.map { (k: String) -> String in
                if let d = e.defaults[k] { return k + "(mặc định " + d + ")" }
                return k
            }
            out += "\n• " + e.path + " — " + e.desc + "\n  Tham số: " + ks.joined(separator: ", ") + "\n"
        }
        return out
    }

    // MARK: Định nghĩa công cụ gửi cho AI
    static let toolDefs: [AIToolDef] = [
        AIToolDef(name: "desm_list_endpoints",
                  description: "Liệt kê các API DESM được phép tra cứu (chỉ đọc) kèm ý nghĩa và tham số lọc. Gọi trước khi dùng desm_query nếu chưa chắc endpoint/tham số.",
                  schema: ["type": "object",
                           "properties": ["filter": ["type": "string", "description": "Từ khoá lọc danh mục (tuỳ chọn), ví dụ rsi, mrf, kiện"]]]),
        AIToolDef(name: "desm_query",
                  description: "Tra dữ liệu thật từ DESM (chỉ đọc) bằng một endpoint trong danh mục. Trả về các dòng dạng JSON.",
                  schema: ["type": "object",
                           "properties": [
                               "endpoint": ["type": "string", "description": "Đường dẫn endpoint, ví dụ /getIdsmOsSummaryList.do"],
                               "params_json": ["type": "string", "description": "Chuỗi JSON các tham số lọc, ví dụ {\"PACKAGE_NO\":\"0009-001\"}. Bỏ trống nếu không lọc."],
                               "max_rows": ["type": "integer", "description": "Số dòng tối đa trả về (mặc định 40, tối đa 300)."],
                           ],
                           "required": ["endpoint"]]),
        AIToolDef(name: "desm_read_open_page",
                  description: "Đọc nội dung màn DESM đang mở trên app (lưới, ô lọc, chữ trên trang, màn chi tiết kiện). Dùng khi người dùng hỏi về 'màn này', 'trang này', 'đang hiển thị'.",
                  schema: ["type": "object",
                           "properties": ["limit": ["type": "integer", "description": "Số ký tự tối đa (mặc định 12000, tối đa 40000)."]]]),
    ]

    // MARK: Tiện ích
    static func str(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static let maxChars = 22000

    /// Số dự án mặc định đã lấy (dùng lại 10 phút, chỉ truy cập từ luồng chính).
    static var projectCache: (no: String, at: Date)? = nil

    static func format(_ rows: [[String: Any]], maxRows: Int, ignored: [String]) -> String {
        var head = "Tổng \(rows.count) dòng"
        if rows.count > maxRows { head += ", chỉ hiện \(maxRows) dòng đầu (thu hẹp bộ lọc hoặc tăng max_rows)" }
        if !ignored.isEmpty { head += ". Đã bỏ qua tham số không có trong endpoint: " + ignored.joined(separator: ", ") }
        var out = head + ":\n"
        for r in rows.prefix(maxRows) {
            var o: [String: Any] = [:]
            for (k, v) in r {
                if let s = v as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { o[k] = t }
                } else if v is NSNumber {
                    o[k] = v
                }
            }
            if let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), let s = String(data: d, encoding: .utf8) {
                out += s + "\n"
            }
            if out.utf8.count > maxChars { out += "…(đã cắt vì quá dài, hãy thu hẹp bộ lọc)\n"; break }
        }
        return out
    }
}

extension BrowserModel {
    /// Chạy một công cụ AI xin gọi; luôn trả chuỗi (lỗi cũng là chuỗi để AI tự xử lý).
    @MainActor
    func runDesmTool(_ name: String, _ args: [String: Any]) async -> String {
        switch name {
        case "desm_list_endpoints":
            return DesmAITools.catalogText(filter: DesmAITools.str(args["filter"] ?? ""))
        case "desm_read_open_page":
            let limit = min(max(DesmAITools.int(args["limit"]) ?? 12000, 1000), 40000)
            return await readOpenPageText(limit: limit)
        case "desm_query":
            return await desmToolQuery(args)
        default:
            return "Công cụ không tồn tại: " + name
        }
    }

    @MainActor
    private func desmToolQuery(_ a: [String: Any]) async -> String {
        let ep = DesmAITools.str(a["endpoint"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let path = ep.hasPrefix("/") ? ep : "/" + ep
        guard let e = DesmAITools.catalog.first(where: { $0.path == path }) else {
            return "Endpoint không nằm trong danh mục cho phép (chỉ đọc). Gọi desm_list_endpoints để xem danh sách."
        }
        var obj: [String: Any] = [:]
        if let s = a["params_json"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                guard let o = (try? JSONSerialization.jsonObject(with: Data(t.utf8))) as? [String: Any] else {
                    return "params_json không phải JSON hợp lệ. Ví dụ: {\"PACKAGE_NO\":\"0009-001\"}"
                }
                obj = o
            }
        } else if let o = a["params_json"] as? [String: Any] {
            obj = o
        }
        var given: [String: String] = [:]
        var ignored: [String] = []
        for (k, v) in obj {
            if e.keys.contains(k) { given[k] = DesmAITools.str(v) } else { ignored.append(k) }
        }
        let maxRows = min(max(DesmAITools.int(a["max_rows"]) ?? 40, 1), 300)

        var project = ""
        if e.keys.contains("PROJECT_NO") {
            if let g = given["PROJECT_NO"], !g.isEmpty { project = g }
            else if let c = DesmAITools.projectCache, Date().timeIntervalSince(c.at) < 600 { project = c.no }
            else {
                do {
                    project = try await desmProjectNo()
                    DesmAITools.projectCache = (no: project, at: Date())
                } catch {
                    AILog.add("✗ Không lấy được số dự án: " + error.localizedDescription)
                    return "Không lấy được số dự án (phiên DESM có thể đã hết hạn): " + error.localizedDescription
                }
            }
        }
        var parts: [String] = []
        for k in e.keys {
            var v = given[k] ?? e.defaults[k] ?? ""
            if k == "PROJECT_NO" { v = project }
            parts.append(k + "=" + BrowserModel.enc(v))
        }
        do {
            let rows = try await desmQueryAsync(e.path, body: parts.joined(separator: "&"))
            let t1 = Date()
            let box = DesmRowsBox(isJSON: true, rows: rows)
            let text = await Task.detached(priority: .userInitiated) { () -> String in
                return DesmAITools.format(box.rows ?? [], maxRows: maxRows, ignored: ignored)
            }.value
            AILog.add("Định dạng " + String(rows.count) + " dòng → " + String(text.utf8.count / 1024) + " KB mất " + String(format: "%.2f", Date().timeIntervalSince(t1)) + "s")
            return text
        } catch {
            AILog.add("✗ " + e.path + ": " + error.localizedDescription)
            return "Lỗi gọi " + e.path + ": " + error.localizedDescription
        }
    }

    /// Đọc chữ của màn đang mở (dùng hàm `__desmDodo.pageText` do DodoBubble.swift tiêm vào trang).
    /// evaluateJavaScript có thể không bao giờ gọi lại (trang đang bận/đang chuyển trang) nên có hạn 12 giây; callback chỉ được dùng đúng một lần.
    @MainActor
    func readOpenPageText(limit: Int) async -> String {
        guard let wv = webView else { return "Không có trang nào đang mở." }
        let js = "(function(){try{return (window.__desmDodo && window.__desmDodo.pageText) ? String(window.__desmDodo.pageText(\(limit)) || '') : '';}catch(e){return '';}})()"
        let t0 = Date()
        AILog.add("Đọc trang đang mở (tối đa " + String(limit) + " ký tự)…")
        let res: String? = await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let gate = AIGate()
            wv.evaluateJavaScript(js) { r, _ in
                if gate.claim() { c.resume(returning: (r as? String) ?? "") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                if gate.claim() { c.resume(returning: nil) }
            }
        }
        let secs = String(format: "%.1f", Date().timeIntervalSince(t0))
        guard let t = res else {
            AILog.add("✗ Đọc trang QUÁ THỜI GIAN sau " + secs + "s (trang bận hoặc đang chuyển trang)")
            return "Trang không phản hồi sau 12 giây (có thể đang tải hoặc đang bận). Hãy bảo người dùng chờ trang tải xong rồi hỏi lại."
        }
        AILog.add("← Đọc trang xong sau " + secs + "s, " + String(t.utf8.count / 1024) + " KB")
        return t.isEmpty ? "Không đọc được nội dung trang (trang trống hoặc chưa tải xong)." : t
    }
}
