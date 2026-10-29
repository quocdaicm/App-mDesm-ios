// ScanActions.swift — kết quả quét (Package No / QR) -> gọi JS __desmFindPkg / __desmFindDetail trong trang.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

extension BrowserModel {
    /// Quét xong: điền Số kiện hàng, Search rồi mở chi tiết kiện (theo cài đặt) trong trang DESM đang mở.
    /// Package No → điền ô Package No; Packing List No (Shipment No / Shipping Invoice No) → điền ô Packing List No.
    func runScan(_ c: PkgCandidate) {
        let open = UserDefaults.standard.object(forKey: "desmScanOpenDetail") as? Bool ?? true
        switch c.kind {
        case .package:
            let cfg: [String: Any] = ["term": c.term, "key": c.key, "open": open]
            guard let d = try? JSONSerialization.data(withJSONObject: cfg),
                  let js = String(data: d, encoding: .utf8) else { return }
            showToast("Đang tìm kiện \(c.display)…")
            webView?.evaluateJavaScript("window.__desmFindPkg ? window.__desmFindPkg(\(js)) : 0;", completionHandler: nil)
        case .packingList:
            let cfg: [String: Any] = ["pl": c.term, "open": open]
            guard let d = try? JSONSerialization.data(withJSONObject: cfg),
                  let js = String(data: d, encoding: .utf8) else { return }
            showToast("Đang tìm Packing List \(c.display)…")
            webView?.evaluateJavaScript("window.__desmFindPackingList ? window.__desmFindPackingList(\(js)) : 0;", completionHandler: nil)
        }
    }
}

extension BrowserModel {
    /// Quét QR nhãn hạng mục (DETAIL!!!…): tra Material Code ở trang Hạng mục chi tiết rồi mở kiện chứa hạng mục đó.
    func runQRScan(_ d: QRDetail) {
        let open = UserDefaults.standard.object(forKey: "desmScanOpenDetail") as? Bool ?? true
        let cfg: [String: Any] = ["material": d.material, "pl": d.plName, "open": open]
        guard let data = try? JSONSerialization.data(withJSONObject: cfg),
              let js = String(data: data, encoding: .utf8) else { return }
        showToast("Đang tìm hạng mục \(d.material)…")
        webView?.evaluateJavaScript("window.__desmFindDetail ? window.__desmFindDetail(\(js)) : 0;", completionHandler: nil)
    }
}
