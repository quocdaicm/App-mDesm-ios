// PageSnapshot.swift — chụp ảnh toàn bộ trang (ảnh thật của trang web, KHÔNG vẽ lại / dàn lại bố cục).
//
// Cách làm: dùng WKWebView.takeSnapshot (đúng những gì đang hiển thị trên màn hình) rồi "cuộn và ghép":
//  1. Tìm vùng cuộn chính của trang (cuộn của cả trang, hoặc khung cuộn bên trong / iframe cùng domain — như danh sách thẻ, chi tiết kiện, TreeGrid).
//  2. Cuộn từng đoạn bằng đúng chiều cao vùng nhìn thấy, mỗi đoạn chụp một ảnh thật.
//  3. Ghép: phần trên vùng cuộn (tiêu đề…) lấy từ ảnh đầu, các đoạn nối nhau, phần dưới lấy từ ảnh cuối.
//  4. Trả trang về vị trí cuộn cũ. Không sửa CSS / chiều cao của trang → ảnh giống hệt màn hình, chỉ dài hơn.
// Thanh cố định/dính (fixed/sticky) trong vùng cuộn chỉ hiện ở đoạn đầu, các đoạn sau tạm ẩn để không lặp lại.
// TreeGrid cuộn ảo vẫn đủ dòng vì ta cuộn thật cho nó tự dựng lại từng đoạn.

import SwiftUI
import WebKit

