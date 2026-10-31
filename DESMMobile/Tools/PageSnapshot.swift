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
      // Thanh trên của danh sách thẻ đang ẩn (do cuộn) → hiện lại rồi để Swift dò lại sau khi bố cục ổn định
      try { if (best.el.__tophid && best.el.__setHidden) { best.el.__setHidden(false); return JSON.stringify({ iw: VW, redo: 1 }); } } catch (e) {}
      T.__desmShotBusy = true;   // khoá ẩn/hiện thanh trên khi cuộn lúc chụp (xem scroll listener của #desmCards)
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
            let shot = await self.buildFullPageImage(wv)
            guard let shot = shot else { self.showToast("Không chụp được trang"); return }
            self.finishShot(shot: shot)
        }
    }

    @MainActor
    private func buildFullPageImage(_ wv: WKWebView) async -> FullShot? {
        let bounds = wv.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        // 1) Dò vùng cuộn chính
        var probe = await shotEval(wv, BrowserModel.shotProbeJS)
        if let s = probe, s.contains("\"redo\"") {
            await shotWait(0.5)
            probe = await shotEval(wv, BrowserModel.shotProbeJS)
        }
        var info: [String: Double] = [:]
        if let s = probe, let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] {
            for (k, v) in o { if let n = v as? NSNumber { info[k] = n.doubleValue } }
        }
        guard let iw = info["iw"], iw > 1, let sh = info["sh"], let ch = info["ch"], ch > 1,
              let rx = info["x"], let ry0 = info["y"], let rw = info["w"], let rh0 = info["h"], let st0 = info["st"] else {
            // Không có gì để cuộn: chụp thẳng màn hình hiện tại
            guard let one = await shotSnap(wv) else { return nil }
            return FullShot(width: bounds.width, total: bounds.height, headerH: 0, contentH: bounds.height, footerH: 0, ry: 0, rh: bounds.height,
                            first: one, slices: [(0, one)], last: nil)
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
        _ = await shotEval(wv, "window.__desmShotScroll(\(st0)); window.__desmShotBusy = false")

        // 5) Trả về dữ liệu ghép; PNG (có thể bị giảm độ phân giải) và PDF (giữ nguyên độ phân giải) dựng từ đây
        return FullShot(width: bounds.width, total: total, headerH: headerH, contentH: contentH, footerH: footerH, ry: ry, rh: rh,
                        first: first, slices: slices, last: last)
    }

    /// Ghi CSV ra thư mục tạm (UTF-8 + BOM) rồi mở share sheet (cùng sheet với ảnh chụp trang).
    func shareCSV(_ csv: String, baseName: String) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(baseName)-\(f.string(from: Date())).csv")
        var data = Data([0xEF, 0xBB, 0xBF]); data.append(Data(csv.utf8))
        do { try data.write(to: url); shotItem = ShareItem(url: url) }
        catch { showToast("Không lưu được file: \(error.localizedDescription)") }
    }

    /// Lưu PNG + PDF vào thư mục tạm rồi mở share sheet (PNG trước để xem nhanh, PDF giữ nét cho trang dài).
    func finishShot(shot: FullShot) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: Date())
        let dir = FileManager.default.temporaryDirectory
        let pngURL = dir.appendingPathComponent("desm-page-\(stamp).png")
        let pdfURL = dir.appendingPathComponent("desm-page-\(stamp).pdf")
        var urls: [URL] = []
        if let png = shot.image().pngData(), (try? png.write(to: pngURL)) != nil { urls.append(pngURL) }
        if shot.writePDF(to: pdfURL) { urls.append(pdfURL) }
        guard let first = urls.first else { showToast("Không tạo được file ảnh"); return }
        shotItem = ShareItem(url: first, extra: Array(urls.dropFirst()))
    }
}

/// Dữ liệu một lần chụp cuộn-ghép: vẽ lại được ra ảnh PNG hoặc PDF.
struct FullShot {
    let width: CGFloat, total: CGFloat, headerH: CGFloat, contentH: CGFloat, footerH: CGFloat, ry: CGFloat, rh: CGFloat
    let first: UIImage
    let slices: [(off: CGFloat, img: UIImage)]
    let last: UIImage?

