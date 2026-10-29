// PageSnapshot.swift — chụp ảnh toàn bộ trang.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Chụp ảnh toàn bộ trang
//
// Cách làm: (1) tạm mở rộng các khung cuộn bên trong trang (iframe, vùng overflow auto/scroll/hidden) cho hiện hết chiều cao;
// (2) WKWebView.createPDF với vùng = toàn bộ nội dung cuộn; (3) vẽ trang PDF thành ảnh PNG (giới hạn ~12 000 px cạnh dài, ~80 triệu điểm ảnh);
// (4) khôi phục kiểu cũ của trang. Trang quá dài để thành PNG thì xuất PDF. Lưu ý: bảng TreeGrid chỉ vẽ các dòng đang hiển thị (cuộn ảo)
// nên các dòng chưa cuộn tới có thể không có trong ảnh.
extension BrowserModel {
    static let shotExpandJS = #"""
    (function() {
      var saved = window.__desmShotSaved = [];
      function fix(doc, lvl) {
        var els = doc.querySelectorAll('*'), n = Math.min(els.length, 20000);
        for (var i = 0; i < n; i++) {
          var e = els[i], t = e.tagName;
          if (t === 'HTML' || t === 'BODY' || t === 'IFRAME' || t === 'FRAME') continue;
          if (e.clientHeight > 80 && e.scrollHeight > e.clientHeight + 20) {
            var cs = doc.defaultView.getComputedStyle(e);
            if (/(auto|scroll|hidden)/.test(cs.overflowY)) {
              saved.push([e, e.style.cssText]);
              e.style.setProperty('height', 'auto', 'important');
              e.style.setProperty('max-height', 'none', 'important');
              e.style.setProperty('overflow', 'visible', 'important');
            }
          }
        }
        if (lvl > 3) return;
        var fs = doc.querySelectorAll('iframe,frame');
        for (var j = 0; j < fs.length; j++) {
          try {
            var d = fs[j].contentDocument;
            if (d && d.documentElement && d.location.origin === location.origin) {
              fix(d, lvl + 1);
              var h = Math.max(d.documentElement.scrollHeight, d.body ? d.body.scrollHeight : 0);
              if (h > fs[j].clientHeight) {
                saved.push([fs[j], fs[j].style.cssText]);
                fs[j].style.setProperty('height', h + 'px', 'important');
                fs[j].style.setProperty('min-height', h + 'px', 'important');
                fs[j].setAttribute('scrolling', 'no');
              }
            }
          } catch (e) {}
        }
      }
      try { fix(document, 0); } catch (e) {}
      return saved.length;
    })();
    """#

    static let shotRestoreJS = #"""
    (function() {
      var s = window.__desmShotSaved || [];
      for (var i = s.length - 1; i >= 0; i--) { try { s[i][0].style.cssText = s[i][1]; } catch (e) {} }
      window.__desmShotSaved = [];
    })();
    """#

    func captureFullPage() {
        guard let wv = webView else { showToast("Chưa có trang để chụp"); return }
        showToast("Đang chụp toàn trang…")
        wv.evaluateJavaScript(BrowserModel.shotExpandJS) { _, _ in
            // chờ trang dàn lại bố cục sau khi mở rộng
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let size = wv.scrollView.contentSize
                guard size.width > 1, size.height > 1 else {
                    wv.evaluateJavaScript(BrowserModel.shotRestoreJS, completionHandler: nil)
                    self.showToast("Không đo được kích thước trang"); return
                }
                let cfg = WKPDFConfiguration()
                cfg.rect = CGRect(origin: .zero, size: size)
                wv.createPDF(configuration: cfg) { result in
                    wv.evaluateJavaScript(BrowserModel.shotRestoreJS, completionHandler: nil)
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let data): self.finishShot(pdf: data)
                        case .failure(let e): self.showToast("Không chụp được: \(e.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    func finishShot(pdf: Data) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: Date())
        let tmp = FileManager.default.temporaryDirectory
        func sharePDF(_ note: String) {
            let url = tmp.appendingPathComponent("desm-page-\(stamp).pdf")
            do { try pdf.write(to: url); showToast(note); shotItem = ShareItem(url: url) }
            catch { showToast("Không lưu được file: \(error.localizedDescription)") }
        }
        guard let provider = CGDataProvider(data: pdf as CFData), let doc = CGPDFDocument(provider), let page = doc.page(at: 1) else {
            sharePDF("Không dựng được ảnh, xuất PDF"); return
        }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 1, box.height > 1 else { sharePDF("Không dựng được ảnh, xuất PDF"); return }
        var scale = UIScreen.main.scale
        scale = min(scale, 12000 / max(box.width, box.height))
        scale = min(scale, (80_000_000 / (box.width * box.height)).squareRoot())
        if scale < 0.4 { sharePDF("Trang quá dài để thành ảnh, đã xuất PDF"); return }
        let outSize = CGSize(width: (box.width * scale).rounded(), height: (box.height * scale).rounded())
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1; fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: outSize, format: fmt).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: outSize))
            let c = ctx.cgContext
            c.translateBy(x: 0, y: outSize.height)
            c.scaleBy(x: scale, y: -scale)
            c.translateBy(x: -box.minX, y: -box.minY)
            c.drawPDFPage(page)
        }
        guard let png = img.pngData() else { sharePDF("Không tạo được PNG, đã xuất PDF"); return }
        let url = tmp.appendingPathComponent("desm-page-\(stamp).png")
        do { try png.write(to: url); shotItem = ShareItem(url: url) }
        catch { showToast("Không lưu được file: \(error.localizedDescription)") }
    }
}
