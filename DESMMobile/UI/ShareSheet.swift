// ShareSheet.swift — chia sẻ file/văn bản qua share sheet.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Cài đặt: chế độ hiển thị, CSS/từ điển bổ sung, đăng nhập, quét, và nhóm công cụ tinh chỉnh
/// (cấu trúc trang, HTML/script, nhật ký API, tải nội dung địa chỉ). Xem DEV_NOTES.md §7.

// MARK: - Chụp toàn bộ màn hình sheet (danh sách dài) thành MỘT ảnh dài
//
// Nút máy ảnh nổi ở góc dưới phải của mọi sheet gắn `.desmSheet()` / `.desmShotButton()`.
// Cách làm: tìm UIScrollView đang hiện lớn nhất trong sheet, cuộn từng đoạn bằng đúng chiều cao vùng nhìn,
// chụp từng đoạn (drawHierarchy) rồi ghép; phần đầu (thanh tiêu đề, bộ lọc) và phần cuối lấy từ ảnh chụp gốc.
// Chạy được với ScrollView + LazyVStack, List, và cả màn không cuộn (khi đó chỉ chụp đúng màn hình sheet).

enum DesmShot {
    final class Anchor { weak var view: UIView? }

    /// Controller ngoài cùng của sheet (đi ngược chuỗi responder, lấy cái ngoài cùng đang được present).
    static func hostController(of v: UIView) -> UIViewController? {
        var found: UIViewController? = nil
        var r: UIResponder? = v
        while let cur = r {
            if let vc = cur as? UIViewController, vc.presentingViewController != nil { found = vc }
            r = cur.next
        }
        return found
    }

    private static func visible(_ v: UIView) -> Bool {
        var x: UIView? = v
        while let c = x {
            if c.isHidden || c.alpha < 0.01 { return false }
            x = c.superview
        }
        return true
    }

    /// UIScrollView cuộn dọc được, đang hiện, có diện tích hiển thị lớn nhất trong sheet.
    private static func pickScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView? = nil
        var bestArea: CGFloat = 0
        func walk(_ v: UIView) {
            if let s = v as? UIScrollView, visible(s) {
                let inset = s.adjustedContentInset
                let vp = s.bounds.height - inset.top - inset.bottom
                if vp > 80, s.contentSize.height > vp + 1 {
                    let r = s.convert(s.bounds, to: root).intersection(root.bounds)
                    let a = r.isNull ? 0 : r.width * r.height
                    if a > bestArea { bestArea = a; best = s }
                }
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(root)
        return best
    }

    @MainActor
    static func capture(from anchor: UIView) async -> UIImage? {
        guard let host = hostController(of: anchor) else { return nil }
        let root: UIView = host.view
        let size = root.bounds.size
        guard size.width > 10, size.height > 10 else { return nil }
        let scale = root.traitCollection.displayScale > 0 ? root.traitCollection.displayScale : 3
        let bg = (root.backgroundColor ?? UIColor.systemBackground).resolvedColor(with: root.traitCollection)

        func snap() -> UIImage {
            let f = UIGraphicsImageRendererFormat()
            f.scale = scale; f.opaque = true
            return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
                bg.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                root.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
        }

        guard let sv = pickScrollView(in: root) else { return snap() }   // màn không cuộn: chụp luôn

        let rect = sv.convert(sv.bounds, to: root)
        let inset = sv.adjustedContentInset
        let vpTop = rect.minY + inset.top
        let vpH = sv.bounds.height - inset.top - inset.bottom
        let originalOffset = sv.contentOffset
        let hadIndicator = sv.showsVerticalScrollIndicator
        sv.showsVerticalScrollIndicator = false
        defer {
            sv.setContentOffset(originalOffset, animated: false)
            sv.showsVerticalScrollIndicator = hadIndicator
        }

        // 1) về đầu danh sách, chụp đoạn đầu
        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: -inset.top), animated: false)
        sv.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 350_000_000)
        var slices: [(CGFloat, UIImage)] = []          // (toạ độ nội dung của mép trên vùng nhìn, ảnh)
        let firstC = sv.contentOffset.y + inset.top
        slices.append((firstC, snap()))
        var covered = firstC + vpH                      // mép dưới đã chụp (toạ độ nội dung)

        // 2) cuộn từng đoạn (contentSize của LazyVStack có thể lớn dần nên đọc lại mỗi vòng)
        var loops = 0
        while covered < sv.contentSize.height - 0.5 && loops < 80 {
            loops += 1
            let maxC = max(0, sv.contentSize.height - vpH)
            let target = min(covered, maxC)
            sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: target - inset.top), animated: false)
            sv.layoutIfNeeded()
            try? await Task.sleep(nanoseconds: 350_000_000)
            let c = sv.contentOffset.y + inset.top
            let img = snap()
            slices.append((c, img))
            let newCovered = c + vpH
            if newCovered <= covered + 0.5 { break }    // không cuộn thêm được nữa
            covered = newCovered
        }

        // 3) ghép
        let footerTop = vpTop + vpH
        let footerH = max(0, size.height - footerTop)
        let total = vpTop + covered + footerH
        let maxPixels: CGFloat = 20000                  // tránh ảnh quá lớn làm hết bộ nhớ
        let outScale = min(scale, maxPixels / max(total, 1))
        let f = UIGraphicsImageRendererFormat()
        f.scale = outScale; f.opaque = true
        let width = size.width
        let out = UIGraphicsImageRenderer(size: CGSize(width: width, height: total), format: f).image { ctx in
            let c = ctx.cgContext
            bg.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: total))
            // phần đầu (tiêu đề, bộ lọc…) từ ảnh đầu tiên
            if let first = slices.first, vpTop > 0 {
                c.saveGState(); c.clip(to: CGRect(x: 0, y: 0, width: width, height: vpTop))
                first.1.draw(at: CGPoint(x: 0, y: 0)); c.restoreGState()
            }
            // phần danh sách: ảnh có mép vùng nhìn ở y = vpTop → đặt sao cho mép đó rơi vào vpTop + c
            for (cy, img) in slices {
                c.saveGState(); c.clip(to: CGRect(x: 0, y: vpTop + cy, width: width, height: vpH))
                img.draw(at: CGPoint(x: 0, y: cy)); c.restoreGState()
            }
            // phần cuối từ ảnh cuối cùng
            if footerH > 0.5, let last = slices.last {
                c.saveGState(); c.clip(to: CGRect(x: 0, y: vpTop + covered, width: width, height: footerH))
                last.1.draw(at: CGPoint(x: 0, y: last.0)); c.restoreGState()
            }
        }
        return out
    }

    /// Lưu PNG vào thư mục tạm rồi mở share sheet (lưu vào Ảnh, Files, gửi Zalo…) ngay trên sheet đang mở.
    @MainActor
    static func share(_ img: UIImage, from anchor: UIView) async {
        guard let host = hostController(of: anchor) else { return }
        let data: Data? = await Task.detached(priority: .userInitiated) { img.pngData() }.value
        guard let png = data else { return }
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("desm-\(df.string(from: Date())).png")
        do { try png.write(to: url) } catch { return }
        var top: UIViewController = host
        while let n = top.presentedViewController { top = n }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = av.popoverPresentationController {
            pop.sourceView = host.view
            pop.sourceRect = CGRect(x: host.view.bounds.maxX - 40, y: host.view.bounds.maxY - 40, width: 1, height: 1)
        }
        top.present(av, animated: true)
    }
}