    /// Vẽ nội dung (không tô nền) theo toạ độ canvas 0...total.
    func draw(_ c: CGContext) {
        if headerH > 0 {
            c.saveGState(); c.clip(to: CGRect(x: 0, y: 0, width: width, height: headerH))
            first.draw(at: .zero); c.restoreGState()
        }
        // thân: mỗi đoạn vẽ cắt đúng vùng cuộn, đoạn sau đè lên đoạn trước
        for s in slices {
            c.saveGState()
            c.clip(to: CGRect(x: 0, y: headerH + s.off, width: width, height: rh))
            s.img.draw(at: CGPoint(x: 0, y: s.off))
            c.restoreGState()
        }
        if footerH > 1, let l = last {
            let originY = headerH + contentH - (ry + rh)
            c.saveGState(); c.clip(to: CGRect(x: 0, y: total - footerH, width: width, height: footerH))
            l.draw(at: CGPoint(x: 0, y: originY)); c.restoreGState()
        }
    }

    /// PNG: giảm độ phân giải khi trang quá dài (giới hạn cạnh 16000 px và ~60 triệu điểm ảnh).
    func image() -> UIImage {
        var scale = UIScreen.main.scale
        scale = min(scale, 16000 / max(total, 1))
        scale = min(scale, (60_000_000 / (width * max(total, 1))).squareRoot())
        scale = max(scale, 0.5)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale; fmt.opaque = true
        let size = CGSize(width: width, height: total)
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            draw(ctx.cgContext)
        }
    }

    /// PDF: ảnh các đoạn được nhúng nguyên độ phân giải gốc; trang dài hơn 14.000 pt tự chia thành nhiều trang (giới hạn của PDF ~14.400 pt).
    func writePDF(to url: URL) -> Bool {
        let pageMax: CGFloat = 14000
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: width, height: min(total, pageMax)))
        do {
            try renderer.writePDF(to: url) { ctx in
                var y0: CGFloat = 0
                repeat {
                    let ph = min(pageMax, total - y0)
                    ctx.beginPage(withBounds: CGRect(x: 0, y: 0, width: width, height: ph), pageInfo: [:])
                    let c = ctx.cgContext
                    c.saveGState()
                    c.clip(to: CGRect(x: 0, y: 0, width: width, height: ph))
                    UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: width, height: ph))
                    c.translateBy(x: 0, y: -y0)
                    draw(c)
                    c.restoreGState()
                    y0 += ph
                } while y0 < total - 0.5
            }
            return true
        } catch { return false }
    }
}

// MARK: - Chẩn đoán giao diện (Cài đặt > Nâng cao > Chẩn đoán giao diện)
// Đi qua từng khung (iframe cùng domain) của trang đang mở và báo: script của app đã chạy chưa, CSS còn hay bị DESM xoá,
// lưới Package đã dựng thẻ chưa... Chỉ ĐỌC, không sửa gì (trừ nút "Áp lại ngay" do người dùng bấm). Không gửi dữ liệu đi đâu.

struct DesmDiagFrame: Identifiable {
    let id = UUID()
    let path: String, url: String, ready: String, mode: String, styleState: String
    let blocked: Bool, scriptRan: Bool, hasClass: Bool, hasApplyAll: Bool
    let grids: Int, pkgGrid: Bool, cards: Int, hidden: Bool

    init(_ d: [String: Any]) {
        path = d["path"] as? String ?? "?"; url = d["url"] as? String ?? ""; ready = d["ready"] as? String ?? ""
        mode = d["mode"] as? String ?? ""; styleState = d["style"] as? String ?? ""
        blocked = d["blocked"] as? Bool ?? false; scriptRan = d["ran"] as? Bool ?? false
        hasClass = d["cls"] as? Bool ?? false; hasApplyAll = d["apply"] as? Bool ?? false
        grids = d["grids"] as? Int ?? 0; pkgGrid = d["pkg"] as? Bool ?? false
        cards = d["cards"] as? Int ?? -1; hidden = d["hidden"] as? Bool ?? false
    }

