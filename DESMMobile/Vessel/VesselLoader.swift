// VesselLoader.swift — tải danh sách tàu và tiến trình vận chuyển.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

extension BrowserModel {
    @MainActor
    func fetchVesselsAsync() async throws -> [DesmVessel] {
        let P = Self.enc(try await desmProjectNo())
        let list = try await desmQueryAsync("/vessel/getVesselFinderList.do", body: "PROJECT_NO=\(P)")
        func s(_ r: [String: Any], _ k: String) -> String {
            if let v = r[k] as? String { return v.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = r[k] as? NSNumber { return n.stringValue }
            return ""
        }
        func d(_ r: [String: Any], _ k: String) -> Double? {
            if let n = r[k] as? NSNumber { return n.doubleValue }
            if let v = r[k] as? String { return Double(v.trimmingCharacters(in: .whitespaces)) }
            return nil
        }
        var out: [DesmVessel] = []
        for (i, r) in list.enumerated() {
            var v = DesmVessel(id: "\(i)-\(s(r, "INV_NO"))")
            v.invoice = s(r, "INV_NO"); v.vessel = s(r, "VESSEL_NAME"); v.mfr = s(r, "MFR")
            v.pol = s(r, "POL"); v.pod = s(r, "POD"); v.item = s(r, "MAIN_ITEM")
            let etd = s(r, "ETD_ATD"), eta = s(r, "ETA_ATA")
            v.departed = !etd.isEmpty && !etd.hasPrefix("(")
            v.arrived = !eta.isEmpty && !eta.hasPrefix("(")
            v.etd = etd.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            v.eta = eta.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            v.lat = d(r, "LATITUDE"); v.lon = d(r, "LONGITUDE")
            v.pl = s(r, "PL_NO"); v.imo = s(r, "IMO"); v.project = s(r, "PROJECT_NO")
            func ms(_ k: String) -> Date? { d(r, k).map { Date(timeIntervalSince1970: $0 / 1000) } }
            v.atd = ms("ATD"); v.etdD = ms("ETD"); v.eta2 = ms("ETA"); v.ata = ms("ATA")
            if v.atd != nil { v.departed = true }
            if v.ata != nil { v.arrived = true }
            out.append(v)
        }
        return out
    }

    func fetchVessels(done: @escaping ([DesmVessel], String) -> Void) {
        Task { @MainActor in
            do { done(try await self.fetchVesselsAsync(), "") }
            catch { done([], error.localizedDescription) }
        }
    }
}

extension BrowserModel {
    /// Tiến trình vận chuyển của một chuyến: /selectDesmShippingStatusList.do (body như trang Shipping Status của DESM).
    /// Mã Invoice ở danh sách tàu (INV_NO) và ở Shipping Status (INVOICE_NO) có thể khác dạng, nên ghép theo INVOICE_NO hoặc tên tàu.
    @MainActor
    func fetchShipInfoAsync(_ v: DesmVessel) async throws -> DesmShipInfo {
        // lần 1: theo mã Invoice đầy đủ; lần 2: theo nhóm số (vd "0002") mà web dùng làm VOYAGE/INVOICE tìm kiếm
        var tries = [v.invoice]
        if let g = v.invoice.split(separator: "-").first(where: { $0.count >= 3 && $0.allSatisfy { $0.isNumber } }) { tries.append(String(g)) }
        func norm(_ x: String) -> String { x.lowercased().filter { $0.isLetter || $0.isNumber } }
        for t in tries {
            let rows = try await desmQueryAsync("/selectDesmShippingStatusList.do", body: "PROJECT_NO=\(Self.enc(v.project))&VOYAGE_NO=&INVOICE_NO=\(Self.enc(t))&SHIPPING_STATUS=&DATA_CREATED_YN=")
            func str(_ r: [String: Any], _ k: String) -> String { (r[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
            let hit = rows.first { norm(str($0, "INVOICE_NO")) == norm(v.invoice) }
                ?? rows.first { !v.vessel.isEmpty && norm(str($0, "VESSEL_NAME")) == norm(v.vessel) }
            guard let r = hit else { continue }
            func dt(_ k: String) -> Date? { (r[k] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } }
            var info = DesmShipInfo()
            info.status = str(r, "SHIPPING_STATUS"); info.bl = str(r, "BL_NO"); info.line = str(r, "SHIPPING_LINE")
            info.mode = str(r, "SHIPPING_MODE"); info.vessel = str(r, "VESSEL_NAME")
            info.volume = (r["VOLUME"] as? NSNumber)?.doubleValue ?? 0; info.grossKg = (r["GROSS_WEIGHT"] as? NSNumber)?.doubleValue ?? 0
            let now = Date()
            func ms(_ id: String, _ title: String, actual: String?, plan: String?) -> DesmShipMilestone {
                if let a = actual, let d = dt(a) { return .init(id: id, title: title, date: d, done: d <= now, planned: false) }
                if let pl = plan, let d = dt(pl) { return .init(id: id, title: title, date: d, done: false, planned: true) }
                return .init(id: id, title: title, date: nil, done: false, planned: false)
            }
            info.milestones = [
                ms("rdy", "Hàng sẵn sàng", actual: "CARGO_READY_DATE", plan: nil),
                ms("dep", "Khởi hành", actual: "ATD", plan: "ETD"),
                ms("arr", "Đến cảng", actual: "ATA", plan: "ETA"),
                ms("dis", "Dỡ hàng tại cảng", actual: "DISCHARGING_AT_PORT", plan: nil),
                ms("out", "Kéo ra khỏi cảng", actual: "PULLING_OUT_FROM_PORT", plan: nil),
                ms("site", "Đến công trường", actual: "ON_SITE", plan: nil),
            ]
            return info
        }
        throw DesmAPIError.message("Chưa có dữ liệu tiến trình cho chuyến này.")
    }

    func fetchShipInfo(_ v: DesmVessel, done: @escaping (DesmShipInfo?, String) -> Void) {
        Task { @MainActor in
            do { done(try await self.fetchShipInfoAsync(v), "") }
            catch { done(nil, error.localizedDescription) }
        }
    }
}
