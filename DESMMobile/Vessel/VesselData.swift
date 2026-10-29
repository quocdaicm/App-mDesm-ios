// VesselData.swift — mô hình dữ liệu tàu, cảng, tuyến.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Bản đồ tàu (mục "Thêm")
//
// Dữ liệu: POST /vessel/getVesselFinderList.do (PROJECT_NO) — trang "Vessel Finder" của DESM (MENU_SEQ=1057), mỗi dòng là một chuyến tàu:
// INV_NO, VESSEL_NAME, MFR, POL (cảng đi), POD (cảng đến), ETD_ATD / ETA_ATA (có ngoặc "( )" = dự kiến, không ngoặc = thực tế), MAIN_ITEM, LATITUDE, LONGITUDE.
// Lưu ý: ở dữ liệu đã bắt được, LATITUDE/LONGITUDE đều null nên DESM chưa có vị trí tàu; khi đó bản đồ vẽ tuyến cảng đi -> cảng đến
// (toạ độ cảng tra từ bảng nhỏ trong app, cảng lạ thì tra bằng CLGeocoder). Khi DESM có toạ độ thì tàu được đặt đúng vị trí.
// CHƯA kiểm chứng trên máy thật.

struct DesmVessel: Identifiable, Hashable {
    let id: String
    var invoice = "", vessel = "", mfr = "", pol = "", pod = "", etd = "", eta = "", item = ""
    var departed = false, arrived = false
    var lat: Double? = nil, lon: Double? = nil
    var pl = "", imo = "", project = ""
    var atd: Date? = nil, etdD: Date? = nil, eta2: Date? = nil, ata: Date? = nil   // mốc thời gian chính xác từ API (epoch ms)
    var tStart: Date? { atd ?? etdD ?? DesmRoutes.parseDate(etd) }
    var tEnd: Date? { ata ?? eta2 ?? DesmRoutes.parseDate(eta) }
    /// Sắp đến: chưa đến và ETA trong 7 ngày tới (cùng quy tắc tô dòng của trang web DESM).
    var arrivingSoon: Bool {
        guard !arrived, let e = tEnd else { return false }
        let d = e.timeIntervalSinceNow / 86400
        return d >= 0 && d < 7
    }
}

/// Một mốc trong tiến trình vận chuyển (từ /selectDesmShippingStatusList.do).
struct DesmShipMilestone: Identifiable {
    let id: String
    var title: String
    var date: Date?
    var done: Bool          // đã xảy ra (có ngày thật và ngày đã qua)
    var planned: Bool       // ngày còn là dự kiến
}
struct DesmShipInfo {
    var status = "", bl = "", line = "", mode = "", vessel = ""
    var volume = 0.0, grossKg = 0.0
    var milestones: [DesmShipMilestone] = []
}

enum DesmPorts {
    static func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
    /// Toạ độ gần đúng của các cảng hay gặp (không phải số liệu của DESM).
    static let known: [String: CLLocationCoordinate2D] = [
        "haiphong": .init(latitude: 20.8449, longitude: 106.6881),
        "busan": .init(latitude: 35.1028, longitude: 129.0403),
        "hochiminh": .init(latitude: 10.7597, longitude: 106.7933),
        "hochiminhcity": .init(latitude: 10.7597, longitude: 106.7933),
        "catlai": .init(latitude: 10.7597, longitude: 106.7933),
        "om4jetty": .init(latitude: 10.1000, longitude: 105.6300),
        "incheon": .init(latitude: 37.4563, longitude: 126.5927),
        "ulsan": .init(latitude: 35.5384, longitude: 129.3114),
        "shanghai": .init(latitude: 31.2304, longitude: 121.4737),
        "singapore": .init(latitude: 1.2644, longitude: 103.8222),
    ]
}

/// Tuyến biển/sông gần đúng: danh sách điểm mốc đi qua giữa cảng đi và cảng đến (không phải dữ liệu AIS, không dùng cho hàng hải).
/// Khoá = "<cảng đi>|<cảng đến>" đã qua DesmPorts.key; tuyến chiều ngược lại được suy ra bằng cách đảo thứ tự.
/// Muốn thêm tuyến mới: thêm một dòng vào `via` (vĩ độ, kinh độ), chọn điểm nằm trên mặt nước.
enum DesmRoutes {
    static func c(_ la: Double, _ lo: Double) -> CLLocationCoordinate2D { .init(latitude: la, longitude: lo) }