/// View ẩn để lấy UIView của sheet (dùng tìm controller/scroll view).
struct DesmShotProbe: UIViewRepresentable {
    let anchor: DesmShot.Anchor
    func makeUIView(context: Context) -> UIView {
        let v = UIView(); v.isUserInteractionEnabled = false; v.backgroundColor = .clear
        anchor.view = v
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) { anchor.view = uiView }
}

struct DesmShotModifier: ViewModifier {
    var enabled = true
    @State private var anchor = DesmShot.Anchor()
    @State private var capturing = false
    @State private var note: String? = nil

    func run() {
        guard !capturing, let v = anchor.view else { return }
        capturing = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)   // đợi nút ẩn đi rồi mới chụp
            let img = await DesmShot.capture(from: v)
            capturing = false
            guard let img = img else { flash("Không chụp được màn hình này"); return }
            await DesmShot.share(img, from: v)
        }
    }
    func flash(_ s: String) {
        note = s
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            note = nil
        }
    }

    func body(content: Content) -> some View {
        content
            .background(DesmShotProbe(anchor: anchor))
            .overlay(alignment: .bottomTrailing) {
                if enabled && !capturing {
                    Button { run() } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Color.tabBlue.opacity(0.92)))
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    }
                    .padding(.trailing, 16).padding(.bottom, 22)
                    .accessibilityLabel("Chụp cả danh sách thành một ảnh")
                }
            }
            .overlay {
                if capturing { Color.clear.contentShape(Rectangle()) }   // chặn chạm khi đang cuộn chụp
            }
            .overlay(alignment: .bottom) {
                if let n = note {
                    Text(n).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.78)))
                        .padding(.bottom, 28)
                }
            }
    }
}

extension View {
    /// Thêm nút chụp cả danh sách thành một ảnh dài (dùng cho sheet không đi qua `desmSheet()`).
    func desmShotButton() -> some View { modifier(DesmShotModifier()) }
}
