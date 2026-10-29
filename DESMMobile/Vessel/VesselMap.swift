// VesselMap.swift — bản đồ MapKit: ghim cảng/tàu.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

final class DesmVesselPin: MKPointAnnotation {
    enum Kind { case pol, pod, ship }
    var kind = Kind.pol
    var vesselId = ""
    var estimated = false
    var eastbound = true   // hướng chạy sang phải/trái màn hình, để lật con tàu
    var active = false     // chuyến đang xem VÀ đã khởi hành: chỉ khi đó mới có hiệu ứng sóng
    var heading = 0.0      // hướng tuyến tại cảng đi (độ, 0 = bắc, theo chiều kim đồng hồ), để xoay mũi tên
}

/// Mốc cảng đi / cảng đến: huy hiệu tròn nhỏ có viền trắng + nhãn tên cảng.
/// Chỉ chuyến ĐANG XEM và đã khởi hành mới có hiệu ứng (vòng sóng nhẹ, rơi xuống khi hiện); các chuyến khác là mốc tĩnh, mờ hơn.
/// Cảng đi: mũi tên xoay theo hướng tuyến. Cảng đến: ghim xanh dương.
final class DesmPortView: MKAnnotationView {
    static let W: CGFloat = 104, H: CGFloat = 50, cy: CGFloat = 16, D: CGFloat = 24
    let badge = UIView(), icon = UIImageView(), label = UILabel(), pill = UIView()
    let ring = CAShapeLayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let W = Self.W, H = Self.H, cy = Self.cy, D = Self.D
        frame = CGRect(x: 0, y: 0, width: W, height: H)
        centerOffset = CGPoint(x: 0, y: H / 2 - cy)   // tâm huy hiệu trùng toạ độ cảng
        canShowCallout = true
        ring.frame = CGRect(x: 0, y: 0, width: W, height: H)
        ring.path = UIBezierPath(ovalIn: CGRect(x: W / 2 - 17, y: cy - 17, width: 34, height: 34)).cgPath
        ring.fillColor = UIColor.clear.cgColor; ring.lineWidth = 1.5
        layer.addSublayer(ring)
        badge.frame = CGRect(x: W / 2 - D / 2, y: cy - D / 2, width: D, height: D)
        badge.layer.cornerRadius = D / 2
        badge.layer.borderWidth = 2; badge.layer.borderColor = UIColor.white.cgColor
        badge.layer.shadowColor = UIColor.black.cgColor; badge.layer.shadowOpacity = 0.25
        badge.layer.shadowRadius = 2.5; badge.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(badge)
        icon.frame = badge.bounds; icon.contentMode = .center; icon.tintColor = .white
        badge.addSubview(icon)
        pill.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        pill.layer.cornerRadius = 7.5
        label.font = .systemFont(ofSize: 10, weight: .bold); label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.7
        pill.addSubview(label); addSubview(pill)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ a: DesmVesselPin) {
        let isPod = a.kind == .pod
        let col = isPod ? UIColor(red: 47 / 255, green: 125 / 255, blue: 224 / 255, alpha: 1) : UIColor(red: 0.42, green: 0.47, blue: 0.56, alpha: 1)
        badge.backgroundColor = col
        let cfg = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        icon.image = UIImage(systemName: isPod ? "mappin" : "arrow.up", withConfiguration: cfg)
        // mũi tên cảng đi chỉ theo hướng tuyến (arrow.up = hướng bắc, xoay theo góc phương vị)
        icon.transform = isPod ? .identity : CGAffineTransform(rotationAngle: CGFloat(a.heading * .pi / 180))
        label.text = a.title ?? ""; label.textColor = col
        let w = min(98, max(30, label.intrinsicContentSize.width + 12))
        pill.frame = CGRect(x: (Self.W - w) / 2, y: Self.cy + Self.D / 2 + 3, width: w, height: 15)
        label.frame = pill.bounds.insetBy(dx: 4, dy: 0)
        ring.strokeColor = col.cgColor; ring.removeAllAnimations(); badge.layer.removeAllAnimations()
        if a.active {
            ring.isHidden = false
            let g = CAAnimationGroup(); g.duration = 2.4; g.repeatCount = .infinity
            let sc = CABasicAnimation(keyPath: "transform.scale"); sc.fromValue = 0.6; sc.toValue = 1.15
            let op = CABasicAnimation(keyPath: "opacity"); op.fromValue = 0.7; op.toValue = 0
            g.animations = [sc, op]; g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(g, forKey: "ripple")
            let drop = CASpringAnimation(keyPath: "transform.scale"); drop.fromValue = 0.2; drop.toValue = 1
            drop.damping = 9; drop.initialVelocity = 5; drop.duration = drop.settlingDuration
            badge.layer.add(drop, forKey: "drop")
            alpha = 1; pill.alpha = 1
        } else {
            ring.isHidden = true
            alpha = 0.75
        }
    }
}