extension BrowserModel {
    /// Tìm vùng cuộn lớn nhất (chiếm ≥ 20% màn hình, thật sự cuộn được) và dựng sẵn hàm cuộn / ẩn thanh cố định trên window.
    static let shotProbeJS = #"""
    (function() {
      var T = window, VW = T.innerWidth, VH = T.innerHeight, best = null;
      T.__desmShotEl = null; T.__desmShotHidden = [];
      function offsetOf(win) {
        var x = 0, y = 0;
        try {
          while (win !== win.top) {
            var fe = win.frameElement; if (!fe) return null;
            var r = fe.getBoundingClientRect(); x += r.left + fe.clientLeft; y += r.top + fe.clientTop; win = win.parent;
          }
        } catch (e) { return null; }
        return [x, y];
      }
      function canScroll(el) {
        try { var s0 = el.scrollTop; el.scrollTop = s0 + 10; var ok = el.scrollTop !== s0; el.scrollTop = s0; return ok; } catch (e) { return false; }
      }
      function consider(el, win, root) {
        var off = offsetOf(win); if (!off) return;
        var sh = el.scrollHeight, ch, r;
        if (root) { ch = win.innerHeight; r = { l: 0, t: 0, w: win.innerWidth, h: ch }; }
        else { ch = el.clientHeight; var b = el.getBoundingClientRect(); r = { l: b.left + el.clientLeft, t: b.top + el.clientTop, w: el.clientWidth, h: ch }; }
        var ext = sh - ch; if (ext <= 20 || ch <= 0) return;
        var x = off[0] + r.l, y = off[1] + r.t;
        if (x < -2 || y < -2 || x + r.w > VW + 2 || y + r.h > VH + 2) return;
        if (r.w * r.h < 0.2 * VW * VH) return;
        if (best && ext <= best.ext) return;
        if (!canScroll(el)) return;
        best = { el: el, ext: ext, x: x, y: y, w: r.w, h: r.h, sh: sh, ch: ch, st: el.scrollTop, root: root };
      }
      function scan(win, lvl) {
        var doc; try { doc = win.document; } catch (e) { return; }
        if (!doc || !doc.documentElement) return;
        consider(doc.scrollingElement || doc.documentElement, win, true);
        var els = doc.querySelectorAll('body *'), n = Math.min(els.length, 20000);
        for (var i = 0; i < n; i++) {
          var e = els[i];
          if (e.clientHeight > 80 && e.scrollHeight > e.clientHeight + 20) {
            var oy = win.getComputedStyle(e).overflowY;
            if (oy === 'auto' || oy === 'scroll' || oy === 'overlay') consider(e, win, false);
          }
        }
        if (lvl > 3) return;
        var fs = doc.querySelectorAll('iframe,frame');
        for (var j = 0; j < fs.length; j++) { try { var cw = fs[j].contentWindow; if (cw && cw.document) scan(cw, lvl + 1); } catch (e) {} }
      }
      scan(T, 0);
      if (!best) return JSON.stringify({ iw: VW });
      T.__desmShotEl = best.el;
      T.__desmShotScroll = function(y) { var e = T.__desmShotEl; e.scrollTop = y; return e.scrollTop; };
      T.__desmShotHide = function() {
        var e = T.__desmShotEl, doc = e.ownerDocument, win = doc.defaultView, rr;
        if (e === doc.documentElement || e === doc.scrollingElement) rr = { left: 0, top: 0, right: win.innerWidth, bottom: win.innerHeight };
        else rr = e.getBoundingClientRect();
        var els = doc.querySelectorAll('body *'), n = Math.min(els.length, 20000);
        for (var i = 0; i < n; i++) {
          var x = els[i];
          try {
            var p = win.getComputedStyle(x).position;
            if (p !== 'fixed' && p !== 'sticky') continue;
            if (x.contains(e)) continue;
            var b = x.getBoundingClientRect();
            if (b.right < rr.left || b.left > rr.right || b.bottom < rr.top || b.top > rr.bottom) continue;
            T.__desmShotHidden.push([x, x.style.getPropertyValue('visibility'), x.style.getPropertyPriority('visibility')]);
            x.style.setProperty('visibility', 'hidden', 'important');
          } catch (err) {}
        }
      };
      T.__desmShotUnhide = function() {
        var s = T.__desmShotHidden || [];
        for (var i = 0; i < s.length; i++) {
          try { s[i][0].style.removeProperty('visibility'); if (s[i][1]) s[i][0].style.setProperty('visibility', s[i][1], s[i][2]); } catch (e) {}
        }
        T.__desmShotHidden = [];
      };
      return JSON.stringify({ iw: VW, x: best.x, y: best.y, w: best.w, h: best.h, sh: best.sh, ch: best.ch, st: best.st });
    })();
    """#

    private func shotEval(_ wv: WKWebView, _ js: String) async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            wv.evaluateJavaScript(js) { r, _ in
                if let s = r as? String { c.resume(returning: s) }
                else if let n = r as? NSNumber { c.resume(returning: n.stringValue) }
                else { c.resume(returning: nil) }
            }
        }
    }

    private func shotSnap(_ wv: WKWebView) async -> UIImage? {
        await withCheckedContinuation { (c: CheckedContinuation<UIImage?, Never>) in
            let cfg = WKSnapshotConfiguration()
            cfg.rect = wv.bounds
            cfg.afterScreenUpdates = true
            wv.takeSnapshot(with: cfg) { img, _ in c.resume(returning: img) }
        }
    }

    private func shotWait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func captureFullPage() {
        guard let wv = webView else { showToast("Chưa có trang để chụp"); return }
        showToast("Đang chụp toàn trang…")
        Task { @MainActor in
            let img = await self.buildFullPageImage(wv)
            guard let img = img else { self.showToast("Không chụp được trang"); return }
            self.finishShot(image: img)
        }
    }

    @MainActor
    private func buildFullPageImage(_ wv: WKWebView) async -> UIImage? {
        let bounds = wv.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        // 1) Dò vùng cuộn chính
        let probe = await shotEval(wv, BrowserModel.shotProbeJS)
        var info: [String: Double] = [:]
        if let s = probe, let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] {
            for (k, v) in o { if let n = v as? NSNumber { info[k] = n.doubleValue } }
        }
        guard let iw = info["iw"], iw > 1, let sh = info["sh"], let ch = info["ch"], ch > 1,
              let rx = info["x"], let ry0 = info["y"], let rw = info["w"], let rh0 = info["h"], let st0 = info["st"] else {
            // Không có gì để cuộn: chụp thẳng màn hình hiện tại
            return await shotSnap(wv)
        }
        _ = rx; _ = rw
        let k = bounds.width / CGFloat(iw)                 // điểm màn hình / px CSS
        let ry = CGFloat(ry0) * k, rh = CGFloat(rh0) * k
        let contentH = CGFloat(sh) * k
        let headerH = ry
        let footerH = max(0, bounds.height - (ry + rh))
        let total = headerH + contentH + footerH
        let maxSlices = 80
        let n = min(maxSlices, Int(ceil(sh / ch)))

        // 2) Đoạn đầu: cuộn về 0, chụp
        _ = await shotEval(wv, "window.__desmShotScroll(0)")
        await shotWait(0.45)
        guard let first = await shotSnap(wv) else { return nil }
        var slices: [(off: CGFloat, img: UIImage)] = [(0, first)]

        // 3) Các đoạn sau
        if n > 1 { _ = await shotEval(wv, "window.__desmShotHide()") }
        var i = 1
        while i < n {
            let y = min(Double(i) * ch, sh - ch)
            let actual = Double(await shotEval(wv, "window.__desmShotScroll(\(y))") ?? "") ?? y
            await shotWait(0.4)
            if let im = await shotSnap(wv) { slices.append((CGFloat(actual) * k, im)) }
            i += 1
        }

        // 4) Phần dưới vùng cuộn: chụp lại khi thanh cố định đã hiện, ở cuối trang
        var last: UIImage? = nil
        _ = await shotEval(wv, "window.__desmShotUnhide()")
        if footerH > 1 {
            _ = await shotEval(wv, "window.__desmShotScroll(\(sh))")
            await shotWait(0.4)
            last = await shotSnap(wv)
        }
        // trả vị trí cuộn cũ
        _ = await shotEval(wv, "window.__desmShotScroll(\(st0))")

        // 5) Ghép ảnh
        var scale = UIScreen.main.scale
        scale = min(scale, 16000 / max(total, 1))
        scale = min(scale, (60_000_000 / (bounds.width * max(total, 1))).squareRoot())
        scale = max(scale, 0.5)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale; fmt.opaque = true
        let size = CGSize(width: bounds.width, height: total)
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let c = ctx.cgContext
            // phần trên
            if headerH > 0 {
                c.saveGState(); c.clip(to: CGRect(x: 0, y: 0, width: bounds.width, height: headerH))
                first.draw(at: .zero); c.restoreGState()
            }
            // thân: mỗi đoạn vẽ cắt đúng vùng cuộn, đoạn sau đè lên đoạn trước
            for s in slices {
                c.saveGState()
                c.clip(to: CGRect(x: 0, y: headerH + s.off, width: bounds.width, height: rh))
                s.img.draw(at: CGPoint(x: 0, y: s.off))
                c.restoreGState()
            }
            // phần dưới
            if footerH > 1, let l = last {
                let originY = headerH + contentH - (ry + rh)
                c.saveGState(); c.clip(to: CGRect(x: 0, y: total - footerH, width: bounds.width, height: footerH))
                l.draw(at: CGPoint(x: 0, y: originY)); c.restoreGState()
            }
        }
    }

    func finishShot(image: UIImage) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("desm-page-\(f.string(from: Date())).png")
        guard let png = image.pngData() else { showToast("Không tạo được file ảnh"); return }
        do { try png.write(to: url); shotItem = ShareItem(url: url) }
        catch { showToast("Không lưu được file: \(error.localizedDescription)") }
    }
}