    /// Các điểm bất thường (rỗng = khung này ổn).
    var problems: [String] {
        if blocked { return hidden ? [] : ["Khung khác domain hoặc chưa tải, app không đọc được"] }
        var p: [String] = []
        if !scriptRan { p.append("Script của app CHƯA chạy trong khung này (nếu màn hình hỏng, đây là nghi phạm số 1)"); return p }
        if mode == "mobile" {
            if styleState == "missing" { p.append("CSS giao diện điện thoại đã bị xoá khỏi khung (DESM xoá style) — bấm \"Áp lại ngay\"") }
            if styleState == "outdated" { p.append("CSS trong khung khác bản hiện tại của app") }
            if !hasClass { p.append("Thiếu class desm-mobile-mode trên <html>") }
        }
        if !hasApplyAll { p.append("Hàm tự áp lại (__desmApplyAll) không có") }
        if mode == "mobile" && pkgGrid && cards < 0 { p.append("Có lưới Package nhưng chưa dựng danh sách thẻ") }
        return p
    }
}

extension BrowserModel {
    static let diagJS = #"""
    (function() {
      var ID = 'desm-mobile-custom-style', CLS = 'desm-mobile-mode', out = [];
      function walk(win, path, depth, hidden) {
        var r = { path: path, depth: depth, hidden: !!hidden };
        try {
          var doc = win.document; void doc.documentElement;
          var loc = win.location, m = /MENU_SEQ=\d+/.exec(loc.search || '');
          r.url = (loc.pathname || '') + (m ? '?' + m[0] : '');
          r.ready = doc.readyState;
          var cfg = win.__desmCfg; r.ran = !!cfg; r.mode = cfg ? String(cfg.mode || '') : '';
          var st = doc.getElementById(ID);
          r.style = !st ? 'missing' : (cfg && st.textContent !== cfg.css ? 'outdated' : 'ok');
          r.cls = doc.documentElement.classList.contains(CLS);
          r.apply = typeof win.__desmApplyAll === 'function';
          var n = 0, pk = false;
          try {
            var L = win.TGGrids || [];
            for (var i = 0; i < L.length; i++) {
              var g = L[i];
              if (g && g.MainTag && doc.documentElement.contains(g.MainTag)) { n++; if (g.Cols && g.Cols.PACKAGE_NO && g.Cols.STORAGE_LOCATION) pk = true; }
            }
          } catch (e) {}
          r.grids = n; r.pkg = pk;
          var cb = doc.getElementById('desmCards'); r.cards = cb ? cb.querySelectorAll('.desm-card').length : -1;
          out.push(r);
          var fs = doc.querySelectorAll('iframe,frame');
          for (var j = 0; j < fs.length; j++) {
            var f = fs[j], nm = f.id || f.name || ('#' + j), hid = f.offsetWidth === 0 || f.offsetHeight === 0 || f.id === 'desmDetailFrame';
            var cw = null; try { cw = f.contentWindow; void cw.document.documentElement; } catch (e) { cw = null; }
            if (cw) walk(cw, path + ' › ' + nm, depth + 1, hid);
            else out.push({ path: path + ' › ' + nm, depth: depth + 1, blocked: true, hidden: hid, url: String(f.getAttribute('src') || '').split('?')[0] });
          }
        } catch (e) { r.blocked = true; out.push(r); }
      }
      walk(window, 'Trang chính', 0, false);
      return JSON.stringify({ frames: out });
    })();
    """#

    @MainActor
    func runDiagnostics() async -> [DesmDiagFrame]? {
        guard let wv = webView else { return nil }
        let s: String? = await withCheckedContinuation { c in
            wv.evaluateJavaScript(BrowserModel.diagJS) { r, _ in c.resume(returning: r as? String) }
        }
        guard let s = s, let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
              let arr = o["frames"] as? [[String: Any]] else { return nil }
        return arr.map { DesmDiagFrame($0) }
    }
}

struct DesmDiagView: View {
    @ObservedObject var model: BrowserModel
    @State private var frames: [DesmDiagFrame] = []
    @State private var loading = true
    @State private var failed = false

    var issueCount: Int { frames.reduce(0) { $0 + $1.problems.count } }

    var report: String {
        var t = "DESM — chẩn đoán giao diện (\(Date()))\n"
        for f in frames {
            t += "\n[\(f.path)] \(f.url) ready=\(f.ready) chạyScript=\(f.scriptRan) mode=\(f.mode) css=\(f.styleState) class=\(f.hasClass) áp lại=\(f.hasApplyAll) lưới=\(f.grids) lướiPackage=\(f.pkgGrid) thẻ=\(f.cards)"
            if f.blocked { t += " (không đọc được)" }
            for p in f.problems { t += "\n  ! \(p)" }
        }
        return t
    }

    func load() async {
        loading = true
        if let r = await model.runDiagnostics() { frames = r; failed = false } else { frames = []; failed = true }
        loading = false
    }

    func mark(_ title: String, _ ok: Bool?, _ detail: String = "") -> some View {
        HStack {
            Image(systemName: ok == nil ? "minus.circle" : (ok! ? "checkmark.circle.fill" : "xmark.octagon.fill"))
                .foregroundColor(ok == nil ? .gray : (ok! ? .green : .red))
            Text(title)
            Spacer()
            if !detail.isEmpty { Text(detail).foregroundColor(.secondary).font(.footnote) }
        }
    }

    var body: some View {
        List {
            Section {
                if loading { HStack { ProgressView(); Text("Đang kiểm tra…") } }
                else if failed { Text("Chưa có trang để kiểm tra. Hãy mở màn hình DESM rồi vào lại đây.").foregroundColor(.secondary) }
                else if issueCount == 0 { Label("Không thấy bất thường ở \(frames.count) khung", systemImage: "checkmark.seal.fill").foregroundColor(.green) }
                else { Label("\(issueCount) điểm bất thường — xem các khung bên dưới", systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange) }
            } footer: {
                Text("Chẩn đoán đọc màn hình đang mở phía sau Cài đặt. Nên mở đúng màn hình đang hỏng rồi vào đây. Chỉ đọc, không gửi dữ liệu đi đâu.")
            }
            ForEach(frames) { f in
                Section {
                    if f.blocked {
                        mark("Đọc được khung", f.hidden ? nil : false, f.hidden ? "ẩn" : "")
                    } else {
                        mark("Script của app đã chạy", f.scriptRan)
                        if f.scriptRan {
                            mark("CSS giao diện còn trong khung", f.mode == "mobile" ? f.styleState == "ok" : nil, f.mode == "mobile" ? "" : "chế độ \(f.mode)")
                            mark("Class desm-mobile-mode", f.mode == "mobile" ? f.hasClass : nil)
                            mark("Tự áp lại sẵn sàng", f.hasApplyAll)
                            if f.grids > 0 { mark("Lưới TreeGrid", true, "\(f.grids) lưới") }
                            if f.pkgGrid { mark("Danh sách thẻ Package", f.cards >= 0, f.cards >= 0 ? "\(f.cards) thẻ" : "chưa dựng") }
                        }
                    }
                    ForEach(f.problems, id: \.self) { Text($0).font(.footnote).foregroundColor(.red) }
                } header: {
                    Text(f.path + (f.url.isEmpty ? "" : "  ·  " + f.url) + (f.hidden ? "  (khung ẩn)" : ""))
                        .textCase(nil)
                }
            }
            Section {
                Button("Áp lại giao diện ngay") {
                    model.applyStyles()
                    Task { try? await Task.sleep(nanoseconds: 900_000_000); await load() }
                }
                Button("Sao chép báo cáo") {
                    UIPasteboard.general.string = report
                    model.showToast("Đã sao chép báo cáo chẩn đoán")
                }.disabled(frames.isEmpty)
            }
        }
        .navigationTitle("Chẩn đoán giao diện")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Chạy lại") { Task { await load() } } } }
        .task { await load() }
    }
}
