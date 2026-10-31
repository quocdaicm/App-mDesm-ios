// UserScript.swift — makeScript(): TOÀN BỘ JS giao diện tiêm vào mọi frame của DESM (xem chỉ mục JS ở DEV_NOTES §4).

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

extension BrowserModel {
    // MARK: - Tiêm giao diện

    /// JS idempotent: áp/gỡ CSS + viewport cho tài liệu hiện tại và iframe cùng origin,
    /// tự áp lại nếu trang xóa style/class/viewport hoặc tạo iframe mới (mở tab).
    func makeScript() -> String {
        let config: [String: Any] = [
            "mode": layoutMode.rawValue,
            "fitWidth": fitWidth,
            "scope": scopeOnly,
            "hosts": BrowserModel.allowedHosts,
            "css": MobileStyles.css + "\n" + customCSS,
            "vi": viLang,
            "dict": ViDict.pairs,
            "custom": customPairs
        ]
        let json = (try? JSONSerialization.data(withJSONObject: config, options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"mode\":\"off\"}"
        return UserJS.head(json) + "\n" + UserJS.all.joined(separator: "\n")
    }
}

/// JS giao diện được chia thành nhiều phần (file JS*.swift). `all` là thứ tự ghép — KHÔNG đổi thứ tự khi chưa kiểm tra:
/// các biến mức trên cùng (vd `var CTL`, `var DI_HIDE`) phải được khai báo trước khi hàm dùng chúng chạy.
enum UserJS {
    static var all: [String] {
        [ui, gridItems, detail, pkgCards, genericCards, chrome, viet, scan, tail]
    }

    static func head(_ json: String) -> String {
        #"""
        (function() {
          /* CHỈ MỤC (chi tiết trong DEV_NOTES.md §4)
             Giao diện : allowed, setViewport, navHandlers, addFilterBar, buildForm, formify, fixMaps, slimHeader, defaultToolbar, modalLock
             Lưới      : gridText, colShown, compactGrid, pkgGridOf, genGridOf, genericCards, cardView, openDetail, colToggle
             Hạng mục  : diLoadFast (API /getIdsmOsDetailList.do) -> diLoad (khung ẩn MENU_SEQ=197, cách cũ), diSelect, diShow, diWarm
             Quét      : __desmFindPkg/findPkgIn, __desmFindDetail/findDetailIn (QR: tra Material Code), ensurePkgDoc
             Việt hoá  : vi* (viMap, viText, viWalk, viApply...)   Đăng nhập: findUser, __desmFill, credHook
             Vòng áp   : apply, applyAll, __desmApplyAll, __desmRevert (script tự áp lại khi trang xoá style/tạo iframe mới) */
          var w = window;
          w.__desmCfg = \#(json);
          var ID = 'desm-mobile-custom-style', CLS = 'desm-mobile-mode';
          var VP = 'width=device-width, initial-scale=1, viewport-fit=cover';
        """#
    }

    /// Vòng áp lại (apply/applyAll/__desmRevert), quan sát DOM và đóng IIFE
    static let tail = #"""
          function enhance(doc) { navHandlers(doc); formify(doc); fixMaps(doc); try { colToggle(doc); } catch (e) {} }
          function apply(doc) {
            var root = doc.documentElement; if (!root) return;
            var c = w.__desmCfg;
            var mobile = c.mode === 'mobile' && allowed(doc);
            var style = doc.getElementById(ID);
            if (mobile) {
              if (!style) {
                style = doc.createElement('style'); style.id = ID; style.textContent = c.css;
                root.appendChild(style);
              } else if (style.textContent !== c.css) { style.textContent = c.css; }
              if (!root.classList.contains(CLS)) root.classList.add(CLS);
              if (w === w.top && !root.classList.contains('desm-top')) root.classList.add('desm-top');
              enhance(doc);
            } else {
              if (style) style.remove();
              if (root.classList.contains(CLS)) root.classList.remove(CLS);
              if (root.classList.contains('desm-top')) root.classList.remove('desm-top');
              if (root.classList.contains('desm-nav-open')) root.classList.remove('desm-nav-open');
            }
            if (doc === document && w === w.top) setViewport(doc);
            viApply(doc);
          }
          function applyAll(doc) {
            apply(doc);
            var fs = doc.querySelectorAll('iframe,frame');
            for (var i = 0; i < fs.length; i++) {
              try { var d = fs[i].contentDocument; if (d) applyAll(d); } catch (e) {}
            }
          }
          w.__desmApplyAll = function() { applyAll(document); };
          // Rời chế độ Mobile: tải lại khung nào đã bị sắp xếp lại biểu mẫu để trở về bố cục gốc.
          w.__desmRevert = function() {
            (function r(doc) {
              try {
                if (doc.querySelector('[data-desm-form]')) { doc.defaultView.location.reload(); return; }
                var fs = doc.querySelectorAll('iframe,frame');
                for (var i = 0; i < fs.length; i++) {
                  try { if (fs[i].contentDocument) r(fs[i].contentDocument); } catch (e) {}
                }
              } catch (e) {}
            })(document);
          };
          w.__desmApplyAll();
          if (w.__desmCfg.vi) { try { viInit(); } catch (e) {} }

          if (!w.__desmInit) {
            w.__desmInit = true;
            try { w.setInterval(function() { try { modalLock(document); } catch (e) {} }, 250); } catch (e) {}
            try {
              new MutationObserver(function() { apply(document); }).observe(document.documentElement,
                { attributes: true, attributeFilter: ['class'], childList: true });
            } catch (e) {}
            var watch = function(f) {
              if (f.__desmW) return; f.__desmW = 1;
              f.addEventListener('load', function() { try { if (f.contentDocument) applyAll(f.contentDocument); } catch (e) {} });
              try { if (f.contentDocument && f.contentDocument.readyState !== 'loading') applyAll(f.contentDocument); } catch (e) {}
            };
            var lastForm = 0, trail = 0;
            var scan = function() {
              try { credHook(document); } catch (e) {}
              if (w.__desmCfg.mode === 'mobile' && allowed(document)) {
                var now = Date.now();
                if (now - lastForm > 400) { lastForm = now; navHandlers(document); formify(document); fixMaps(document); try { colToggle(document); } catch (e) {} }
                else if (!trail) {
                  // Lần quét bị bỏ qua do giới hạn 400ms: hẹn quét bù, nếu không lưới nạp muộn sẽ lộ khung bảng xanh cho tới khi có thay đổi DOM khác
                  trail = w.setTimeout(function() { trail = 0; try { schedule(); } catch (e) {} }, 450);
                }
              }
              var fs = document.querySelectorAll('iframe,frame');
              for (var i = 0; i < fs.length; i++) watch(fs[i]);
            };
            var queued = false;
            var schedule = function() {
              if (queued) return; queued = true;
              (w.requestAnimationFrame || w.setTimeout)(function() { queued = false; scan(); });
            };
            try {
              new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
            } catch (e) {}
            document.addEventListener('DOMContentLoaded', function() {
              scan(); applyAll(document);
              [1000, 2500, 5000].forEach(function(ms) { w.setTimeout(function() { try { schedule(); } catch (e) {} }, ms); });
              if (document.head) {
                try { new MutationObserver(function() { setViewport(document); })
                  .observe(document.head, { childList: true }); } catch (e) {}
              }
            });
          }
        })();
        """#
}