    // Biển Đông ven bờ Việt Nam, từ vịnh Bắc Bộ xuống cửa sông Hậu / Vũng Tàu.
    static let tonkinToSouth: [CLLocationCoordinate2D] = [
        c(20.60, 107.05), c(18.70, 106.90), c(16.30, 108.90), c(13.60, 109.55), c(11.40, 109.50), c(10.00, 108.30),
    ]
    static let toDinhAn: [CLLocationCoordinate2D] = [
        c(9.30, 107.00), c(9.48, 106.55), // cửa Định An (sông Hậu)
        c(9.62, 106.28), c(9.80, 106.05), c(9.95, 105.88), c(10.04, 105.76),
    ]
    // Busan -> eo Đài Loan -> nam đảo Hải Nam -> ven bờ Việt Nam.
    static let busanToVietnam: [CLLocationCoordinate2D] = [
        c(34.40, 129.30), c(32.80, 128.40), c(29.00, 125.80), c(25.30, 121.60), c(24.00, 119.60),
        c(22.00, 116.80), c(19.50, 113.80), c(17.60, 111.40), c(14.80, 110.30), c(11.40, 109.50), c(9.90, 108.20),
    ]
    // Vũng Tàu -> sông Lòng Tàu -> Cát Lái.
    static let toCatLai: [CLLocationCoordinate2D] = [
        c(10.30, 107.12), c(10.40, 107.02), c(10.55, 106.93), c(10.66, 106.79),
    ]

    static let via: [String: [CLLocationCoordinate2D]] = [
        "haiphong|om4jetty": tonkinToSouth + toDinhAn,
        "haiphong|hochiminh": tonkinToSouth + toCatLai,
        "haiphong|catlai": tonkinToSouth + toCatLai,
        "busan|hochiminh": busanToVietnam + toCatLai,
        "busan|catlai": busanToVietnam + toCatLai,
        "busan|om4jetty": busanToVietnam + [c(9.30, 107.00)] + toDinhAn,
    ]

    /// Đường đi từ cảng đi đến cảng đến. Không có tuyến khai báo thì chỉ là đoạn thẳng (known = false).
    static func path(pol: String, pod: String, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> (pts: [CLLocationCoordinate2D], known: Bool) {
        let kp = DesmPorts.key(pol), kd = DesmPorts.key(pod)
        if let v = via[kp + "|" + kd] { return ([a] + v + [b], true) }
        if let v = via[kd + "|" + kp] { return ([a] + v.reversed() + [b], true) }
        return ([a, b], false)
    }

    /// Phương vị (độ, 0 = bắc, theo chiều kim đồng hồ) từ a đến b.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180, dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(la2), x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dl)
        return atan2(y, x) * 180 / .pi
    }

    static func parseDate(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "() ")).prefix(10)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        for fmt in ["yyyy-MM-dd", "yyyy/MM/dd", "dd/MM/yyyy", "dd-MM-yyyy"] {
            f.dateFormat = fmt
            if let d = f.date(from: String(t)) { return d }
        }
        return nil
    }

    /// Vị trí ước tính của tàu đang đi: tỉ lệ thời gian (ATD -> ETA) áp lên độ dài tuyến. nil nếu thiếu ngày hoặc tàu chưa đi / đã đến.
    static func estimate(_ v: DesmVessel, along pts: [CLLocationCoordinate2D], now: Date = Date()) -> (CLLocationCoordinate2D, Double, Bool, Int)? {
        guard v.departed, !v.arrived, pts.count >= 2, let t0 = v.tStart, let t1 = v.tEnd, t1 > t0 else { return nil }
        let f = min(0.97, max(0.03, now.timeIntervalSince(t0) / t1.timeIntervalSince(t0)))
        var seg: [Double] = []
        for i in 1..<pts.count { seg.append(MKMapPoint(pts[i - 1]).distance(to: MKMapPoint(pts[i]))) }
        let total = seg.reduce(0, +)
        guard total > 0 else { return nil }
        var want = total * f
        for i in 0..<seg.count {
            if want <= seg[i] || i == seg.count - 1 {
                let u = seg[i] > 0 ? min(1, want / seg[i]) : 0
                return (.init(latitude: pts[i].latitude + (pts[i + 1].latitude - pts[i].latitude) * u,
                              longitude: pts[i].longitude + (pts[i + 1].longitude - pts[i].longitude) * u), f,
                        pts[i + 1].longitude >= pts[i].longitude, i)
            }
            want -= seg[i]
        }
        return nil
    }
}