/// Con tàu: thân tàu nhấp nhô nhẹ theo sóng; vòng sóng chỉ hiện khi đây là chuyến đang xem.
final class DesmShipView: MKAnnotationView {
    let ring = CAShapeLayer()
    let hull = UIImageView()
    var pulsing = false

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        centerOffset = .zero
        canShowCallout = true
        ring.path = UIBezierPath(ovalIn: CGRect(x: 6, y: 6, width: 32, height: 32)).cgPath
        ring.frame = bounds
        ring.fillColor = UIColor.clear.cgColor; ring.lineWidth = 1.5
        layer.addSublayer(ring)
        let cfg = UIImage.SymbolConfiguration(pointSize: 19, weight: .bold)
        hull.image = UIImage(systemName: "ferry.fill", withConfiguration: cfg)
        hull.contentMode = .center
        hull.frame = bounds
        hull.layer.shadowColor = UIColor.black.cgColor; hull.layer.shadowOpacity = 0.35
        hull.layer.shadowRadius = 2.5; hull.layer.shadowOffset = CGSize(width: 0, height: 1.5)
        addSubview(hull)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ a: DesmVesselPin) {
        let col: UIColor = a.estimated ? .systemOrange : .systemGreen
        hull.tintColor = col
        ring.strokeColor = col.cgColor
        hull.transform = a.eastbound ? .identity : CGAffineTransform(scaleX: -1, y: 1)
        pulsing = a.active
        alpha = a.active ? 1 : 0.8
        startAnimating()
    }

    func startAnimating() {
        ring.removeAllAnimations(); ring.isHidden = !pulsing
        if pulsing {
            let g = CAAnimationGroup(); g.duration = 2.4; g.repeatCount = .infinity
            let sc = CABasicAnimation(keyPath: "transform.scale"); sc.fromValue = 0.55; sc.toValue = 1.2
            let op = CABasicAnimation(keyPath: "opacity"); op.fromValue = 0.7; op.toValue = 0
            g.animations = [sc, op]; g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(g, forKey: "pulse")
        }
        hull.layer.removeAllAnimations()
        let bob = CABasicAnimation(keyPath: "transform.translation.y"); bob.fromValue = -1.5; bob.toValue = 1.5
        bob.duration = 1.0; bob.autoreverses = true; bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        hull.layer.add(bob, forKey: "bob")
    }
    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { startAnimating() } }
}

struct DesmVesselMap: UIViewRepresentable {
    var vessels: [DesmVessel]
    var ports: [String: CLLocationCoordinate2D]
    var selected: String?
    var tick = 0   // tăng định kỳ để tàu ước tính trượt dần dọc tuyến

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Vẽ tuyến của một chuyến: nếu tàu có vị trí ước tính thì chia "đã đi" (liền, xanh) / "còn lại" (chấm, xám).
    static func addRoute(_ m: MKMapView, _ v: DesmVessel, _ r: (pts: [CLLocationCoordinate2D], known: Bool), tag: String) {
        if v.lat == nil, let (c, _, _, i) = DesmRoutes.estimate(v, along: r.pts) {
            var done = Array(r.pts[0...i]) + [c], rest = [c] + Array(r.pts[(i + 1)...])
            let l1 = MKPolyline(coordinates: &done, count: done.count); l1.title = "done" + tag
            let l2 = MKPolyline(coordinates: &rest, count: rest.count); l2.title = tag
            m.addOverlay(l2); m.addOverlay(l1)
        } else {
            var cs = r.pts
            let line: MKPolyline = r.known ? MKPolyline(coordinates: &cs, count: cs.count) : MKGeodesicPolyline(coordinates: &cs, count: cs.count)
            line.title = tag
            m.addOverlay(line)
        }
    }

    /// Chỉ cập nhật phần phụ thuộc thời gian: vị trí tàu ước tính (trượt mượt) và ranh giới đã đi / còn lại.
    func refreshLive(_ m: MKMapView, _ co: Coordinator) {
        m.removeOverlays(m.overlays)
        for v in vessels {
            if let r = co.routes[v.id] { Self.addRoute(m, v, r, tag: selected == v.id ? "sel" : "") }
        }
        for case let p as DesmVesselPin in m.annotations where p.kind == .ship && p.estimated {
            guard let v = vessels.first(where: { $0.id == p.vesselId }), let r = co.routes[v.id],
                  let (c, f, east, _) = DesmRoutes.estimate(v, along: r.pts) else { continue }
            p.eastbound = east
            p.subtitle = "Ước tính theo lịch ~\(Int(f * 100))% hành trình · " + v.invoice
            UIView.animate(withDuration: 1.5) { p.coordinate = c }
        }
    }
    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.pointOfInterestFilter = .excludingAll
        m.showsCompass = false
        m.layer.cornerRadius = 16; m.clipsToBounds = true
        return m
    }
    func updateUIView(_ m: MKMapView, context: Context) {
        let sig = vessels.map { $0.id }.joined(separator: ",") + "|" + (selected ?? "") + "|\(ports.count)"
        if context.coordinator.sig == sig {
            if context.coordinator.tick != tick { context.coordinator.tick = tick; refreshLive(m, context.coordinator) }
            return
        }
        context.coordinator.sig = sig; context.coordinator.tick = tick; context.coordinator.routes = [:]
        m.removeAnnotations(m.annotations); m.removeOverlays(m.overlays)
        var focus: [MKMapPoint] = []
        func pt(_ c: CLLocationCoordinate2D) -> MKMapPoint { MKMapPoint(c) }
        for v in vessels {
            let isSel = selected == nil || selected == v.id
            let active = selected == v.id && v.departed && !v.arrived   // chỉ chuyến đang xem và đang đi mới có hiệu ứng
            let a = ports[DesmPorts.key(v.pol)], b = ports[DesmPorts.key(v.pod)]
            var routePts: [CLLocationCoordinate2D] = []
            if let a = a, let b = b {
                let r = DesmRoutes.path(pol: v.pol, pod: v.pod, a: a, b: b)
                routePts = r.pts
                context.coordinator.routes[v.id] = r
                Self.addRoute(m, v, r, tag: selected == v.id ? "sel" : "")
                if isSel { for q in r.pts { focus.append(pt(q)) } }
            }
            if let a = a {
                let p = DesmVesselPin(); p.coordinate = a; p.kind = .pol; p.vesselId = v.id; p.title = v.pol; p.subtitle = "Cảng đi · " + v.invoice
                p.active = active; p.heading = DesmRoutes.bearing(from: a, to: routePts.count > 1 ? routePts[1] : (b ?? a))
                m.addAnnotation(p); if isSel { focus.append(pt(a)) }
            }
            if let b = b {
                let p = DesmVesselPin(); p.coordinate = b; p.kind = .pod; p.vesselId = v.id; p.title = v.pod; p.subtitle = "Cảng đến · " + v.invoice
                p.active = active
                m.addAnnotation(p); if isSel { focus.append(pt(b)) }
            }
            if let la = v.lat, let lo = v.lon, abs(la) <= 90, abs(lo) <= 180 {
                let c = CLLocationCoordinate2D(latitude: la, longitude: lo)
                let p = DesmVesselPin(); p.coordinate = c; p.kind = .ship; p.vesselId = v.id; p.active = active
                p.title = v.vessel.isEmpty ? v.invoice : v.vessel; p.subtitle = v.invoice
                m.addAnnotation(p); if isSel { focus.append(pt(c)) }
            } else if let (c, f, east, _) = DesmRoutes.estimate(v, along: routePts) {
                let p = DesmVesselPin(); p.coordinate = c; p.kind = .ship; p.estimated = true; p.eastbound = east; p.active = active; p.vesselId = v.id
                p.title = v.vessel.isEmpty ? v.invoice : v.vessel
                p.subtitle = "Ước tính theo lịch ~\(Int(f * 100))% hành trình · " + v.invoice
                m.addAnnotation(p); if isSel { focus.append(pt(c)) }
            }
        }
        if let first = focus.first {
            var rect = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
            for q in focus.dropFirst() { rect = rect.union(MKMapRect(origin: q, size: MKMapSize(width: 0, height: 0))) }
            m.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 50, left: 40, bottom: 50, right: 40), animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var sig = ""
        var tick = 0
        var routes: [String: (pts: [CLLocationCoordinate2D], known: Bool)] = [:]
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let l = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: l)
            let t = l.title ?? ""
            let sel = t.hasSuffix("sel")
            let blue = UIColor(red: 47 / 255, green: 125 / 255, blue: 224 / 255, alpha: 1)
            r.lineCap = .round; r.lineJoin = .round
            if t.hasPrefix("done") {
                r.strokeColor = sel ? blue : blue.withAlphaComponent(0.55)
                r.lineWidth = sel ? 5 : 3
            } else {
                r.strokeColor = sel ? UIColor.systemGray : UIColor.systemGray3
                r.lineWidth = sel ? 3 : 2
                r.lineDashPattern = [2, 7]
            }
            return r
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let a = annotation as? DesmVesselPin else { return nil }
            if a.kind == .ship {
                let sv = (mapView.dequeueReusableAnnotationView(withIdentifier: "desmShip") as? DesmShipView)
                    ?? DesmShipView(annotation: a, reuseIdentifier: "desmShip")
                sv.annotation = a; sv.configure(a); sv.zPriority = .max
                return sv
            }
            let pv = (mapView.dequeueReusableAnnotationView(withIdentifier: "desmPort") as? DesmPortView)
                ?? DesmPortView(annotation: a, reuseIdentifier: "desmPort")
            pv.annotation = a; pv.configure(a); pv.zPriority = a.kind == .pod ? .defaultSelected : .defaultUnselected
            return pv
        }
    }
}
