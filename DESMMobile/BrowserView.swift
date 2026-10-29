// BrowserView.swift — file trung tâm của app DESM Mobile.
//  1) LayoutMode + BrowserModel: trạng thái app, cài đặt (@AppStorage), tạo và cài script tiêm vào trang.
//  2) makeScript(): TOÀN BỘ JS tiêm vào mọi frame của DESM (giao diện mobile, lưới dạng thẻ, danh sách hạng mục, quét, Việt hoá).
//     Chỉ mục hàm JS ở đầu script và trong DEV_NOTES.md §4.
//  3) Tiện ích lấy HTML/script/nhật ký API/nội dung URL (phục vụ tinh chỉnh) — cuối file.
//  4) BrowserView (thanh trên/dưới, nút nổi, quét) và SettingsView (Cài đặt).
// Quy ước: JS nằm trong chuỗi thô #""" """# (viết \s, \n như JS thường; nội suy Swift là \#( )); mọi script phải idempotent.
// Xem DEV_NOTES.md để biết những điều đã biết/chưa kiểm chứng về web DESM.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

enum LayoutMode: String, CaseIterable, Identifiable {
    case mobile, fit, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mobile: return "Mobile (sắp xếp lại)"
        case .fit: return "Thu nhỏ vừa màn hình"
        case .off: return "Giao diện gốc"
        }
    }
    var shortTitle: String {
        switch self {
        case .mobile: return "Mobile"
        case .fit: return "Vừa màn hình"
        case .off: return "Gốc"
        }
    }
    var symbol: String {
        switch self {
        case .mobile: return "iphone.gen3"
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .off: return "desktopcomputer"
        }
    }
    var next: LayoutMode {
        switch self {
        case .mobile: return .fit
        case .fit: return .off
        case .off: return .mobile
        }
    }
}

/// Trạng thái trung tâm: địa chỉ, tiến trình, chế độ hiển thị, cài đặt (CSS bổ sung, từ điển, Việt hoá), tham chiếu tới
/// WKWebView/WKUserContentController. Tạo script tiêm (makeScript) và cài vào trang (installUserScript/evaluateNow).
final class BrowserModel: ObservableObject {
    static let homeURL = "https://desm.doosanenerbility.com/main.do?lang=en"
    /// Chỉ áp dụng giao diện cho các domain này khi bật "Chỉ áp dụng cho DESM".
    static let allowedHosts = ["doosanenerbility.com"]

    @Published var address = BrowserModel.homeURL
    @Published var pageTitle = "DESM Mobile"
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var showSettings = false
    @Published var shotItem: ShareItem?      // ảnh chụp toàn trang chờ chia sẻ/lưu
    @Published var errorMessage: String?
    @Published var toast: String?
    /// Hàng đợi hộp thoại tự vẽ (alert/confirm của trang, hỏi lưu tài khoản...): hiện cái đầu tiên ở đáy màn hình.
    @Published var dialogQueue: [DesmDialogState] = []
    func presentDialog(_ s: DesmDialogState) { dialogQueue.append(s) }
    func finishDialog() { if !dialogQueue.isEmpty { dialogQueue.removeFirst() } }
    /// Ẩn thanh trên + thanh dưới (tự ẩn khi vào được trang DESM, bấm nút nổi để hiện lại)
    @Published var barsHidden = false
    private var wasInDesm = false
    // Tự kết nối lại khi hết phiên đăng nhập (xem extension "Tự kết nối lại" bên dưới)
    var reconnecting = false          // đang trong quá trình đăng nhập lại tự động
    var autoSubmitCount = 0           // số lần tự bấm Login trong lần kết nối lại này
    var reconnectTimes: [Date] = []   // các lần kết nối lại gần đây (chặn lặp vô hạn)
    var lastReconnectAt: Date?
    var backgroundedAt: Date?         // lúc app xuống nền
    /// Đang ở trong DESM (không phải trang đăng nhập): dùng để hiện nút quét camera
    @Published var inDesm = false
    /// Số thông báo DESM chưa mở (hiện chấm đỏ trên nút "Thêm" và số trên icon app).
    @Published var unreadNotices = 0

    /// Gọi sau mỗi lần tải xong trang: vừa vào được DESM (không phải trang đăng nhập) thì tự ẩn thanh; rời DESM thì hiện lại.
    func updateBars(for url: URL?) {
        let host = url?.host?.lowercased() ?? ""
        let path = url?.path.lowercased() ?? ""
        let inDesm = BrowserModel.allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) } && !path.contains("login")
        if inDesm && !wasInDesm { withAnimation(.easeInOut(duration: 0.2)) { barsHidden = true } }
        if !inDesm && barsHidden { withAnimation(.easeInOut(duration: 0.2)) { barsHidden = false } }
        if self.inDesm != inDesm { self.inDesm = inDesm }
        wasInDesm = inDesm
    }

    @Published var layoutMode: LayoutMode {
        didSet { UserDefaults.standard.set(layoutMode.rawValue, forKey: "desmLayoutMode") }
    }
    @Published var fitWidth: Int {
        didSet { UserDefaults.standard.set(fitWidth, forKey: "desmFitWidth") }
    }
    @Published var scopeOnly: Bool {
        didSet { UserDefaults.standard.set(scopeOnly, forKey: "desmScopeOnly") }
    }
    @Published var compactHeader: Bool {
        didSet { UserDefaults.standard.set(compactHeader, forKey: "desmCompactHeader") }
    }
    @AppStorage("desmCustomCSS") var customCSS = ""
    @AppStorage("desmCustomDict") var customDict = ""
    /// Dịch giao diện web DESM sang tiếng Việt (lớp dịch phía app, không đổi ngôn ngữ phía máy chủ)
    @Published var viLang: Bool {
        didSet { UserDefaults.standard.set(viLang, forKey: "desmViLang") }
    }

    weak var webView: WKWebView?
    weak var contentController: WKUserContentController?

    init() {
        let ud = UserDefaults.standard
        layoutMode = LayoutMode(rawValue: ud.string(forKey: "desmLayoutMode") ?? "") ?? .mobile
        let w = ud.integer(forKey: "desmFitWidth")
        fitWidth = w == 0 ? 1280 : w
        scopeOnly = ud.object(forKey: "desmScopeOnly") as? Bool ?? true
        compactHeader = ud.object(forKey: "desmCompactHeader") as? Bool ?? true
        viLang = ud.object(forKey: "desmViLang") as? Bool ?? false
    }

    /// Bật/tắt tiếng Việt. fromPage = true khi người dùng chọn trong ô Language của trang (trang tự tải lại theo ngôn ngữ máy chủ).
    func setVietnamese(_ on: Bool, fromPage: Bool = false) {
        guard viLang != on else { return }
        viLang = on
        applyStyles()
        if !on && !fromPage { webView?.reload() }   // tắt dịch: tải lại để trả về chữ gốc
    }

    private var customPairs: [[String]] {
        customDict.split(whereSeparator: \.isNewline).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { return nil }
            guard let i = t.firstIndex(of: "=") else { return nil }
            let k = t[..<i].trimmingCharacters(in: .whitespaces)
            let v = t[t.index(after: i)...].trimmingCharacters(in: .whitespaces)
            return (k.isEmpty || v.isEmpty) ? nil : [k, v]
        }
    }

    func loadAddress() {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { errorMessage = "Vui lòng nhập địa chỉ website."; return }
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = url.host, host.contains(".") else {
            errorMessage = "Địa chỉ không hợp lệ. Hãy nhập URL dạng https://example.com"
            return
        }
        address = url.absoluteString
        webView?.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45))
    }

    func navigate(_ url: URL) {
        address = url.absoluteString
        webView?.load(URLRequest(url: url, timeoutInterval: 45))
    }
    func reload() { webView?.reload() }
    func goBack() {
        webView?.evaluateJavaScript("window.__desmBack ? window.__desmBack() : 0;") { [weak self] r, _ in
            if (r as? Int ?? 0) == 1 { return }
            if self?.webView?.canGoBack == true { self?.webView?.goBack() }
        }
    }
    func goForward() { if webView?.canGoForward == true { webView?.goForward() } }
    func home() {
        address = BrowserModel.homeURL
        loadAddress()
    }

    func setMode(_ mode: LayoutMode) {
        let old = layoutMode
        layoutMode = mode
        applyStyles()
        if old == .mobile && mode != .mobile {
            webView?.evaluateJavaScript("window.__desmRevert && window.__desmRevert();", completionHandler: nil)
        }
    }

    func cycleMode() {
        setMode(layoutMode.next)
        showToast(layoutMode.title)
    }

    /// Footer 5 tab: mở mục menu DESM tương ứng; không tìm thấy thì mở ngăn kéo menu để người dùng tự chọn.
    func openDesmTab(_ tab: DesmTab) {
        func q(_ v: String?) -> String { v.map { "'\($0)'" } ?? "null" }
        let js = "window.__desmOpenMenu ? window.__desmOpenMenu(\(q(tab.menuId)), '\(tab.pattern)') : 0;"
        webView?.evaluateJavaScript(js) { [weak self] r, _ in
            if (r as? Int ?? 0) == 0 {
                self?.webView?.evaluateJavaScript("window.__desmToggleDrawer && window.__desmToggleDrawer();", completionHandler: nil)
                self?.showToast("Chọn mục “\(tab.title)” trong menu")
            }
        }
    }

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    // MARK: - Tiêm giao diện

    /// JS idempotent: áp/gỡ CSS + viewport cho tài liệu hiện tại và iframe cùng origin,
    /// tự áp lại nếu trang xóa style/class/viewport hoặc tạo iframe mới (mở tab).
    private func makeScript() -> String {
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
        return #"""
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

          function allowed(doc) {
            var c = w.__desmCfg;
            if (!c.scope) return true;
            var h = '';
            try {
              h = (doc.location.hostname || '').toLowerCase();
              if (!h && w.parent !== w) h = (w.parent.location.hostname || '').toLowerCase();
            } catch (e) {}
            return c.hosts.some(function(s) { return h === s || h.endsWith('.' + s); });
          }
          function setViewport(doc) {
            var c = w.__desmCfg;
            var head = doc.head; if (!head) return;
            var on = c.mode !== 'off' && allowed(doc);
            var want = c.mode === 'fit' ? ('width=' + c.fitWidth + ', viewport-fit=cover') : VP;
            var m = doc.querySelector('meta[name="viewport"]');
            if (on) {
              if (!m) {
                m = doc.createElement('meta'); m.name = 'viewport';
                m.setAttribute('data-desm', '1'); m.content = want; head.appendChild(m);
              } else if (m.content !== want) {
                if (!m.hasAttribute('data-desm-orig')) m.setAttribute('data-desm-orig', m.content);
                m.content = want;
              }
            } else if (m) {
              if (m.getAttribute('data-desm') === '1') { m.remove(); }
              else if (m.hasAttribute('data-desm-orig')) {
                m.content = m.getAttribute('data-desm-orig'); m.removeAttribute('data-desm-orig');
              }
            }
          }
          function navHandlers(doc) {
            if (doc.__desmNav || !doc.getElementById('accordionSidebar')) return;
            doc.__desmNav = true;
            var root = doc.documentElement;
            doc.addEventListener('click', function(e) {
              var c = w.__desmCfg;
              if (!(c.mode === 'mobile' && allowed(doc))) return;
              var t = e.target;
              if (!t || !t.closest) return;
              if (t.closest('#sidebarToggleTop')) {
                e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
                root.classList.toggle('desm-nav-open');
                return;
              }
              if (!root.classList.contains('desm-nav-open')) return;
              if (!t.closest('#accordionSidebar')) { root.classList.remove('desm-nav-open'); return; }
              var a = t.closest('a');
              if (a && (a.classList.contains('collapse-item') ||
                  (a.classList.contains('nav-link') && !a.hasAttribute('data-toggle')))) {
                setTimeout(function() { root.classList.remove('desm-nav-open'); }, 0);
              }
            }, true);
          }
          var CTL = 'input:not([type=hidden]),select,textarea';
          function activeCount(t) {
            var n = 0;
            [].forEach.call(t.querySelectorAll('input:not([type=hidden]):not([type=checkbox]):not([type=radio]),select,textarea'), function(c) {
              if (c.readOnly || c.disabled) return;
              if (c.tagName === 'SELECT') {
                if (c.multiple) { if (c.selectedOptions && c.selectedOptions.length) n++; }
                else if (c.value !== '') n++;
              } else if ((c.value || '').trim()) n++;
            });
            return n;
          }
          function addFilterBar(doc, t) {
            var outer = t.parentElement ? t.parentElement.closest('table') : null;
            var anchor = outer || t;
            var host = anchor.parentNode; if (!host) return;
            var bar = doc.createElement('div'); bar.className = 'desm-filter-bar';
            var tg = doc.createElement('button'); tg.type = 'button'; tg.className = 'desm-filter-toggle';
            var lab = doc.createElement('span'); var chev = doc.createElement('span');
            tg.appendChild(lab); tg.appendChild(chev);
            var bx = doc.createElement('div'); bx.className = 'desm-btns';
            bar.appendChild(tg); bar.appendChild(bx);
            if (outer) {
              [].filter.call(outer.querySelectorAll('button'), function(b) { return !t.contains(b); })
                .forEach(function(b) { bx.appendChild(b); });
            }
            // Hàng tìm nhanh: Packing List No. + Package No. luôn hiện ở đầu, đồng bộ với ô trong bộ lọc
            function pick(re) {
              var rows = t.querySelectorAll('tr.desm-field');
              for (var i = 0; i < rows.length; i++) {
                var lb = rows[i].querySelector('td.desm-lbl');
                if (lb && re.test((lb.textContent || '').replace(/\s+/g, ' ').trim())) {
                  var c = rows[i].querySelector('input:not([type=hidden]):not([type=checkbox]):not([type=radio])');
                  if (c) return { row: rows[i], ctl: c };
                }
              }
              return null;
            }
            var qp = pick(/^(packing\s*list\s*no|số packing list)/i), qk = pick(/^(package\s*no|số kiện hàng)/i);
            if (qp || qk) {
              var qr = doc.createElement('div'); qr.className = 'desm-quick';
              [[qp, 'Packing List No.'], [qk, 'Package No.']].forEach(function(pair) {
                var f = pair[0]; if (!f) return;
                var inp = doc.createElement('input'); inp.type = 'text'; inp.placeholder = pair[1];
                inp.setAttribute('autocomplete', 'off'); inp.setAttribute('enterkeyhint', 'search');
                inp.value = f.ctl.value || '';
                inp.addEventListener('input', function() {
                  f.ctl.value = inp.value;
                  ['input', 'change'].forEach(function(n) { f.ctl.dispatchEvent(new Event(n, { bubbles: true })); });
                });
                inp.addEventListener('keydown', function(e) {
                  if (e.key === 'Enter') { e.preventDefault(); var sb = bx.firstElementChild; if (sb) sb.click(); inp.blur(); }
                });
                var sync = function() { if (doc.activeElement !== inp) inp.value = f.ctl.value || ''; };
                f.ctl.addEventListener('input', sync); f.ctl.addEventListener('change', sync);
                f.row.classList.add('desm-dup');
                qr.appendChild(inp);
              });
              bar.appendChild(qr);
            }
            host.insertBefore(bar, anchor);
            if (outer) outer.classList.add('desm-outer');
            function setCollapsed(on) {
              t.classList.toggle('desm-collapsed', on);
              if (outer) outer.classList.toggle('desm-collapsed', on);
            }
            function refresh() {
              var n = activeCount(t);
              lab.textContent = 'Bộ lọc' + (n ? ' (' + n + ')' : '');
              chev.textContent = t.classList.contains('desm-collapsed') ? '▾' : '▴';
            }
            tg.addEventListener('click', function() { setCollapsed(!t.classList.contains('desm-collapsed')); refresh(); });
            t.addEventListener('change', refresh, true);
            t.addEventListener('input', refresh, true);
            bx.addEventListener('click', function(e) {
              var b = e.target.closest ? e.target.closest('button') : null;
              if (!b) return;
              if (b === bx.firstElementChild || /search/i.test(b.id || '')) {
                setTimeout(function() { setCollapsed(true); refresh(); }, 200);
              }
              setTimeout(refresh, 120);
            }, false);
            refresh();
          }
          function buildForm(doc, t) {
            var groups = [], cur = null;
            [].slice.call(t.rows).forEach(function(tr) {
              [].slice.call(tr.cells).forEach(function(td) {
                var hasCtl = !!td.querySelector(CTL);
                var txt = (td.textContent || '').replace(/\s+/g, ' ').trim();
                if (hasCtl) {
                  if (!cur) { cur = { lbl: null, ctl: [] }; groups.push(cur); }
                  cur.ctl.push(td);
                } else if (txt) {
                  cur = { lbl: td, ctl: [] }; groups.push(cur);
                } else {
                  td.classList.add('desm-empty');
                }
              });
            });
            var tb = doc.createElement('tbody'); tb.className = 'desm-tb';
            groups.forEach(function(g) {
              var tr = doc.createElement('tr'); tr.className = 'desm-field';
              if (g.lbl) { g.lbl.classList.add('desm-lbl'); tr.appendChild(g.lbl); }
              g.ctl.forEach(function(td) { tr.appendChild(td); });
              var wide = !g.ctl.length || g.ctl.length > 1 ||
                g.ctl.some(function(td) { return !!td.querySelector('select[multiple]'); });
              if (wide) tr.classList.add('desm-wide');
              tb.appendChild(tr);
            });
            [].forEach.call(t.tBodies, function(b) { b.classList.add('desm-orig'); });
            t.appendChild(tb);
            t.setAttribute('data-desm-form', '1');
            if (!t.closest('.modal') && t.querySelectorAll(CTL).length >= 6) {
              try { addFilterBar(doc, t); } catch (e) {}
            }
          }
          function formify(doc) {
            var ts = doc.querySelectorAll('table:not([data-desm-form]):not([data-desm-chk])');
            for (var n = 0; n < ts.length; n++) {
              var t = ts[n];
              if (/(^|\s)TM/.test(t.className || '') || t.querySelector('table,th')) {
                t.setAttribute('data-desm-chk', '1'); continue;
              }
              var nc = t.querySelectorAll(CTL).length;
              if (nc < 3) { if (nc > 0) t.setAttribute('data-desm-chk', '1'); continue; }
              try { buildForm(doc, t); } catch (e) { t.setAttribute('data-desm-chk', '1'); }
            }
          }
          function fixMaps(doc) {
            var dl = doc.querySelectorAll('.modal, .ui-dialog');
            for (var i = 0; i < dl.length; i++) {
              var im = dl[i].querySelectorAll('img,canvas,svg');
              for (var j = 0; j < im.length; j++) {
                var m = im[j], r;
                try { r = m.getBoundingClientRect(); } catch (e) { continue; }
                if (r.width < 160 || r.height < 100) continue;
                var box = m.parentElement; if (!box || box.hasAttribute('data-desm-map')) continue;
                box.setAttribute('data-desm-map', '1');
                var all = box.querySelectorAll('*');
                for (var k = 0; k < all.length; k++) {
                  var cs = null; try { cs = doc.defaultView.getComputedStyle(all[k]); } catch (e) {}
                  if (cs && (cs.position === 'absolute' || /^(area|rect|polygon|path|circle)$/i.test(all[k].tagName))) {
                    all[k].style.cursor = 'pointer';
                    all[k].style.touchAction = 'manipulation';
                  }
                }
              }
            }
          }
          // Lưới Package: chỉ giữ thanh chọn tất cả + Package No. + Location (Location đặt ngay cạnh Package No.)
          function gridText(G, row, c) {
            var t = '';
            try { if (G.GetString) t = G.GetString(row, c); } catch (e) {}
            if (!t) { try { t = G.GetValue ? G.GetValue(row, c) : row[c]; } catch (e) {} }
            return String(t == null ? '' : t).replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim();
          }
          function colShown(G, c) {
            var o = G.Cols[c]; if (!o) return false;
            return !(o.Visible === 0 || o.Visible === false || o.Visible === '0');
          }
          function compactGrid(win, on) {
            var list = win.TGGrids; if (!list || !list.length) return;
            for (var gi = 0; gi < list.length; gi++) {
              var G = list[gi];
              if (!G || !G.Cols || !G.Rows || !G.Rows.Header || G.__desmFail) continue;
              var keep = {}, found = 0;
              for (var c in G.Cols) {
                var tx = gridText(G, G.Rows.Header, c);
                if (/^package\s*no\.?$/i.test(tx)) { keep[c] = 'p'; found++; }
                else if (/^location$/i.test(tx)) { keep[c] = 'l'; found++; }
              }
              if (found < 2) continue;
              G.__desmTry = (G.__desmTry || 0);
              if (G.__desmTry > 12) continue;
              var changed = false;
              for (var c2 in G.Cols) {
                if (c2 === 'Panel' || c2 === 'Group' || keep[c2] !== undefined) continue;
                if (G.Cols[c2] && G.Cols[c2].CanHide === 0) continue;
                try {
                  var shown = colShown(G, c2);
                  if (on && shown) { G.HideCol(c2); changed = true; }
                  else if (!on && !shown) { G.ShowCol(c2); changed = true; }
                } catch (e) { G.__desmFail = 1; return; }
              }
              if (changed && on) G.__desmWDone = false;
              // Chia đều bề rộng khả dụng cho 2 cột để Package No. và Location nằm sát nhau, vừa màn hình dọc
              var main = G.MainTag || null, host = main ? main.parentNode : null;
              var cw = (host && host.clientWidth) ? host.clientWidth : 378, sc = 1;
              // Khung lưới đổi bề rộng (xoay màn hình...): báo cho TreeGrid tính lại kích thước
              if (host && host.clientWidth && G.__desmHW !== host.clientWidth) {
                var firstW = G.__desmHW === undefined;
                G.__desmHW = host.clientWidth;
                if (!firstW) { try { win.dispatchEvent(new win.Event('resize')); } catch (eR) {} }
              }
              try {
                var tb0 = main && main.querySelector('table'), mt = tb0 && win.getComputedStyle(tb0).transform;
                var mm = mt && mt.match(/matrix\(([^,]+)/); if (mm) sc = parseFloat(mm[1]) || 1;
              } catch (e) {}
              var avail = Math.floor(cw / sc) - 46;
              var pwid = Math.max(170, Math.round(avail * 0.6)), lwid = Math.max(90, avail - pwid);
              var orig = G.__desmOrig = G.__desmOrig || {};
              for (var k in keep) {
                try {
                  var o = G.Cols[k]; if (!o) continue;
                  if (!orig[k]) orig[k] = { w: o.Width, r: o.RelWidth };
                  if (!colShown(G, k)) { G.ShowCol(k); changed = true; }
                  if (!on) {
                    if (G.__desmWDone !== 'off') {
                      try { G.SetAttribute(null, k, 'RelWidth', orig[k].r || 0, 1); } catch (e3) {}
                      if (G.SetWidth && orig[k].w != null) G.SetWidth(k, parseFloat(orig[k].w) || 100);
                      changed = true;
                    }
                    continue;
                  }
                  var weight = keep[k] === 'p' ? 60 : 40, target = keep[k] === 'p' ? pwid : lwid;
                  var cur = parseFloat(o.Width), rel = parseFloat(o.RelWidth);
                  if (G.__desmWDone !== 'on' || rel !== weight || isNaN(cur) || Math.abs(cur - target) > 1) {
                    try { G.SetAttribute(null, k, 'RelWidth', weight, 1); } catch (e4) {}
                    if (G.SetWidth) G.SetWidth(k, target);
                    changed = true;
                  }
                } catch (e) {}
              }
              G.__desmWDone = on ? 'on' : 'off';
              G.__desmTry = changed ? G.__desmTry + 1 : 0;
            }
          }
          // ===== Lấy danh sách Detail Item của một kiện: nạp trang "Hạng mục chi tiết" (MENU_SEQ=197) trong khung ẩn,
          // điền Số kiện hàng rồi bấm Search và đọc lưới kết quả. Khung ẩn được giữ lại để lần sau dùng lại cho nhanh.
          function diTop(idoc) { var w = idoc.defaultView; try { if (w.top.document && w.top.document.body) return w.top; } catch (e) {} return w; }
          function diGrid(w) {
            try {
              for (var i = 0; i < w.TGGrids.length; i++) {
                var g = w.TGGrids[i];
                if (g && g.Cols && g.Cols.MATERIAL_CODE && g.Cols.PACKAGE_NO && g.Rows) return g;
              }
            } catch (e) {}
            return null;
          }
          function diRows(G) {
            var out = [];
            function add(r) { if (r && r.Kind === 'Data' && !(r.Visible === 0 || r.Visible === '0' || r.Visible === false || r.Deleted)) out.push(r); }
            try {
              if (G.GetFirstVisible && G.GetNextVisible) {
                var r0 = G.GetFirstVisible(), n = 0;
                while (r0 && n++ < 5000) { add(r0); r0 = G.GetNextVisible(r0); }
              }
            } catch (e) { out = []; }
            if (!out.length) { for (var id in G.Rows) add(G.Rows[id]); }
            return out;
          }
          function diFrame(top, cb) {
            var D = top.document, fr = D.getElementById('desmDetailFrame');
            if (!fr) {
              fr = D.createElement('iframe'); fr.id = 'desmDetailFrame'; fr.setAttribute('aria-hidden', 'true'); fr.tabIndex = -1;
              fr.src = '/page_crt.do?MENU_SEQ=197';
              fr.style.cssText = DI_HIDE;
              D.body.appendChild(fr);
            }
            var t0 = Date.now();
            (function poll() {
              var w = null; try { w = fr.contentWindow; } catch (e) {}
              try {
                if (w && diGrid(w) && w.document.getElementById('txtPackageNo') && w.document.getElementById('btnSearch')) { cb(w); return; }
              } catch (e) {}
              if (Date.now() - t0 > 25000) { cb(null); return; }
              setTimeout(poll, 120);
            })();
          }
          // Đợi ô Dự án trong khung ẩn được điền (mặc định của trang); quá 10 giây thì chép từ trang Package / tab đang mở.
          // Đồng thời đóng hộp thoại báo lỗi "required values" nếu lần Search trước đã làm nó hiện ra.
          function diCloseAlerts(top) {
            try {
              var ms = top.document.querySelectorAll('.modal.show, .modal.in, .modal[style*="display: block"]');
              for (var i = 0; i < ms.length; i++) {
                var b = ms[i].querySelector('[data-dismiss="modal"], .close, button');
                if (b) b.click();
              }
              top.document.documentElement.classList.remove('desm-modal-open');
            } catch (e) {}
          }
          function diFindProject(idoc, top) {
            var docs = [idoc];
            try { var fs = top.document.querySelectorAll('iframe'); for (var i = 0; i < fs.length; i++) { if (fs[i].id !== 'desmDetailFrame') { try { if (fs[i].contentDocument) docs.push(fs[i].contentDocument); } catch (e) {} } } } catch (e) {}
            for (var j = 0; j < docs.length; j++) {
              try {
                var c = docs[j].getElementById('txtProjectCode');
                if (c && c.value) { var n = docs[j].getElementById('txtProjectName'); return { code: c.value, name: n ? n.value : '' }; }
              } catch (e) {}
            }
            return null;
          }
          function diProject(w, idoc, top, cb) {
            var d = w.document, t0 = Date.now(), copied = false;
            (function poll() {
              var c = d.getElementById('txtProjectCode');
              if (c && c.value) { try { top.__desmProj = c.value; } catch (e0) {} diCloseAlerts(top); cb(true); return; }
              var el = Date.now() - t0;
              if (el > 10000 && !copied) {
                copied = true;
                var p = diFindProject(idoc, top);
                if (p && c) {
                  c.value = p.code; var n = d.getElementById('txtProjectName'); if (n) n.value = p.name;
                  ['input', 'change'].forEach(function(e) { c.dispatchEvent(new w.Event(e, { bubbles: true })); });
                  try { c.classList.remove('validation-error'); if (n) n.classList.remove('validation-error'); } catch (e) {}
                  try { top.__desmProj = p.code; } catch (e0) {} diCloseAlerts(top); cb(true); return;
                }
              }
              if (el > 15000) { cb(false); return; }
              setTimeout(poll, 100);
            })();
          }
          // Mở sẵn khung ẩn "Hạng mục chi tiết" ngay khi màn hình Package hiện, để lúc mở kiện không phải chờ nạp trang
          function diWarm(idoc) {
            try {
              var top = diTop(idoc);
              if (top.__desmDIwarm) return;
              top.__desmDIwarm = 1;
              setTimeout(function() { diFrame(top, function() {}); }, 1200);
            } catch (e) {}
          }
          // n = số hạng mục dự kiến (từ cột A/O "4/0"): đủ n dòng là xong ngay, khỏi đợi lưới "ổn định".
          // skippable = true: nếu trong lúc chờ hàng đợi có yêu cầu mới hơn thì bỏ qua yêu cầu cũ.
          function diLoad(idoc, pkg, cb, n, skippable) {
            var top = diTop(idoc), cache = top.__desmDI = top.__desmDI || {};
            if (cache[pkg]) { cb(cache[pkg]); return; }
            var seq = top.__desmDIseq = (top.__desmDIseq || 0) + 1;
            n = (n > 0) ? n : 0;
            function run(done) {
              diFrame(top, function(w) {
                var G = w && diGrid(w);
                if (!G) { done(null); return; }
                var d = w.document, inp = d.getElementById('txtPackageNo'), pl = d.getElementById('txtPackingListNo');
                function setv(x, v) { x.value = v; ['input', 'change'].forEach(function(e) { x.dispatchEvent(new w.Event(e, { bubbles: true })); }); }
                // Ô Dự án (bắt buộc) do trang tự điền bất đồng bộ; bấm Search khi còn trống sẽ báo "required values have not been entered".
                diProject(w, idoc, top, function(projOk) {
                if (!projOk) { done(null); return; }
                setv(inp, pkg); if (pl && pl.value) setv(pl, '');
                var sv0 = d.getElementById('txtSearchValue1'); if (sv0 && sv0.value) setv(sv0, '');
                d.getElementById('btnSearch').click();
                var t0 = Date.now(), last = '', stable = 0;
                function finish(hit) {
                  // Có dự kiến n > 0 mà không thấy dòng nào = lần nạp hỏng (chưa phải kiện rỗng) → báo lỗi để thử lại
                  if (!hit.length && n > 0) { done(null); return; }
                  done(hit.map(function(r) {
                    var o = {}; ['PACKAGE_NO', 'DESCRIPTION', 'DRAWING_NO', 'TAG_NO', 'REMARKS', 'COMMENTS', 'MATERIAL_CODE', 'LOCATION', 'PROJECT_NO', 'UNIT', 'NET', 'GROSS',
                      'IN_QTY', 'OUT_QTY', 'REMAIN_QTY', 'RSI_QTY', 'BALANCE_QTY', 'MRF_QTY', 'MRF_BALANCE_QTY', 'RSI_CANCEL_QTY',
                      'REPORT_SHORT', 'REPORT_OVER', 'REPORT_DMG', 'REPORT_MISSING', 'REPORT_SHORT_QTY', 'REPORT_OVER_QTY', 'REPORT_DMG_QTY', 'REPORT_MISSING_QTY'].forEach(function(c) { o[c] = gridText(G, r, c); });
                    o._id = r.id;
                    return o;
                  }));
                }
                (function poll() {
                  var all = diRows(G), hit = all.filter(function(r) { return gridText(G, r, 'PACKAGE_NO') === pkg; });
                  var sig = all.length + '|' + hit.length; stable = sig === last ? stable + 1 : 0; last = sig;
                  var el = Date.now() - t0;
                  if ((n && hit.length >= n && stable >= 1 && el > 150) || (hit.length && stable >= 5 && el > 900) ||
                      (!all.length && stable >= 20 && el > 5000) || el > 15000) { finish(hit); return; }
                  setTimeout(poll, 100);
                })();
                });
              });
            }
            top.__desmDIq = (top.__desmDIq || Promise.resolve()).then(function() {
              return new Promise(function(res) {
                if (cache[pkg]) { cb(cache[pkg]); res(); return; }
                if (skippable && seq !== top.__desmDIseq) { res(); return; }
                run(function(rows) {
                  if (rows === null) {
                    // Hỏng 1 lần: bỏ khung ẩn cũ, tạo lại khung mới rồi thử thêm một lần
                    try { var old = top.document.getElementById('desmDetailFrame'); if (old && old.parentNode) old.parentNode.removeChild(old); } catch (e) {}
                    run(function(rows2) {
                      if (rows2 && (rows2.length || !n)) cache[pkg] = rows2;
                      cb(rows2); res();
                    });
                    return;
                  }
                  if (rows.length || !n) cache[pkg] = rows;
                  cb(rows); res();
                });
              });
            });
          }
          // Đường nhanh: gọi thẳng API của lưới "Hạng mục chi tiết" (/getIdsmOsDetailList.do) bằng jQuery của trang
          // (kế thừa ajaxSetup/phiên đăng nhập) thay vì nạp trang ẩn rồi bấm Search. Lỗi thì quay về cách cũ (diLoad).
          function diLoadFast(idoc, pkg, cb, n, skippable) {
            var top = diTop(idoc), W = idoc.defaultView, $j = null;
            try { $j = W.jQuery || W.$ || top.jQuery || top.$; } catch (e) {}
            var proj = null; try { proj = top.__desmProj || (diFindProject(idoc, top) || {}).code; } catch (e) {}
            function slow() { diLoad(idoc, pkg, cb, n, skippable); }
            if (!$j || !$j.ajax || !proj) { slow(); return; }
            var used = false;
            function nz(v) { return String(v == null ? '' : v).replace(/\s+/g, ' ').trim(); }
            function fail() { if (used) return; used = true; slow(); }
            var param = { PAGE_NUM: 1, PAGE_CNT: 5000, PROJECT_NO: proj, PACKAGE_LIST_NO: '', PACKAGE_NO: pkg, DESCRIPTION: '', DRAWING_NO: '',
              TAG_NO: '', QTY_TYPE: 'rsi', QTY: '', KEY1: '', VALUE1: '', LOCATION: '', SEQUENCE: '', VENDOR: '', ATTRIBUTE10: '',
              TYPE: '', CATEGORY: '', SUB_CATEGORY: '', COMMENTS: '' };
            try {
              $j.ajax({
                url: '/getIdsmOsDetailList.do', data: param, timeout: 15000,
                success: function(data) {
                  if (used) return;
                  var list = data && data.results && data.results.list;
                  if (!list || !list.length && data.results === 'Err') { fail(); return; }
                  var hit = [].filter.call(list, function(r) { return r && nz(r.PACKAGE_NO) === nz(pkg); });
                  if (!hit.length && n > 0) { fail(); return; }
                  used = true;
                  var rows = hit.map(function(r) {
                    var o = {}; ['PACKAGE_NO', 'DESCRIPTION', 'DRAWING_NO', 'TAG_NO', 'REMARKS', 'COMMENTS', 'MATERIAL_CODE', 'LOCATION', 'PROJECT_NO', 'UNIT', 'NET', 'GROSS',
                      'IN_QTY', 'OUT_QTY', 'REMAIN_QTY', 'RSI_QTY', 'BALANCE_QTY', 'MRF_QTY', 'MRF_BALANCE_QTY', 'RSI_CANCEL_QTY',
                      'REPORT_SHORT', 'REPORT_OVER', 'REPORT_DMG', 'REPORT_MISSING', 'REPORT_SHORT_QTY', 'REPORT_OVER_QTY', 'REPORT_DMG_QTY', 'REPORT_MISSING_QTY'].forEach(function(c) { o[c] = nz(r[c]); });
                    o._id = null;
                    return o;
                  });
                  cb(rows);
                  // Mở sẵn lưới ẩn ở nền để lúc chạm ghim/Location Update không phải đợi
                  setTimeout(function() { try { diLoad(idoc, pkg, function() {}, n, true); } catch (e) {} }, 400);
                },
                error: fail
              });
            } catch (e) { fail(); }
          }
          function diProj(idoc) { var top = diTop(idoc); try { return top.__desmProj || (diFindProject(idoc, top) || {}).code || ''; } catch (e) { return ''; } }
          // Gọi API dạng {results:{list:[...]}} bằng jQuery của trang (kế thừa phiên đăng nhập); ok(list, tổng) / bad()
          function diAjax(idoc, url, param, ok, bad) {
            var top = diTop(idoc), W = idoc.defaultView, $j = null;
            try { $j = W.jQuery || W.$ || top.jQuery || top.$; } catch (e) {}
            if (!$j || !$j.ajax) { bad(); return; }
            try {
              $j.ajax({ url: url, data: param, timeout: 20000,
                success: function(d) {
                  var res = d && d.results, list = Array.isArray(res) ? res : (res && res.list);
                  if (!res || res === 'Err' || !list) { bad(); return; } ok(list, Array.isArray(res) ? res.length : res.length);
                },
                error: function() { bad(); } });
            } catch (e) { bad(); }
          }
          // Lưu hạng mục: giống btnSaveClick của plDetail.js — /saveIdsmOsDetailList.do, tham số list = JSON mảng dòng; lỗi khi result.error != null
          function diSave(idoc, list, ok, bad) {
            var top = diTop(idoc), W = idoc.defaultView, $j = null;
            try { $j = W.jQuery || W.$ || top.jQuery || top.$; } catch (e) {}
            if (!$j || !$j.ajax) { bad('không tìm thấy jQuery của trang'); return; }
            try {
              $j.ajax({ url: '/saveIdsmOsDetailList.do', data: { list: JSON.stringify(list) }, timeout: 30000,
                success: function(r) { if (r && r.error != null) bad(String(r.error)); else ok(r); },
                error: function(_x, st) { bad('lỗi mạng hoặc hết phiên (' + st + ')'); } });
            } catch (e) { bad('không gửi được yêu cầu'); }
          }
          var DI_HIDE = 'position:fixed;left:-200vw;top:0;width:100vw;height:80vh;border:0;opacity:0;pointer-events:none;';
          // Chọn đúng các hạng mục trong lưới ẩn (xs = mảng) rồi bấm nút Location Update gốc của trang "Hạng mục chi tiết"
          function diSelect(idoc, pkg, xs, cb) {
            var top = diTop(idoc);
            function nz(v) { return String(v == null ? '' : v).replace(/\s+/g, ' ').trim(); }
            function same(G, r, x) {
              return nz(gridText(G, r, 'PACKAGE_NO')) === nz(pkg) && nz(gridText(G, r, 'MATERIAL_CODE')) === nz(x.MATERIAL_CODE) &&
                nz(gridText(G, r, 'TAG_NO')) === nz(x.TAG_NO) && nz(gridText(G, r, 'DESCRIPTION')) === nz(x.DESCRIPTION);
            }
            function attempt(retried) {
              diFrame(top, function(w) {
                var G = w && diGrid(w); if (!G) { cb(false); return; }
                var rows = diRows(G), targets = [], missing = false;
                xs.forEach(function(x) {
                  var t = null, byId = G.Rows[x._id];
                  if (byId && targets.indexOf(byId) < 0 && same(G, byId, x)) t = byId;
                  for (var i = 0; !t && i < rows.length; i++) if (targets.indexOf(rows[i]) < 0 && same(G, rows[i], x)) t = rows[i];
                  if (t) targets.push(t); else missing = true;
                });
                if (missing) {
                  if (retried) { cb(false); return; }
                  try { delete (top.__desmDI || {})[pkg]; } catch (e) {}
                  diLoad(idoc, pkg, function() { attempt(true); }); return;
                }
                try {
                  rows.forEach(function(r) {
                    var sel = !!r.Selected && r.Selected !== '0', want = targets.indexOf(r) >= 0;
                    if (want !== sel) G.SelectRow(r, want ? 1 : 0);
                  });
                } catch (e) { cb(false); return; }
                var btn = w.document.getElementById('btnLocationSetup');
                if (!btn) { cb(false); return; }
                btn.click(); cb(true);
                // Hộp thoại bản đồ đo kích thước lúc mở: bắn thêm 'resize' để canvas/ảnh bản đồ tính lại và vẽ
                [150, 600, 1500].forEach(function(ms) {
                  setTimeout(function() { try { w.dispatchEvent(new w.Event('resize')); } catch (e) {} }, ms);
                });
              });
            }
            attempt(false);
          }
          // Trong khung: nền trong suốt và ẩn toàn bộ trang Hạng mục chi tiết, chỉ chừa hộp thoại bản đồ (và hộp thoại báo lỗi)
          // để phía sau là màn hình chi tiết kiện của app thay vì trang tìm kiếm của DESM.
          function diClean(fr, on) {
            try {
              var d = fr.contentDocument; if (!d) return;
              var st = d.getElementById('desmFrameClean');
              if (!on) { if (st && st.parentNode) st.parentNode.removeChild(st); return; }
              if (st) return;
              st = d.createElement('style'); st.id = 'desmFrameClean';
              st.textContent = 'html, body { background:transparent!important; }' +
                'body * { visibility:hidden!important; }' +
                '.modal, .modal *, .modal-backdrop { visibility:visible!important; }' +
                '#alert-success, #alert-failure, #alert-warning, #alert-success *, #alert-failure *, #alert-warning * { visibility:visible!important; }';
              (d.head || d.documentElement).appendChild(st);
            } catch (e) {}
          }
          // Đưa khung ẩn lên toàn màn hình (để thao tác hộp thoại cập nhật vị trí của DESM), có thanh "Xong" để quay lại
          function diShow(idoc, onClose) {
            var top = diTop(idoc), D = top.document, fr = D.getElementById('desmDetailFrame');
            if (!fr) {
              fr = D.createElement('iframe'); fr.id = 'desmDetailFrame'; fr.tabIndex = -1;
              fr.src = '/page_crt.do?MENU_SEQ=197'; fr.style.cssText = DI_HIDE; D.body.appendChild(fr);
            }
            if (D.getElementById('desmDetailFrameBar')) return;
            fr.removeAttribute('aria-hidden');
            // Hộp thoại xác nhận "Are you sure to comfirm?" của DESM được dựng ở tài liệu ngoài cùng (top), z-index thấp hơn khung này
            // nên bị khung phủ kín che mất: nâng các lớp hộp thoại/nền mờ của top lên trên khung trong lúc khung đang hiện.
            var zs = D.getElementById('desmFrameZFix');
            if (!zs) {
              zs = D.createElement('style'); zs.id = 'desmFrameZFix';
              zs.textContent = '.modal, .ui-dialog, .swal2-container, .bootbox { z-index:2147483600!important; }' +
                '.modal-backdrop, .ui-widget-overlay { z-index:2147483500!important; }';
              (D.head || D.documentElement).appendChild(zs);
            }
            var bar = D.createElement('div'); bar.id = 'desmDetailFrameBar';
            bar.className = 'desm-detail-top desm-frame-bar';
            bar.style.cssText = 'position:fixed;left:0;top:0;right:0;z-index:2147483200;';
            var b = D.createElement('button'); b.type = 'button'; b.className = 'desm-detail-back'; b.textContent = '‹  Xong';
            var t = D.createElement('div'); t.className = 'desm-detail-title'; t.textContent = 'Cập nhật vị trí hạng mục';
            bar.appendChild(b); bar.appendChild(t); D.body.appendChild(bar);
            bar.style.display = 'none'; // vẫn giữ trong DOM để nút Back/vuốt quay lại (__desmBack) bấm được
            fr.setAttribute('allowtransparency', 'true');
            fr.style.cssText = 'position:fixed;left:0;top:0;width:100vw;height:100vh;' +
              'border:0;opacity:1;pointer-events:auto;z-index:2147483100;background:transparent;';
            diClean(fr, true);
            b.addEventListener('click', function() {
              // Đóng hộp thoại bản đồ còn mở trong khung trước khi ẩn khung đi
              try { fr.contentWindow.__desmAutoBack = 0; } catch (e) {}
              try {
                var fw = fr.contentWindow, dlg = fw.document.getElementById('dlgDesmLocation');
                if (dlg && fw.jQuery) fw.jQuery(dlg).modal('hide');
              } catch (e) {}
              if (bar.parentNode) bar.parentNode.removeChild(bar);
              try { var z2 = D.getElementById('desmFrameZFix'); if (z2 && z2.parentNode) z2.parentNode.removeChild(z2); } catch (e) {}
              diClean(fr, false);
              fr.style.cssText = DI_HIDE; fr.setAttribute('aria-hidden', 'true');
              onClose();
            });
          }
          // Màn hình chi tiết một kiện hàng (mở khi chạm thẻ ở chế độ "Chạm: Chi tiết"). Dữ liệu đọc từ dòng TreeGrid tương ứng.
          function openDetail(idoc, G, rowId, no, onClose) {
            var win = idoc.defaultView, r = G.Rows[rowId]; if (!r) return;
            // Phủ toàn màn hình: dựng trên tài liệu ngoài cùng nếu cùng domain, không được thì dựng trong khung hiện tại
            var doc = idoc;
            try { if (win.top !== win && win.top.document && win.top.document.body) doc = win.top.document; } catch (e) { doc = idoc; }
            var old = doc.getElementById('desmDetail'); if (old && old.parentNode) old.parentNode.removeChild(old);
            function el(tag, cls, text) {
              var e = doc.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e;
            }
            function g(c) { return gridText(G, r, c); }
            function num(c, d) {
              var raw = null; try { raw = G.GetValue ? G.GetValue(r, c) : null; } catch (e) {}
              var t = String(raw != null && raw !== '' && !isNaN(parseFloat(raw)) ? raw : g(c)).replace(/,/g, ''), v = parseFloat(t);
              return isNaN(v) ? (t || '-') : v.toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
            }
            function pair(c) { // "24.000/0.000" -> "24/0"
              return g(c).split('/').map(function(x) {
                var v = parseFloat(x.replace(/,/g, '')); return isNaN(v) ? x.trim() : String(v);
              }).join('/');
            }
            function shortDate(t) { return /^\d\d\/\d\d\/\d\d$/.test(t) ? '20' + t : t; }
            var pkgNo = g('PACKAGE_NO');
            var ao = g('OUT_STATUS'), nLines = parseInt(ao.split('/')[0], 10);
            var ov = el('div', 'desm-detail'); ov.id = 'desmDetail';
            function close() {
              [].forEach.call(doc.querySelectorAll('.desm-sub'), function(n) { if (n.parentNode) n.parentNode.removeChild(n); });
              if (ov.parentNode) ov.parentNode.removeChild(ov);
              doc.documentElement.classList.remove('desm-detail-open');
              if (onClose) onClose();
            }
            // Thanh trên: quay lại + tiêu đề
            var top = el('div', 'desm-detail-top');
            var back = el('button', 'desm-detail-back', '‹  Search'); back.type = 'button';
            back.addEventListener('click', close);
            top.appendChild(back); top.appendChild(el('div', 'desm-detail-title', 'Package'));
            ov.appendChild(top);
            var body = el('div', 'desm-detail-body');
            // Khối thông tin chính
            var m = el('div', 'desm-dcard');
            m.appendChild(el('div', 'desm-d-h', '#' + no + ' ' + (g('PACKAGE_LIST_NO') || pkgNo)));
            m.appendChild(el('div', 'desm-d-l', pkgNo));
            if (g('DESCRIPTION')) m.appendChild(el('div', 'desm-d-l', g('DESCRIPTION')));
            var lines = el('div', 'desm-d-l', 'Detail Item Lines ');
            lines.appendChild(el('span', 'desm-d-red', isNaN(nLines) ? '-' : String(nLines)));
            m.appendChild(lines);
            var tri = el('div', 'desm-d-tri');
            tri.appendChild(el('span', '', g('PACKAGE_STATUS') || 'N/A'));
            tri.appendChild(el('span', '', ao || '-'));
            tri.appendChild(el('span', '', pair('OUT_STATUS_QTY') || '-'));
            m.appendChild(tri);
            m.appendChild(el('div', 'desm-d-l', 'S/C & Excel Remarks ' + g('REMARKS')));
            m.appendChild(el('hr', 'desm-d-hr'));
            var tl = el('div', 'desm-d-two');
            tl.appendChild(el('span', '', g('PACKAGE_TYPE') || '-'));
            var lc = el('span', 'desm-d-loc');
            var NS = 'http://www.w3.org/2000/svg';
            var svg = doc.createElementNS(NS, 'svg'); svg.setAttribute('viewBox', '0 0 24 24');
            svg.setAttribute('width', '18'); svg.setAttribute('height', '18');
            var pth = doc.createElementNS(NS, 'path');
            pth.setAttribute('d', 'M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9.5a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5z');
            pth.setAttribute('fill', 'none'); pth.setAttribute('stroke', 'currentColor'); pth.setAttribute('stroke-width', '2');
            svg.appendChild(pth); lc.appendChild(svg); lc.appendChild(el('span', '', g('STORAGE_LOCATION') || '—'));
            tl.appendChild(lc); m.appendChild(tl);
            body.appendChild(m);
            // Received / MRR Received / V/C
            function triple(items) {
              var b = el('div', 'desm-dband desm-dband3');
              items.forEach(function(x) {
                var c = el('div', 'desm-dband-c'); c.appendChild(el('div', 'desm-dband-k', x[0]));
                c.appendChild(el('div', 'desm-dband-v' + (x[2] ? ' desm-u' : ''), x[1])); b.appendChild(c);
              });
              return b;
            }
            body.appendChild(triple([
              ['Received', shortDate(g('RECEIPT_DATE')) || '-'],
              ['MRR Received', shortDate(g('MRR_RECEIVED_DATE')) || '-'],
              ['V/C', g('VISUAL_CHECK') || '-', true]
            ]));
            // Kích thước & trọng lượng
            var dm = el('div', 'desm-dband desm-dband6');
            [['L(cm)', num('L_CM', 3)], ['W(cm)', num('W_CM', 3)], ['H(cm)', num('H_CM', 3)],
             ['CBM', num('VOLUME', 3)], ['Net(kg)', num('NET', 3)], ['Gross', num('GROSS', 3)]].forEach(function(x) {
              var c = el('div', 'desm-dband-c'); c.appendChild(el('div', 'desm-dband-k', x[0]));
              c.appendChild(el('div', 'desm-dband-v', x[1])); dm.appendChild(c);
            });
            body.appendChild(dm);
            // SHORT / OVER / DMG / MISSING (chỉ xem)
            function flag(c) {
              var v = g(c).toUpperCase(), q = parseFloat(g(c + '_QTY').replace(/,/g, ''));
              return (v && v !== '0' && v !== 'N' && v !== 'FALSE') || (!isNaN(q) && q > 0);
            }
            var fl = el('div', 'desm-dband desm-dband4');
            [['SHORT', 'REPORT_SHORT'], ['OVER', 'REPORT_OVER'], ['DMG', 'REPORT_DMG'], ['MISSING', 'REPORT_MISSING']].forEach(function(x) {
              var c = el('div', 'desm-dband-c'); c.appendChild(el('div', 'desm-dband-v', x[0]));
              var cb = doc.createElement('input'); cb.type = 'checkbox'; cb.className = 'desm-chk';
              cb.checked = flag(x[1]); cb.disabled = true; c.appendChild(cb); fl.appendChild(c);
            });
            body.appendChild(fl);
            // Detail Item List: nạp tự động từ trang "Hạng mục chi tiết" theo mã kiện, bấm nút để thu gọn / mở lại
            var dl = el('button', 'desm-detail-list', 'Detail Item List  ↑'); dl.type = 'button';
            var note = el('div', 'desm-detail-note');
            var dis = el('div', 'desm-ditems');
            var shown = true;
            dl.addEventListener('click', function() {
              shown = !shown; dis.style.display = shown ? '' : 'none';
              dl.textContent = 'Detail Item List  ' + (shown ? '↑' : '↓');
            });
            function dash(v) { return v ? v : '-'; }
            var chosen = [], itemCards = [], selAll = null, selTxt = null, selBar = null, lu = null;
            function refreshSel() {
              itemCards.forEach(function(ic) {
                var on = chosen.indexOf(ic.x) >= 0;
                ic.card.classList.toggle('desm-sel', on); ic.ck.checked = on;
              });
              if (selAll) {
                selAll.checked = itemCards.length > 0 && chosen.length === itemCards.length;
                selAll.indeterminate = chosen.length > 0 && chosen.length < itemCards.length;
              }
              if (selTxt) selTxt.textContent = 'Chọn tất cả · ' + itemCards.length + ' hạng mục' + (chosen.length ? ' · đã chọn ' + chosen.length : '');
              if (lu) {
                // Chưa tích chọn hạng mục nào: ẩn hẳn nút Location Update; tích chọn xong mới hiện
                lu.style.display = chosen.length ? '' : 'none';
                lu.textContent = chosen.length ? 'Location Update (' + chosen.length + ' hạng mục)' : 'Location Update';
              }
            }
            // ===== Màn hình lồng nhau: Detail Item -> RSI & MRF List -> RSI Detail =====
            function subScreen(title, backText) {
              var sov = el('div', 'desm-detail desm-sub');
              var st = el('div', 'desm-detail-top');
              var sb = el('button', 'desm-detail-back', '‹  ' + backText); sb.type = 'button';
              function sclose() { if (sov.parentNode) sov.parentNode.removeChild(sov); }
              sb.addEventListener('click', sclose);
              st.appendChild(sb); st.appendChild(el('div', 'desm-detail-title', title)); sov.appendChild(st);
              var sbody = el('div', 'desm-detail-body'); sov.appendChild(sbody);
              doc.body.appendChild(sov);
              return { ov: sov, body: sbody, close: sclose };
            }
            function fnum(v) {
              var t = String(v == null ? '' : v).replace(/,/g, ''), n = parseFloat(t);
              if (t === '' || isNaN(n)) return '-';
              return n.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 3 });
            }
            function bandOf(items) {
              var b = el('div', 'desm-dband desm-dband4');
              items.forEach(function(it) {
                var c = el('div', 'desm-dband-c'); c.appendChild(el('div', 'desm-dband-k', it[0]));
                c.appendChild(el('div', 'desm-dband-v', it[1])); b.appendChild(c);
              });
              return b;
            }
            function rsiParam(over) {
              var p = { PAGE_NUM: 1, PAGE_CNT: 5000, PROJECT_NO: '', RSI_NO: '', RSI_NAME: '', SUBCONTRACTOR: '', ATTRIBUTE10: '', MATERIAL_CODE: '',
                START_REQUEST_DATE: '', END_REQUEST_DATE: '', BALANCE_QTY: '', TYPE: '', CATEGORY: '', SUB_CATEGORY: '', PACKING_LIST_NO: '',
                PACKAGE_NO: '', ITEM_DESC: '', MASTER_SHOP_UNIT: '', MASTER_SHOP_BLDG: '', SHOP_UNIT: '', SHOP_BLDG: '' };
              for (var k in over) p[k] = over[k];
              if (!p.PROJECT_NO) p.PROJECT_NO = diProj(idoc);
              return p;
            }
            function sameStr(a, b2) { return String(a == null ? '' : a).replace(/\s+/g, ' ').trim() === String(b2 == null ? '' : b2).replace(/\s+/g, ' ').trim(); }
            // Màn "Detail Item": thông tin + số lượng của một hạng mục, kèm danh sách RSI của hạng mục đó
            function openItemDetail(x) {
              if (x.UNIT === undefined || x.TRK_ITEM_NAME === undefined || (x.UNIT === '' && x.IN_QTY === '' && x.REMAIN_QTY === '')) {
                // Hàng đến từ lưới ẩn/bộ nhớ cũ nên thiếu số lượng: lấy lại bản đầy đủ bằng API rồi mở
                diAjax(idoc, '/getIdsmOsDetailList.do', { PAGE_NUM: 1, PAGE_CNT: 5000, PROJECT_NO: x.PROJECT_NO || diProj(idoc), PACKAGE_LIST_NO: '', PACKAGE_NO: x.PACKAGE_NO, DESCRIPTION: '', DRAWING_NO: '',
                  TAG_NO: '', QTY_TYPE: 'rsi', QTY: '', KEY1: '', VALUE1: '', LOCATION: '', SEQUENCE: '', VENDOR: '', ATTRIBUTE10: '',
                  TYPE: '', CATEGORY: '', SUB_CATEGORY: '', COMMENTS: '' }, function(list) {
                  var full = null;
                  [].forEach.call(list, function(r) { if (!full && String(r.MATERIAL_CODE == null ? '' : r.MATERIAL_CODE) === String(x.MATERIAL_CODE || '') && String(r.PACKAGE_NO == null ? '' : r.PACKAGE_NO) === String(x.PACKAGE_NO)) full = r; });
                  if (!full) { showItemDetail(x); return; }
                  var o = {}; for (var k in x) o[k] = x[k];
                  for (var k2 in full) { var v = full[k2]; if (o[k2] === undefined || o[k2] === '') o[k2] = v == null ? '' : String(v); }
                  showItemDetail(o);
                }, function() { showItemDetail(x); });
                return;
              }
              showItemDetail(x);
            }
            function showItemDetail(x) {
              var S = subScreen('Detail Item', 'Package'), b = S.body;
              var m = el('div', 'desm-dcard');
              m.appendChild(el('div', 'desm-d-h', x.PACKAGE_NO));
              m.appendChild(el('div', 'desm-d-l', 'ITEM : ' + dash(x.DESCRIPTION)));
              m.appendChild(el('div', 'desm-d-l', 'DWG : ' + (x.DRAWING_NO || 'N/A')));
              m.appendChild(el('div', 'desm-d-l', 'TAG : ' + (x.TAG_NO || 'N/A')));
              m.appendChild(el('div', 'desm-d-l', 'Net Weight(Kg) : ' + fnum(x.NET)));
              m.appendChild(el('div', 'desm-d-l', dash(x.MATERIAL_CODE) + ' / ' + dash(x.UNIT)));
              m.appendChild(el('div', 'desm-d-l', 'Location : ' + dash(x.LOCATION)));
              b.appendChild(m);
              b.appendChild(bandOf([["In Q'ty", fnum(x.IN_QTY)], ["Out Q'ty", fnum(x.OUT_QTY)], ['Remain', fnum(x.REMAIN_QTY)], ["RSI Q'ty", fnum(x.RSI_QTY)]]));
              b.appendChild(bandOf([['RSI Bal.', fnum(x.BALANCE_QTY)], ["MRF Q'ty", fnum(x.MRF_QTY)], ['MRF Bal.', fnum(x.MRF_BALANCE_QTY)], ['Cancel', fnum(x.RSI_CANCEL_QTY)]]));
              // SHORT / OVER / DMG / MISSING + số lượng + Remarks: sửa được và lưu qua /saveIdsmOsDetailList.do (giống nút Save của trang web).
              // Web chỉ cho sửa khi IS_CONFIRM_MATERIAL = 'Y'; cờ REPORT_* gửi "1"/"0" theo số lượng > 0.
              function qn(v) { var n = parseFloat(String(v == null ? '' : v).replace(/,/g, '')); return isNaN(n) ? 0 : n; }
              var canEdit = x.TRK_ITEM_NAME !== undefined && String(x.IS_CONFIRM_MATERIAL == null ? '' : x.IS_CONFIRM_MATERIAL).toUpperCase() === 'Y';
              var fl = el('div', 'desm-dband desm-dband4'), fq = el('div', 'desm-dband desm-dband4 desm-fqty'), flds = [];
              [['SHORT', 'REPORT_SHORT'], ['OVER', 'REPORT_OVER'], ['DMG', 'REPORT_DMG'], ['MISSING', 'REPORT_MISSING']].forEach(function(f) {
                var q1 = qn(x[f[1]]), q2 = qn(x[f[1] + '_QTY']), on = q1 > 0 || q2 > 0;
                var c = el('div', 'desm-dband-c'); c.appendChild(el('div', 'desm-dband-v', f[0]));
                var cb = doc.createElement('input'); cb.type = 'checkbox'; cb.className = 'desm-chk'; cb.disabled = !canEdit;
                cb.checked = on; c.appendChild(cb); fl.appendChild(c);
                var qc = el('div', 'desm-dband-c'), qi = doc.createElement('input');
                qi.type = 'text'; qi.setAttribute('inputmode', 'decimal'); qi.className = 'desm-sub-in'; qi.placeholder = "Q'ty";
                qi.value = q2 > 0 ? String(q2) : ''; qi.disabled = !canEdit || !on; qc.appendChild(qi); fq.appendChild(qc);
                cb.addEventListener('change', function() { qi.disabled = !cb.checked; if (cb.checked) { try { qi.focus(); } catch (e) {} } else qi.value = ''; });
                flds.push({ name: f[0], col: f[1], cb: cb, qi: qi, orig: x[f[1] + '_QTY'] });
              });
              b.appendChild(fl); b.appendChild(fq);
              var rmk = doc.createElement('textarea'); rmk.className = 'desm-sub-in desm-rmk'; rmk.rows = 3; rmk.placeholder = 'Remarks';
              rmk.value = x.REMARKS == null ? '' : String(x.REMARKS); rmk.disabled = !canEdit; b.appendChild(rmk);
              if (x.COMMENTS) b.appendChild(el('div', 'desm-detail-note', 'Note: ' + x.COMMENTS));
              var svBtn = el('button', 'desm-detail-list', 'SAVE'); svBtn.type = 'button'; svBtn.disabled = !canEdit;
              var svMsg = el('div', 'desm-detail-note', canEdit ? '' : (x.TRK_ITEM_NAME === undefined ? 'Chưa tải đủ dữ liệu hạng mục nên chưa thể lưu.' : 'Hạng mục chưa được xác nhận (Confirm Material) nên không sửa được.'));
              svBtn.addEventListener('click', function() {
                var bad = '', vals = {};
                flds.forEach(function(f) {
                  var on = f.cb.checked, q = on ? parseFloat(String(f.qi.value).replace(/,/g, '')) : 0;
                  if (on && (isNaN(q) || q <= 0)) bad = bad || ('Nhập số lượng > 0 cho ' + f.name + '.');
                  vals[f.col] = on ? q : ((f.orig == null || f.orig === '') ? '' : 0);
                });
                var rsiQ = qn(x.RSI_QTY), mrfQ = qn(x.MRF_QTY), inQ = qn(x.IN_QTY);
                if (!bad && inQ < (rsiQ - mrfQ)) bad = "In Q'ty nhỏ hơn (RSI Q'ty − MRF Q'ty), không thể lưu.";
                if (bad) { svMsg.style.color = '#dc2626'; svMsg.textContent = bad; return; }
                var win = doc.defaultView;
                if (win.confirm && !win.confirm('Lưu thay đổi của hạng mục này?')) return;
                var row = {
                  PROJECT_NO: x.PROJECT_NO || diProj(idoc), TRK_ITEM_NAME: x.TRK_ITEM_NAME, PACKAGE_NO: x.PACKAGE_NO, MATERIAL_CODE: x.MATERIAL_CODE,
                  ITEM_SIZE: x.ITEM_SIZE, DESCRIPTION: x.DESCRIPTION, DRAWING_NO: x.DRAWING_NO, LOCATION: x.LOCATION, TAG_NO: x.TAG_NO, UNIT: x.UNIT,
                  IN_QTY: (x.IN_QTY === '' || x.IN_QTY == null) ? '' : inQ, MATERIAL: x.MATERIAL, REMARKS: rmk.value,
                  REPORT_SHORT: qn(vals.REPORT_SHORT) > 0 ? '1' : '0', REPORT_OVER: qn(vals.REPORT_OVER) > 0 ? '1' : '0',
                  REPORT_DMG: qn(vals.REPORT_DMG) > 0 ? '1' : '0', REPORT_MISSING: qn(vals.REPORT_MISSING) > 0 ? '1' : '0',
                  REPORT_SHORT_QTY: vals.REPORT_SHORT, REPORT_OVER_QTY: vals.REPORT_OVER, REPORT_DMG_QTY: vals.REPORT_DMG, REPORT_MISSING_QTY: vals.REPORT_MISSING
                };
                for (var k in row) if (row[k] == null) row[k] = '';
                svBtn.disabled = true; svMsg.style.color = ''; svMsg.textContent = 'Đang lưu…';
                diSave(idoc, [row], function() {
                  svBtn.disabled = false; svMsg.style.color = '#15803d'; svMsg.textContent = 'Đã lưu ✓';
                  x.REMARKS = row.REMARKS;
                  ['REPORT_SHORT', 'REPORT_OVER', 'REPORT_DMG', 'REPORT_MISSING'].forEach(function(c) { x[c] = row[c]; x[c + '_QTY'] = row[c + '_QTY']; });
                  flds.forEach(function(f) { f.orig = row[f.col + '_QTY']; });
                  try { delete (diTop(idoc).__desmDI || {})[pkgNo]; } catch (e) {}
                  try { if (ov.parentNode) loadItems(true); } catch (e) {}
                }, function(msg) {
                  svBtn.disabled = false; svMsg.style.color = '#dc2626'; svMsg.textContent = 'Lưu thất bại: ' + msg;
                });
              });
              b.appendChild(svBtn); b.appendChild(svMsg);
              var lub = el('button', 'desm-detail-list', 'Location Update'); lub.type = 'button';
              lub.addEventListener('click', function() { updateItemsLoc([x]); });
              b.appendChild(lub);
              var elb = el('button', 'desm-detail-list', 'Lịch sử thay đổi (Edit Log)'); elb.type = 'button';
              elb.addEventListener('click', function() { openEditLog(x); });
              b.appendChild(elb);
              var rb = el('button', 'desm-detail-list', 'RSI & MRF List  ↑'); rb.type = 'button';
              var rn = el('div', 'desm-detail-note', 'Đang tải RSI & MRF…'), rl = el('div', 'desm-ditems'), open = true;
              var rl1 = el('div', ''), rl2 = el('div', ''); rl.appendChild(rl1); rl.appendChild(rl2);
              rb.addEventListener('click', function() { open = !open; rl.style.display = open ? '' : 'none'; rb.textContent = 'RSI & MRF List  ' + (open ? '↑' : '↓'); });
              b.appendChild(rb); b.appendChild(rn); b.appendChild(rl);
              var pend = 2, cnt = 0, failed = 0;
              function done() {
                if (--pend > 0 || !S.ov.parentNode) return;
                rn.textContent = cnt ? '' : (failed ? 'Không tải được danh sách RSI/MRF.' : 'Hạng mục này chưa có phiếu RSI hoặc MRF.');
              }
              diAjax(idoc, '/getDesmRsiViewList.do', rsiParam({ PROJECT_NO: x.PROJECT_NO, MATERIAL_CODE: x.MATERIAL_CODE }), function(list) {
                if (!S.ov.parentNode) return;
                var hit = [].filter.call(list, function(r) { return sameStr(r.MATERIAL_CODE, x.MATERIAL_CODE); });
                cnt += hit.length;
                hit.forEach(function(r) {
                  var c = el('div', 'desm-rsi-card');
                  var t1 = el('div', 'desm-rsi-row'); t1.appendChild(el('span', 'desm-ditem-no', dash(r.RSI_NO))); t1.appendChild(el('span', '', dash(r.STATUS)));
                  c.appendChild(t1);
                  c.appendChild(el('div', 'desm-ditem-l', dash(r.SUBCONTRACTOR) + ' · ' + dash(r.RSI_NAME)));
                  var t3 = el('div', 'desm-rsi-row'); t3.appendChild(el('span', '', dash(r.RSI_APPROVED_DATE || r.REQUEST_DATE)));
                  t3.appendChild(el('span', '', fnum(r.REQ_QTY) + ' ' + (r.UNIT || ''))); c.appendChild(t3);
                  c.addEventListener('click', function() { openRsiDetail(r); });
                  rl1.appendChild(c);
                });
                done();
              }, function() { failed++; done(); });
              // MRF của hạng mục (/getMrfSummaryList.do): mỗi dòng là một thẻ, chạm để xem cả MRF
              diAjax(idoc, '/getMrfSummaryList.do', mrfParam({ PROJECT_NO: x.PROJECT_NO, MATERIAL_CODE: x.MATERIAL_CODE }), function(list) {
                if (!S.ov.parentNode) return;
                var hit = [].filter.call(list, function(r) { return sameStr(r.MATERIAL_CODE, x.MATERIAL_CODE); });
                cnt += hit.length;
                hit.forEach(function(r) {
                  var c = el('div', 'desm-rsi-card desm-mrf-card');
                  var t1 = el('div', 'desm-rsi-row'); t1.appendChild(el('span', 'desm-ditem-no', dash(r.MRF_NO)));
                  t1.appendChild(el('span', '', dash(r.STATUS))); c.appendChild(t1);
                  c.appendChild(el('div', 'desm-ditem-l', dash(r.SUBCONTRACTOR)));
                  var t3 = el('div', 'desm-rsi-row'); t3.appendChild(el('span', '', dash(r.MRF_NAME)));
                  t3.appendChild(el('span', '', dash(r.RETURN_REQ_DATE))); c.appendChild(t3);
                  var t4 = el('div', 'desm-rsi-row'); t4.appendChild(el('span', '', dash(r.DESCRIPTION || r.RSI_DESCRIPTION)));
                  t4.appendChild(el('span', '', fnum(r.MRF_REQ_RETURN_QTY) + ' ' + (r.UNIT || x.UNIT || ''))); c.appendChild(t4);
                  c.addEventListener('click', function() { openMrfDetail(r, x.UNIT); });
                  rl2.appendChild(c);
                });
                done();
              }, function() { failed++; done(); });
            }
            // Màn "Edit Log": lịch sử chỉnh sửa của một hạng mục. Dữ liệu: /getDesmPlDetailEditLogList.do {PROJECT_NO, TRK_ITEM_NAME, MATERIAL_CODE}
            // (giống popup "Material record" của plDetail.js / desmPlDtlEditLogPopUp.js; results là mảng dòng). Mỗi dòng là một bản ghi sau lần sửa;
            // so từng bản với bản cũ hơn liền kề để hiện phần thay đổi.
            function openEditLog(x) {
              var S = subScreen('Edit Log', 'Detail Item'), b = S.body;
              var m = el('div', 'desm-dcard');
              m.appendChild(el('div', 'desm-d-h', dash(x.MATERIAL_CODE)));
              m.appendChild(el('div', 'desm-d-l', dash(x.DESCRIPTION)));
              m.appendChild(el('div', 'desm-d-l', dash(x.PACKAGE_NO)));
              b.appendChild(m);
              var rn = el('div', 'desm-detail-note', 'Đang tải…'), rl = el('div', 'desm-ditems');
              b.appendChild(rn); b.appendChild(rl);
              if (!x.TRK_ITEM_NAME) { rn.textContent = 'Chưa tải đủ dữ liệu hạng mục (thiếu TRK_ITEM_NAME) nên chưa xem được Edit Log.'; return; }
              var FIELDS = [['LOCATION', 'Location'], ['IN_QTY', "In Q'ty"], ['REMARKS', 'Remarks'], ['DESCRIPTION', 'Item'], ['DRAWING_NO', 'DWG'], ['TAG_NO', 'TAG'], ['UNIT', 'Unit'],
                ['MATERIAL', 'Material'], ['REPORT_SHORT_QTY', 'Short'], ['REPORT_OVER_QTY', 'Over'], ['REPORT_DMG_QTY', 'DMG'], ['REPORT_MISSING_QTY', 'Missing']];
              function v(r, k) { return String(r[k] == null ? '' : r[k]).replace(/\s+/g, ' ').trim(); }
              diAjax(idoc, '/getDesmPlDetailEditLogList.do', { PROJECT_NO: x.PROJECT_NO || diProj(idoc), TRK_ITEM_NAME: x.TRK_ITEM_NAME, MATERIAL_CODE: x.MATERIAL_CODE }, function(list) {
                if (!S.ov.parentNode) return;
                var rows = [].slice.call(list);
                rows.sort(function(a, c) { return v(c, 'CREATION_DATE_TXT') > v(a, 'CREATION_DATE_TXT') ? 1 : (v(c, 'CREATION_DATE_TXT') < v(a, 'CREATION_DATE_TXT') ? -1 : 0); });
                rn.textContent = rows.length ? rows.length + ' bản ghi (mới nhất trước)' : 'Hạng mục này chưa có lịch sử chỉnh sửa.';
                rows.forEach(function(r, i) {
                  var c = el('div', 'desm-rsi-card');
                  var t1 = el('div', 'desm-rsi-row'); t1.appendChild(el('span', 'desm-ditem-no', dash(r.CREATION_DATE_TXT))); t1.appendChild(el('span', '', dash(r.CREATED_BY))); c.appendChild(t1);
                  var old = rows[i + 1], diffs = [];
                  if (old) FIELDS.forEach(function(f) { if (v(r, f[0]) !== v(old, f[0])) diffs.push(f[1] + ': ' + (v(old, f[0]) || '-') + ' → ' + (v(r, f[0]) || '-')); });
                  if (old) c.appendChild(el('div', 'desm-ditem-l', diffs.length ? 'Thay đổi — ' + diffs.join(' · ') : 'Không đổi so với bản trước'));
                  c.appendChild(el('div', 'desm-ditem-l', '📍 ' + dash(r.LOCATION) + (r.LOC_UPDATE_DATE ? '   (' + r.LOC_UPDATE_DATE + (r.LOC_UPDATED_BY ? ' · ' + r.LOC_UPDATED_BY : '') + ')' : '')));
                  c.appendChild(el('div', 'desm-ditem-l', "In Q'ty : " + fnum(r.IN_QTY) + ' ' + (r.UNIT || '') + (r.REMARKS ? '   Remarks : ' + r.REMARKS : '')));
                  var rep = [['Short', 'REPORT_SHORT_QTY'], ['Over', 'REPORT_OVER_QTY'], ['DMG', 'REPORT_DMG_QTY'], ['Missing', 'REPORT_MISSING_QTY']]
                    .filter(function(f) { return parseFloat(v(r, f[1])) > 0; }).map(function(f) { return f[0] + ' ' + fnum(r[f[1]]); });
                  if (rep.length) c.appendChild(el('div', 'desm-ditem-l', rep.join(' · ')));
                  rl.appendChild(c);
                });
              }, function() { if (S.ov.parentNode) rn.textContent = 'Không tải được Edit Log.'; });
            }
            // Màn "Lịch sử thay đổi vị trí" của cả kiện: gom Edit Log của mọi hạng mục trong kiện, chỉ giữ các lần LOCATION đổi,
            // gộp các hạng mục được chuyển cùng lúc (cùng ngày, người, vị trí cũ -> mới) thành một dòng.
            function openLocLog() {
              var S = subScreen('Lịch sử thay đổi vị trí', 'Package'), b = S.body;
              var m = el('div', 'desm-dcard'); m.appendChild(el('div', 'desm-d-h', pkgNo)); b.appendChild(m);
              var rn = el('div', 'desm-detail-note', 'Đang tải…'), rl = el('div', 'desm-ditems');
              b.appendChild(rn); b.appendChild(rl);
              function v(r, k) { return String(r[k] == null ? '' : r[k]).replace(/\s+/g, ' ').trim(); }
              diAjax(idoc, '/getIdsmOsDetailList.do', { PAGE_NUM: 1, PAGE_CNT: 5000, PROJECT_NO: diProj(idoc), PACKAGE_LIST_NO: '', PACKAGE_NO: pkgNo, DESCRIPTION: '', DRAWING_NO: '',
                TAG_NO: '', QTY_TYPE: 'rsi', QTY: '', KEY1: '', VALUE1: '', LOCATION: '', SEQUENCE: '', VENDOR: '', ATTRIBUTE10: '',
                TYPE: '', CATEGORY: '', SUB_CATEGORY: '', COMMENTS: '' }, function(list) {
                if (!S.ov.parentNode) return;
                var items = [].filter.call(list, function(r) { return r && r.TRK_ITEM_NAME; });
                if (!items.length) { rn.textContent = 'Kiện này chưa có hạng mục chi tiết để tra lịch sử.'; return; }
                var events = [], idx = 0, running = 0, done = 0, failed = 0;
                function finish() {
                  if (!S.ov.parentNode) return;
                  var groups = {}, order = [];
                  events.forEach(function(e) {
                    var k = [e.date, e.by, e.from, e.to].join('|');
                    if (!groups[k]) { groups[k] = { e: e, labels: [] }; order.push(k); }
                    if (groups[k].labels.indexOf(e.label) < 0) groups[k].labels.push(e.label);
                  });
                  var gs = order.map(function(k) { return groups[k]; });
                  gs.sort(function(a, c) { return a.e.date < c.e.date ? 1 : (a.e.date > c.e.date ? -1 : 0); });
                  rn.textContent = gs.length ? gs.length + ' lần đổi vị trí (mới nhất trước)' : 'Kiện này chưa có lịch sử thay đổi vị trí.';
                  if (failed) rn.textContent += ' · ' + failed + ' hạng mục không tải được log';
                  gs.forEach(function(g) {
                    var c = el('div', 'desm-rsi-card');
                    var t1 = el('div', 'desm-rsi-row'); t1.appendChild(el('span', 'desm-ditem-no', dash(g.e.date))); t1.appendChild(el('span', '', dash(g.e.by))); c.appendChild(t1);
                    c.appendChild(el('div', 'desm-ditem-l', '📍 ' + (g.e.from || '(ban đầu)') + ' → ' + dash(g.e.to)));
                    var shownL = g.labels.slice(0, 3).join(' · ') + (g.labels.length > 3 ? ' …' : '');
                    c.appendChild(el('div', 'desm-ditem-l', g.labels.length + ' hạng mục: ' + shownL));
                    rl.appendChild(c);
                  });
                }
                function after() {
                  running--; done++;
                  if (done >= items.length) { finish(); return; }
                  rn.textContent = 'Đang tải… ' + done + '/' + items.length;
                  next();
                }
                function next() {
                  while (running < 4 && idx < items.length) {
                    (function(it) {
                      running++;
                      diAjax(idoc, '/getDesmPlDetailEditLogList.do', { PROJECT_NO: it.PROJECT_NO || diProj(idoc), TRK_ITEM_NAME: it.TRK_ITEM_NAME, MATERIAL_CODE: it.MATERIAL_CODE }, function(l2) {
                        var rows = [].slice.call(l2);
                        rows.sort(function(a, c) { var x1 = v(a, 'CREATION_DATE_TXT'), x2 = v(c, 'CREATION_DATE_TXT'); return x1 > x2 ? 1 : (x1 < x2 ? -1 : 0); });
                        rows.forEach(function(r, i) {
                          var loc = v(r, 'LOCATION'), prev = i ? v(rows[i - 1], 'LOCATION') : '';
                          if (i ? loc !== prev : !!loc) {
                            events.push({ date: v(r, 'LOC_UPDATE_DATE') || v(r, 'CREATION_DATE_TXT'), by: v(r, 'LOC_UPDATED_BY') || v(r, 'CREATED_BY'),
                              from: prev, to: loc, label: v(it, 'DESCRIPTION') || v(it, 'MATERIAL_CODE') });
                          }
                        });
                        after();
                      }, function() { failed++; after(); });
                    })(items[idx++]);
                  }
                }
                next();
              }, function() { if (S.ov.parentNode) rn.textContent = 'Không tải được danh sách hạng mục của kiện.'; });
            }
            function mrfParam(over) {
              var p = { PROJECT_NO: '', RSI_NO: '', RSI_NAME: '', SUBCONTRACTOR: '', MATERIAL_CODE: '', RSI_START_REQUEST_DATE: '', RSI_END_REQUEST_DATE: '',
                ZIM_ATTRIBUTE10: '', RSI_BALANCE_QTY: '', TYPE: '', CATEGORY: '', SUB_CATEGORY: '', PACKING_LIST_NO: '', MRF_NO: '', MRF_NAME: '',
                PACKAGE_NO: '', ITEM_DESC: '', RETURN_TYPE: '', MRF_BALANCE_QTY: '' };
              for (var k in over) p[k] = over[k];
              if (!p.PROJECT_NO) p.PROJECT_NO = diProj(idoc);
              return p;
            }
            // Màn "MRF Detail": các dòng của một MRF (RSI, kiện, vật tư, số lượng trả, vị trí). Dữ liệu: /getMrfSummaryList.do
            function openMrfDetail(h, unit) {
              var S = subScreen('MRF Detail', 'Detail Item'), b = S.body;
              var m = el('div', 'desm-dcard desm-mrf-head');
              m.appendChild(el('div', 'desm-d-h', dash(h.MRF_NO)));
              m.appendChild(el('div', 'desm-d-l', dash(h.SUBCONTRACTOR) + ' · ' + dash(h.STATUS)));
              m.appendChild(el('div', 'desm-d-l', dash(h.MRF_NAME)));
              if (h.RETURN_REQ_DATE) m.appendChild(el('div', 'desm-d-l', 'Ngày yêu cầu trả : ' + h.RETURN_REQ_DATE));
              b.appendChild(m);
              var rn = el('div', 'desm-detail-note', 'Đang tải…'), rl = el('div', 'desm-ditems');
              b.appendChild(rn); b.appendChild(rl);
              diAjax(idoc, '/getMrfSummaryList.do', mrfParam({ PROJECT_NO: h.PROJECT_NO, MRF_NO: h.MRF_NO }), function(list) {
                if (!S.ov.parentNode) return;
                var rows = [].filter.call(list, function(r) { return sameStr(r.MRF_NO, h.MRF_NO); });
                rn.textContent = rows.length ? rows.length + ' dòng' : 'MRF này không có dòng nào.';
                rows.forEach(function(r) {
                  var c = el('div', 'desm-rsi-card desm-mrf-card');
                  var t1 = el('div', 'desm-rsi-row'); t1.appendChild(el('span', 'desm-ditem-no', dash(r.RSI_NO)));
                  t1.appendChild(el('span', 'desm-mrf-type', dash(r.RETURN_TYPE))); c.appendChild(t1);
                  c.appendChild(el('div', 'desm-ditem-no', dash(r.RSI_NAME)));
                  c.appendChild(el('div', 'desm-ditem-no', dash(r.PACKAGE_NO)));
                  c.appendChild(el('div', 'desm-ditem-l', dash(r.DESCRIPTION || r.RSI_DESCRIPTION)));
                  c.appendChild(el('div', 'desm-ditem-l', 'DWG : ' + (r.DRAWING_NO || 'N/A') + '   TAG : ' + (r.TAG_NO || 'N/A')));
                  var ft = el('div', 'desm-rsi-row'); ft.appendChild(el('span', '', dash(r.MATERIAL_CODE)));
                  ft.appendChild(el('span', 'desm-mrf-type', fnum(r.MRF_REQ_RETURN_QTY) + ' / ' + fnum(r.MRF_RETURN_QTY) + ' ' + (r.UNIT || unit || ''))); c.appendChild(ft);
                  c.appendChild(el('div', 'desm-ditem-l', '📍 ' + dash(r.LOCATION) + '   Req : ' + dash(r.RETURN_REQ_DATE)));
                  rl.appendChild(c);
                });
              }, function() { if (S.ov.parentNode) rn.textContent = 'Không tải được chi tiết MRF.'; });
            }
            // Màn "RSI Detail": các hạng mục thuộc một RSI, lọc theo PKG / SCH
            function openRsiDetail(h) {
              var S = subScreen('RSI Detail', 'Detail Item'), b = S.body;
              var m = el('div', 'desm-dcard');
              m.appendChild(el('div', 'desm-d-h', dash(h.RSI_NO)));
              m.appendChild(el('div', 'desm-d-l', dash(h.SUBCONTRACTOR) + ' · ' + dash(h.STATUS)));
              m.appendChild(el('div', 'desm-d-l', dash(h.RSI_NAME)));
              m.appendChild(el('div', 'desm-d-l', dash(h.RSI_APPROVED_DATE || h.REQUEST_DATE)));
              b.appendChild(m);
              var fb = el('div', 'desm-sub-filter');
              var fp = doc.createElement('input'); fp.placeholder = 'PKG.'; fp.className = 'desm-sub-in';
              var fs = doc.createElement('input'); fs.placeholder = 'SCH.'; fs.className = 'desm-sub-in';
              fb.appendChild(fp); fb.appendChild(fs); b.appendChild(fb);
              var rn = el('div', 'desm-detail-note', 'Đang tải…'), rl = el('div', 'desm-ditems'), all = [];
              b.appendChild(rn); b.appendChild(rl);
              function draw() {
                while (rl.firstChild) rl.removeChild(rl.firstChild);
                var p = fp.value.trim().toLowerCase(), s = fs.value.trim().toLowerCase();
                var rows = all.filter(function(r) {
                  return (!p || String(r.PACKAGE_NO || '').toLowerCase().indexOf(p) >= 0) &&
                    (!s || (String(r.DESCRIPTION || '') + ' ' + String(r.MATERIAL_CODE || '')).toLowerCase().indexOf(s) >= 0);
                });
                rn.textContent = all.length ? rows.length + ' / ' + all.length + ' hạng mục' : 'RSI này không có hạng mục.';
                rows.forEach(function(r) {
                  var c = el('div', 'desm-rsi-card');
                  c.appendChild(el('div', 'desm-ditem-no', dash(r.PACKAGE_NO)));
                  c.appendChild(el('div', 'desm-ditem-l', dash(r.DESCRIPTION)));
                  var ft = el('div', 'desm-rsi-row'); ft.appendChild(el('span', '', dash(r.MATERIAL_CODE)));
                  ft.appendChild(el('span', '', fnum(r.REQ_QTY) + ' / ' + fnum(r.HANDOVER_QTY) + ' ' + (r.UNIT || ''))); c.appendChild(ft);
                  rl.appendChild(c);
                });
              }
              fp.addEventListener('input', draw); fs.addEventListener('input', draw);
              diAjax(idoc, '/getDesmRsiViewList.do', rsiParam({ PROJECT_NO: h.PROJECT_NO, RSI_NO: h.RSI_NO }), function(list) {
                if (!S.ov.parentNode) return;
                all = [].filter.call(list, function(r) { return sameStr(r.RSI_NO, h.RSI_NO); });
                draw();
              }, function() { if (S.ov.parentNode) rn.textContent = 'Không tải được danh sách hạng mục của RSI.'; });
            }
            function renderItems(rows) {
              while (dis.firstChild) dis.removeChild(dis.firstChild);
              chosen = []; itemCards = []; selAll = null; selTxt = null;
              if (rows.length) {
                selBar = el('label', 'desm-ditems-bar');
                selAll = doc.createElement('input'); selAll.type = 'checkbox'; selAll.className = 'desm-chk';
                selAll.addEventListener('change', function() {
                  chosen = selAll.checked ? itemCards.map(function(ic) { return ic.x; }) : [];
                  refreshSel();
                });
                selTxt = el('span', 'desm-cards-count', '');
                selBar.appendChild(selAll); selBar.appendChild(selTxt); dis.appendChild(selBar);
              }
              rows.forEach(function(x) {
                var c = el('div', 'desm-ditem');
                var ck = doc.createElement('input'); ck.type = 'checkbox'; ck.className = 'desm-chk desm-ditem-chk';
                c.appendChild(ck); c.appendChild(el('span', 'desm-card-hit'));
                var noEl = el('div', 'desm-ditem-no', x.PACKAGE_NO);
                noEl.addEventListener('click', function(ev) { ev.stopPropagation(); openItemDetail(x); });
                c.appendChild(noEl);
                c.appendChild(el('div', 'desm-ditem-l', dash(x.DESCRIPTION)));
                c.appendChild(el('div', 'desm-ditem-l', dash(x.DRAWING_NO)));
                c.appendChild(el('div', 'desm-ditem-l', dash(x.TAG_NO)));
                c.appendChild(el('div', 'desm-ditem-l', dash(x.REMARKS || x.COMMENTS)));
                var ft = el('div', 'desm-ditem-foot');
                ft.appendChild(el('span', '', dash(x.MATERIAL_CODE)));
                var lc2 = el('span', 'desm-d-loc');
                var sv2 = doc.createElementNS(NS, 'svg'); sv2.setAttribute('viewBox', '0 0 24 24');
                sv2.setAttribute('width', '16'); sv2.setAttribute('height', '16');
                var p2 = doc.createElementNS(NS, 'path'); p2.setAttribute('d', pth.getAttribute('d'));
                p2.setAttribute('fill', 'none'); p2.setAttribute('stroke', 'currentColor'); p2.setAttribute('stroke-width', '2');
                sv2.appendChild(p2); lc2.appendChild(sv2); lc2.appendChild(el('span', '', dash(x.LOCATION)));
                lc2.classList.add('desm-ditem-locbtn');
                // Chạm ghim = cập nhật riêng hạng mục này; chạm thẻ = tích chọn (để cập nhật hàng loạt bằng nút ở đáy)
                lc2.addEventListener('click', function(ev) { ev.stopPropagation(); updateItemsLoc([x]); });
                // Chạm ô vuông bên trái = tích chọn (để cập nhật vị trí hàng loạt); chạm chỗ khác trên thẻ = mở chi tiết hạng mục
                c.addEventListener('click', function(ev) {
                  if (!(ev.target && ev.target.classList && ev.target.classList.contains('desm-card-hit'))) { openItemDetail(x); return; }
                  var i = chosen.indexOf(x); if (i >= 0) chosen.splice(i, 1); else chosen.push(x);
                  refreshSel();
                });
                ft.appendChild(lc2); c.appendChild(ft); dis.appendChild(c);
                itemCards.push({ x: x, card: c, ck: ck });
              });
              if (!rows.length) note.textContent = 'Không có hạng mục chi tiết nào cho kiện này.';
              else { note.textContent = ''; lines.lastChild.textContent = String(rows.length); }
              refreshSel();
            }
            var LSK = 'desmDI2:' + pkgNo, shown = null;
            function lsGet() { try { var v = JSON.parse(localStorage.getItem(LSK) || 'null'); return v && v.rows && v.rows.length ? v.rows : null; } catch (e) { return null; } }
            function lsSet(rows) { try { if (rows && rows.length) localStorage.setItem(LSK, JSON.stringify({ t: Date.now(), rows: rows })); } catch (e) {} }
            function lsDel() { try { localStorage.removeItem(LSK); } catch (e) {} }
            function loadItems(fresh) {
              if (fresh) { lsDel(); shown = null; }
              var cached = fresh ? null : lsGet();
              if (cached) { shown = JSON.stringify(cached); renderItems(cached); note.textContent = 'Đang cập nhật…'; }
              else note.textContent = 'Đang tải danh sách hạng mục…';
              diLoadFast(idoc, pkgNo, function(rows) {
                if (!ov.parentNode) return;
                if (rows && shown) {
                  lsSet(rows);
                  if (JSON.stringify(rows) !== shown) { shown = JSON.stringify(rows); renderItems(rows); } else note.textContent = '';
                  return;
                }
                if (rows) lsSet(rows);
                if (!rows && shown) { note.textContent = ''; return; }
                if (!rows) {
                  note.textContent = 'Không tải được danh sách hạng mục. ';
                  var rb = el('button', 'desm-detail-list', 'Thử lại'); rb.type = 'button';
                  rb.addEventListener('click', function() { loadItems(true); });
                  note.appendChild(rb);
                  return;
                }
                renderItems(rows);
              }, nLines, true);
            }
            // Lưu vị trí thật xong (saveDesmLocation.do, sau khi bấm OK ở hộp thoại xác nhận) thì tự bấm "‹ Xong"
            // để quay về danh sách hạng mục của kiện (danh sách tự nạp lại). Chỉ tự quay lại 1 lần cho mỗi lần mở.
            function autoBackOnSave() {
              try {
                var fr = diTop(idoc).document.getElementById('desmDetailFrame'), fw = fr && fr.contentWindow; if (!fw) return;
                fw.__desmAutoBack = 1;
                diClean(fr, true);
                function goBack() {
                  try { var bk = diTop(idoc).document.querySelector('#desmDetailFrameBar .desm-detail-back'); if (bk) bk.click(); } catch (e) {}
                }
                // Đóng/hủy xong mà không còn hộp thoại nào đang mở (bản đồ, xác nhận...) thì mới quay về chi tiết kiện.
                // KHÔNG quay lại ngay khi hộp thoại bản đồ ẩn đi: DESM ẩn nó để hiện hộp thoại xác nhận (OK/Cancel).
                function anyModalOpen() {
                  var docs = [fw.document]; try { docs.push(diTop(idoc).document); } catch (e) {}
                  for (var di = 0; di < docs.length; di++) {
                    var ms = docs[di].querySelectorAll('.modal'), vw = docs[di].defaultView;
                    for (var mi = 0; mi < ms.length; mi++) {
                      try {
                        var cs = vw.getComputedStyle(ms[mi]);
                        if (cs.display !== 'none' && cs.visibility !== 'hidden' && parseFloat(cs.opacity || '1') > 0.05 && ms[mi].offsetHeight > 0) return true;
                      } catch (e) {}
                    }
                  }
                  return false;
                }
                function backWhenIdle() {
                  if (fw.__desmIdleTimer) return;
                  var calm = 0, n = 0;
                  fw.__desmIdleTimer = fw.setInterval(function() {
                    n++;
                    if (anyModalOpen()) calm = 0; else calm++;
                    if (calm >= 3 || n > 100) { fw.clearInterval(fw.__desmIdleTimer); fw.__desmIdleTimer = 0; if (calm >= 3) goBack(); }
                  }, 500);
                }
                if (fw.jQuery && !fw.__desmHideHook) {
                  fw.__desmHideHook = 1;
                  fw.jQuery(fw.document).on('hidden.bs.modal hidden', '#dlgDesmLocation', function() { backWhenIdle(); });
                }
                if (fw.__desmSaveHook) return;
                fw.__desmSaveHook = 1;
                var X = fw.XMLHttpRequest.prototype, oo = X.open, os = X.send;
                X.open = function(m, u) { try { this.__desmU = String(u == null ? '' : u); } catch (e) {} return oo.apply(this, arguments); };
                X.send = function() {
                  var x = this;
                  // CHÚ Ý: saveDesmLocationCheck.do chỉ là bước KIỂM TRA trước khi hiện hộp thoại xác nhận. Việc lưu thật là
                  // saveDesmLocation.do (chạy sau khi bấm OK). Chỉ quay lại sau khi lưu thật thành công (không có "error").
                  if (/saveDesmLocation\.do/.test(x.__desmU || '')) {
                    x.addEventListener('loadend', function() {
                      var good = false;
                      try { good = x.status === 200 && !/"error"\s*:\s*(?!null\b)/i.test(x.responseText || ''); } catch (e) {}
                      if (!good || !fw.__desmAutoBack) return;
                      fw.__desmAutoBack = 0;
                      setTimeout(goBack, 1300);
                    });
                  }
                  return os.apply(this, arguments);
                };
              } catch (e) {}
            }
            // Cập nhật vị trí cho một hoặc nhiều hạng mục (như nút Location Update ở trang Hạng mục chi tiết)
            function updateItemsLoc(xs) {
              note.textContent = 'Đang mở cập nhật vị trí…';
              // Hiện khung lên toàn màn hình TRƯỚC khi bấm Location Update: hộp thoại bản đồ mở trong khung đang hiển thị
              // (trước đây mở lúc khung còn ẩn ngoài màn hình nên bản đồ không tải/không vẽ được).
              diShow(idoc, function() {
                try { delete (diTop(idoc).__desmDI || {})[pkgNo]; } catch (e) {}
                if (ov.parentNode) loadItems(true);
              });
              diSelect(idoc, pkgNo, xs, function(ok) {
                if (ok) { note.textContent = ''; autoBackOnSave(); return; }
                note.textContent = 'Không chọn được hạng mục (lưới chưa sẵn sàng). Thử lại sau vài giây.';
                try { var bk = diTop(idoc).document.querySelector('#desmDetailFrameBar .desm-detail-back'); if (bk) bk.click(); } catch (e) {}
              });
            }
            loadItems();
            var llb = el('button', 'desm-detail-list', 'Lịch sử thay đổi vị trí'); llb.type = 'button';
            llb.addEventListener('click', function() { openLocLog(); });
            body.appendChild(llb);
            body.appendChild(dl); body.appendChild(note); body.appendChild(dis);
            ov.appendChild(body);
            // Nút Location Update: chỉ chọn đúng kiện này rồi bấm nút cập nhật vị trí gốc của DESM
            lu = el('button', 'desm-detail-lu', 'Location Update'); lu.type = 'button';
            lu.addEventListener('click', function() {
              if (chosen.length) { updateItemsLoc(chosen.slice()); return; }
              var btn = idoc.getElementById('btnLocationSetup');
              if (!btn) { note.textContent = 'Không tìm thấy nút cập nhật vị trí trên trang.'; return; }
              try {
                for (var id in G.Rows) {
                  var x = G.Rows[id]; if (!x || x.Kind !== 'Data') continue;
                  var s = !!x.Selected && x.Selected !== '0';
                  if (id === rowId ? !s : s) G.SelectRow(x, id === rowId ? 1 : 0);
                }
              } catch (e) {}
              close(); btn.click();
            });
            ov.appendChild(lu);
            refreshSel();
            doc.documentElement.classList.add('desm-detail-open');
            doc.body.appendChild(ov);
          }
          // Lưới Package dạng thẻ (card): mỗi kiện hàng một thẻ gồm Package No, mô tả, loại kiện, A/O và Location.
          // Chạm thẻ = chọn dòng tương ứng trong lưới TreeGrid (ẩn bên dưới) để Location Update/Delete hoạt động.
          function cardView(doc) {
            var win = doc.defaultView; if (!win || !win.TGGrids || !win.TGGrids.length) return;
            var G = null;
            for (var gi = 0; gi < win.TGGrids.length; gi++) {
              var g = win.TGGrids[gi];
              if (g && g.Cols && g.Cols.PACKAGE_NO && g.Cols.STORAGE_LOCATION && g.Rows) { G = g; break; }
            }
            if (!G || !G.MainTag) return;
            // MainTag có thể là chính khung chứa lưới hoặc thẻ .GridMain bên trong: luôn lấy đúng khung chứa lưới
            var gm = G.MainTag;
            if (!(gm.classList && gm.classList.contains('GridMain')) && gm.querySelector) {
              var inner = gm.querySelector('.GridMain'); if (inner) gm = inner;
            }
            var host = gm.parentNode;
            // An toàn: không bao giờ ẩn khung đang chứa thanh lọc / thanh nút
            if (!host || !host.parentNode || host.contains(doc.getElementById('toolbar')) || host.querySelector('.desm-filter-bar')) return;
            // Cho phần quét camera mở thẳng màn hình chi tiết của một kiện theo id dòng
            win.__desmOpenPkg = function(id) {
              try {
                var r0 = G.Rows[id]; if (!r0) return false;
                var list = diRows(G), n = 1;
                for (var k = 0; k < list.length; k++) { if (list[k].id === id) { n = k + 1; break; } }
                openDetail(doc, G, id, n, function() { var b2 = doc.getElementById('desmCards'); if (b2) b2.__sig = null; cardView(doc); });
                return true;
              } catch (e) { return false; }
            };
            if (win.__desmCards === undefined) win.__desmCards = true;
            var on = !!win.__desmCards;
            var box = doc.getElementById('desmCards');
            if (!box) {
              box = doc.createElement('div'); box.id = 'desmCards';
              host.parentNode.insertBefore(box, host.nextSibling);
            }
            var tb = doc.getElementById('toolbar');
            if (tb && !doc.getElementById('desmViewToggle')) {
              var vb = doc.createElement('button');
              vb.type = 'button'; vb.id = 'desmViewToggle'; vb.className = 'btn btn-secondary btn-sm';
              vb.addEventListener('click', function(e) {
                e.preventDefault(); e.stopPropagation();
                win.__desmCards = !win.__desmCards; box.__sig = null;
                cardView(doc);
              });
              tb.appendChild(vb);
            }
            var vb2 = doc.getElementById('desmViewToggle');
            if (vb2) vb2.textContent = on ? 'Dạng: Thẻ' : 'Dạng: Bảng';
            // Tùy chọn khi chạm thẻ: "Chọn" (chọn dòng như cũ) hoặc "Chi tiết" (mở màn hình thông tin kiện hàng)
            if (win.__desmTapDetail === undefined) {
              var sv = ''; try { sv = win.localStorage.getItem('desmTapDetail2') || ''; } catch (e) {}
              win.__desmTapDetail = sv !== '0';   // mặc định: chạm thẻ = mở chi tiết; chạm ô vuông bên trái = chọn (để Location Update)
            }
            if (tb && !doc.getElementById('desmTapToggle')) {
              var tt = doc.createElement('button');
              tt.type = 'button'; tt.id = 'desmTapToggle'; tt.className = 'btn btn-secondary btn-sm';
              tt.addEventListener('click', function(e) {
                e.preventDefault(); e.stopPropagation();
                win.__desmTapDetail = !win.__desmTapDetail;
                try { win.localStorage.setItem('desmTapDetail2', win.__desmTapDetail ? '1' : '0'); } catch (e2) {}
                box.__sig = null; cardView(doc);
              });
              tb.appendChild(tt);
            }
            var tt2 = doc.getElementById('desmTapToggle');
            if (tt2) tt2.textContent = win.__desmTapDetail ? 'Chạm: Chi tiết' : 'Chạm: Chọn';
            host.classList.toggle('desm-grid-off', on);
            box.style.display = on ? '' : 'none';
            if (!on) {
              if (tb) tb.classList.remove('desm-tb-nosel');
              if (box.__wasOn) { box.__wasOn = false; try { win.dispatchEvent(new win.Event('resize')); } catch (e) {} }
              return;
            }
            box.__wasOn = true;
            try {
              var top = box.getBoundingClientRect().top;
              box.style.height = Math.max(160, win.innerHeight - top - 4) + 'px';
            } catch (e) {}
            var rows = [];
            function addRow(r) {
              if (!r || r.Kind !== 'Data') return;
              if (r.Visible === 0 || r.Visible === '0' || r.Visible === false || r.Deleted) return;
              rows.push(r);
            }
            try {
              if (G.GetFirstVisible && G.GetNextVisible) {
                var r0 = G.GetFirstVisible(), guard = 0;
                while (r0 && guard++ < 5000) { addRow(r0); r0 = G.GetNextVisible(r0); }
              }
            } catch (e) { rows = []; }
            if (!rows.length) { for (var id0 in G.Rows) addRow(G.Rows[id0]); }
            function isSel(r) { return !!r.Selected && r.Selected !== '0'; }
            var items = rows.map(function(r) {
              return {
                id: r.id, sel: isSel(r),
                no: gridText(G, r, 'PACKAGE_NO'), desc: gridText(G, r, 'DESCRIPTION'),
                type: gridText(G, r, 'PACKAGE_TYPE'), list: gridText(G, r, 'PACKAGE_LIST_NO'),
                ao: gridText(G, r, 'OUT_STATUS'), loc: gridText(G, r, 'STORAGE_LOCATION'),
                ok: gridText(G, r, 'IS_CONFIRM_MATERIAL').toUpperCase() === 'Y'
              };
            });
            // Mặc định ẩn nút Xóa vị trí / Cập nhật vị trí; chỉ hiện khi đã tích chọn ít nhất một kiện
            if (tb) tb.classList.toggle('desm-tb-nosel', !items.some(function(i) { return i.sel; }));
            // Thanh nút đổi chiều cao (thu/mở) nên tính lại chiều cao vùng thẻ cho vừa màn hình
            try { box.style.height = Math.max(160, win.innerHeight - box.getBoundingClientRect().top - 4) + 'px'; } catch (e) {}
            try { diWarm(box.ownerDocument); } catch (e) {}
            var sig = items.map(function(i) { return [i.id, i.sel ? 1 : 0, i.no, i.desc, i.type, i.list, i.ao, i.loc, i.ok ? 1 : 0].join('|'); }).join('\n') + '#' + (win.__desmTapDetail ? 1 : 0);
            if (box.__sig === sig) return;
            box.__sig = sig;
            var keep = box.scrollTop;
            while (box.firstChild) box.removeChild(box.firstChild);
            function el(tag, cls, text) {
              var e = doc.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e;
            }
            var nSel = items.filter(function(i) { return i.sel; }).length;
            var bar = el('label', 'desm-cards-bar');
            var all = doc.createElement('input'); all.type = 'checkbox'; all.className = 'desm-chk';
            all.checked = items.length > 0 && nSel === items.length;
            all.indeterminate = nSel > 0 && nSel < items.length;
            all.addEventListener('change', function() {
              var want = all.checked ? 1 : 0;
              items.forEach(function(it) {
                var r = G.Rows[it.id]; if (!r) return;
                if (isSel(r) !== !!want) { try { G.SelectRow(r, want); } catch (e) {} }
              });
              box.__sig = null; cardView(doc);
            });
            bar.appendChild(all);
            bar.appendChild(el('span', 'desm-cards-count', 'Chọn tất cả · ' + items.length + ' kiện' + (nSel ? ' · đã chọn ' + nSel : '')));
            box.appendChild(bar);
            if (!items.length) box.appendChild(el('div', 'desm-cards-empty', 'Chưa có kiện hàng nào. Hãy nhập điều kiện lọc rồi bấm Search.'));
            var tapDetail = !!win.__desmTapDetail;
            items.forEach(function(it, idx) {
              var card = el('div', 'desm-card' + (it.sel ? ' desm-sel' : '') + (it.ok ? ' desm-ok' : ''));
              var ck = doc.createElement('input'); ck.type = 'checkbox'; ck.className = 'desm-chk desm-card-chk';
              ck.checked = it.sel; card.appendChild(ck);
              if (tapDetail) card.appendChild(el('span', 'desm-card-hit'));
              card.appendChild(el('div', 'desm-card-no', it.no));
              if (it.desc) card.appendChild(el('div', 'desm-card-desc', it.desc));
              var sub = [it.type, it.list].filter(function(x) { return x; }).join(' · ');
              if (sub) card.appendChild(el('div', 'desm-card-sub', sub));
              var foot = el('div', 'desm-card-foot');
              foot.appendChild(el('span', 'desm-card-ao', it.ao ? 'A/O : ' + it.ao : ''));
              var loc = el('span', 'desm-card-loc');
              var NS = 'http://www.w3.org/2000/svg';
              var svg = doc.createElementNS(NS, 'svg'); svg.setAttribute('viewBox', '0 0 24 24');
              svg.setAttribute('width', '16'); svg.setAttribute('height', '16');
              var pth = doc.createElementNS(NS, 'path');
              pth.setAttribute('d', 'M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9.5a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5z');
              pth.setAttribute('fill', 'none'); pth.setAttribute('stroke', 'currentColor'); pth.setAttribute('stroke-width', '2');
              svg.appendChild(pth); loc.appendChild(svg);
              loc.appendChild(el('span', 'desm-card-loctxt', it.loc || '—'));
              foot.appendChild(loc); card.appendChild(foot);
              card.addEventListener('click', function(ev) {
                var r = G.Rows[it.id]; if (!r) return;
                // Chế độ "Chi tiết": chạm vùng ô tích bên trái = chọn dòng, chạm chỗ khác = mở chi tiết
                if (tapDetail && !(ev.target && ev.target.classList && ev.target.classList.contains('desm-card-hit'))) {
                  openDetail(doc, G, it.id, idx + 1, function() { box.__sig = null; cardView(doc); });
                  return;
                }
                try { G.SelectRow(r, isSel(r) ? 0 : 1); } catch (e) {}
                box.__sig = null; cardView(doc);
              });
              box.appendChild(card);
            });
            box.scrollTop = keep;
          }
          // ===== Danh sách dạng thẻ cho các lưới khác (RSI, MRR, MRF, MPR...): mỗi dòng một thẻ, chạm thẻ để mở rộng toàn bộ cột,
          // chạm vùng ô tích bên trái để chọn dòng (các nút Confirm/Delete... của trang vẫn dùng dòng đã chọn).
          function genGridOf(win) {
            var best = null, bh = -1;
            try {
              for (var i = 0; win.TGGrids && i < win.TGGrids.length; i++) {
                var g = win.TGGrids[i];
                if (!g || !g.Cols || !g.Rows || !g.Rows.Header || !g.MainTag) continue;
                if (g.Cols.PACKAGE_NO && g.Cols.STORAGE_LOCATION) continue; // lưới Package đã có cardView riêng
                if (g.Cols.MATERIAL_CODE && g.Cols.PACKAGE_NO) continue;     // lưới Hạng mục chi tiết
                var hit = /(^|[\s_])(RSI|MRR|MRF|MPR)(_|\s|$)/i.test(Object.keys(g.Cols).join(' '));
                if (!hit) {
                  for (var c in g.Cols) { if (/(^|\W)(RSI|MRR|MRF|MPR)(\W|$)/i.test(gridText(g, g.Rows.Header, c))) { hit = true; break; } }
                }
                if (!hit) continue;
                var h = 0; try { h = g.MainTag.offsetHeight || 0; } catch (e) {}
                if (h > bh) { best = g; bh = h; }
              }
            } catch (e) {}
            return best;
          }
          // ===== Sửa dòng MRR: Received Date / Visual Check hàng loạt, lưu như nút Save của popup MRR trên web =====
          // Web (desmMrrCreationPopUp.js): đọc /getDesmMrrInfoList.do {MRR_HEADER_ID} -> results.{headerList,lineList};
          // lưu /saveDesmMrrSave.do với TRANS_TYPE='Incomplete', updateList = JSON các dòng đã đổi. Chỉ sửa được khi STATUS = Incomplete/Rejected.
          function mrrFmt(d) {
            if (d == null || d === '') return '';
            var s = String(d).trim(), m;
            if ((m = /^(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2})/.exec(s))) return m[1] + '/' + ('0' + m[2]).slice(-2) + '/' + ('0' + m[3]).slice(-2);
            if ((m = /^(\d{2})[\/\-.](\d{2})[\/\-.](\d{2})$/.exec(s))) return '20' + m[1] + '/' + m[2] + '/' + m[3];
            var t = /^\d{10,}$/.test(s) ? new Date(Number(s)) : new Date(s);
            if (isNaN(t.getTime())) return '';
            return t.getFullYear() + '/' + ('0' + (t.getMonth() + 1)).slice(-2) + '/' + ('0' + t.getDate()).slice(-2);
          }
          function mrrKeep(v) { var f = mrrFmt(v); return f || (v == null ? '' : String(v)); }
          function mrrPost(win, url, data, ok, bad) {
            var $j = null; try { $j = win.jQuery || win.$; } catch (e) {}
            if (!$j || !$j.ajax) { bad('không tìm thấy jQuery của trang'); return; }
            try {
              $j.ajax({ url: url, data: data, timeout: 30000, success: function(d) { ok(d); },
                error: function(_x, st) { bad('lỗi mạng hoặc hết phiên (' + st + ')'); } });
            } catch (e) { bad('không gửi được yêu cầu'); }
          }
          function mrrEditor(win, doc, hid, projNo, afterSave) {
            var ov = el('div', 'desm-detail desm-sub'), tp = el('div', 'desm-detail-top');
            var bk = el('button', 'desm-detail-back', '‹  MRR'); bk.type = 'button';
            bk.addEventListener('click', function() { if (ov.parentNode) ov.parentNode.removeChild(ov); });
            tp.appendChild(bk); tp.appendChild(el('div', 'desm-detail-title', 'MRR Lines')); ov.appendChild(tp);
            var body = el('div', 'desm-detail-body'); ov.appendChild(body); doc.body.appendChild(ov);
            var H = null, lines = [], sel = {}, note = { t: 'Đang tải…', c: '' };
            function load() {
              mrrPost(win, '/getDesmMrrInfoList.do', { MRR_HEADER_ID: hid }, function(d) {
                var r = d && d.results;
                if (!r || r === 'Err' || !r.headerList || !r.headerList.length || !Array.isArray(r.lineList)) { note = { t: 'Không tải được MRR.', c: '#dc2626' }; render(); return; }
                H = r.headerList[0]; lines = r.lineList; sel = {}; render();
              }, function(m) { note = { t: 'Không tải được MRR: ' + m, c: '#dc2626' }; render(); });
            }
            function render() {
              while (body.firstChild) body.removeChild(body.firstChild);
              if (!H) { body.appendChild(el('div', 'desm-detail-note', note.t)); return; }
              var canEdit = H.STATUS === 'Incomplete' || H.STATUS === 'Rejected';
              var card = el('div', 'desm-dcard');
              card.appendChild(el('div', 'desm-d-h', H.MRR_NO || ''));
              card.appendChild(el('div', 'desm-d-l', H.MRR_NAME || ''));
              card.appendChild(el('div', 'desm-d-l', 'Status : ' + (H.STATUS || '-')));
              card.appendChild(el('div', 'desm-d-l', 'Received : ' + (H.RECEIVED_DATE_FROM || '-') + ' ~ ' + (H.RECEIVED_DATE_TO || '-')));
              card.appendChild(el('div', 'desm-d-l', 'Inspection : ' + (H.INSPECTION_DATE_FROM || '-') + ' ~ ' + (H.INSPECTION_DATE_TO || '-')));
              body.appendChild(card);
              if (!canEdit) body.appendChild(el('div', 'desm-detail-note', 'MRR đang ở trạng thái ' + (H.STATUS || '?') + ' nên chỉ xem, không sửa được.'));
              var cnt = el('div', 'desm-detail-note');
              function nSel() { var n = 0; for (var k in sel) if (sel[k]) n++; return n; }
              function refreshCnt() { cnt.textContent = lines.length + ' dòng' + (nSel() ? ' · đã chọn ' + nSel() : ''); }
              var cards = [];
              function refreshCards() {
                cards.forEach(function(c) {
                  var on = !!sel[c.i]; c.card.classList.toggle('desm-sel', on); c.ck.checked = on;
                  c.rd.textContent = 'Received: ' + (mrrFmt(lines[c.i].RECEIVED_DATE) || '-');
                  c.vc.textContent = 'V/C: ' + (lines[c.i].VISUAL_CHECK || '-') + (lines[c.i].__chg ? '  ● đã sửa' : '');
                });
                refreshCnt();
              }
              if (canEdit) {
                var bar = el('div', 'desm-ditems-bar'), all = doc.createElement('input'); all.type = 'checkbox'; all.className = 'desm-chk';
                bar.appendChild(all); bar.appendChild(el('span', '', 'Chọn tất cả'));
                bar.addEventListener('click', function(ev) {
                  var on = !(lines.length && nSel() === lines.length); if (ev.target === all) on = all.checked;
                  lines.forEach(function(_l, i) { sel[i] = on; }); all.checked = on; refreshCards();
                });
                body.appendChild(bar);
                var di = doc.createElement('input'); di.type = 'date'; di.className = 'desm-sub-in desm-mrr-in';
                var db = el('button', 'desm-detail-list', 'Đặt Received Date cho dòng đã chọn'); db.type = 'button';
                db.addEventListener('click', function() {
                  if (!nSel()) { note = { t: 'Chưa chọn dòng nào.', c: '#dc2626' }; msgEl.style.color = note.c; msgEl.textContent = note.t; return; }
                  if (!di.value) { msgEl.style.color = '#dc2626'; msgEl.textContent = 'Chưa chọn ngày.'; return; }
                  var v = di.value.replace(/-/g, '/');
                  lines.forEach(function(l, i) { if (sel[i]) { l.RECEIVED_DATE = v; l.__chg = 1; } });
                  msgEl.style.color = ''; msgEl.textContent = 'Đã đặt Received Date ' + v + ' (chưa lưu).'; refreshCards();
                });
                var vs = doc.createElement('select'); vs.className = 'desm-sub-in desm-mrr-in';
                ['Good', 'Defect'].forEach(function(o) { var op = doc.createElement('option'); op.value = o; op.textContent = o; vs.appendChild(op); });
                var vb = el('button', 'desm-detail-list', 'Đặt Visual Check cho dòng đã chọn'); vb.type = 'button';
                vb.addEventListener('click', function() {
                  if (!nSel()) { msgEl.style.color = '#dc2626'; msgEl.textContent = 'Chưa chọn dòng nào.'; return; }
                  lines.forEach(function(l, i) { if (sel[i]) { l.VISUAL_CHECK = vs.value; l.__chg = 1; } });
                  msgEl.style.color = ''; msgEl.textContent = 'Đã đặt Visual Check ' + vs.value + ' (chưa lưu).'; refreshCards();
                });
                body.appendChild(di); body.appendChild(db); body.appendChild(vs); body.appendChild(vb);
              }
              body.appendChild(cnt);
              var listEl = el('div', 'desm-ditems');
              lines.forEach(function(l, i) {
                var c = el('div', 'desm-ditem'), ck = doc.createElement('input'); ck.type = 'checkbox'; ck.className = 'desm-chk desm-ditem-chk';
                c.appendChild(ck); c.appendChild(el('div', 'desm-ditem-no', l.PACKAGE_NO || '-'));
                c.appendChild(el('div', 'desm-ditem-l', l.DESCRIPTION || '-'));
                var ft = el('div', 'desm-ditem-foot'), rd = el('span', ''), vc = el('span', ''); ft.appendChild(rd); ft.appendChild(vc); c.appendChild(ft);
                if (canEdit) c.addEventListener('click', function() { sel[i] = !sel[i]; refreshCards(); }); else ck.style.display = 'none';
                cards.push({ i: i, card: c, ck: ck, rd: rd, vc: vc }); listEl.appendChild(c);
              });
              var msgEl = el('div', 'desm-detail-note', note.t); msgEl.style.color = note.c;
              if (canEdit) {
                var sv = el('button', 'desm-detail-list', 'SAVE'); sv.type = 'button';
                sv.addEventListener('click', function() {
                  var chg = lines.filter(function(l) { return l.__chg; });
                  function err(t) { msgEl.style.color = '#dc2626'; msgEl.textContent = t; }
                  if (!chg.length) { err('Chưa có thay đổi nào để lưu.'); return; }
                  var from = H.RECEIVED_DATE_FROM || '', to = H.RECEIVED_DATE_TO || '';
                  if (!from || !to) { err('MRR chưa có khoảng Received Date (From/To). Hãy nhập trên bản web trước.'); return; }
                  if (from > to) { err('Received Date From lớn hơn To.'); return; }
                  var sD = Number(from.replace(/\//g, '')), eD = Number(to.replace(/\//g, '')), badPkg = '';
                  lines.forEach(function(l) {
                    var rd = mrrFmt(l.RECEIVED_DATE); if (!rd || badPkg) return;
                    var n = Number(rd.replace(/\//g, '')); if (n < sD || n > eD) badPkg = l.PACKAGE_NO || '?';
                  });
                  if (badPkg) { err('Received Date nằm ngoài khoảng ' + from + ' ~ ' + to + ' [Package No: ' + badPkg + ']'); return; }
                  if (win.confirm && !win.confirm('Lưu ' + chg.length + ' dòng đã sửa của MRR này?')) return;
                  var list = chg.map(function(l) {
                    var o = { MRR_LINE_ID: l.MRR_LINE_ID, TRK_ITEM_NAME: l.TRK_ITEM_NAME, PACKING_LIST_NO: l.PACKAGE_LIST_NO, PACKAGE_NO: l.PACKAGE_NO,
                      DESCRIPTION: l.DESCRIPTION, SHIPMENT_NO: l.ATTRIBUTE10, PACKAGE_TYPE: l.PACKAGE_TYPE, VISUAL_CHECK: l.VISUAL_CHECK,
                      VISUAL_CHECK_DATE: mrrKeep(l.VISUAL_CHECK_DATE), STORAGE_LOCATION: l.STORAGE_LOCATION, RECEIVED_DATE: mrrKeep(l.RECEIVED_DATE),
                      REMARKS: l.REMARKS, ATTACH_GRP_CD: l.ATTACH_GRP_CD, FILE_PATH: l.FILE_PATH, QTY: l.QTY };
                    for (var k in o) if (o[k] == null) o[k] = '';
                    return o;
                  });
                  var pd = { MRR_HEADER_ID: hid, MRR_NO: H.MRR_NO, MRR_NAME: H.MRR_NAME, STATUS: H.STATUS, RECEIVED_DATE_FROM: from, RECEIVED_DATE_TO: to,
                    INSPECTION_DATE_FROM: H.INSPECTION_DATE_FROM, INSPECTION_DATE_TO: H.INSPECTION_DATE_TO, REMARK: H.REMARK, ATTACH_GRP_CD: H.ATTACH_GRP_CD,
                    PREPARED_BY: H.PREPARED_BY, CHECKED_BY: H.CHECKED_BY, CONFIRMED_BY: H.CONFIRMED_BY, APPROVED_BY: '', TRANS_TYPE: 'Incomplete', PROJECT_NO: projNo };
                  for (var k2 in pd) if (pd[k2] == null) pd[k2] = '';
                  pd.updateList = JSON.stringify(list);
                  sv.disabled = true; msgEl.style.color = ''; msgEl.textContent = 'Đang lưu…';
                  mrrPost(win, '/saveDesmMrrSave.do', pd, function(r) {
                    sv.disabled = false;
                    if (r && r.error != null) { err('Lưu thất bại: ' + r.error); return; }
                    note = { t: 'Đã lưu ✓', c: '#15803d' }; try { afterSave(); } catch (e) {} load();
                  }, function(m) { sv.disabled = false; err('Lưu thất bại: ' + m); });
                });
                body.appendChild(sv);
              }
              body.appendChild(msgEl); body.appendChild(listEl);
              refreshCards();
            }
            load();
          }
          // Màn chi tiết của một dòng RSI / MRF / MRR / MPR: chạm thẻ để vào. Hiện toàn bộ cột của dòng; RSI và MRF nạp thêm các dòng bên trong.
          function genDetail(win, doc, G, it) {
            function el(tag, cls, text) { var e = doc.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
            function dash(v) { return v == null || v === '' ? '-' : v; }
            function fn(v) {
              var s = String(v == null ? '' : v).replace(/,/g, ''), n = parseFloat(s);
              if (s === '' || isNaN(n)) return '-';
              return n.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 3 });
            }
            function same(a, b) { return String(a == null ? '' : a).replace(/\s+/g, ' ').trim() === String(b == null ? '' : b).replace(/\s+/g, ' ').trim(); }
            var isMrf = !!(G.Cols.MRF_NO), isRsi = !isMrf && !!(G.Cols.RSI_NO), isMrr = !!(G.Cols.MRR_NO);
            var title = isMrf ? 'MRF Detail' : (isRsi ? 'RSI Detail' : (isMrr ? 'MRR Detail' : 'Chi tiết'));
            var ov = el('div', 'desm-detail desm-sub'), tp = el('div', 'desm-detail-top');
            var bk = el('button', 'desm-detail-back', '‹  Quay lại'); bk.type = 'button';
            bk.addEventListener('click', function() { if (ov.parentNode) ov.parentNode.removeChild(ov); });
            tp.appendChild(bk); tp.appendChild(el('div', 'desm-detail-title', title)); ov.appendChild(tp);
            var body = el('div', 'desm-detail-body'); ov.appendChild(body);
            var head = el('div', 'desm-dcard');
            head.appendChild(el('div', 'desm-d-h', it.title || '—'));
            if (it.stat) head.appendChild(el('div', 'desm-d-l', it.stat));
            it.all.forEach(function(d) {
              if (!d.v) return;
              var kv = el('div', 'desm-gkv'); kv.appendChild(el('span', 'desm-gk', d.h)); kv.appendChild(el('span', 'desm-gv', d.v)); head.appendChild(kv);
            });
            body.appendChild(head);
            if (isMrr && G.Cols.INSPECTION_DATE_FROM && it.r.MRR_HEADER_ID != null && it.r.MRR_HEADER_ID !== '') {
              var eb = el('button', 'desm-detail-list', 'Sửa dòng MRR (Received Date / Visual Check)'); eb.type = 'button';
              eb.addEventListener('click', function() {
                var pj = ''; try { pj = (doc.getElementById('txtProjectCode') || {}).value || ''; } catch (e) {}
                mrrEditor(win, doc, it.r.MRR_HEADER_ID, pj || it.r.PROJECT_NO || '', function() {
                  try { doc.getElementById('btnSearch').click(); } catch (e) {}
                });
              });
              body.appendChild(eb);
            }
            if (isRsi || isMrf) {
              var rn = el('div', 'desm-detail-note', 'Đang tải…'), rl = el('div', 'desm-ditems');
              body.appendChild(rn); body.appendChild(rl);
              var proj = it.r.PROJECT_NO || diProj(doc);
              if (isRsi) {
                var rsiNo = it.r.RSI_NO != null && it.r.RSI_NO !== '' ? it.r.RSI_NO : it.title;
                diAjax(doc, '/getDesmRsiViewList.do', { PAGE_NUM: 1, PAGE_CNT: 5000, PROJECT_NO: proj, RSI_NO: rsiNo, RSI_NAME: '', SUBCONTRACTOR: '', ATTRIBUTE10: '', MATERIAL_CODE: '',
                  START_REQUEST_DATE: '', END_REQUEST_DATE: '', BALANCE_QTY: '', TYPE: '', CATEGORY: '', SUB_CATEGORY: '', PACKING_LIST_NO: '',
                  PACKAGE_NO: '', ITEM_DESC: '', MASTER_SHOP_UNIT: '', MASTER_SHOP_BLDG: '', SHOP_UNIT: '', SHOP_BLDG: '' }, function(list) {
                  if (!ov.parentNode) return;
                  var rows = [].filter.call(list, function(r) { return same(r.RSI_NO, rsiNo); });
                  rn.textContent = rows.length ? rows.length + ' hạng mục' : 'RSI này không có hạng mục.';
                  rows.forEach(function(r) {
                    var c = el('div', 'desm-rsi-card');
                    c.appendChild(el('div', 'desm-ditem-no', dash(r.PACKAGE_NO)));
                    c.appendChild(el('div', 'desm-ditem-l', dash(r.DESCRIPTION)));
                    var ft = el('div', 'desm-rsi-row'); ft.appendChild(el('span', '', dash(r.MATERIAL_CODE)));
                    ft.appendChild(el('span', '', fn(r.REQ_QTY) + ' / ' + fn(r.HANDOVER_QTY) + ' ' + (r.UNIT || ''))); c.appendChild(ft);
                    rl.appendChild(c);
                  });
                }, function() { if (ov.parentNode) rn.textContent = 'Không tải được danh sách hạng mục của RSI.'; });
              } else {
                var mrfNo = it.r.MRF_NO != null && it.r.MRF_NO !== '' ? it.r.MRF_NO : it.title;
                diAjax(doc, '/getMrfSummaryList.do', { PROJECT_NO: proj, RSI_NO: '', RSI_NAME: '', SUBCONTRACTOR: '', MATERIAL_CODE: '', RSI_START_REQUEST_DATE: '', RSI_END_REQUEST_DATE: '',
                  ZIM_ATTRIBUTE10: '', RSI_BALANCE_QTY: '', TYPE: '', CATEGORY: '', SUB_CATEGORY: '', PACKING_LIST_NO: '', MRF_NO: mrfNo, MRF_NAME: '',
                  PACKAGE_NO: '', ITEM_DESC: '', RETURN_TYPE: '', MRF_BALANCE_QTY: '' }, function(list) {
                  if (!ov.parentNode) return;
                  var rows = [].filter.call(list, function(r) { return same(r.MRF_NO, mrfNo); });
                  rn.textContent = rows.length ? rows.length + ' dòng' : 'MRF này không có dòng nào.';
                  rows.forEach(function(r) {
                    var c = el('div', 'desm-rsi-card desm-mrf-card');
                    var t1 = el('div', 'desm-rsi-row'); t1.appendChild(el('span', 'desm-ditem-no', dash(r.RSI_NO)));
                    t1.appendChild(el('span', 'desm-mrf-type', dash(r.RETURN_TYPE))); c.appendChild(t1);
                    c.appendChild(el('div', 'desm-ditem-no', dash(r.PACKAGE_NO)));
                    c.appendChild(el('div', 'desm-ditem-l', dash(r.DESCRIPTION || r.RSI_DESCRIPTION)));
                    var ft = el('div', 'desm-rsi-row'); ft.appendChild(el('span', '', dash(r.MATERIAL_CODE)));
                    ft.appendChild(el('span', 'desm-mrf-type', fn(r.MRF_REQ_RETURN_QTY) + ' / ' + fn(r.MRF_RETURN_QTY) + ' ' + (r.UNIT || ''))); c.appendChild(ft);
                    c.appendChild(el('div', 'desm-ditem-l', '📍 ' + dash(r.LOCATION) + '   Req : ' + dash(r.RETURN_REQ_DATE)));
                    rl.appendChild(c);
                  });
                }, function() { if (ov.parentNode) rn.textContent = 'Không tải được chi tiết MRF.'; });
              }
            }
            doc.body.appendChild(ov);
          }
          function genericCards(doc) {
            var win = doc.defaultView; if (!win || !win.TGGrids || !win.TGGrids.length) return;
            try { var fe = win.frameElement; if (fe && (fe.id === 'desmDetailFrame' || !isShown(fe))) return; } catch (e) {}
            var G = genGridOf(win); if (!G) return;
            var gm = G.MainTag;
            if (!(gm.classList && gm.classList.contains('GridMain')) && gm.querySelector) {
              var inner = gm.querySelector('.GridMain'); if (inner) gm = inner;
            }
            var host = gm.parentNode;
            if (!host || !host.parentNode || host.contains(doc.getElementById('toolbar')) || host.querySelector('.desm-filter-bar')) return;
            if (win.__desmGen === undefined) {
              var sv = ''; try { sv = win.localStorage.getItem('desmGenCards') || ''; } catch (e) {}
              win.__desmGen = sv !== '0';
            }
            win.__desmGenOpen = win.__desmGenOpen || {};
            var on = !!win.__desmGen;
            function el(tag, cls, text) {
              var e = doc.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e;
            }
            function isSel(r) { return !!r.Selected && r.Selected !== '0'; }
            var box = doc.getElementById('desmGenCards');
            if (!box) {
              box = el('div', ''); box.id = 'desmGenCards';
              host.parentNode.insertBefore(box, host.nextSibling);
              var bar = el('div', 'desm-gbar');
              var all = doc.createElement('input'); all.type = 'checkbox'; all.className = 'desm-chk desm-gall';
              var q = doc.createElement('input'); q.type = 'search'; q.className = 'desm-gq'; q.placeholder = 'Lọc nhanh trong danh sách…';
              var cnt = el('span', 'desm-gcnt', '');
              var tg = el('button', 'desm-gbtn', ''); tg.type = 'button';
              var list = el('div', 'desm-glist');
              bar.appendChild(all); bar.appendChild(q); bar.appendChild(cnt); bar.appendChild(tg);
              box.appendChild(bar); box.appendChild(list);
              box.__all = all; box.__q = q; box.__cnt = cnt; box.__tg = tg; box.__list = list;
              q.addEventListener('input', function() { box.__sig = null; genericCards(doc); });
              tg.addEventListener('click', function(e) {
                e.preventDefault(); e.stopPropagation();
                win.__desmGen = !win.__desmGen;
                try { win.localStorage.setItem('desmGenCards', win.__desmGen ? '1' : '0'); } catch (e2) {}
                box.__sig = null; genericCards(doc);
              });
              all.addEventListener('change', function() {
                var want = all.checked ? 1 : 0;
                (box.__rowsShown || []).forEach(function(r) { if (isSel(r) !== !!want) { try { G.SelectRow(r, want); } catch (e) {} } });
                box.__sig = null; genericCards(doc);
              });
            }
            box.__tg.textContent = on ? 'Dạng: Thẻ' : 'Dạng: Bảng';
            host.classList.toggle('desm-grid-off', on);
            box.classList.toggle('desm-gtable', !on);
            if (!on) {
              box.style.height = '';
              if (box.__wasOn) { box.__wasOn = false; try { win.dispatchEvent(new win.Event('resize')); } catch (e) {} }
              box.__sig = 'off'; return;
            }
            box.__wasOn = true;
            try {
              var topY = box.getBoundingClientRect().top;
              box.style.height = Math.max(160, win.innerHeight - topY - 4) + 'px';
            } catch (e) {}
            // Cột hiển thị (có tiêu đề), phân loại: số phiếu, trạng thái, ngày, còn lại
            var cols = [];
            for (var c in G.Cols) {
              if (c === 'Panel' || c === 'Group' || !colShown(G, c)) continue;
              var ht = gridText(G, G.Rows.Header, c); if (!ht) continue;
              cols.push({ c: c, h: ht });
            }
            var titleCol = null, statCols = [], dateCols = [], restCols = [];
            cols.forEach(function(x) {
              if (!titleCol && (/(RSI|MRR|MRF|MPR)\W*(NO|NUMBER|#)/i.test(x.h) || /(RSI|MRR|MRF|MPR)_?(NO|NUMBER)$/i.test(x.c))) titleCol = x;
            });
            cols.forEach(function(x) {
              if (x === titleCol) return;
              if (/status|state/i.test(x.h)) statCols.push(x);
              else if (/date|time|etd|atd|eta|ata/i.test(x.h)) dateCols.push(x);
              else restCols.push(x);
            });
            if (!titleCol && restCols.length) titleCol = restCols.shift();
            var rows = diRows(G), qv = pkgNorm(box.__q.value);
            var items = rows.map(function(r) {
              var o = { r: r, id: r.id, sel: isSel(r), all: cols.map(function(x) { return { h: x.h, v: gridText(G, r, x.c) }; }) };
              o.title = titleCol ? gridText(G, r, titleCol.c) : '';
              o.stat = statCols.map(function(x) { return gridText(G, r, x.c); }).filter(function(v) { return v; })[0] || '';
              o.dates = dateCols.map(function(x) { return { h: x.h, v: gridText(G, r, x.c) }; }).filter(function(d) { return d.v; });
              o.rest = restCols.map(function(x) { return { h: x.h, v: gridText(G, r, x.c) }; }).filter(function(d) { return d.v; });
              o.hay = pkgNorm(o.all.map(function(d) { return d.v; }).join(' '));
              return o;
            }).filter(function(o) { return !qv || o.hay.indexOf(qv) >= 0; });
            box.__rowsShown = items.map(function(o) { return o.r; });
            var nSel = items.filter(function(o) { return o.sel; }).length;
            var sig = items.map(function(o) { return [o.id, o.sel ? 1 : 0, o.title, o.stat, o.all.length, o.all.map(function(d) { return d.v; }).join('~'), win.__desmGenOpen[o.id] ? 1 : 0].join('|'); }).join('\n') + '#' + qv;
            if (box.__sig === sig) return;
            box.__sig = sig;
            box.__all.checked = items.length > 0 && nSel === items.length;
            box.__all.indeterminate = nSel > 0 && nSel < items.length;
            box.__cnt.textContent = items.length + ' dòng' + (nSel ? ' · chọn ' + nSel : '');
            var list = box.__list, keep = box.scrollTop;
            while (list.firstChild) list.removeChild(list.firstChild);
            if (!items.length) {
              list.appendChild(el('div', 'desm-cards-empty', qv ? 'Không có dòng nào khớp.' : 'Chưa có dữ liệu. Hãy nhập điều kiện lọc rồi bấm Search.'));
            }
            function tone(s) {
              if (/reject|cancel|delete|fail|damage/i.test(s)) return 'bad';
              if (/complete|confirm|approv|done|close|receiv|ok\b/i.test(s)) return 'ok';
              if (s) return 'wait';
              return '';
            }
            items.forEach(function(it) {
              var t = tone(it.stat), open = !!win.__desmGenOpen[it.id];
              var card = el('div', 'desm-card desm-gcard' + (t ? ' desm-g-' + t : '') + (it.sel ? ' desm-sel' : '') + (open ? ' desm-gopen' : ''));
              var ck = doc.createElement('input'); ck.type = 'checkbox'; ck.className = 'desm-chk desm-card-chk'; ck.checked = it.sel;
              card.appendChild(ck); card.appendChild(el('span', 'desm-card-hit'));
              var top = el('div', 'desm-gtop');
              top.appendChild(el('div', 'desm-card-no', it.title || '—'));
              if (it.stat) top.appendChild(el('span', 'desm-gpill' + (t ? ' desm-gp-' + t : ''), it.stat));
              card.appendChild(top);
              it.rest.slice(0, 3).forEach(function(d) {
                var kv = el('div', 'desm-gkv'); kv.appendChild(el('span', 'desm-gk', d.h)); kv.appendChild(el('span', 'desm-gv', d.v)); card.appendChild(kv);
              });
              if (it.dates.length) {
                var foot = el('div', 'desm-card-foot');
                it.dates.slice(0, 2).forEach(function(d) { foot.appendChild(el('span', 'desm-card-ao', d.h + ': ' + d.v)); });
                card.appendChild(foot);
              }
              var more = el('div', 'desm-gmore');
              it.all.forEach(function(d) {
                if (!d.v) return;
                var kv = el('div', 'desm-gkv'); kv.appendChild(el('span', 'desm-gk', d.h)); kv.appendChild(el('span', 'desm-gv', d.v)); more.appendChild(kv);
              });
              if (G.Cols.MRR_NO && G.Cols.INSPECTION_DATE_FROM && it.r.MRR_HEADER_ID != null && it.r.MRR_HEADER_ID !== '') {
                var eb = el('button', 'desm-detail-list', 'Sửa dòng MRR (Received Date / Visual Check)'); eb.type = 'button';
                eb.addEventListener('click', function(ev) {
                  ev.stopPropagation();
                  var pj = ''; try { pj = (doc.getElementById('txtProjectCode') || {}).value || ''; } catch (e) {}
                  mrrEditor(win, doc, it.r.MRR_HEADER_ID, pj || it.r.PROJECT_NO || '', function() {
                    try { doc.getElementById('btnSearch').click(); } catch (e) {}
                  });
                });
                more.appendChild(eb);
              }
              card.appendChild(more);
              card.addEventListener('click', function(ev) {
                if (ev.target && ev.target.classList && ev.target.classList.contains('desm-card-hit')) {
                  try { G.SelectRow(it.r, it.sel ? 0 : 1); } catch (e) {}
                } else {
                  // Chạm thẻ = vào xem chi tiết bên trong (chạm ô vuông bên trái = chọn dòng)
                  genDetail(win, doc, G, it);
                  return;
                }
                box.__sig = null; genericCards(doc);
              });
              list.appendChild(card);
            });
            box.scrollTop = keep;
          }
          // Thu gọn chiều cao tiêu đề + hàng lọc của lưới (mặc định ~120px -> ~56px); tắt chế độ Gọn thì trả lại như cũ
          function slimHeader(win, on) {
            var list = win.TGGrids; if (!list || !list.length) return;
            var TARGET = { Header: 15, AR1: 15, Filter1: 13, Filter2: 13 };
            for (var gi = 0; gi < list.length; gi++) {
              var G = list[gi];
              if (!G || !G.Rows || !G.Rows.Header || !G.Cols || !G.Cols.PACKAGE_NO || G.__desmHFail) continue;
              var orig = G.__desmHOrig = G.__desmHOrig || {};
              var changed = false;
              for (var id in TARGET) {
                var r = G.Rows[id]; if (!r) continue;
                if (orig[id] === undefined) orig[id] = parseFloat(r.Height) || 30;
                var want = on ? TARGET[id] : orig[id];
                if (Math.abs((parseFloat(r.Height) || 0) - want) > 0.5) {
                  try { G.SetAttribute(r, null, 'Height', want, 0); changed = true; } catch (e) { G.__desmHFail = 1; break; }
                }
              }
              if (changed && !G.__desmHFail) { try { G.Rerender(); } catch (e) { try { G.Update && G.Update(); } catch (e2) {} } }
            }
          }
          // Thanh cuối lưới (Style / Size / Scale): đặt mặc định Material - Normal - 90%, mỗi lần mở lưới chỉ áp một lần
          function defaultToolbar(win) {
            var list = win.TGGrids; if (!list || !list.length) return;
            for (var gi = 0; gi < list.length; gi++) {
              var G = list[gi];
              if (!G || !G.Cols || !G.Cols.PACKAGE_NO || !G.Rows || !G.Rows.Header || G.__desmTbDone) continue;
              G.__desmTbDone = 1;
              try { if (G.Style !== undefined && String(G.Style) !== 'Material' && G.SetStyle) G.SetStyle('Material'); } catch (e) {}
              try { if (G.Size !== undefined && String(G.Size) !== 'Normal' && G.SetSize) G.SetSize('Normal'); } catch (e) {}
              try {
                var cur = parseFloat(G.Scale);
                if (G.SetScale && !(cur === 90 || cur === 0.9)) G.SetScale('90%');
              } catch (e) {}
            }
          }
          function colToggle(doc) {
            var win = doc.defaultView; if (!win || !win.TGGrids || !win.TGGrids.length) return;
            if (win.__desmCompact === undefined) win.__desmCompact = true;
            var tb = doc.getElementById('toolbar');
            if (tb && !doc.getElementById('desmColToggle')) {
              var bt = doc.createElement('button');
              bt.type = 'button'; bt.id = 'desmColToggle'; bt.className = 'btn btn-secondary btn-sm';
              bt.addEventListener('click', function(e) {
                e.preventDefault(); e.stopPropagation();
                win.__desmCompact = !win.__desmCompact;
                for (var i = 0; i < win.TGGrids.length; i++) if (win.TGGrids[i]) { win.TGGrids[i].__desmTry = 0; win.TGGrids[i].__desmWDone = null; }
                colToggle(doc);
              });
              tb.insertBefore(bt, tb.firstChild);
            }
            // Thanh nút gọn: mặc định chỉ chừa Location Delete + Location Update, các nút khác gom sau nút "⋯"
            if (tb && doc.getElementById('btnLocationDelete') && doc.getElementById('btnLocationSetup')) {
              tb.classList.add('desm-tb-slim');
              if (!doc.getElementById('desmMoreToggle')) {
                var mb = doc.createElement('button');
                mb.type = 'button'; mb.id = 'desmMoreToggle'; mb.className = 'btn btn-secondary btn-sm';
                mb.textContent = '⋯';
                mb.addEventListener('click', function(e) {
                  e.preventDefault(); e.stopPropagation();
                  tb.classList.toggle('desm-tb-all');
                  mb.textContent = tb.classList.contains('desm-tb-all') ? '×' : '⋯';
                });
                tb.appendChild(mb);
              }
            }
            var b2 = doc.getElementById('desmColToggle');
            if (b2) b2.textContent = win.__desmCompact ? 'Cột: Gọn' : 'Cột: Đủ';
            compactGrid(win, win.__desmCompact);
            try { slimHeader(win, win.__desmCompact); } catch (e) {}
            try { defaultToolbar(win); } catch (e) {}
            try { cardView(doc); } catch (e) {}
            try { genericCards(doc); } catch (e) {}
          }
          // Tự điền tài khoản ở trang đăng nhập: bắt tài khoản khi bấm Login, và hàm điền do app gọi
          function findUser(doc, pw) {
            var root = pw.form || doc, list = root.querySelectorAll('input'), u = null;
            for (var i = 0; i < list.length; i++) {
              var x = list[i], t = (x.type || 'text').toLowerCase();
              if (x === pw) break;
              if (/^(text|email|tel|number)$/.test(t) && !x.disabled && x.offsetParent !== null) u = x;
            }
            return u;
          }
          function setVal(el, v) {
            if (!el) return;
            try {
              var d = Object.getOwnPropertyDescriptor(w.HTMLInputElement.prototype, 'value');
              if (d && d.set) d.set.call(el, v); else el.value = v;
            } catch (e) { el.value = v; }
            ['input', 'change'].forEach(function(n) { el.dispatchEvent(new Event(n, { bubbles: true })); });
          }
          w.__desmFill = function(u, p) {
            var pw = document.querySelector('input[type=password]');
            if (!pw || pw.value) return false;
            var us = findUser(document, pw);
            if (us && !us.value) setVal(us, u);
            setVal(pw, p);
            return true;
          };
          // Tự bấm Login (chỉ app gọi khi đang kết nối lại sau khi hết phiên, đã có tài khoản lưu). Mỗi lần tải trang chỉ một lần.
          w.__desmSubmitLogin = function() {
            var pw = document.querySelector('input[type=password]');
            if (!pw || !pw.value || w.__desmSubmitted) return false;
            var u = findUser(document, pw);
            if (u && !u.value) return false;
            w.__desmSubmitted = true;
            var form = pw.form, btn = null, cand = (form || document).querySelectorAll('button,input[type=submit],input[type=button],a');
            for (var i = 0; i < cand.length; i++) {
              var c = cand[i], t = (c.id || '') + ' ' + (c.className || '') + ' ' + (c.textContent || c.value || '');
              if (/log\s*in|login|sign\s*in|đăng nhập/i.test(t) && c.offsetParent !== null) { btn = c; break; }
            }
            try {
              if (btn) btn.click();
              else if (form && form.requestSubmit) form.requestSubmit();
              else if (form) form.submit();
              else return false;
            } catch (e) { return false; }
            return true;
          };
          function credHook(doc) {
            if (doc.__desmCred || w !== w.top) return;
            var pw = doc.querySelector('input[type=password]');
            if (!pw || !allowed(doc)) return;
            doc.__desmCred = true;
            var grab = function() {
              try {
                var p = doc.querySelector('input[type=password]'); if (!p || !p.value) return;
                var u = findUser(doc, p); if (!u || !u.value) return;
                w.webkit.messageHandlers.desmCred.postMessage({ u: u.value, p: p.value });
              } catch (e) {}
            };
            doc.addEventListener('submit', grab, true);
            doc.addEventListener('click', function(e) {
              var t = e.target && e.target.closest ? e.target.closest('button,input[type=submit],input[type=button],a') : null;
              if (t && /log\s*in|login|sign\s*in|đăng nhập/i.test((t.id || '') + ' ' + (t.className || '') + ' ' + (t.textContent || t.value || ''))) grab();
            }, true);
            doc.addEventListener('keydown', function(e) { if (e.key === 'Enter') grab(); }, true);
          }
          // Hộp thoại (Location Update) mở khi trang đang cuộn xuống: canvas bản đồ tính toạ độ bấm theo pageX/pageY nên bị lệch.
          // Đưa trang về đầu + khoá cuộn trong lúc hộp thoại mở, trả lại vị trí cuộn khi đóng.
          function modalLock(doc) {
            var c = w.__desmCfg;
            if (!(c.mode === 'mobile' && allowed(doc))) return;
            var win = doc.defaultView, root = doc.documentElement; if (!win || !root) return;
            var open = null, ms = doc.querySelectorAll('.modal.show, .ui-dialog');
            for (var i = 0; i < ms.length; i++) {
              var cs = win.getComputedStyle(ms[i]);
              if (cs.display !== 'none' && cs.visibility !== 'hidden') { open = ms[i]; break; }
            }
            if (open) {
              if (!root.classList.contains('desm-modal-open')) {
                doc.__desmSY = [win.pageXOffset || 0, win.pageYOffset || 0];
                root.classList.add('desm-modal-open');
                if (!doc.__desmScrollHook) {
                  doc.__desmScrollHook = true;
                  win.addEventListener('scroll', function() {
                    if (root.classList.contains('desm-modal-open') && (win.pageXOffset || win.pageYOffset)) win.scrollTo(0, 0);
                  }, { passive: true });
                }
              }
              if (win.pageXOffset || win.pageYOffset) win.scrollTo(0, 0);
            } else if (root.classList.contains('desm-modal-open')) {
              root.classList.remove('desm-modal-open');
              var sy = doc.__desmSY || [0, 0];
              try { win.scrollTo(sy[0], sy[1]); } catch (e) {}
            }
          }
          // ===== Dịch giao diện sang tiếng Việt (chỉ khi bật trong Cài đặt hoặc chọn "Tiếng Việt" ở ô Language) =====
          function viNorm(s) { return String(s).replace(/[\u200b\s]+/g, ' ').trim().toLowerCase(); }
          function viMap() {
            var c = w.__desmCfg, sig = (c.dict ? c.dict.length : 0) + ':' + (c.custom ? JSON.stringify(c.custom) : '');
            if (w.__desmViSig === sig && w.__desmViM) return w.__desmViM;
            var m = {};
            (c.dict || []).concat(c.custom || []).forEach(function(p) { if (p && p.length > 1) m[viNorm(p[0])] = p[1]; });
            w.__desmViSig = sig; w.__desmViM = m; return m;
          }
          function viLookup(str) {
            var core = String(str).replace(/^[\s\u200b]+|[\s\u200b]+$/g, '');
            if (!core) return null;
            var v = viMap()[viNorm(core)];
            if (v === undefined) return null;
            var letters = core.replace(/[^A-Za-z]/g, '');
            if (letters.length >= 3 && core === core.toUpperCase()) v = v.toUpperCase();
            if (v === core) return null;
            var lead = str.match(/^[\s\u200b]*/)[0], trail = str.match(/[\s\u200b]*$/)[0];
            return lead + v + trail;
          }
          function viMiss(core) {
            try {
              if (!/^[A-Za-z][A-Za-z &\/\-\.\(\),:'’%]{1,70}$/.test(core)) return;
              var t = w.top; t.__desmMiss = t.__desmMiss || {}; t.__desmMiss[core] = 1;
            } catch (e) {}
          }
          function viText(n) {
            var p = n.parentNode; if (!p || p.nodeType !== 1) return;
            var tg = p.tagName; if (tg === 'SCRIPT' || tg === 'STYLE' || tg === 'TEXTAREA') return;
            if (p.closest && p.closest('#desmCards, #desmDetail, .desm-sub')) return;
            var v = n.nodeValue; if (!v || !/[A-Za-z]/.test(v)) return;
            var r = viLookup(v);
            if (r !== null) { if (r !== v) n.nodeValue = r; return; }
            var cl = (p.getAttribute && p.getAttribute('class')) || '';
            if (!/gridText|gridLinkText|TMCellBase/.test(cl)) viMiss(v.replace(/[\u200b\s]+/g, ' ').trim());
          }
          var VI_ATTR = ['placeholder', 'title', 'alt'];
          function viAttrs(el) {
            if (!el || el.nodeType !== 1) return;
            VI_ATTR.forEach(function(a) {
              var v = el.getAttribute(a); if (!v) return;
              var r = viLookup(v); if (r !== null && r !== v) el.setAttribute(a, r);
            });
            if (el.tagName === 'INPUT' && /^(button|submit|reset)$/i.test(el.type || '')) {
              var r2 = viLookup(el.value || ''); if (r2 !== null && r2 !== el.value) el.value = r2;
            }
          }
          function viWalk(root) {
            if (!root) return;
            if (root.nodeType === 3) { viText(root); return; }
            var doc = root.nodeType === 9 ? root : root.ownerDocument;
            var base = root.nodeType === 9 ? root.documentElement : root;
            if (!doc || !base || base.nodeType !== 1) return;
            viAttrs(base);
            var els = base.querySelectorAll('[placeholder],[title],[alt],input[type=button],input[type=submit],input[type=reset]');
            for (var i = 0; i < els.length; i++) viAttrs(els[i]);
            var tw = doc.createTreeWalker(base, 4, null), n;
            while ((n = tw.nextNode())) viText(n);
          }
          function viPost(lang) {
            try { w.webkit.messageHandlers.desmLang.postMessage({ lang: lang }); } catch (e) {}
          }
          // Thêm mục "Tiếng Việt" vào ô Language của DESM (máy chủ chỉ có en/ko/ru nên mục này do app xử lý)
          function viLangSel(doc) {
            var sel = doc.getElementById('selLang'); if (!sel || !allowed(doc)) return;
            var c = w.__desmCfg;
            if (!sel.querySelector('option[value="vi"]')) {
              var o = doc.createElement('option'); o.value = 'vi'; o.textContent = 'Tiếng Việt'; sel.appendChild(o);
            }
            if (doc.activeElement !== sel) {
              if (c.vi && sel.value !== 'vi') sel.value = 'vi';
              else if (!c.vi && sel.value === 'vi') sel.value = '';
            }
            if (doc.__desmLangHook) return;
            doc.__desmLangHook = true;
            doc.addEventListener('change', function(e) {
              var t = e.target;
              if (!t || t.id !== 'selLang' || doc.__desmBypass) return;
              if (t.value === 'vi') {
                e.stopImmediatePropagation(); e.stopPropagation();
                w.__desmCfg.vi = true; viPost('vi');
                // Cho trang tải ở ngôn ngữ gốc English (từ điển dịch từ English sang Việt)
                doc.__desmBypass = true; t.value = 'en';
                try { t.dispatchEvent(new Event('change', { bubbles: true })); } catch (x) {}
                doc.__desmBypass = false;
                setTimeout(function() { viLangSel(doc); }, 300);
                setTimeout(function() { viLangSel(doc); }, 1500);
              } else if (t.value) {
                w.__desmCfg.vi = false; viPost('site');
              }
            }, true);
          }
          function viInit() {
            if (w.__desmViInit) return; w.__desmViInit = true;
            ['alert', 'confirm', 'prompt'].forEach(function(nm) {
              var o = w[nm]; if (typeof o !== 'function' || o.__desmVi) return;
              var f = function(msg) {
                var a = [].slice.call(arguments);
                try {
                  if (w.__desmCfg.vi && typeof a[0] === 'string') {
                    var r = viLookup(a[0]);
                    if (r === null) {
                      var ch = false, parts = a[0].split('\n').map(function(l) { var x = viLookup(l); if (x !== null) { ch = true; return x; } return l; });
                      if (ch) r = parts.join('\n');
                    }
                    if (r !== null) a[0] = r;
                  }
                } catch (e) {}
                return o.apply(w, a);
              };
              f.__desmVi = 1; w[nm] = f;
            });
            var pend = [], queued = false;
            function flush() {
              queued = false;
              if (!w.__desmCfg.vi) { pend = []; return; }
              var list = pend; pend = [];
              try {
                if (list.length > 400) { viWalk(document); }
                else list.forEach(function(x) { if (x.t === 'a') viAttrs(x.n); else if (x.n.isConnected !== false) viWalk(x.n); });
                viLangSel(document);
              } catch (e) {}
            }
            function push(t, n) {
              pend.push({ t: t, n: n });
              if (!queued) { queued = true; (w.requestAnimationFrame || w.setTimeout)(flush); }
            }
            try {
              new MutationObserver(function(ms) {
                if (!w.__desmCfg.vi) { try { viLangSel(document); } catch (e) {} return; }
                for (var i = 0; i < ms.length; i++) {
                  var m = ms[i];
                  if (m.type === 'childList') { for (var j = 0; j < m.addedNodes.length; j++) push('w', m.addedNodes[j]); }
                  else if (m.type === 'characterData') push('w', m.target);
                  else if (m.type === 'attributes') push('a', m.target);
                }
              }).observe(document.documentElement, { childList: true, subtree: true, characterData: true,
                attributes: true, attributeFilter: ['placeholder', 'title', 'alt', 'value'] });
            } catch (e) {}
          }
          function viApply(doc) {
            var c = w.__desmCfg;
            try { if (allowed(doc)) viLangSel(doc); } catch (e) {}
            if (!c.vi || !allowed(doc)) return;
            viInit();
            try { viWalk(doc); } catch (e) {}
          }
          // ===== Quét camera Package No: điền ô Số kiện hàng, Search, rồi mở chi tiết (hoặc chọn dòng) =====
          function pkgGridOf(win) {
            try {
              for (var i = 0; win.TGGrids && i < win.TGGrids.length; i++) {
                var g = win.TGGrids[i];
                if (g && g.Cols && g.Cols.PACKAGE_NO && g.Cols.STORAGE_LOCATION && g.Rows) return g;
              }
            } catch (e) {}
            return null;
          }
          function isShown(el) { try { return el.offsetWidth > 0 && el.offsetHeight > 0; } catch (e) { return false; } }
          function pkgDoc(doc, depth) {
            try {
              if (doc.getElementById('txtPackageNo') && doc.getElementById('btnSearch') && pkgGridOf(doc.defaultView)) return doc;
            } catch (e) {}
            if (depth > 3) return null;
            var fs = doc.querySelectorAll('iframe,frame');
            for (var i = 0; i < fs.length; i++) {
              var f = fs[i];
              if (f.id === 'desmDetailFrame' || !isShown(f)) continue;
              try { var d = f.contentDocument; if (d) { var r = pkgDoc(d, depth + 1); if (r) return r; } } catch (e) {}
            }
            return null;
          }
          function pkgNorm(s) { return String(s == null ? '' : s).toUpperCase().replace(/[^A-Z0-9]/g, ''); }
          function scanMsg(o) { try { w.webkit.messageHandlers.desmScanResult.postMessage(o); } catch (e) {} }
          // Đang ở màn hình khác thì tự mở tab "Kiện hàng" (menu 196) rồi đợi trang sẵn sàng
          function ensurePkgDoc(cb) {
            var d = pkgDoc(document, 0);
            if (d) { cb(d); return; }
            var a = null;
            try { a = diTop(document).document.getElementById('196'); } catch (e) {}
            if (!a) { cb(null); return; }
            try { a.click(); } catch (e) { cb(null); return; }
            var t0 = Date.now();
            (function poll() {
              var x = pkgDoc(document, 0);
              if (x) { setTimeout(function() { cb(x); }, 300); return; }
              if (Date.now() - t0 > 20000) { cb(null); return; }
              setTimeout(poll, 400);
            })();
          }
          // Footer 5 tab: bấm mục menu bên trái theo tên (Anh/Việt). id = id thẻ <a> nếu biết (vd '196' = Kiện hàng). Trả 1 nếu bấm được.
          w.__desmOpenMenu = function(id, pattern) {
            var D; try { D = diTop(document).document; } catch (e) { D = document; }
            var a = id ? D.getElementById(id) : null;
            if (!a && pattern) {
              var rx = new RegExp(pattern, 'i'), L = D.querySelectorAll('#accordionSidebar a');
              for (var i = 0; i < L.length; i++) {
                if (L[i].hasAttribute('data-toggle')) continue;
                var tx = (L[i].textContent || '').replace(/\s+/g, ' ').trim();
                if (tx && rx.test(tx)) { a = L[i]; break; }
              }
            }
            if (!a) return 0;
            try { a.click(); D.documentElement.classList.remove('desm-nav-open'); return 1; } catch (e) { return 0; }
          };
          // Quay lại trong DESM: đóng lớp phủ (cập nhật vị trí / chi tiết kiện / menu) trước; trả 1 nếu đã xử lý
          w.__desmBack = function() {
            var D; try { D = diTop(document).document; } catch (e) { D = document; }
            var b = D.querySelector('#desmDetailFrameBar .desm-detail-back');
            if (b) { b.click(); return 1; }
            var subs = D.querySelectorAll('.desm-sub .desm-detail-back');
            if (subs.length) { subs[subs.length - 1].click(); return 1; }
            var dd = D.querySelector('#desmDetail .desm-detail-back'); if (dd) { dd.click(); return 1; }
            if (D.documentElement.classList.contains('desm-nav-open')) { D.documentElement.classList.remove('desm-nav-open'); return 1; }
            return 0;
          };
          w.__desmToggleDrawer = function() {
            var D; try { D = diTop(document).document; } catch (e) { D = document; }
            D.documentElement.classList.toggle('desm-nav-open');
          };
          w.__desmFindPkg = function(cfg) {
            ensurePkgDoc(function(d) {
              if (!d) { scanMsg({ status: 'nopage' }); return; }
              findPkgIn(cfg, d);
            });
          };
          function findPkgIn(cfg, d) {
            var win = d.defaultView, G = pkgGridOf(win);
            var inp = d.getElementById('txtPackageNo'), pl = d.getElementById('txtPackingListNo'), key = pkgNorm(cfg.key);
            function setv(x, v) { x.value = v; ['input', 'change'].forEach(function(n) { x.dispatchEvent(new win.Event(n, { bubbles: true })); }); }
            setv(inp, cfg.term);
            if (pl && pl.value) setv(pl, '');
            d.getElementById('btnSearch').click();
            var t0 = Date.now(), last = '', stable = 0;
            (function poll() {
              var rows = diRows(G);
              var hits = rows.filter(function(r) { var v = pkgNorm(gridText(G, r, 'PACKAGE_NO')); return v && v.slice(-key.length) === key; });
              var sig = rows.length + '|' + hits.length; stable = sig === last ? stable + 1 : 0; last = sig;
              var el = Date.now() - t0;
              var done = (hits.length && stable >= 2 && el > 1200) ||
                (!rows.length && stable >= 6 && el > 6000) ||
                (rows.length && !hits.length && stable >= 5 && el > 6000) || el > 20000;
              if (!done) { setTimeout(poll, 400); return; }
              if (!hits.length) { scanMsg({ status: 'notfound', term: cfg.term }); return; }
              if (hits.length > 1) { scanMsg({ status: 'multi', n: hits.length }); return; }
              var r = hits[0];
              if (cfg.open && win.__desmOpenPkg && win.__desmOpenPkg(r.id)) { scanMsg({ status: 'opened' }); return; }
              try {
                rows.forEach(function(x) {
                  var s0 = !!x.Selected && x.Selected !== '0', want = x === r;
                  if (s0 !== want) G.SelectRow(x, want ? 1 : 0);
                });
              } catch (e) {}
              scanMsg({ status: 'ok', term: gridText(G, r, 'PACKAGE_NO') });
            })();
          }
          // Từ "Lịch sử Packing List": mở màn Kiện hàng và lọc theo Packing List No (xoá ô Package No) rồi Search
          w.__desmFindPackingList = function(cfg) {
            ensurePkgDoc(function(d) {
              if (!d) { scanMsg({ status: 'nopage' }); return; }
              var win = d.defaultView, pl = d.getElementById('txtPackingListNo'), inp = d.getElementById('txtPackageNo'), btn = d.getElementById('btnSearch');
              if (!pl || !btn) { scanMsg({ status: 'nopage' }); return; }
              function setv(x, v) { x.value = v; ['input', 'change'].forEach(function(n) { x.dispatchEvent(new win.Event(n, { bubbles: true })); }); }
              var G = cfg.open ? pkgGridOf(win) : null;
              var before = ''; try { before = G ? diRows(G).map(function(r) { return r.id; }).join(',') : ''; } catch (e) {}
              setv(pl, cfg.pl);
              if (inp && inp.value) setv(inp, '');
              btn.click();
              if (!G) { scanMsg({ status: 'plsearch', term: cfg.pl }); return; }
              // Quét camera/ảnh: đợi lưới tải xong; đúng 1 kiện thì mở luôn, nhiều kiện thì để người dùng chọn
              var t0 = Date.now(), last = '', stable = 0;
              (function poll() {
                var rows = diRows(G);
                var sig = rows.map(function(r) { return r.id; }).join(',');
                stable = sig === last ? stable + 1 : 0; last = sig;
                var el = Date.now() - t0;
                var changed = sig !== before;
                var done = (rows.length && changed && stable >= 2 && el > 1200) || (rows.length && stable >= 5 && el > 3500) ||
                  (!rows.length && stable >= 6 && el > 6000) || el > 20000;
                if (!done) { setTimeout(poll, 400); return; }
                if (!rows.length) { scanMsg({ status: 'plempty', term: cfg.pl }); return; }
                if (rows.length === 1 && win.__desmOpenPkg && win.__desmOpenPkg(rows[0].id)) { scanMsg({ status: 'opened' }); return; }
                scanMsg({ status: 'plsearch', term: cfg.pl, n: rows.length });
              })();
            });
          };
          // ===== Quét QR nhãn hạng mục (DETAIL!!!…): tra Material Code ở khung ẩn "Hạng mục chi tiết", lấy Package No rồi mở kiện đó =====
          w.__desmFindDetail = function(cfg) {
            ensurePkgDoc(function(d0) {
              if (!d0) { scanMsg({ status: 'nopage' }); return; }
              findDetailIn(cfg, d0);
            });
          };
          function findDetailIn(cfg, d0) {
            var top = diTop(document), mat = pkgNorm(cfg.material);
            var plk = pkgNorm(String(cfg.pl || '').replace(/^#\s*\d+\s*/, ''));
            function fail(st, n) { scanMsg({ status: st, term: cfg.material, n: n || 0 }); }
            function slowRun() {
            top.__desmDIq = (top.__desmDIq || Promise.resolve()).then(function() {
              return new Promise(function(res) {
                var finished = false;
                function end(f) { if (finished) return; finished = true; try { f(); } catch (e) {} res(); }
                diFrame(top, function(fw) {
                  var G = fw && diGrid(fw);
                  if (!G) { end(function() { fail('dnotfound'); }); return; }
                  diProject(fw, d0, top, function(ok) {
                    var d = fw.document, key = d.getElementById('selSearchKey1'), sv = d.getElementById('txtSearchValue1');
                    var pk = d.getElementById('txtPackageNo'), pl = d.getElementById('txtPackingListNo');
                    if (!ok || !key || !sv) { end(function() { fail('dnotfound'); }); return; }
                    function setv(x, v) { x.value = v; ['input', 'change'].forEach(function(n) { x.dispatchEvent(new fw.Event(n, { bubbles: true })); }); }
                    var oldKey = key.value;
                    setv(key, 'material'); setv(sv, cfg.material);
                    if (pk && pk.value) setv(pk, ''); if (pl && pl.value) setv(pl, '');
                    d.getElementById('btnSearch').click();
                    var t0 = Date.now(), last = '', stable = 0;
                    (function poll() {
                      var rows = diRows(G);
                      var hits = rows.filter(function(r) { return pkgNorm(gridText(G, r, 'MATERIAL_CODE')) === mat; });
                      var sig = rows.length + '|' + hits.length; stable = sig === last ? stable + 1 : 0; last = sig;
                      var el = Date.now() - t0;
                      var done = (hits.length && stable >= 3 && el > 1500) || (!rows.length && stable >= 6 && el > 4000) ||
                        (rows.length && !hits.length && stable >= 5 && el > 6000) || el > 20000;
                      if (!done) { setTimeout(poll, 400); return; }
                      // Trả bộ lọc về như cũ để lần nạp danh sách hạng mục theo kiện không bị lọc nhầm
                      try { setv(sv, ''); setv(key, oldKey); } catch (e) {}
                      if (hits.length > 1 && plk) {
                        var byPl = hits.filter(function(r) {
                          for (var c in G.Cols) { try { if (pkgNorm(gridText(G, r, c)).indexOf(plk) >= 0) return true; } catch (e) {} }
                          return false;
                        });
                        if (byPl.length) hits = byPl;
                      }
                      var pkgs = [];
                      hits.forEach(function(r) { var p = gridText(G, r, 'PACKAGE_NO'); if (p && pkgs.indexOf(p) < 0) pkgs.push(p); });
                      if (!pkgs.length) { end(function() { fail('dnotfound'); }); return; }
                      if (pkgs.length > 1) { end(function() { fail('dmulti', pkgs.length); }); return; }
                      end(function() {
                        scanMsg({ status: 'dfound', term: pkgs[0] });
                        w.__desmFindPkg({ term: pkgs[0], key: pkgs[0], open: cfg.open });
                      });
                    })();
                  });
                });
              });
            });
            }
            // Đường nhanh: gọi thẳng API lưới Hạng mục chi tiết, lọc theo Material Code (KEY1='material'); không có kết quả/lỗi thì dùng cách cũ
            var $j = null, proj = null, once = false;
            try { var W0 = d0.defaultView; $j = W0.jQuery || W0.$ || top.jQuery || top.$; } catch (e) {}
            try { proj = top.__desmProj || (diFindProject(d0, top) || {}).code; } catch (e) {}
            function slowOnce() { if (once) return; once = true; slowRun(); }
            if (!$j || !$j.ajax || !proj) { slowRun(); return; }
            try {
              $j.ajax({
                url: '/getIdsmOsDetailList.do', timeout: 15000,
                data: { PAGE_NUM: 1, PAGE_CNT: 5000, PROJECT_NO: proj, PACKAGE_LIST_NO: '', PACKAGE_NO: '', DESCRIPTION: '', DRAWING_NO: '',
                  TAG_NO: '', QTY_TYPE: 'rsi', QTY: '', KEY1: 'material', VALUE1: cfg.material, LOCATION: '', SEQUENCE: '', VENDOR: '',
                  ATTRIBUTE10: '', TYPE: '', CATEGORY: '', SUB_CATEGORY: '', COMMENTS: '' },
                success: function(data) {
                  if (once) return;
                  var list = data && data.results && data.results.list;
                  if (!list || !list.length) { slowOnce(); return; }
                  var hits = [].filter.call(list, function(r) { return r && pkgNorm(r.MATERIAL_CODE) === mat; });
                  if (!hits.length) { slowOnce(); return; }
                  if (hits.length > 1 && plk) {
                    var byPl = hits.filter(function(r) {
                      for (var c in r) { try { if (pkgNorm(r[c]).indexOf(plk) >= 0) return true; } catch (e) {} }
                      return false;
                    });
                    if (byPl.length) hits = byPl;
                  }
                  var pkgs = [];
                  hits.forEach(function(r) { var p = String(r.PACKAGE_NO == null ? '' : r.PACKAGE_NO).trim(); if (p && pkgs.indexOf(p) < 0) pkgs.push(p); });
                  if (!pkgs.length) { slowOnce(); return; }
                  once = true;
                  if (pkgs.length > 1) { fail('dmulti', pkgs.length); return; }
                  scanMsg({ status: 'dfound', term: pkgs[0] });
                  w.__desmFindPkg({ term: pkgs[0], key: pkgs[0], open: cfg.open });
                },
                error: slowOnce
              });
            } catch (e) { slowOnce(); }
          }
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
            var lastForm = 0;
            var scan = function() {
              try { credHook(document); } catch (e) {}
              if (w.__desmCfg.mode === 'mobile' && allowed(document)) {
                var now = Date.now();
                if (now - lastForm > 400) { lastForm = now; navHandlers(document); formify(document); fixMaps(document); try { colToggle(document); } catch (e) {} }
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
              if (document.head) {
                try { new MutationObserver(function() { setViewport(document); })
                  .observe(document.head, { childList: true }); } catch (e) {}
              }
            });
          }
        })();
        """#
    }

    /// Cài script chạy ở document start cho mọi frame của các lần tải trang sau.
    func installUserScript() {
        guard let controller = contentController else { return }
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: makeScript(),
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: BrowserModel.netRecorderSource,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: BrowserModel.snapRecorderSource,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
    }

    /// Áp ngay lên trang đang mở.
    func evaluateNow() {
        webView?.evaluateJavaScript(makeScript(), completionHandler: nil)
    }

    func applyStyles() {
        installUserScript()
        evaluateNow()
    }

    /// Chép danh sách chuỗi tiếng Anh trên trang chưa có trong từ điển (dạng "English = ") để bổ sung bản dịch.
    func copyMissingStrings(_ done: @escaping (String) -> Void) {
        guard let webView = webView else { done("Chưa có trang để đọc."); return }
        let js = "(function(){var m=window.__desmMiss||{};return Object.keys(m).sort().map(function(k){return k+' = ';}).join('\\n');})();"
        webView.evaluateJavaScript(js) { result, _ in
            if let text = result as? String, !text.isEmpty {
                UIPasteboard.general.string = text
                done("Đã sao chép \(text.split(separator: "\n").count) chuỗi chưa dịch. Dán vào khung chat, hoặc điền bản dịch sau dấu = rồi dán vào ô \"Từ điển bổ sung\".")
            } else {
                done("Chưa phát hiện chuỗi nào cần dịch. Hãy bật tiếng Việt và mở màn hình cần kiểm tra trước.")
            }
        }
    }

    // MARK: - Đọc cấu trúc trang để tinh chỉnh CSS

    private static let diagScript = #"""
    (function() {
      var out = [];
      function cls(el) {
        var c = el.getAttribute && el.getAttribute('class');
        return c ? '.' + c.trim().split(/\s+/).slice(0, 3).join('.') : '';
      }
      function desc(el) {
        var cs, r;
        try { cs = getComputedStyle(el); r = el.getBoundingClientRect(); } catch (e) { return el.tagName; }
        var s = el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + cls(el) +
          ' [' + Math.round(r.width) + 'x' + Math.round(r.height) + ' ' + cs.display;
        if (cs.position !== 'static') s += ' ' + cs.position;
        if (cs.cssFloat && cs.cssFloat !== 'none') s += ' float:' + cs.cssFloat;
        if (el.style && el.style.width) s += ' w=' + el.style.width;
        return s + ']';
      }
      function tree(el, depth, ind) {
        if (depth > 7) return;
        var kids = [].filter.call(el.children, function(k) {
          return !/^(script|style|link|meta|svg|path|br|option|i|span|b|label|a|li|td|th|input)$/i.test(k.tagName) || k.id || depth < 2;
        });
        for (var i = 0; i < kids.length && i < 10; i++) {
          out.push(ind + desc(kids[i]));
          tree(kids[i], depth + 1, ind + '  ');
        }
        if (kids.length > 10) out.push(ind + '... +' + (kids.length - 10));
      }
      function base(u) { return (u || '').split('?')[0].split('/').pop(); }
      function dump(doc, label, lvl) {
        out.push('## ' + label + ' ' + (doc.location ? doc.location.pathname : ''));
        try {
          var vp = doc.querySelector('meta[name=viewport]');
          out.push('viewport=' + (vp ? vp.content : 'none') + ' | innerWidth=' + doc.defaultView.innerWidth);
        } catch (e) {}
        out.push('css: ' + [].map.call(doc.querySelectorAll('link[rel=stylesheet]'), function(l) { return base(l.getAttribute('href')); }).slice(0, 15).join(', '));
        out.push('js: ' + [].map.call(doc.querySelectorAll('script[src]'), function(l) { return base(l.getAttribute('src')); }).slice(0, 20).join(', '));
        try {
          var TG = doc.defaultView.TGGrids;
          for (var gi = 0; TG && gi < TG.length; gi++) {
            var G = TG[gi]; if (!G || !G.Cols) continue;
            out.push('TreeGrid#' + gi + ' cols (tên | tiêu đề | Visible | Width | RelWidth | Sec):');
            for (var cn in G.Cols) {
              var co = G.Cols[cn], ht = '';
              try { ht = String(G.GetString ? G.GetString(G.Rows.Header, cn) : '').replace(/<[^>]*>/g, ''); } catch (e) {}
              out.push('  ' + cn + ' | ' + ht + ' | ' + co.Visible + ' | ' + co.Width + ' | ' + co.RelWidth + ' | ' + (co.MainSec != null ? co.MainSec : co.Sec));
            }
          }
        } catch (e) { out.push('TreeGrid: lỗi ' + e); }
        if (doc.body) tree(doc.body, 0, '  ');
        var sel = doc.querySelector('select, input[type=text]');
        if (sel) {
          var box = sel.closest('table,form') || (sel.parentElement && sel.parentElement.parentElement);
          if (box) out.push('form-sample: ' + box.outerHTML.replace(/ value="[^"]*"/g, '').replace(/\s+/g, ' ').slice(0, 2500));
        }
        if (lvl > 2) return;
        var fs = doc.querySelectorAll('iframe,frame');
        for (var i = 0; i < fs.length; i++) {
          var f = fs[i];
          out.push('frame#' + i + ' name=' + (f.name || '') + ' src=' + base(f.getAttribute('src')) + ' size=' + f.clientWidth + 'x' + f.clientHeight);
          try {
            if (f.contentDocument && f.contentDocument.body) dump(f.contentDocument, 'FRAME' + i, lvl + 1);
            else out.push('  (chưa có nội dung)');
          } catch (e) { out.push('  (khác origin, không đọc được)'); }
        }
      }
      dump(document, 'TOP', 0);
      return out.join('\n').slice(0, 16000);
    })();
    """#

    func copyDiagnostics(_ done: @escaping (String) -> Void) {
        guard let webView = webView else { done("Chưa có trang để đọc."); return }
        webView.evaluateJavaScript(BrowserModel.diagScript) { result, error in
            if let text = result as? String, !text.isEmpty {
                UIPasteboard.general.string = text
                done("Đã sao chép \(text.count) ký tự. Hãy dán vào khung chat để gửi.")
            } else {
                done("Không đọc được cấu trúc trang: \(error?.localizedDescription ?? "kết quả rỗng")")
            }
        }
    }

    // MARK: - Lấy mã HTML của trang

    private func exportScript(stripValues: Bool, stripScripts: Bool) -> String {
        return #"""
        (function() {
          var STRIP_V = \#(stripValues ? "true" : "false"), STRIP_S = \#(stripScripts ? "true" : "false");
          var out = [];
          function base(u) { return (u || '').split('?')[0]; }
          function clean(doc) {
            var root = doc.documentElement.cloneNode(true);
            var st = root.querySelector('#desm-mobile-custom-style'); if (st) st.remove();
            root.classList.remove('desm-mobile-mode');
            var vm = root.querySelector('meta[data-desm="1"]'); if (vm) vm.remove();
            [].forEach.call(root.querySelectorAll('meta[data-desm-orig]'), function(m) {
              m.setAttribute('content', m.getAttribute('data-desm-orig')); m.removeAttribute('data-desm-orig');
            });
            if (STRIP_S) {
              [].forEach.call(root.querySelectorAll('script'), function(s) { if (!s.getAttribute('src')) s.remove(); });
            }
            if (STRIP_V) {
              [].forEach.call(root.querySelectorAll('input'), function(i) {
                if (!/^(button|submit|reset|checkbox|radio|image)$/i.test(i.getAttribute('type') || '')) i.removeAttribute('value');
              });
              [].forEach.call(root.querySelectorAll('textarea'), function(t) { t.textContent = ''; });
            }
            return '<!DOCTYPE html>\n' + root.outerHTML;
          }
          function dump(doc, label, lvl) {
            var loc = '';
            try { loc = doc.location.origin + doc.location.pathname; } catch (e) {}
            out.push('<!-- ===== ' + label + ' ' + loc + ' ===== -->');
            out.push(clean(doc));
            if (lvl > 2) return;
            var fs = doc.querySelectorAll('iframe,frame');
            for (var i = 0; i < fs.length; i++) {
              var f = fs[i];
              var name = label + '>FRAME' + i + ' src=' + base(f.getAttribute('src'));
              try {
                if (f.contentDocument && f.contentDocument.documentElement) dump(f.contentDocument, name, lvl + 1);
                else out.push('<!-- ===== ' + name + ' (chưa có nội dung) ===== -->');
              } catch (e) { out.push('<!-- ===== ' + name + ' (khác origin, không đọc được) ===== -->'); }
            }
          }
          dump(document, 'TOP', 0);
          return out.join('\n\n');
        })();
        """#
    }

    /// Tải nội dung các file script của trang (tài nguyên /resources/scripts/... như plDetail.js) bằng phiên đăng nhập hiện có.
    func fetchScriptFiles(done: @escaping (String?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang để đọc."); return }
        let js = #"""
        var list = [], seen = {};
        function add(u) {
          try {
            var a = new URL(u, location.href);
            if (a.origin !== location.origin || !/\.js$/i.test(a.pathname) || seen[a.pathname]) return;
            seen[a.pathname] = 1; list.push(a.href);
          } catch (e) {}
        }
        add('/resources/scripts/material/plDetail.js');
        function scan(doc, l) {
          [].forEach.call(doc.querySelectorAll('script[src]'), function(s) { add(s.src); });
          if (l > 2) return;
          [].forEach.call(doc.querySelectorAll('iframe,frame'), function(f) { try { if (f.contentDocument) scan(f.contentDocument, l + 1); } catch (e) {} });
        }
        scan(document, 0);
        list = list.filter(function(h) {
          var p = new URL(h).pathname;
          return /\/resources\/scripts\//i.test(p) && !/\.min\.js$/i.test(p);
        });
        var out = [], ok = 0;
        for (var i = 0; i < list.length; i++) {
          var path = new URL(list[i]).pathname;
          try {
            var r = await fetch(list[i], { credentials: 'include', cache: 'no-store' });
            var t = await r.text();
            if (r.ok) ok++;
            out.push('/* ===== ' + path + ' (HTTP ' + r.status + ', ' + t.length + ' ký tự) ===== */\n' + t);
          } catch (e) {
            out.push('/* ===== ' + path + ' (LỖI: ' + e + ') ===== */');
          }
        }
        return ok + '/' + list.length + '\u0001' + out.join('\n\n');
        """#
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let v):
                if let str = v as? String, let sep = str.firstIndex(of: "\u{1}") {
                    let head = String(str[..<sep]); let body = String(str[str.index(after: sep)...])
                    done(body, head)
                } else { done(nil, "Không có kết quả.") }
            case .failure(let e):
                done(nil, "Không tải được script: \(e.localizedDescription)")
            }
        }
    }

    /// Lấy HTML hiện tại của trang (gồm iframe cùng origin). `done(html, lỗi)`.
    func fetchHTML(stripValues: Bool, stripScripts: Bool, done: @escaping (String?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang để đọc."); return }
        webView.evaluateJavaScript(exportScript(stripValues: stripValues, stripScripts: stripScripts)) { result, error in
            if let html = result as? String, !html.isEmpty {
                done(html, "")
            } else {
                done(nil, "Không đọc được HTML: \(error?.localizedDescription ?? "kết quả rỗng")")
            }
        }
    }
}

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

/// Màn hình chính: WebView + thanh địa chỉ/nút điều hướng (tự ẩn khi đã vào DESM), nút camera quét, toast và Cài đặt.
struct BrowserView: View {
    @StateObject private var model = BrowserModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showScanner = false
    @State private var showScanChoice = false
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem? = nil
    @State private var photoChoice: ScanChoice? = nil
    @State private var selectedTab: DesmTab = .package
    @State private var showMore = false
    @State private var showPackingHistory = false
    @State private var showActivity = false
    @State private var showEditLog = false
    @State private var showVessel = false
    @State private var showNotice = false
    @State private var showFetcher = false
    @State private var showSource = false
    @State private var docKind: DesmDocKind? = nil
    @State private var showOutgoing = false
    @State private var showWip = false
    @State private var showMrfReturn = false

    var body: some View {
        VStack(spacing: 0) {
            if !model.barsHidden {
                header
                if model.isLoading {
                    ProgressView(value: model.progress).tint(.blue).frame(height: 3)
                } else {
                    Rectangle().fill(Color(.separator).opacity(0.5)).frame(height: 0.5)
                }
            }
            WebView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if let text = model.toast {
                        Text(text)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.top, 8)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: model.toast)
            // Trong DESM: footer 5 tab mới (luôn hiện). Ngoài DESM (trang đăng nhập...): thanh điều hướng cũ, ẩn thì chỉ còn dải an toàn.
            if model.inDesm {
                DesmTabBar(selected: $selectedTab,
                           onScan: { showScanChoice = true },
                           moreBadge: model.unreadNotices,
                           onSelect: { tab in
                               if tab == .more { showMore = true }
                               else if tab == .outbound { showOutgoing = true }
                               else if tab == .inbound { showMrfReturn = true }
                               else { selectedTab = tab; model.openDesmTab(tab) }
                           })
            } else if !model.barsHidden {
                bottomBar
            } else {
                Color.clear.frame(height: 0)
                    .background(FooterBackground().ignoresSafeArea(edges: .bottom))
            }
        }
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)   // bàn phím phủ lên footer, không ép WebView (tránh lưới báo "Too small space" làm mất focus ô nhập)
        .tint(.blue)
        .onChange(of: scenePhase) { phase in
            if phase != .active { model.saveSession(); model.backgroundedAt = model.backgroundedAt ?? Date() }
            else { model.appBecameActive(); model.refreshNoticeBadge() }
        }
        .onChange(of: model.inDesm) { inside in if inside { model.refreshNoticeBadge() } }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in model.refreshNoticeBadge() }
        .desmDialog(model.dialogQueue.first, finish: { model.finishDialog() })
        .desmAlert(isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        ), icon: "exclamationmark.triangle.fill", title: "Không mở được địa chỉ", message: model.errorMessage,
                   actions: [DesmDialogAction(title: "Đóng", kind: .cancel) { model.errorMessage = nil }])
        .fullScreenCover(isPresented: $showScanner) {
            PackageScannerView(onPick: { c in model.runScan(c) }, onQR: { d in model.runQRScan(d) })
        }
        .desmAlert(isPresented: $showScanChoice, icon: "viewfinder", title: "Quét mã", actions: [
            DesmDialogAction(title: "Quét bằng camera", kind: .primary) { showScanner = true },
            DesmDialogAction(title: "Chọn ảnh có sẵn", kind: .normal) { showPhotoPicker = true },
            DesmDialogAction(title: "Hủy", kind: .cancel),
        ])
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .sheet(item: $photoChoice) { ch in
            ScanChoiceSheet(choice: ch, onPick: { c in
                photoChoice = nil
                PkgParser.learn(c)
                model.runScan(c)
            }, onCancel: { photoChoice = nil })
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: pickedPhoto) { item in
            guard let item = item else { return }
            Task {
                var img: UIImage? = nil
                if let data = try? await item.loadTransferable(type: Data.self) { img = UIImage(data: data) }
                pickedPhoto = nil
                guard let img = img else { model.showToast("Không mở được ảnh đã chọn"); return }
                model.showToast("Đang đọc ảnh…")
                ImageScanner.scan(img) { r in
                    switch r {
                    case .detail(let d): model.runQRScan(d)
                    case .package(let c): PkgParser.learn(c); model.runScan(c)
                    case .choose(let ch): photoChoice = ch
                    case .otherQR(let q):
                        UIPasteboard.general.string = q
                        model.showToast("QR chưa hỗ trợ, đã sao chép: \(q.prefix(60))")
                    case .none: model.showToast("Không thấy QR, Package No hay Packing List No trong ảnh")
                    }
                }
            }
        }
        .sheet(isPresented: $showMore) {
            MoreSheet(model: model, onClose: { showMore = false }, onHistory: { showPackingHistory = true }, onDoc: { docKind = $0 }, onWip: { showWip = true }, onActivity: { showActivity = true }, onEditLog: { showEditLog = true }, onVessel: { showVessel = true }, onNotice: { showNotice = true }, onFetch: { showFetcher = true }, onSource: { showSource = true })
                .presentationDetents([.height(560)])
                .presentationDragIndicator(.visible)
                .tint(Color.tabBlue)
        }
        .sheet(isPresented: $showMrfReturn) {
            DesmMrfReturnSheet(model: model, onClose: { showMrfReturn = false })
                .desmSheet()
        }
        .sheet(isPresented: $showWip) {
            DesmWipSheet(model: model, onClose: { showWip = false })
                .desmSheet()
        }
        .sheet(isPresented: $showOutgoing) {
            DesmOutgoingSheet(model: model, onClose: { showOutgoing = false })
                .desmSheet()
        }
        .sheet(item: $docKind) { kind in
            DesmDocSheet(model: model, kind: kind, onClose: { docKind = nil })
                .desmSheet()
        }
        .sheet(isPresented: $showEditLog) {
            DesmEditLogSheet(model: model, onClose: { showEditLog = false })
                .desmSheet()
        }
        .sheet(isPresented: $showActivity) {
            DesmActivitySheet(model: model, onClose: { showActivity = false })
                .desmSheet()
        }
        .sheet(isPresented: $showNotice) {
            DesmNoticeSheet(model: model, onClose: { showNotice = false })
        }
        .sheet(isPresented: $showVessel) {
            DesmVesselSheet(model: model, onClose: { showVessel = false })
                .desmSheet()
        }
        .sheet(isPresented: $showFetcher) {
            DesmFetchSheet(model: model, onClose: { showFetcher = false })
                .desmSheet()
        }
        .sheet(isPresented: $showSource) {
            DesmSourceSheet(model: model, onClose: { showSource = false })
                .desmSheet()
        }
        .sheet(isPresented: $showPackingHistory) {
            PackingHistorySheet(model: model, onClose: { showPackingHistory = false }, onOpen: { pl in
                showPackingHistory = false
                selectedTab = .package
                model.openPackingList(pl)
            })
                .desmSheet()
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
                .desmSheet()
        }
        .sheet(item: $model.shotItem) { item in
            ShareSheet(url: item.url)
        }
    }

    private func modeButton(size: CGFloat) -> some View {
        Button { model.cycleMode() } label: {
            Image(systemName: model.layoutMode.symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: size, height: size)
                .background(model.layoutMode == .off ? Color(.secondarySystemBackground) : Color.blue.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 11))
        }
        .accessibilityLabel("Đổi chế độ hiển thị: \(model.layoutMode.title)")
    }

    private func settingsButton(size: CGFloat) -> some View {
        Button { model.showSettings = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: size, height: size)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11))
        }
        .accessibilityLabel("Cài đặt giao diện")
    }

    private var addressField: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
            TextField("Nhập địa chỉ website…", text: $model.address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { model.loadAddress() }
                .font(.system(size: 14))
            Button { model.loadAddress() } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
            }
            .accessibilityLabel("Mở địa chỉ")
        }
        .padding(.horizontal, 12).padding(.vertical, model.compactHeader ? 7 : 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        VStack(spacing: 8) {
            if !model.compactHeader {
                HStack(spacing: 9) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DESM Mobile").font(.system(size: 16, weight: .bold))
                        Text(model.pageTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 3)
                    modeButton(size: 38)
                    settingsButton(size: 38)
                }
            }
            HStack(spacing: 8) {
                if model.compactHeader {
                    modeButton(size: 34)
                    settingsButton(size: 34)
                }
                addressField
            }
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 8)
        .background(LinearGradient(colors: [Color(red: 0.81, green: 0.90, blue: 0.99), Color(red: 0.89, green: 0.94, blue: 1.0)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            navButton("chevron.left", title: "Quay lại", enabled: model.canGoBack || model.inDesm) { model.goBack() }
            navButton("chevron.right", title: "Tiến", enabled: model.canGoForward) { model.goForward() }
            navButton("house.fill", title: "DESM", enabled: true) { model.home() }
            navButton("arrow.clockwise", title: "Tải lại", enabled: true) { model.reload() }
            navButton("camera.viewfinder", title: "Chụp", enabled: true) { model.captureFullPage() }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white)
                .shadow(color: Color(red: 0.09, green: 0.25, blue: 0.55).opacity(0.16), radius: 12, y: -2)
        )
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
        .background(FooterBackground().ignoresSafeArea(edges: .bottom))
    }

    private func navButton(_ symbol: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(enabled ? Color.tabBlue : Color.tabInk.opacity(0.4))
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .disabled(!enabled)
    }
}

// MARK: - Footer 5 tab (mẫu mới)

/// 5 tab của footer. Muốn đổi mục menu DESM mà tab mở: sửa `menuId` (id thẻ <a> trong menu trái) hoặc `pattern` (regex tên mục, Anh|Việt).
enum DesmTab: CaseIterable, Identifiable {
    case package, inbound, outbound, report, more
    var id: Self { self }
    var title: String {
        switch self {
        case .package: return "Kiện hàng"
        case .inbound: return "Trả hàng"
        case .outbound: return "Xuất kho"
        case .report: return "Báo cáo"
        case .more: return "Thêm"
        }
    }
    var symbol: String {
        switch self {
        case .package: return "shippingbox"
        case .inbound: return "arrow.uturn.backward.circle"
        case .outbound: return "square.and.arrow.up"
        case .report: return "chart.bar.xaxis"
        case .more: return "square.grid.2x2"
        }
    }
    /// id thẻ <a> trong menu (đã biết: 196 = Kiện hàng). nil = tìm theo tên.
    var menuId: String? {
        switch self {
        case .package: return "196"   // Package
        case .inbound: return "816"   // Material Receiving (dự phòng; tab này mở màn Trả hàng native)
        case .outbound: return "376"  // Outgoing Control (dự phòng; tab này mở màn xuất kho native)
        case .report: return "436"    // RSI Summary (xác nhận từ dump DESM 2026-10-29)
        case .more: return nil
        }
    }
    /// Tên mục menu (không phân biệt hoa thường, cả tiếng Anh và tiếng Việt).
    var pattern: String {
        switch self {
        case .package: return "^(Package|Kiện hàng)$"
        case .inbound: return "^(Material Receiving|Nhận vật tư)$"
        case .outbound: return "^(Outgoing Control|Kiểm soát xuất kho)$"
        case .report: return "^(RSI Summary|Tổng hợp RSI)$"
        case .more: return ""
        }
    }
}

private extension Color {
    static let tabBlue = Color(red: 47 / 255, green: 125 / 255, blue: 224 / 255)
    static let tabBlueLight = Color(red: 150 / 255, green: 200 / 255, blue: 248 / 255)
    static let tabInk = Color(red: 112 / 255, green: 133 / 255, blue: 160 / 255)
}

/// Sóng xanh nhạt phía sau thanh tab (như mẫu).
private struct TabWave: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.height * 0.42))
        p.addCurve(to: CGPoint(x: r.width * 0.55, y: r.height * 0.30),
                   control1: CGPoint(x: r.width * 0.18, y: r.height * 0.10),
                   control2: CGPoint(x: r.width * 0.35, y: r.height * 0.55))
        p.addCurve(to: CGPoint(x: r.width, y: r.height * 0.22),
                   control1: CGPoint(x: r.width * 0.75, y: r.height * 0.05),
                   control2: CGPoint(x: r.width * 0.90, y: r.height * 0.40))
        p.addLine(to: CGPoint(x: r.width, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height)); p.closeSubpath()
        return p
    }
}

struct DesmTabBar: View {
    @Binding var selected: DesmTab
    var onScan: () -> Void
    var moreBadge = 0
    var onSelect: (DesmTab) -> Void

    /// Nút camera cố định ở giữa thanh: Kiện hàng, Nhập kho, [camera], Xuất kho, Thêm
    private var scanItem: some View {
        Button(action: onScan) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(LinearGradient(colors: [Color(red: 0.20, green: 0.58, blue: 0.95),
                                                                  Color(red: 0.30, green: 0.72, blue: 0.98)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 2))
                .shadow(color: Color(red: 0.15, green: 0.40, blue: 0.80).opacity(0.35), radius: 6, y: 3)
                .offset(y: -8)
        }
        .buttonStyle(.plain)
        .frame(width: 64)
        .accessibilityLabel("Quét số kiện hàng bằng camera")
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DesmTab.allCases.filter { $0 != .report }) { tab in
                if tab == .outbound { scanItem }
                let on = tab == selected
                Button { onSelect(tab) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: on ? .semibold : .regular))
                            .overlay(alignment: .topTrailing) {
                                if tab == .more && moreBadge > 0 {
                                    Text(moreBadge > 9 ? "9+" : "\(moreBadge)")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                                        .background(Color.red, in: Capsule())
                                        .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                                        .offset(x: 10, y: -7)
                                }
                            }
                        Text(tab.title)
                            .font(.system(size: 11, weight: on ? .bold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? Color.tabBlue : Color.tabInk)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(on ? Color.tabBlue.opacity(0.09) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white)
                .shadow(color: Color(red: 0.09, green: 0.25, blue: 0.55).opacity(0.16), radius: 12, y: -2)
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.9), lineWidth: 1))
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
        .background(
            ZStack {
                Color(red: 0.95, green: 0.97, blue: 1.0)
                TabWave().fill(LinearGradient(colors: [Color.tabBlueLight.opacity(0.45), Color.tabBlueLight.opacity(0.12)],
                                              startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Hộp thoại tự vẽ (thay alert/confirmationDialog hệ thống)
//
// Thẻ bo tròn lớn nằm sát ĐÁY màn hình (tầm ngón cái tay phải), nút cao 52pt chiếm hết chiều ngang, màu theo app.
// `DesmDialogAction.kind`: primary = nút xanh đặc, normal = xanh nhạt, destructive = đỏ nhạt, cancel = xám.
// Chạm nền mờ: chạy nút cancel nếu có; chỉ có một nút thì chạy nút đó; còn lại thì không làm gì.

struct DesmDialogAction: Identifiable {
    enum Kind { case primary, normal, destructive, cancel }
    let id = UUID()
    let title: String
    var kind: Kind = .normal
    var handler: () -> Void = {}
}

struct DesmDialogState: Identifiable {
    let id: String
    var icon: String? = nil
    var title: String
    var message: String? = nil
    var actions: [DesmDialogAction]
    init(id: String = UUID().uuidString, icon: String? = nil, title: String, message: String? = nil, actions: [DesmDialogAction]) {
        self.id = id; self.icon = icon; self.title = title; self.message = message; self.actions = actions
    }
}

struct DesmDialogCard: View {
    let state: DesmDialogState
    let finish: () -> Void

    private func fg(_ k: DesmDialogAction.Kind) -> Color {
        switch k { case .primary: return .white; case .normal: return Color.tabBlue; case .destructive: return .red; case .cancel: return .primary }
    }
    private func bg(_ k: DesmDialogAction.Kind) -> Color {
        switch k {
        case .primary: return Color.tabBlue
        case .normal: return Color.tabBlue.opacity(0.12)
        case .destructive: return Color.red.opacity(0.12)
        case .cancel: return Color(.secondarySystemFill)
        }
    }
    private func run(_ a: DesmDialogAction) { finish(); a.handler() }
    private func backdropTap() {
        if let c = state.actions.first(where: { $0.kind == .cancel }) { run(c) }
        else if state.actions.count == 1, let a = state.actions.first { run(a) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.38).ignoresSafeArea().onTapGesture { backdropTap() }
            VStack(spacing: 12) {
                if let icon = state.icon {
                    Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.tabBlue)
                        .frame(width: 52, height: 52).background(Color.tabBlue.opacity(0.12), in: Circle())
                }
                Text(state.title).font(.system(size: 19, weight: .bold)).multilineTextAlignment(.center)
                if let m = state.message, !m.isEmpty {
                    Text(m).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .lineLimit(12).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    ForEach(state.actions) { a in
                        Button { run(a) } label: {
                            Text(a.title).font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(fg(a.kind))
                                .background(bg(a.kind), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 22, y: 6)
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

extension View {
    /// Hiện hộp thoại đang có trong `state` (nil = ẩn); `finish` gọi khi đóng.
    func desmDialog(_ state: DesmDialogState?, finish: @escaping () -> Void) -> some View {
        overlay { if let s = state { DesmDialogCard(state: s, finish: finish) } }
            .animation(.easeOut(duration: 0.22), value: state?.id)
    }
    /// Thay `.alert(...)`: hiện khi `isPresented` = true, đóng thì đặt lại false rồi chạy hành động đã chọn.
    func desmAlert(isPresented: Binding<Bool>, icon: String? = nil, title: String, message: String? = nil, actions: [DesmDialogAction]) -> some View {
        desmDialog(isPresented.wrappedValue ? DesmDialogState(id: title, icon: icon, title: title, message: message, actions: actions) : nil,
                   finish: { isPresented.wrappedValue = false })
    }
}

/// Kiểu chung cho mọi màn hình native mở từ "Thêm": sheet toàn chiều cao, thanh kéo, màu nhấn xanh của app.
private struct DesmSheetStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Color.tabBlue)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}
private extension View {
    func desmSheet() -> some View { modifier(DesmSheetStyle()) }
}

/// Mục "Thêm": các nút điều hướng/công cụ cũ của thanh dưới + mở menu đầy đủ, Cài đặt.
struct MoreSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void
    var onHistory: () -> Void = {}
    var onDoc: (DesmDocKind) -> Void = { _ in }
    var onWip: () -> Void = {}
    var onActivity: () -> Void = {}
    var onEditLog: () -> Void = {}
    var onVessel: () -> Void = {}
    var onNotice: () -> Void = {}
    var onFetch: () -> Void = {}
    var onSource: () -> Void = {}

    private struct Item: Identifiable {
        let id = UUID(); let symbol: String; let title: String; var enabled = true; let action: () -> Void
    }
    private var items: [Item] {
        [
            Item(symbol: "line.3.horizontal", title: "Menu đầy đủ") {
                model.webView?.evaluateJavaScript("window.__desmToggleDrawer && window.__desmToggleDrawer();", completionHandler: nil)
            },
            Item(symbol: "chevron.left", title: "Quay lại", enabled: model.canGoBack || model.inDesm) { model.goBack() },
            Item(symbol: "chevron.right", title: "Tiến", enabled: model.canGoForward) { model.goForward() },
            Item(symbol: "arrow.clockwise", title: "Tải lại") { model.reload() },
            Item(symbol: "house.fill", title: "Về DESM") { model.home() },
            Item(symbol: "camera.viewfinder", title: "Chụp trang") { model.captureFullPage() },
            Item(symbol: model.layoutMode.symbol, title: model.layoutMode.shortTitle) { model.cycleMode() },
            Item(symbol: "rectangle.topthird.inset.filled", title: model.barsHidden ? "Hiện thanh địa chỉ" : "Ẩn thanh địa chỉ") {
                withAnimation(.easeInOut(duration: 0.2)) { model.barsHidden.toggle() }
            },
            Item(symbol: "clock.arrow.circlepath", title: "Lịch sử Packing List", enabled: model.inDesm) { onHistory() },
            Item(symbol: "doc.text.magnifyingglass", title: "RSI chưa đóng / vừa đóng", enabled: model.inDesm) { onDoc(.rsi) },
            Item(symbol: "chart.bar.xaxis", title: "Tổng hợp RSI", enabled: model.inDesm) { model.openDesmTab(.report) },
            Item(symbol: "arrow.uturn.backward.circle", title: "MRF trả hàng", enabled: model.inDesm) { onDoc(.mrf) },
            Item(symbol: "hammer", title: "WIP Completion", enabled: model.inDesm) { onWip() },
            Item(symbol: "bell.badge", title: "Hoạt động", enabled: model.inDesm) { onActivity() },
            Item(symbol: "clock.arrow.2.circlepath", title: "Tra Edit Log", enabled: model.inDesm) { onEditLog() },
            Item(symbol: "megaphone.fill", title: "Thông báo", enabled: model.inDesm) { onNotice() },
            Item(symbol: "ferry.fill", title: "Bản đồ tàu", enabled: model.inDesm) { onVessel() },
            Item(symbol: "chevron.left.forwardslash.chevron.right", title: "Mã nguồn trang này", enabled: model.inDesm) { onSource() },
            Item(symbol: "square.and.arrow.down.on.square", title: "Tải file / API cho AI", enabled: model.inDesm) { onFetch() },
            Item(symbol: "slider.horizontal.3", title: "Cài đặt") { model.showSettings = true },
        ]
    }

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 38, height: 5).padding(.top, 8)
            Text("Thêm").font(.system(size: 18, weight: .bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(items) { it in
                    Button {
                        onClose()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { it.action() }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: it.symbol).font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.tabBlue)
                            Text(it.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, minHeight: 82)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.tabBlue.opacity(0.08)))
                        .opacity(it.enabled ? 1 : 0.4)
                    }
                    .buttonStyle(.plain).disabled(!it.enabled)
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
    }
}

/// Footer vẽ bằng Canvas theo Branding/footer-bg.svg: gradient xanh, chấm mờ, hai lớp sóng, đường nhấn vàng-xanh ở mép trên.
struct FooterBackground: View {
    private let c1 = Color(red: 23 / 255, green: 37 / 255, blue: 84 / 255)
    private let c2 = Color(red: 29 / 255, green: 78 / 255, blue: 216 / 255)
    private let c3 = Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255)

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.97, blue: 1.0)
            TabWave().fill(LinearGradient(colors: [Color.tabBlueLight.opacity(0.45), Color.tabBlueLight.opacity(0.12)],
                                          startPoint: .top, endPoint: .bottom))
        }
    }
}

extension BrowserModel {
    /// Ghi lại request XHR/fetch của trang DESM (chỉ khi bật trong Cài đặt). Nhật ký nằm trong localStorage của trang, mật khẩu/token được che.
    static let netRecorderSource = #"""
    (function() {
      if (window.__desmNet) return; window.__desmNet = 1;
      if (!/(^|\.)doosanenerbility\.com$/i.test(location.hostname)) return;
      var KEY = 'desmNetLog';
      function on() { try { return localStorage.getItem('desmNetOn') === '1'; } catch (e) { return false; } }
      function cut(s, n) { s = String(s == null ? '' : s); return s.length > n ? s.slice(0, n) + '…[' + s.length + ' ký tự]' : s; }
      function mask(s) {
        return String(s == null ? '' : s).replace(/((?:pass\w*|pwd|token|secret|auth\w*)["']?\s*[=:]\s*["']?)[^&"',}\s]*/gi, '$1***');
      }
      // Gửi từng request sang app (desmNet) để lưu vào file trong máy: không bị giới hạn dung lượng localStorage, không cắt phản hồi API.
      function push(e) {
        if (!on()) return;
        try { window.webkit.messageHandlers.desmNet.postMessage(e); } catch (x) {}
      }
      // Tài nguyên tĩnh (script/css/ảnh/font) chỉ ghi dòng ngắn, không lưu nội dung
      function isStatic(u) { return /\.(js|css|png|jpe?g|gif|svg|ico|woff2?|ttf|otf|map)(\?|#|$)/i.test(String(u == null ? '' : u)); }
      function ctOf(x) { try { return (x.getResponseHeader('content-type') || '').split(';')[0]; } catch (e) { return ''; } }
      // Phát hiện hết phiên: XHR bị chuyển về trang đăng nhập / trả 401 / trả HTML có ô mật khẩu -> báo cho app (desmSession)
      var lastExp = 0;
      function pathOf(u) { try { return new URL(u, location.href).pathname; } catch (e) { return ''; } }
      function expired(why) {
        var n = Date.now(); if (n - lastExp < 15000) return; lastExp = n;
        try { window.webkit.messageHandlers.desmSession.postMessage({ why: why }); } catch (e) {}
      }
      function checkXhr(x, u) {
        try {
          if (/login/i.test(location.pathname)) return;
          if (/login/i.test(pathOf(x.responseURL || '')) && !/login/i.test(pathOf(u))) { expired('redirect'); return; }
          if (x.status === 401) { expired('401'); return; }
          if (x.status === 200 && (x.responseType === '' || x.responseType === 'text')) {
            var t = x.responseText;
            if (t && t.length < 300000 && /^\s*</.test(t.slice(0, 60)) && /<html/i.test(t) && (t.match(/<input[^>]+type=["']?password/gi) || []).length === 1 && /login/i.test(t.slice(0, 5000))) expired('loginhtml');
          }
        } catch (e) {}
      }
      function bodyText(b) {
        if (b == null) return '';
        if (typeof b === 'string') return b;
        try { if (b instanceof URLSearchParams) return b.toString(); } catch (e) {}
        try { if (b instanceof FormData) { var o = []; b.forEach(function(v, k) { o.push(k + '=' + (typeof v === 'string' ? v : '[file]')); }); return o.join('&'); } } catch (e) {}
        return '[không phải văn bản]';
      }
      try {
        var X = XMLHttpRequest.prototype, o = X.open, sd = X.send;
        X.open = function(m, u) { this.__d = { m: m, u: u, t: Date.now() }; return o.apply(this, arguments); };
        X.send = function(b) {
          var d = this.__d, x = this;
          if (d) x.addEventListener('loadend', function() { checkXhr(x, d.u); });
          if (d && on()) {
            d.b = b;
            x.addEventListener('loadend', function() {
              var st = isStatic(d.u), rt = '';
              try { rt = (x.responseType === '' || x.responseType === 'text') ? x.responseText : '[' + x.responseType + ']'; } catch (e) {}
              push({ t: new Date().toISOString(), via: 'xhr', page: location.pathname + location.search, method: d.m, url: cut(mask(new URL(d.u, location.href).href), 2000),
                     body: cut(mask(bodyText(d.b)), 30000), status: x.status, ms: Date.now() - d.t, ct: ctOf(x), len: rt.length,
                     resp: st ? '' : cut(mask(rt), 400000) });
            });
          }
          return sd.apply(this, arguments);
        };
      } catch (e) {}
      try {
        var f = window.fetch;
        if (f) window.fetch = function(inp, init) {
          var t = Date.now(), p = f.apply(this, arguments);
          if (!on()) return p;
          var u = typeof inp === 'string' ? inp : (inp && inp.url), m = (init && init.method) || (inp && inp.method) || 'GET', b = init && init.body;
          return p.then(function(r) {
            try {
              var st = isStatic(u), ct = (r.headers.get('content-type') || '').split(';')[0];
              if (st) {
                push({ t: new Date().toISOString(), via: 'fetch', page: location.pathname + location.search, method: m, url: cut(mask(u), 2000),
                       body: '', status: r.status, ms: Date.now() - t, ct: ct, len: 0, resp: '' });
              } else r.clone().text().then(function(tx) {
                push({ t: new Date().toISOString(), via: 'fetch', page: location.pathname + location.search, method: m, url: cut(mask(u), 2000),
                       body: cut(mask(bodyText(b)), 30000), status: r.status, ms: Date.now() - t, ct: ct, len: tx.length, resp: cut(mask(tx), 400000) });
              });
            } catch (e) {}
            return r;
          });
        };
      } catch (e) {}
    })();
    """#

    /// Tự lưu cấu trúc + HTML + CSS của từng màn hình DESM (gồm cả màn nằm trong iframe) khi người dùng bật "Tự lưu từng màn hình".
    /// Cứ 2,5 giây quét trang và các iframe cùng domain; màn nào nội dung đã ổn định thì gửi sang app (message "desmSnap"). Mỗi màn tối đa 3 lần/lần tải.
    static let snapRecorderSource = #"""
    (function() {
      if (window.__desmSnap) return; window.__desmSnap = 1;
      if (window !== window.top) return;
      if (!/(^|\.)doosanenerbility\.com$/i.test(location.hostname)) return;
      function on() { try { return localStorage.getItem('desmSnapOn') === '1'; } catch (e) { return false; } }
      var last = {}, sentLen = {}, sentN = {}, cssSent = {}, busy = false;
      function frames(doc, lvl, out) {
        out.push(doc);
        if (lvl > 3) return out;
        var fs = doc.querySelectorAll('iframe,frame');
        for (var i = 0; i < fs.length; i++) {
          try { var d = fs[i].contentDocument; if (d && d.documentElement && d.location.origin === location.origin) frames(d, lvl + 1, out); } catch (e) {}
        }
        return out;
      }
      function clean(doc) {
        var root = doc.documentElement.cloneNode(true);
        var st = root.querySelector('#desm-mobile-custom-style'); if (st) st.remove();
        root.classList.remove('desm-mobile-mode');
        var vm = root.querySelector('meta[data-desm="1"]'); if (vm) vm.remove();
        [].forEach.call(root.querySelectorAll('meta[data-desm-orig]'), function(m) {
          m.setAttribute('content', m.getAttribute('data-desm-orig')); m.removeAttribute('data-desm-orig');
        });
        [].forEach.call(root.querySelectorAll('script'), function(s) { if (!s.getAttribute('src')) s.remove(); });
        [].forEach.call(root.querySelectorAll('input'), function(i) {
          if (!/^(button|submit|reset|checkbox|radio|image)$/i.test(i.getAttribute('type') || '')) i.removeAttribute('value');
        });
        [].forEach.call(root.querySelectorAll('textarea'), function(t) { t.textContent = ''; });
        return '<!DOCTYPE html>\n' + root.outerHTML;
      }
      function outline(doc) {
        var out = [], n = 0;
        (function walk(el, d) {
          if (n > 700 || d > 9) return;
          var tag = el.tagName.toLowerCase();
          if (/^(script|style|link|meta|noscript|br)$/.test(tag)) return;
          n++;
          var s = tag + (el.id ? '#' + el.id : '') + (typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\s+/).join('.') : '');
          if (el.children.length === 0) { var t = (el.textContent || '').trim().slice(0, 40); if (t) s += ' "' + t + '"'; }
          out.push(new Array(d + 1).join('  ') + s);
          for (var i = 0; i < el.children.length; i++) walk(el.children[i], d + 1);
        })(doc.body || doc.documentElement, 0);
        return out.join('\n');
      }
      async function tick() {
        if (busy || !on()) return; busy = true;
        try {
          var list = frames(document, 0, []);
          for (var i = 0; i < list.length; i++) {
            var doc = list[i], path = '', search = '';
            try { if (doc.location.href === 'about:blank') continue; path = doc.location.pathname; search = doc.location.search; } catch (e) { continue; }
            if (!doc.body) continue;
            var len = doc.documentElement.innerHTML.length;
            if (last[path] !== len) { last[path] = len; continue; }   // đợi nội dung ổn định (2 lần đo liên tiếp bằng nhau)
            if (sentLen[path] === len || (sentN[path] || 0) >= 3) continue;
            sentLen[path] = len; sentN[path] = (sentN[path] || 0) + 1;
            var links = [], files = [];
            [].forEach.call(doc.querySelectorAll('link[rel~=stylesheet][href]'), function(l) { links.push(l.href); });
            for (var k = 0; k < links.length; k++) {
              var u = links[k]; if (cssSent[u]) continue; cssSent[u] = 1;
              try { var r = await fetch(u, { credentials: 'include' }); files.push({ url: u, status: r.status, text: await r.text() }); } catch (e) {}
            }
            try {
              window.webkit.messageHandlers.desmSnap.postMessage({ path: path, search: search, title: doc.title || '', t: new Date().toISOString(),
                top: doc === document, html: clean(doc), outline: outline(doc), cssLinks: links, cssFiles: files });
            } catch (e) {}
          }
        } catch (e) {}
        busy = false;
      }
      setInterval(tick, 2500);
    })();
    """#

    func setSnap(_ on: Bool) {
        webView?.evaluateJavaScript("try{localStorage.setItem('desmSnapOn','\(on ? "1" : "0")')}catch(e){}", completionHandler: nil)
    }

    func setNetLog(_ on: Bool) {
        webView?.evaluateJavaScript("try{localStorage.setItem('desmNetOn','\(on ? "1" : "0")')}catch(e){}", completionHandler: nil)
    }

    func clearNetLog() {
        NetLogStore.clear()
        webView?.evaluateJavaScript("try{localStorage.removeItem('desmNetLog')}catch(e){}", completionHandler: nil)
    }

    enum NetLogFormat { case text, json, summary }

    /// Đọc nhật ký API đã ghi (file trong máy). text = đọc từng request; json = máy đọc được, đủ phản hồi; summary = tóm tắt từng endpoint.
    func fetchNetLog(format: NetLogFormat = .text, done: @escaping (String?, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let entries = NetLogStore.entries()
            let out: String
            switch format {
            case .text: out = NetLogStore.exportText(entries)
            case .json: out = NetLogStore.exportJSON(entries)
            case .summary: out = NetLogStore.exportSummary(entries)
            }
            DispatchQueue.main.async {
                if entries.isEmpty { done(nil, "Chưa có request nào được ghi. Hãy bật ghi API, thao tác trên trang rồi quay lại.") }
                else { done(out, "") }
            }
        }
    }

    /// Tải nội dung một địa chỉ cùng domain (script, trang, API GET) bằng phiên đăng nhập hiện có.
    func fetchURLText(_ path: String, done: @escaping (String?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang để đọc."); return }
        let js = #"""
        var a;
        try { a = new URL(u, location.href); } catch (e) { return 'LỖI: địa chỉ không hợp lệ'; }
        if (a.origin !== location.origin) return 'LỖI: chỉ tải được địa chỉ cùng domain với trang đang mở (' + location.origin + ')';
        var r = await fetch(a.href, { credentials: 'include', cache: 'no-store' });
        var t = await r.text();
        return 'HTTP ' + r.status + ' ' + (r.headers.get('content-type') || '') + ' ' + a.href + '\n\n' + t;
        """#
        webView.callAsyncJavaScript(js, arguments: ["u": path], in: nil, in: .page) { result in
            switch result {
            case .success(let v):
                if let t = v as? String { done(t, "") } else { done(nil, "Không có kết quả.") }
            case .failure(let e):
                done(nil, "Không tải được: \(e.localizedDescription)")
            }
        }
    }
}

// MARK: - Tự kết nối lại khi hết phiên đăng nhập
//
// Vấn đề: sau một thời gian (hoặc qua đêm) phiên DESM phía máy chủ hết hạn, nhưng app vẫn nạp lại địa chỉ cũ với cookie cũ
// nên trang trống/không chạy thay vì quay về trang đăng nhập. Cách xử lý:
//  1) Khi mở app: khôi phục cookie rồi "thăm dò" main.do bằng URLSession; hết phiên (chuyển về login, 401, có ô mật khẩu, hoặc
//     lần dùng cuối quá lâu và đã lưu tài khoản) thì xoá cookie cũ và mở https://desm.doosanenerbility.com/login.do.
//  2) Khi app quay lại từ nền sau > 10 phút: thăm dò tương tự.
//  3) Khi đang dùng: JS (netRecorderSource) phát hiện XHR bị đẩy về login/401/HTML đăng nhập -> message "desmSession".
//  4) Ở trang đăng nhập: app tự điền tài khoản đã lưu (CredStore) và, nếu đang kết nối lại, tự bấm Login (__desmSubmitLogin).
// Chống lặp: tối đa 3 lần kết nối lại / 5 phút và 2 lần tự bấm Login mỗi lần; sau đó chuyển sang đăng nhập thủ công.
// Bật/tắt: Cài đặt > "Tự đăng nhập lại khi hết phiên" (khoá desmAutoReconnect, mặc định bật).
extension BrowserModel {
    static let loginURL = "https://desm.doosanenerbility.com/login.do"
    /// Lần dùng cuối quá ngưỡng này thì coi như phiên đã hết, khỏi thăm dò.
    static let staleSessionAge: TimeInterval = 6 * 3600

    static var edgeSwipe: Bool { UserDefaults.standard.object(forKey: "desmEdgeSwipe") as? Bool ?? true }

    static var autoReconnect: Bool { UserDefaults.standard.object(forKey: "desmAutoReconnect") as? Bool ?? true }

    func markActive() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "desmLastActive") }

    private var lastActiveAge: TimeInterval? {
        let t = UserDefaults.standard.double(forKey: "desmLastActive")
        return t > 0 ? Date().timeIntervalSince1970 - t : nil
    }

    enum SessionProbe { case none, valid, expired, unknown }

    /// Gọi sau mỗi lần tải xong một trang: vào được DESM (không phải trang đăng nhập) = kết nối lại thành công.
    func sessionDidLoad(_ url: URL?) {
        let host = url?.host?.lowercased() ?? ""
        let path = url?.path.lowercased() ?? ""
        guard host == "doosanenerbility.com" || host.hasSuffix(".doosanenerbility.com"), !path.contains("login") else { return }
        markActive()
        if reconnecting { reconnecting = false; autoSubmitCount = 0 }
    }

    /// Xoá cookie DESM trong WKWebView (chỉ cookie; giữ localStorage/bộ nhớ đệm khác).
    func clearDesmCookies(_ done: @escaping () -> Void) {
        guard let store = webView?.configuration.websiteDataStore else { done(); return }
        let types: Set<String> = [WKWebsiteDataTypeCookies]
        store.fetchDataRecords(ofTypes: types) { records in
            let mine = records.filter { $0.displayName.lowercased().contains("doosanenerbility") }
            if mine.isEmpty { done(); return }
            store.removeData(ofTypes: types, for: mine) { done() }
        }
    }

    /// Thăm dò xem phiên còn dùng được không (không đụng tới WKWebView). Lỗi mạng -> .unknown (cứ nạp trang như thường).
    func probeSession(_ completion: @escaping (SessionProbe) -> Void) {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { completion(.unknown); return }
        store.getAllCookies { cookies in
            let mine = cookies.filter { $0.domain.lowercased().contains("doosanenerbility") }
            if mine.isEmpty { completion(.none); return }
            guard let url = URL(string: BrowserModel.homeURL) else { completion(.unknown); return }
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            req.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: mine)
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            cfg.timeoutIntervalForRequest = 8
            URLSession(configuration: cfg).dataTask(with: req) { data, resp, err in
                guard err == nil, let http = resp as? HTTPURLResponse else { completion(.unknown); return }
                if http.statusCode == 401 { completion(.expired); return }
                if http.statusCode >= 500 || http.statusCode == 0 { completion(.unknown); return }
                let path = http.url?.path.lowercased() ?? ""
                if path.contains("login") { completion(.expired); return }
                // Không dò "ô mật khẩu" trong HTML nữa: main.do có sẵn form đổi mật khẩu nên luôn bị nhận nhầm là hết phiên.
                // Trường hợp máy chủ trả trang đăng nhập mà không redirect đã có checkLoginForm (ô mật khẩu hiển thị) lo.
                _ = data
                completion(.valid)
            }.resume()
        }
    }

    /// Mở trang đăng nhập (sau khi xoá cookie cũ). `auto` = true: tự điền + tự bấm Login nếu có tài khoản lưu.
    func openLogin(auto: Bool) {
        guard let wv = webView, let url = URL(string: BrowserModel.loginURL) else { return }
        reconnecting = auto
        autoSubmitCount = 0
        SessionStore.clear()
        clearDesmCookies {
            DispatchQueue.main.async { wv.load(URLRequest(url: url, timeoutInterval: 45)) }
        }
    }

    /// Phiên đã hết: xoá phiên cũ và đăng nhập lại. Có giới hạn số lần để không lặp vô hạn.
    func reconnectSession(reason: String) {
        guard BrowserModel.autoReconnect else { return }
        let now = Date()
        if let last = lastReconnectAt, now.timeIntervalSince(last) < 10 { return }
        reconnectTimes = reconnectTimes.filter { now.timeIntervalSince($0) < 300 }
        if reconnectTimes.count >= 3 {
            reconnecting = false
            showToast("Không tự đăng nhập lại được, hãy đăng nhập thủ công")
            return
        }
        reconnectTimes.append(now); lastReconnectAt = now
        showToast(CredStore.load() != nil && CredStore.enabled ? "Phiên đã hết hạn, đang đăng nhập lại…" : "Phiên đã hết hạn, hãy đăng nhập lại")
        openLogin(auto: true)
    }

    /// Mở app: khôi phục cookie xong thì kiểm tra phiên rồi mới nạp trang (đăng nhập lại nếu cần).
    func startLoad(_ webView: WKWebView) {
        let start = URL(string: address) ?? URL(string: BrowserModel.homeURL)!
        guard BrowserModel.autoReconnect else { webView.load(URLRequest(url: start, timeoutInterval: 45)); return }
        // Lâu không dùng + đã lưu tài khoản (đăng nhập lại êm) -> khỏi thăm dò, đăng nhập lại luôn.
        // Chưa lưu tài khoản thì chỉ dựa vào thăm dò để không bắt người dùng gõ lại khi phiên vẫn còn.
        if let age = lastActiveAge, age > BrowserModel.staleSessionAge, CredStore.enabled, CredStore.load() != nil {
            DispatchQueue.main.async { self.openLogin(auto: true) }
            return
        }
        probeSession { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .none: self.openLogin(auto: true)          // chưa có phiên: vào thẳng trang đăng nhập (tự điền nếu có tài khoản)
                case .expired: self.reconnecting = true; self.reconnectTimes.append(Date()); self.lastReconnectAt = Date(); self.showToast("Phiên đã hết hạn, đang đăng nhập lại…"); self.openLogin(auto: true)
                case .valid, .unknown: webView.load(URLRequest(url: start, timeoutInterval: 45))
                }
            }
        }
    }

    /// App quay lại từ nền: nếu đã nằm nền lâu thì kiểm tra phiên (không làm gì khi đang ở trang đăng nhập).
    func appBecameActive() {
        guard BrowserModel.autoReconnect, let t = backgroundedAt else { return }
        backgroundedAt = nil
        guard Date().timeIntervalSince(t) > 600, inDesm else { return }
        probeSession { [weak self] result in
            DispatchQueue.main.async { if result == .expired || result == .none { self?.reconnectSession(reason: "foreground") } }
        }
    }
}

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
struct SettingsView: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var shareItem: ShareItem?
    @AppStorage("desmExportStripValues2") private var stripValues = false
    @AppStorage("desmRememberLogin") private var rememberLogin = true
    @AppStorage("desmAutofill") private var autofill = true
    @AppStorage("desmAutoReconnect") private var autoReconnect = true
    @AppStorage("desmExportStripScripts2") private var stripScripts = false
    @AppStorage("desmScanOpenDetail") private var scanOpenDetail = true
    @AppStorage("desmNetLogOn") private var netLogOn = false
    @AppStorage("desmSnapOn") private var snapOn = false
    @AppStorage("desmEdgeSwipe") private var edgeSwipe = true
    @State private var fetchPath = ""

    private func shareText(_ text: String, prefix: String, ext: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(formatter.string(from: Date())).\(ext)")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            shareItem = ShareItem(url: url)
        } catch {
            message = "Không lưu được file: \(error.localizedDescription)"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                languageSection
                scanSection
                loginSection
                Section {
                    NavigationLink("Nâng cao & công cụ phát triển") { advancedForm }
                } footer: {
                    Text("CSS và từ điển bổ sung, ghi API, lưu mã HTML/script của trang. Chỉ cần khi tinh chỉnh app.")
                }
            }
            .onAppear { model.setNetLog(netLogOn); model.setSnap(snapOn) }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Xong") { model.applyStyles(); dismiss() } } }
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
            }
        }
        .desmAlert(isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        ), icon: "info.circle.fill", title: "Kết quả", message: message,
                   actions: [DesmDialogAction(title: "OK", kind: .primary) { message = nil }])
    }

    // MARK: Cài đặt chính

    private var displaySection: some View {
        Section {
            Picker("Chế độ", selection: Binding(
                get: { model.layoutMode },
                set: { model.setMode($0) }
            )) {
                ForEach(LayoutMode.allCases) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)

            if model.layoutMode == .fit {
                Stepper("Độ rộng khi thu nhỏ: \(model.fitWidth)px", value: Binding(
                    get: { model.fitWidth },
                    set: { model.fitWidth = $0; model.applyStyles() }
                ), in: 700...1800, step: 100)
            }
            Toggle("Chỉ áp dụng cho DESM", isOn: Binding(
                get: { model.scopeOnly },
                set: { model.scopeOnly = $0; model.applyStyles() }
            ))
            Toggle("Thu gọn thanh trên", isOn: $model.compactHeader)
            Toggle("Vuốt mép màn hình để quay lại / tiến", isOn: $edgeSwipe)
        } header: {
            Text("Hiển thị")
        } footer: {
            Text("Mobile: sắp xếp lại bố cục cho màn hình nhỏ. Vừa màn hình: bản desktop thu nhỏ, phóng to bằng hai ngón. Gốc: không can thiệp. Vuốt từ mép trái để quay lại trang trước, từ mép phải để tiến.")
        }
    }

    private var languageSection: some View {
        Section {
            Toggle("Giao diện DESM bằng tiếng Việt", isOn: Binding(
                get: { model.viLang },
                set: { model.setVietnamese($0) }
            ))
        } header: {
            Text("Ngôn ngữ")
        } footer: {
            Text("Dịch nhãn, nút, menu, tiêu đề cột và hộp thoại; dữ liệu (mã kiện, mô tả hàng, vị trí) giữ nguyên. Nên để ngôn ngữ gốc của trang là English.")
        }
    }

    private var scanSection: some View {
        Section {
            Toggle("Quét xong mở luôn chi tiết kiện", isOn: $scanOpenDetail)
        } header: {
            Text("Quét Package No")
        } footer: {
            Text("Bấm nút camera ở giữa thanh dưới khi đang ở màn hình Package. App đọc Package No trên tem, điền ô Số kiện hàng rồi Search. Không có dòng khớp chính xác thì báo không tìm thấy, không mở nhầm kiện.")
        }
    }

    private var loginSection: some View {
        Section {
            Toggle("Ghi nhớ phiên đăng nhập", isOn: $rememberLogin)
            Toggle("Tự điền tài khoản ở trang đăng nhập", isOn: $autofill)
            Toggle("Tự đăng nhập lại khi hết phiên", isOn: $autoReconnect)
            Button("Xóa tài khoản và phiên đã lưu", role: .destructive) {
                CredStore.clear()
                SessionStore.clear()
                model.showToast("Đã xóa tài khoản và phiên đã lưu")
            }
        } header: {
            Text("Đăng nhập")
        } footer: {
            Text("Tài khoản (chỉ khi bạn đồng ý lưu) và phiên được giữ trong Keychain của máy này. Khi phiên DESM hết hạn, app quay về trang đăng nhập, điền tài khoản đã lưu và tự bấm Login; cần bật \"Tự điền tài khoản\" và đã lưu tài khoản.")
        }
    }

    // MARK: Nâng cao

    private var advancedForm: some View {
        Form {
            Section {
                TextEditor(text: $model.customCSS)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 110)
                Button("Xóa CSS bổ sung", role: .destructive) { model.customCSS = ""; model.applyStyles() }
            } header: {
                Text("CSS bổ sung")
            } footer: {
                Text("Áp dụng khi bấm Xong.")
            }

            Section {
                TextEditor(text: $model.customDict)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 110)
                Button("Sao chép chuỗi chưa dịch") { model.copyMissingStrings { message = $0 } }
            } header: {
                Text("Từ điển bổ sung")
            } footer: {
                Text("Mỗi dòng: English = Tiếng Việt. Áp dụng khi bấm Xong.")
            }

            Section {
                Toggle("Tự lưu cấu trúc & CSS từng màn hình", isOn: $snapOn)
                    .onChange(of: snapOn) { model.setSnap($0) }
                Button("Lưu tất cả màn hình đã ghi (1 file)…") {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let text = SnapStore.export()
                        DispatchQueue.main.async {
                            guard let text = text else { message = "Chưa ghi màn hình nào. Bật công tắc rồi mở lần lượt các màn hình DESM."; return }
                            shareText(text, prefix: "desm-screens", ext: "txt")
                        }
                    }
                }
                Button("Xóa các màn hình đã ghi", role: .destructive) {
                    SnapStore.clear(); message = "Đã xóa các màn hình đã ghi."
                }
            } header: {
                Text("Ghi từng màn hình")
            } footer: {
                Text("Bật công tắc rồi vào lần lượt từng màn hình (menu) của DESM, chờ vài giây cho trang tải xong. App tự lưu cây cấu trúc, HTML và toàn bộ file CSS của từng màn, kể cả màn nằm trong khung con. Xong thì lưu một file duy nhất và gửi cho tác giả. Nhớ tắt công tắc và xóa khi xong.")
            }

            Section {
                Toggle("Ghi lại các request API của trang", isOn: $netLogOn)
                    .onChange(of: netLogOn) { model.setNetLog($0) }
                Button("Lưu nhật ký API (JSON đầy đủ)…") {
                    model.fetchNetLog(format: .json) { text, error in
                        guard let text = text else { message = error; return }
                        shareText(text, prefix: "desm-api-full", ext: "json")
                    }
                }
                Button("Lưu tóm tắt các endpoint…") {
                    model.fetchNetLog(format: .summary) { text, error in
                        guard let text = text else { message = error; return }
                        shareText(text, prefix: "desm-api-summary", ext: "txt")
                    }
                }
                Button("Lưu nhật ký API (văn bản)…") {
                    model.fetchNetLog { text, error in
                        guard let text = text else { message = error; return }
                        shareText(text, prefix: "desm-api", ext: "txt")
                    }
                }
                Button("Xóa nhật ký API", role: .destructive) {
                    model.clearNetLog(); message = "Đã xóa nhật ký API."
                }
            } header: {
                Text("Nhật ký API")
            } footer: {
                Text("Bật công tắc, thao tác trên trang DESM (Search, quét, mở chi tiết…) rồi quay lại lưu file. Nhật ký nằm trong máy, có địa chỉ API, tham số và phản hồi đầy đủ của API dữ liệu; mật khẩu/token được che. Nhớ tắt và xóa khi xong.")
            }

            Section {
                Button("Lưu HTML trang đang mở…") {
                    model.fetchHTML(stripValues: stripValues, stripScripts: stripScripts) { html, error in
                        guard let html = html else { message = error; return }
                        shareText(html, prefix: "desm-page", ext: "html")
                    }
                }
                Button("Lưu script của trang…") {
                    model.fetchScriptFiles { text, info in
                        guard let text = text else { message = info; return }
                        message = "Đã tải \(info) file script."
                        shareText(text, prefix: "desm-scripts", ext: "txt")
                    }
                }
                Button("Sao chép cấu trúc trang đang mở") { model.copyDiagnostics { message = $0 } }
                Toggle("Ẩn giá trị trong ô nhập", isOn: $stripValues)
                Toggle("Bỏ mã script nội tuyến", isOn: $stripScripts)
            } header: {
                Text("Mã nguồn trang")
            } footer: {
                Text("Mở màn hình cần xem (Package, Hạng mục chi tiết…) trước. HTML có thể chứa thông tin nội bộ, hãy kiểm tra trước khi chia sẻ.")
            }

            Section {
                Button("Thu thập mẫu API (loginStatus + chuỗi giao diện)…") {
                    let specs = ["GET /loginStatus.do",
                                 "POST /getMessageProperties.do",
                                 "GET /getMessageProperties.do"]
                    var out = "DESM — mẫu API (loginStatus, getMessageProperties)\n"
                    func next(_ i: Int) {
                        if i >= specs.count { shareText(out, prefix: "desm-api-sample", ext: "txt"); return }
                        model.fetchResource(specs[i]) { r, err in
                            out += "\n===== \(specs[i]) =====\n"
                            if let r = r {
                                let body = r.text.count > 200_000 ? String(r.text.prefix(200_000)) + "\n…(cắt bớt)" : r.text
                                out += "HTTP \(r.status) · \(r.contentType) · \(r.text.count) ký tự\n\(body)\n"
                            } else { out += "LỖI: \(err)\n" }
                            next(i + 1)
                        }
                    }
                    next(0)
                }
            } header: {
                Text("Thu thập mẫu API")
            } footer: {
                Text("Cần đang ở DESM và đã đăng nhập. Gọi /loginStatus.do và /getMessageProperties.do rồi lưu một file để gửi lại cho tác giả. Nội dung phản hồi có thể chứa thông tin nội bộ, hãy xem trước khi chia sẻ.")
            }

            Section {
                TextField("Địa chỉ, vd /resources/scripts/…js", text: $fetchPath)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Tải nội dung địa chỉ và lưu file…") {
                    let path = fetchPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !path.isEmpty else { message = "Hãy nhập địa chỉ cần tải."; return }
                    model.fetchURLText(path) { text, error in
                        guard let text = text else { message = error; return }
                        shareText(text, prefix: "desm-fetch", ext: "txt")
                    }
                }
            } header: {
                Text("Tải địa chỉ")
            } footer: {
                Text("Tải script, trang hoặc API dạng GET cùng domain bằng phiên đăng nhập hiện có.")
            }
        }
        .navigationTitle("Nâng cao")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Nhật ký API lưu thành file trong máy
//
// Trang gửi từng request/phản hồi (message "desmNet") khi người dùng bật "Ghi lại các request API"; app nối vào file JSON-lines
// trong thư mục Caches (tối đa ~40 MB, quá thì bỏ nửa cũ). API dữ liệu được lưu đủ phản hồi (tới 400 000 ký tự mỗi request);
// script/css/ảnh/font chỉ ghi một dòng. Mật khẩu/token đã được che từ phía trang. Xuất ra 3 dạng: text, json, tóm tắt endpoint.
enum NetLogStore {
    private static let q = DispatchQueue(label: "desm.netlog")
    private static let maxBytes = 40_000_000
    private static let staticPattern = #"\.(js|css|png|jpe?g|gif|svg|ico|woff2?|ttf|otf|map)$"#

    private static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("desm-netlog.jsonl")
    }

    static func append(_ obj: [String: Any]) {
        q.async {
            guard JSONSerialization.isValidJSONObject(obj), var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
            data.append(0x0A)
            let u = fileURL
            if let h = try? FileHandle(forWritingTo: u) {
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
                try? h.close()
                let size = ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.intValue ?? 0
                if size > maxBytes { trimHalf(u) }
            } else {
                try? data.write(to: u)
            }
        }
    }

    private static func trimHalf(_ u: URL) {
        guard let all = try? Data(contentsOf: u) else { return }
        guard let nl = all[(all.startIndex + all.count / 2)...].firstIndex(of: 0x0A) else { return }
        try? Data(all[(nl + 1)...]).write(to: u)
    }

    static func clear() {
        q.sync { try? FileManager.default.removeItem(at: fileURL) }
    }

    static func entries() -> [[String: Any]] {
        q.sync { () -> [[String: Any]] in
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            var out: [[String: Any]] = []
            for line in data.split(separator: 0x0A) {
                if let o = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] { out.append(o) }
            }
            return out
        }
    }

    private static func str(_ e: [String: Any], _ k: String) -> String { (e[k] as? String) ?? "" }
    private static func num(_ e: [String: Any], _ k: String) -> Int { (e[k] as? NSNumber)?.intValue ?? 0 }
    private static func cut(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n)) + "…[\(s.count) ký tự]" : s }

    static func exportText(_ es: [[String: Any]]) -> String {
        var parts: [String] = []
        for (i, e) in es.enumerated() {
            let body = str(e, "body"), resp = str(e, "resp")
            let bodyText = body.isEmpty ? "(rỗng)" : body
            let respText = resp.isEmpty ? "(rỗng)" : resp
            var s = "#\(i + 1) \(str(e, "t")) [\(str(e, "via"))] \(str(e, "method")) \(str(e, "url"))\n"
            s += "   màn hình: \(str(e, "page"))\n"
            s += "   body: \(bodyText)\n"
            s += "   -> HTTP \(num(e, "status")) (\(num(e, "ms")) ms) \(str(e, "ct")) \(num(e, "len")) ký tự\n"
            s += "   phản hồi: \(respText)"
            parts.append(s)
        }
        return parts.joined(separator: "\n\n")
    }

    static func exportJSON(_ es: [[String: Any]]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: es, options: [.withoutEscapingSlashes]) else { return "[]" }
        return String(decoding: d, as: UTF8.self)
    }

    /// Mô tả cấu trúc JSON phản hồi (tên trường), để biết app cần đọc trường nào.
    private static func shape(_ resp: String) -> String {
        guard let d = resp.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) else {
            return resp.isEmpty ? "(rỗng)" : "(không phải JSON hoặc bị cắt) " + cut(resp, 300)
        }
        func keys(_ o: Any) -> String {
            if let m = o as? [String: Any] { return "{" + m.keys.sorted().joined(separator: ", ") + "}" }
            return "\(type(of: o))"
        }
        if let m = j as? [String: Any] {
            var s = keys(m)
            for (k, v) in m.sorted(by: { $0.key < $1.key }) {
                if let a = v as? [Any] { s += "\n      \(k)[\(a.count)] mỗi phần tử: " + (a.first.map(keys) ?? "(trống)") }
            }
            return s
        }
        if let a = j as? [Any] { return "[\(a.count)] mỗi phần tử: " + (a.first.map(keys) ?? "(trống)") }
        return "\(type(of: j))"
    }

    static func exportSummary(_ es: [[String: Any]]) -> String {
        struct G {
            var method = "", name = ""
            var count = 0, totalMs = 0, maxLen = 0
            var statuses = Set<Int>(), pages = Set<String>()
            var query = "", body = "", resp = ""
        }
        var groups: [String: G] = [:]
        var order: [String] = []
        var staticCount = 0
        for e in es {
            let url = str(e, "url"), method = str(e, "method").uppercased()
            let comps = URLComponents(string: url)
            let path = comps?.path ?? url
            if str(e, "resp").isEmpty, path.range(of: staticPattern, options: [.regularExpression, .caseInsensitive]) != nil { staticCount += 1; continue }
            let name = (comps?.host ?? "") + path
            let key = method + " " + name
            if groups[key] == nil { groups[key] = G(method: method, name: name); order.append(key) }
            var g = groups[key]!
            g.count += 1; g.totalMs += num(e, "ms"); g.statuses.insert(num(e, "status"))
            let page = str(e, "page"); if !page.isEmpty { g.pages.insert(page) }
            if g.query.isEmpty, let q = comps?.query { g.query = q }
            if g.body.isEmpty { g.body = str(e, "body") }
            let len = num(e, "len")
            if len >= g.maxLen || g.resp.isEmpty { g.maxLen = len; g.resp = str(e, "resp") }
            groups[key] = g
        }
        var out = "TÓM TẮT API: \(order.count) endpoint (bỏ qua \(staticCount) tài nguyên tĩnh js/css/ảnh/font), \(es.count) request\n"
        for key in order {
            guard let g = groups[key] else { continue }
            out += "\n== \(g.method) \(g.name) ==\n"
            out += "  số lần gọi: \(g.count) | HTTP: \(g.statuses.sorted().map(String.init).joined(separator: ",")) | TB \(g.totalMs / max(g.count, 1)) ms | phản hồi lớn nhất: \(g.maxLen) ký tự\n"
            out += "  màn hình: \(g.pages.sorted().prefix(4).joined(separator: " ; "))\n"
            if !g.query.isEmpty { out += "  query mẫu: \(cut(g.query, 600))\n" }
            if !g.body.isEmpty { out += "  body mẫu: \(cut(g.body, 800))\n" }
            out += "  cấu trúc phản hồi: \(shape(g.resp))\n"
        }
        return out
    }
}


// MARK: - Tự lưu cấu trúc/HTML/CSS từng màn hình
//
// Mỗi màn hình (theo pathname, kể cả màn trong iframe) lưu một file JSON trong Caches/desm-snap/screens; mỗi file CSS lưu một file ở css/.
// Xuất gộp thành MỘT file văn bản: mục lục, rồi từng màn (cây cấu trúc + HTML), sau cùng toàn bộ CSS.
enum SnapStore {
    private static let q = DispatchQueue(label: "desm.snap")
    private static var dir: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("desm-snap") }
    private static var screensDir: URL { dir.appendingPathComponent("screens") }
    private static var cssDir: URL { dir.appendingPathComponent("css") }

    private static func safe(_ s: String) -> String {
        var r = ""
        for c in s.unicodeScalars { r.append(CharacterSet.alphanumerics.contains(c) || c == "." || c == "-" ? Character(c) : "_") }
        return String(r.prefix(120))
    }

    static func save(_ d: [String: Any]) {
        q.async {
            guard let path = d["path"] as? String else { return }
            let fm = FileManager.default
            try? fm.createDirectory(at: screensDir, withIntermediateDirectories: true)
            try? fm.createDirectory(at: cssDir, withIntermediateDirectories: true)
            var meta = d
            let files = (d["cssFiles"] as? [[String: Any]]) ?? []
            meta["cssFiles"] = nil
            for f in files {
                guard let url = f["url"] as? String, let text = f["text"] as? String else { continue }
                let p = URLComponents(string: url)?.path ?? url
                let st = (f["status"] as? NSNumber)?.intValue ?? 0
                try? "/* ===== \(url) (HTTP \(st), \(text.count) ký tự) ===== */\n\(text)\n".write(to: cssDir.appendingPathComponent(safe(p) + ".txt"), atomically: true, encoding: .utf8)
            }
            if JSONSerialization.isValidJSONObject(meta), let data = try? JSONSerialization.data(withJSONObject: meta) {
                try? data.write(to: screensDir.appendingPathComponent(safe(path) + ".json"))
            }
        }
    }

    static func clear() { q.sync { try? FileManager.default.removeItem(at: dir) } }

    private static func screenFiles() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: screensDir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func count() -> Int { q.sync { screenFiles().count } }

    static func export() -> String? {
        q.sync { () -> String? in
            let files = screenFiles()
            if files.isEmpty { return nil }
            var screens: [[String: Any]] = []
            for f in files {
                if let data = try? Data(contentsOf: f), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { screens.append(o) }
            }
            var out = "DESM — CẤU TRÚC, HTML VÀ CSS TỪNG MÀN HÌNH\n\nMỤC LỤC (\(screens.count) màn hình)\n"
            for (i, s) in screens.enumerated() {
                let html = (s["html"] as? String) ?? ""
                let css = ((s["cssLinks"] as? [String]) ?? []).map { URLComponents(string: $0)?.path ?? $0 }.joined(separator: ", ")
                out += "\(i + 1). \((s["path"] as? String) ?? "?")\((s["search"] as? String) ?? "")  | \((s["title"] as? String) ?? "")  | HTML \(html.count) ký tự | CSS: \(css.isEmpty ? "(không)" : css)\n"
            }
            for (i, s) in screens.enumerated() {
                out += "\n\n########## MÀN \(i + 1): \((s["path"] as? String) ?? "?")\((s["search"] as? String) ?? "") ##########\n"
                out += "Tiêu đề: \((s["title"] as? String) ?? "")  | Ghi lúc: \((s["t"] as? String) ?? "")  | \((s["top"] as? Bool) == true ? "trang chính" : "khung con (iframe)")\n"
                out += "\n--- CÂY CẤU TRÚC ---\n\((s["outline"] as? String) ?? "")\n"
                out += "\n--- HTML ---\n\((s["html"] as? String) ?? "")\n"
            }
            let cssFiles = ((try? FileManager.default.contentsOfDirectory(at: cssDir, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            out += "\n\n########## TOÀN BỘ CSS (\(cssFiles.count) file) ##########\n"
            for f in cssFiles { out += "\n" + ((try? String(contentsOf: f, encoding: .utf8)) ?? "") }
            return out
        }
    }
}


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

    private func finishShot(pdf: Data) {
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


// MARK: - Lịch sử tải lên Packing List (mục "Thêm")
//
// Tương ứng khung "Packing List Upload History (Last 3 days)" ở trang chủ DESM (home.do).
// Nguồn dữ liệu (theo nhật ký API 2026-10-28):
//   POST /getInitDefailProject.do                      -> results[0].SEGMENT1 = mã dự án mặc định (vd. T25026)
//   POST /dashboard/getHomeSummary.do  PROJECT_NO=..&DAY_TERM=3 -> results[] gồm INVOICE_NO, SHIPMENT_NO, ORGINAL_FILE,
//        RESULT (SUCCESSFUL / FILE FORMAT ERROR ...), CREATION_DATE, LAST_UPDATED_BY, PROJECT_NAME, ATT_ID
// Gọi bằng fetch trong trang DESM nên dùng sẵn phiên đăng nhập. CHƯA kiểm chứng: DAY_TERM khác 3 (1, 7) có được máy chủ chấp nhận không.

struct PackingUploadRecord: Identifiable, Hashable {
    let id: String
    let invoice: String
    let shipment: String
    let file: String
    let result: String
    let created: String
    let user: String
    let project: String
    let attId: String
    var isSuccess: Bool { result.uppercased() == "SUCCESSFUL" }
}

extension BrowserModel {
    func fetchPackingHistory(days: Int, done: @escaping ([PackingUploadRecord]?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang DESM để lấy dữ liệu."); return }
        let js = #"""
        if (!/(^|\.)doosanenerbility\.com$/i.test(location.hostname)) return JSON.stringify({ err: 'Hãy mở DESM và đăng nhập trước.' });
        const H = { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest' };
        async function post(u, b) {
          const r = await fetch(u, { method: 'POST', credentials: 'include', cache: 'no-store', headers: H, body: b });
          const t = await r.text();
          try { return JSON.parse(t); } catch (e) { throw new Error('HTTP ' + r.status + ': phản hồi không phải JSON (có thể đã hết phiên)'); }
        }
        try {
          const pj = await post('/getInitDefailProject.do', '');
          const no = pj && Array.isArray(pj.results) && pj.results[0] && pj.results[0].SEGMENT1;
          if (!no) return JSON.stringify({ err: 'Chưa có dự án mặc định trong DESM.' });
          const s = await post('/dashboard/getHomeSummary.do', 'PROJECT_NO=' + encodeURIComponent(no) + '&DAY_TERM=' + days);
          if (!s || !Array.isArray(s.results)) return JSON.stringify({ err: 'Máy chủ trả về lỗi.' });
          return JSON.stringify({ list: s.results });
        } catch (e) { return JSON.stringify({ err: String(e && e.message || e) }); }
        """#
        webView.callAsyncJavaScript(js, arguments: ["days": days], in: nil, in: .page) { result in
            switch result {
            case .failure(let e):
                done(nil, "Không tải được: \(e.localizedDescription)")
            case .success(let v):
                guard let text = v as? String, let data = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    done(nil, "Không đọc được phản hồi."); return
                }
                if let err = obj["err"] as? String { done(nil, err); return }
                let rows = obj["list"] as? [[String: Any]] ?? []
                func str(_ r: [String: Any], _ k: String) -> String {
                    if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if let n = r[k] as? NSNumber { return n.stringValue }
                    return ""
                }
                var seen = Set<String>()
                var out: [PackingUploadRecord] = []
                for (i, r) in rows.enumerated() {
                    let att = str(r, "ATT_ID")
                    let key = att.isEmpty ? "row\(i)" : att
                    if !seen.insert(key).inserted { continue }
                    out.append(PackingUploadRecord(
                        id: key, invoice: str(r, "INVOICE_NO"), shipment: str(r, "SHIPMENT_NO"),
                        file: str(r, "ORGINAL_FILE"), result: str(r, "RESULT"),
                        created: str(r, "CREATION_DATE"), user: str(r, "LAST_UPDATED_BY"),
                        project: str(r, "PROJECT_NAME"), attId: att))
                }
                out.sort { $0.created > $1.created }   // "yyyy/MM/dd HH:mm" so sánh chuỗi được
                done(out, "")
            }
        }
    }
}

extension BrowserModel {
    /// Mở màn Kiện hàng và lọc theo Packing List No (bấm một dòng trong Lịch sử Packing List).
    func openPackingList(_ pl: String) {
        guard let d = try? JSONSerialization.data(withJSONObject: ["pl": pl]),
              let js = String(data: d, encoding: .utf8) else { return }
        showToast("Đang mở kiện của \(pl)…")
        webView?.evaluateJavaScript("window.__desmFindPackingList ? window.__desmFindPackingList(\(js)) : 0;", completionHandler: nil)
    }

    /// Tải file xlsx đã upload (theo ATT_ID) bằng phiên đăng nhập của trang, lưu vào thư mục tạm. `done(url, lỗi)`.
    /// CHƯA kiểm chứng: địa chỉ tải của DESM. Script tự dò địa chỉ chứa "download" trong home.do và các script của nó,
    /// rồi thử thêm vài địa chỉ phổ biến; chỉ nhận phản hồi là file (không phải HTML/JSON). Lỗi thì liệt kê các địa chỉ đã thử.
    func downloadPackingFile(attId: String, fileName: String, done: @escaping (URL?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang DESM để tải."); return }
        let js = #"""
        if (!/(^|\.)doosanenerbility\.com$/i.test(location.hostname)) return JSON.stringify({ err: 'Hãy mở DESM và đăng nhập trước.' });
        const tried = [];
        const urls = [];
        function add(u) { u = String(u || '').split('?')[0]; if (u && urls.indexOf(u) < 0) urls.push(u); }
        try {
          const html = await (await fetch('/home.do', { credentials: 'include', cache: 'no-store' })).text();
          const found = (t) => { for (const m of t.matchAll(/["']([^"'\s]*download[^"'\s]*?\.do)(?:\?[^"'\s]*)?["']/gi)) add(m[1].charAt(0) === '/' ? m[1] : '/' + m[1]); };
          found(html);
          const srcs = [];
          for (const m of html.matchAll(/<script[^>]+src=["']([^"']+)["']/gi)) {
            const u = m[1];
            if (/^(https?:)?\/\//i.test(u) && u.indexOf(location.host) < 0) continue;
            if (/jquery|bootstrap|fontawesome|datatables|chart|moment|popper|treegrid|GridE/i.test(u)) continue;
            srcs.push(u);
          }
          for (const u of srcs.slice(0, 12)) {
            try { found(await (await fetch(u, { credentials: 'include' })).text()); } catch (e) {}
          }
        } catch (e) {}
        ['/fileDownload.do', '/common/fileDownload.do', '/downloadFile.do', '/common/downloadFile.do', '/attachFileDownload.do', '/fileDown.do'].forEach(add);
        const names = ['ATT_ID', 'attId'];
        for (const u of urls.slice(0, 14)) {
          for (const n of names) {
            const full = u + '?' + n + '=' + encodeURIComponent(att);
            try {
              const r = await fetch(full, { credentials: 'include', cache: 'no-store' });
              const ct = (r.headers.get('content-type') || '').toLowerCase();
              if (!r.ok) { tried.push(u + ' ' + r.status); continue; }
              const buf = new Uint8Array(await r.arrayBuffer());
              const zip = buf.length > 3 && buf[0] === 0x50 && buf[1] === 0x4B;
              if (!zip && (/text\/html|json|text\/plain/.test(ct) || buf.length < 100)) { tried.push(u + ' không phải file'); continue; }
              let bin = '';
              for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000));
              return JSON.stringify({ b64: btoa(bin) });
            } catch (e) { tried.push(u + ' lỗi'); }
          }
        }
        return JSON.stringify({ err: 'Không tìm được địa chỉ tải file. Đã thử: ' + (tried.slice(0, 6).join('; ') || 'không có') });
        """#
        webView.callAsyncJavaScript(js, arguments: ["att": attId], in: nil, in: .page) { result in
            switch result {
            case .failure(let e):
                done(nil, "Không tải được: \(e.localizedDescription)")
            case .success(let v):
                guard let text = v as? String, let data = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    done(nil, "Không đọc được phản hồi."); return
                }
                if let err = obj["err"] as? String { done(nil, err); return }
                guard let b64 = obj["b64"] as? String, let bytes = Data(base64Encoded: b64), !bytes.isEmpty else {
                    done(nil, "File tải về rỗng."); return
                }
                var name = fileName.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { name = "packing-list-\(attId)" }
                if (name as NSString).pathExtension.isEmpty { name += ".xlsx" }
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("desm-packing-\(UUID().uuidString)", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(name)
                    try bytes.write(to: url)
                    done(url, "")
                } catch { done(nil, "Không lưu được file: \(error.localizedDescription)") }
            }
        }
    }
}

struct PackingHistorySheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void
    var onOpen: (String) -> Void = { _ in }

    @State private var days = 3
    @State private var records: [PackingUploadRecord] = []
    @State private var loading = false
    @State private var error: String? = nil
    @State private var downloadingID: String? = nil
    @State private var shareItem: ShareItem? = nil
    @State private var downloadError: String? = nil

    private func download(_ r: PackingUploadRecord) {
        guard downloadingID == nil, !r.attId.isEmpty else { return }
        downloadingID = r.id
        model.downloadPackingFile(attId: r.attId, fileName: r.file) { url, err in
            downloadingID = nil
            if let url = url { shareItem = ShareItem(url: url) } else { downloadError = err }
        }
    }

    private func load() {
        loading = true; error = nil
        model.fetchPackingHistory(days: days) { list, err in
            loading = false
            if let list = list { records = list } else { records = []; error = err }
        }
    }

    private func badge(_ r: PackingUploadRecord) -> some View {
        Text(r.result.isEmpty ? "—" : r.result)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(r.isSuccess ? Color.green : Color.red)
            .background((r.isSuccess ? Color.green : Color.red).opacity(0.12), in: Capsule())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Khoảng ngày", selection: $days) {
                    Text("1 ngày").tag(1)
                    Text("3 ngày").tag(3)
                    Text("7 ngày").tag(7)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .onChange(of: days) { _ in load() }

                if loading && records.isEmpty {
                    Spacer(); ProgressView("Đang tải…"); Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(.orange)
                        Text(error).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Thử lại") { load() }.buttonStyle(.borderedProminent)
                    }.padding(24)
                    Spacer()
                } else if records.isEmpty {
                    Spacer()
                    Text("Không có lượt tải lên nào trong \(days) ngày gần đây.").font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    List(records) { r in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(r.invoice.isEmpty ? "(không có Invoice)" : r.invoice)
                                    .font(.system(size: 15, weight: .bold))
                                Spacer(minLength: 6)
                                badge(r)
                            }
                            if !r.file.isEmpty || !r.attId.isEmpty {
                                HStack(alignment: .center, spacing: 8) {
                                    Label(r.file.isEmpty ? "Tệp Packing List" : r.file, systemImage: "doc.text").font(.system(size: 13))
                                        .foregroundStyle(.primary).lineLimit(2)
                                    Spacer(minLength: 6)
                                    if !r.attId.isEmpty {
                                        Button { download(r) } label: {
                                            if downloadingID == r.id {
                                                ProgressView().frame(width: 32, height: 32)
                                            } else {
                                                Image(systemName: "arrow.down.circle")
                                                    .font(.system(size: 22)).frame(width: 32, height: 32)
                                            }
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(downloadingID != nil)
                                        .accessibilityLabel("Tải file xlsx")
                                    }
                                }
                            }
                            HStack(spacing: 10) {
                                if !r.shipment.isEmpty { Text("Shipment \(r.shipment)") }
                                if !r.created.isEmpty { Text(r.created) }
                                if !r.user.isEmpty { Text(r.user).lineLimit(1) }
                            }
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture { if !r.invoice.isEmpty { onOpen(r.invoice) } }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lịch sử Packing List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
        }
        .onAppear { if records.isEmpty && !loading { load() } }
        .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
        .desmAlert(isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } }),
                   icon: "exclamationmark.triangle.fill", title: "Không tải được file", message: downloadError,
                   actions: [DesmDialogAction(title: "OK", kind: .primary)])
    }
}


// MARK: - RSI chưa đóng / vừa đóng và MRF trả hàng (mục "Thêm")
//
// Nguồn dữ liệu (nhật ký API 2026-10-28), tất cả POST, dùng phiên đăng nhập của trang:
//   RSI Summary   /getDesmRsiViewList.do   (STATUS, REQ_QTY, HANDOVER_QTY, BALANCE_QTY, REQUEST_DATE, RSI_APPROVED_DATE)
//   Outgoing      /getDesmRsiOutGoingList.do (HANDOVER_DATE, HANDOVER_QTY)
//   MRF Summary   /getMrfSummaryList.do    (STATUS, MRF_REQ_RETURN_QTY, MRF_RETURN_QTY, MRF_BALANCE_QTY, RETURN_REQ_DATE)
//   Return Control /getDesmMrfReturnList.do (RETURN_DATE, RETURN_QTY)
// QUY ƯỚC (suy từ dữ liệu, CHƯA xác nhận với nghiệp vụ DESM): "chưa đóng" = tổng số lượng còn lại (BALANCE_QTY / MRF_BALANCE_QTY) > 0;
// "vừa đóng" = có bàn giao / trả hàng trong N ngày gần đây và không còn số lượng còn lại. Chưa biết hết các giá trị STATUS.
// CHƯA kiểm chứng: máy chủ lọc đúng theo START/END_*_DATE khi để trống số phiếu (đã lọc thêm phía máy khách để an toàn).

enum DesmDocKind: String, Identifiable {
    case rsi, mrf
    var id: String { rawValue }
    var title: String { self == .rsi ? "RSI" : "MRF trả hàng" }
    var noun: String { self == .rsi ? "xuất" : "trả" }
}

struct DesmDocGroup: Identifiable, Hashable {
    let id: String
    var name = ""
    var date = ""
    var closeDate = ""
    var status = ""
    var extra = ""
    var lines = 0
    var qty = 0.0
    var done = 0.0
    var balance: Double? = nil
}

extension BrowserModel {
    /// POST một endpoint .do bằng phiên đăng nhập hiện có; trả mảng dòng (results hoặc results.list).
    func desmQuery(_ path: String, body: String, done: @escaping ([[String: Any]]?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang DESM để lấy dữ liệu."); return }
        let js = #"""
        if (!/(^|\.)doosanenerbility\.com$/i.test(location.hostname)) return JSON.stringify({ err: 'Hãy mở DESM và đăng nhập trước.' });
        try {
          const r = await fetch(path, { method: 'POST', credentials: 'include', cache: 'no-store',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest' }, body: body });
          const t = await r.text(); let s;
          try { s = JSON.parse(t); } catch (e) { return JSON.stringify({ err: 'HTTP ' + r.status + ': phản hồi không phải JSON (có thể đã hết phiên)' }); }
          const x = s && s.results;
          const list = Array.isArray(x) ? x : (x && Array.isArray(x.list) ? x.list : null);
          if (!list) return JSON.stringify({ err: 'Máy chủ trả về lỗi.' });
          return JSON.stringify({ list: list });
        } catch (e) { return JSON.stringify({ err: String(e && e.message || e) }); }
        """#
        webView.callAsyncJavaScript(js, arguments: ["path": path, "body": body], in: nil, in: .page) { result in
            switch result {
            case .failure(let e): done(nil, "Không tải được: \(e.localizedDescription)")
            case .success(let v):
                guard let text = v as? String, let data = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { done(nil, "Không đọc được phản hồi."); return }
                if let err = obj["err"] as? String { done(nil, err); return }
                done(obj["list"] as? [[String: Any]] ?? [], "")
            }
        }
    }

    private static func fstr(_ r: [String: Any], _ k: String) -> String {
        if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = r[k] as? NSNumber { return n.stringValue }
        return ""
    }
    private static func fnum(_ r: [String: Any], _ k: String) -> Double {
        if let n = r[k] as? NSNumber { return n.doubleValue }
        if let s = r[k] as? String { return Double(s) ?? 0 }
        return 0
    }
    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
    }

    /// Gộp các dòng thành từng phiếu (theo số phiếu).
    private static func groups(_ rows: [[String: Any]], doc: String, name: String, date: String, status: String, extra: String,
                               qty: String, done: String, bal: String?, close: String?) -> [DesmDocGroup] {
        var order: [String] = []; var map: [String: DesmDocGroup] = [:]
        for r in rows {
            let id = fstr(r, doc); if id.isEmpty { continue }
            var g: DesmDocGroup
            if let ex = map[id] { g = ex } else { g = DesmDocGroup(id: id); order.append(id) }
            g.lines += 1
            if g.name.isEmpty { g.name = fstr(r, name) }
            if g.date.isEmpty { g.date = fstr(r, date) }
            if g.status.isEmpty { g.status = fstr(r, status) }
            if g.extra.isEmpty { g.extra = fstr(r, extra) }
            g.qty += fnum(r, qty); g.done += fnum(r, done)
            if let b = bal { g.balance = (g.balance ?? 0) + fnum(r, b) }
            if let c = close { let v = fstr(r, c); if v > g.closeDate { g.closeDate = v } }
            map[id] = g
        }
        return order.compactMap { map[$0] }
    }

    /// open = còn số lượng chưa xử lý (mới nhất trước); closed = vừa bàn giao/trả trong `days` ngày và không còn số lượng còn lại.
    func fetchDocs(kind: DesmDocKind, days: Int, done: @escaping ([DesmDocGroup], [DesmDocGroup], String) -> Void) {
        desmQuery("/getInitDefailProject.do", body: "") { rows, err in
            guard let rows = rows else { done([], [], err); return }
            guard let no = rows.first?["SEGMENT1"] as? String, !no.isEmpty else { done([], [], "Chưa có dự án mặc định trong DESM."); return }
            let P = Self.enc(no)
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
            let cal = Calendar.current; let now = Date()
            let today = f.string(from: now)
            let cutoff = f.string(from: cal.date(byAdding: .day, value: -days, to: now) ?? now)
            let openFrom = f.string(from: cal.date(byAdding: .day, value: -180, to: now) ?? now)
            func d(_ s: String) -> String { Self.enc(s) }

            let pathA: String, bodyA: String, pathB: String, bodyB: String
            switch kind {
            case .rsi:
                pathA = "/getDesmRsiViewList.do"
                bodyA = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&ATTRIBUTE10=&MATERIAL_CODE=&START_REQUEST_DATE=\(d(openFrom))&END_REQUEST_DATE=\(d(today))&BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&PACKAGE_NO=&ITEM_DESC=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
                pathB = "/getDesmRsiOutGoingList.do"
                bodyB = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&START_HANDOVER_DATE=\(d(cutoff))&END_HANDOVER_DATE=\(d(today))&PACKAGE_NO=&SUBCONTRACTOR=&RSI_NO=&MATERIAL_CODE=&ATTRIBUTE10=&RSI_NAME=&TYPE=&CATEGORY=&SUB_CATEGORY=&COMMENTS=&PACKING_LIST_NO=&PENDING=&RECEIVER_REMARK=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
            case .mrf:
                pathA = "/getMrfSummaryList.do"
                bodyA = "PROJECT_NO=\(P)&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&MATERIAL_CODE=&RSI_START_REQUEST_DATE=&RSI_END_REQUEST_DATE=&ZIM_ATTRIBUTE10=&RSI_BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&MRF_NO=&MRF_NAME=&PACKAGE_NO=&ITEM_DESC=&RETURN_TYPE=&MRF_BALANCE_QTY="
                pathB = "/getDesmMrfReturnList.do"
                bodyB = "PROJECT_NO=\(P)&START_HANDOVER_DATE=\(d(cutoff))&END_HANDOVER_DATE=\(d(today))&PACKAGE_NO=&SUBCONTRACTOR=&MRF_NO=&MATERIAL_CODE=&ATTRIBUTE10=&MRF_NAME=&TYPE=&CATEGORY="
            }
            self.desmQuery(pathA, body: bodyA) { rowsA, errA in
                guard let rowsA = rowsA else { done([], [], errA); return }
                self.desmQuery(pathB, body: bodyB) { rowsB, errB in
                    guard let rowsB = rowsB else { done([], [], errB); return }
                    let a: [DesmDocGroup], b: [DesmDocGroup]
                    switch kind {
                    case .rsi:
                        a = Self.groups(rowsA, doc: "RSI_NO", name: "RSI_NAME", date: "REQUEST_DATE", status: "STATUS", extra: "SUBCONTRACTOR",
                                        qty: "REQ_QTY", done: "HANDOVER_QTY", bal: "BALANCE_QTY", close: nil)
                        b = Self.groups(rowsB, doc: "RSI_NO", name: "RSI_NAME", date: "REQUEST_DATE", status: "", extra: "SUBCONTRACTOR",
                                        qty: "REQ_QTY", done: "HANDOVER_QTY", bal: nil, close: "HANDOVER_DATE")
                    case .mrf:
                        a = Self.groups(rowsA, doc: "MRF_NO", name: "MRF_NAME", date: "RETURN_REQ_DATE", status: "STATUS", extra: "RETURN_TYPE",
                                        qty: "MRF_REQ_RETURN_QTY", done: "MRF_RETURN_QTY", bal: "MRF_BALANCE_QTY", close: nil)
                        b = Self.groups(rowsB, doc: "MRF_NO", name: "MRF_NAME", date: "RETURN_REQ_DATE", status: "", extra: "RETURN_TYPE",
                                        qty: "REQ_RETURN_QTY", done: "RETURN_QTY", bal: nil, close: "RETURN_DATE")
                    }
                    let open = a.filter { ($0.balance ?? 0) > 0 }.sorted { $0.date > $1.date }
                    let byId = Dictionary(a.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
                    var closed: [DesmDocGroup] = []
                    for var g in b where g.closeDate >= cutoff {
                        if let m = byId[g.id] {
                            if (m.balance ?? 0) > 0 { continue }   // còn số lượng chưa xử lý: thuộc nhóm "chưa đóng"
                            g.balance = m.balance; g.status = m.status
                        }
                        closed.append(g)
                    }
                    closed.sort { $0.closeDate > $1.closeDate }
                    done(open, closed, "")
                }
            }
        }
    }
}

struct DesmDocSheet: View {
    @ObservedObject var model: BrowserModel
    let kind: DesmDocKind
    var onClose: () -> Void

    @State private var tab = 0
    @State private var days = 7
    @State private var openList: [DesmDocGroup] = []
    @State private var closedList: [DesmDocGroup] = []
    @State private var loading = false
    @State private var error: String? = nil

    private func load() {
        loading = true; error = nil
        model.fetchDocs(kind: kind, days: days) { o, c, err in
            loading = false
            if err.isEmpty { openList = o; closedList = c } else { openList = []; closedList = []; error = err }
        }
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }

    private var current: [DesmDocGroup] { tab == 0 ? openList : closedList }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Nhóm", selection: $tab) {
                    Text("Chưa đóng (\(openList.count))").tag(0)
                    Text("Vừa đóng (\(closedList.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 10)
                if tab == 1 {
                    Picker("Trong", selection: $days) {
                        Text("1 ngày").tag(1); Text("3 ngày").tag(3); Text("7 ngày").tag(7); Text("30 ngày").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16).padding(.top, 8)
                    .onChange(of: days) { _ in load() }
                }
                Spacer().frame(height: 8)

                if loading && current.isEmpty && error == nil {
                    Spacer(); ProgressView("Đang tải…"); Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(.orange)
                        Text(error).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Thử lại") { load() }.buttonStyle(.borderedProminent)
                    }.padding(24)
                    Spacer()
                } else if current.isEmpty {
                    Spacer()
                    Text(tab == 0 ? "Không có \(kind.title) nào còn chưa đóng."
                                  : "Không có \(kind.title) nào vừa đóng trong \(days) ngày gần đây.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    List(current) { g in
                        NavigationLink {
                            DesmDocDetailView(model: model, kind: kind, group: g)
                        } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(g.id).font(.system(size: 15, weight: .bold))
                                Spacer(minLength: 6)
                                if !g.status.isEmpty {
                                    Text(g.status).font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .foregroundStyle(Color.tabBlue)
                                        .background(Color.tabBlue.opacity(0.12), in: Capsule())
                                }
                            }
                            if !g.name.isEmpty { Text(g.name).font(.system(size: 13)).lineLimit(2) }
                            HStack(spacing: 10) {
                                Text("\(g.lines) dòng")
                                Text("Đã \(kind.noun) \(fmt(g.done))/\(fmt(g.qty))")
                                if let b = g.balance { Text("còn \(fmt(b))").foregroundStyle(b > 0 ? Color.red : Color.green) }
                            }.font(.system(size: 12, weight: .medium))
                            HStack(spacing: 10) {
                                if !g.date.isEmpty { Text("Yêu cầu \(g.date)") }
                                if !g.closeDate.isEmpty { Text("Đóng \(g.closeDate)") }
                                if !g.extra.isEmpty { Text(g.extra).lineLimit(1) }
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(kind == .rsi ? "RSI" : "MRF trả hàng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
        }
        .onAppear { if openList.isEmpty && closedList.isEmpty && !loading { load() } }
    }
}


// MARK: - Chi tiết một phiếu RSI / MRF
//
// Tải lại theo số phiếu (đúng như log: RSI_NO / MRF_NO, không giới hạn ngày) rồi ghép:
//   RSI: getDesmRsiViewList (dòng yêu cầu, tồn) + getDesmRsiOutGoingList (ngày bàn giao), ghép theo Package No + Material Code.
//   MRF: getMrfSummaryList (dòng trả, tồn) + getDesmMrfReturnList (ngày trả), ghép theo MRF_LINE_ID.

struct DesmDocLine: Identifiable {
    let id: Int
    var code = "", desc = "", pkg = "", list = "", loc = "", unit = "", date = "", note = ""
    var req = 0.0, done = 0.0
    var bal: Double? = nil
}

struct DesmDocDetail {
    var header: [(String, String)] = []
    var lines: [DesmDocLine] = []
}

extension BrowserModel {
    private static func dstr(_ r: [String: Any], _ k: String) -> String {
        if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = r[k] as? NSNumber { return n.stringValue }
        return ""
    }
    private static func dnum(_ r: [String: Any], _ k: String) -> Double {
        if let n = r[k] as? NSNumber { return n.doubleValue }
        if let s = r[k] as? String { return Double(s) ?? 0 }
        return 0
    }

    func fetchDocDetail(kind: DesmDocKind, no: String, done: @escaping (DesmDocDetail?, String) -> Void) {
        desmQuery("/getInitDefailProject.do", body: "") { rows, err in
            guard let rows = rows else { done(nil, err); return }
            guard let pj = rows.first?["SEGMENT1"] as? String, !pj.isEmpty else { done(nil, "Chưa có dự án mặc định trong DESM."); return }
            func e(_ s: String) -> String {
                s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
            }
            let P = e(pj), N = e(no)
            let pathA: String, bodyA: String, pathB: String, bodyB: String
            switch kind {
            case .rsi:
                pathA = "/getDesmRsiViewList.do"
                bodyA = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&RSI_NO=\(N)&RSI_NAME=&SUBCONTRACTOR=&ATTRIBUTE10=&MATERIAL_CODE=&START_REQUEST_DATE=&END_REQUEST_DATE=&BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&PACKAGE_NO=&ITEM_DESC=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
                pathB = "/getDesmRsiOutGoingList.do"
                bodyB = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&START_HANDOVER_DATE=&END_HANDOVER_DATE=&PACKAGE_NO=&SUBCONTRACTOR=&RSI_NO=\(N)&MATERIAL_CODE=&ATTRIBUTE10=&RSI_NAME=&TYPE=&CATEGORY=&SUB_CATEGORY=&COMMENTS=&PACKING_LIST_NO=&PENDING=&RECEIVER_REMARK=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
            case .mrf:
                pathA = "/getMrfSummaryList.do"
                bodyA = "PROJECT_NO=\(P)&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&MATERIAL_CODE=&RSI_START_REQUEST_DATE=&RSI_END_REQUEST_DATE=&ZIM_ATTRIBUTE10=&RSI_BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&MRF_NO=\(N)&MRF_NAME=&PACKAGE_NO=&ITEM_DESC=&RETURN_TYPE=&MRF_BALANCE_QTY="
                pathB = "/getDesmMrfReturnList.do"
                bodyB = "PROJECT_NO=\(P)&START_HANDOVER_DATE=&END_HANDOVER_DATE=&PACKAGE_NO=&SUBCONTRACTOR=&MRF_NO=\(N)&MATERIAL_CODE=&ATTRIBUTE10=&MRF_NAME=&TYPE=&CATEGORY="
            }
            self.desmQuery(pathA, body: bodyA) { rowsA, errA in
                guard let rowsA = rowsA else { done(nil, errA); return }
                self.desmQuery(pathB, body: bodyB) { rowsB, _ in
                    let rowsB = rowsB ?? []   // thiếu ngày bàn giao/trả thì vẫn hiện dòng
                    func s(_ r: [String: Any], _ k: String) -> String { Self.dstr(r, k) }
                    func n(_ r: [String: Any], _ k: String) -> Double { Self.dnum(r, k) }
                    var detail = DesmDocDetail()
                    switch kind {
                    case .rsi:
                        var dates: [String: String] = [:]
                        for r in rowsB {
                            let k = s(r, "PACKAGE_NO") + "|" + s(r, "MATERIAL_CODE"); let d = s(r, "HANDOVER_DATE")
                            if d > (dates[k] ?? "") { dates[k] = d }
                        }
                        let src = rowsA.isEmpty ? rowsB : rowsA
                        if let r = src.first {
                            detail.header = [("Tên phiếu", s(r, "RSI_NAME")), ("Trạng thái", s(r, "STATUS")), ("Đơn vị", s(r, "SUBCONTRACTOR")),
                                             ("Ngày yêu cầu", s(r, "REQUEST_DATE")), ("Ngày duyệt", s(r, "RSI_APPROVED_DATE"))]
                        }
                        for (i, r) in src.enumerated() {
                            let k = s(r, "PACKAGE_NO") + "|" + s(r, "MATERIAL_CODE")
                            var l = DesmDocLine(id: i)
                            l.code = s(r, "MATERIAL_CODE"); l.desc = s(r, "DESCRIPTION"); l.pkg = s(r, "PACKAGE_NO")
                            l.list = s(r, "INVOICE_NUM").isEmpty ? s(r, "PACKING_LIST_NO") : s(r, "INVOICE_NUM")
                            l.loc = s(r, "LOCATION"); l.unit = s(r, "UNIT"); l.note = s(r, "COMMENTS")
                            l.req = n(r, "REQ_QTY"); l.done = n(r, "HANDOVER_QTY")
                            if r["BALANCE_QTY"] != nil { l.bal = n(r, "BALANCE_QTY") }
                            l.date = dates[k] ?? s(r, "HANDOVER_DATE")
                            detail.lines.append(l)
                        }
                    case .mrf:
                        var dates: [String: String] = [:]
                        for r in rowsB {
                            let k = s(r, "MRF_LINE_ID"); let d = s(r, "RETURN_DATE")
                            if d > (dates[k] ?? "") { dates[k] = d }
                        }
                        let src = rowsA.isEmpty ? rowsB : rowsA
                        if let r = src.first {
                            detail.header = [("Tên phiếu", s(r, "MRF_NAME")), ("Trạng thái", s(r, "STATUS")), ("Loại trả", s(r, "RETURN_TYPE")),
                                             ("RSI gốc", s(r, "RSI_NO")), ("Đơn vị", s(r, "SUBCONTRACTOR")),
                                             ("Ngày yêu cầu trả", s(r, "RETURN_REQ_DATE")), ("Ngày duyệt", s(r, "APPROVED_DATE"))]
                        }
                        for (i, r) in src.enumerated() {
                            var l = DesmDocLine(id: i)
                            l.code = s(r, "MATERIAL_CODE"); l.desc = s(r, "DESCRIPTION"); l.pkg = s(r, "PACKAGE_NO")
                            l.list = s(r, "PACKAGE_LIST_NO"); l.loc = s(r, "LOCATION"); l.unit = s(r, "UNIT"); l.note = s(r, "COMMENTS")
                            let hasA = r["MRF_REQ_RETURN_QTY"] != nil
                            l.req = n(r, hasA ? "MRF_REQ_RETURN_QTY" : "REQ_RETURN_QTY")
                            l.done = n(r, hasA ? "MRF_RETURN_QTY" : "RETURN_QTY")
                            if r["MRF_BALANCE_QTY"] != nil { l.bal = n(r, "MRF_BALANCE_QTY") }
                            l.date = dates[s(r, "MRF_LINE_ID")] ?? s(r, "RETURN_DATE")
                            detail.lines.append(l)
                        }
                    }
                    detail.header = detail.header.filter { !$0.1.isEmpty }
                    done(detail, "")
                }
            }
        }
    }
}

struct DesmDocDetailView: View {
    @ObservedObject var model: BrowserModel
    let kind: DesmDocKind
    let group: DesmDocGroup

    @State private var detail: DesmDocDetail? = nil
    @State private var loading = false
    @State private var error: String? = nil

    private func load() {
        loading = true; error = nil
        model.fetchDocDetail(kind: kind, no: group.id) { d, err in
            loading = false
            if let d = d { detail = d } else { error = err }
        }
    }
    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }

    var body: some View {
        Group {
            if let error = error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(.orange)
                    Text(error).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Thử lại") { load() }.buttonStyle(.borderedProminent)
                }.padding(24)
            } else if let d = detail {
                List {
                    Section {
                        ForEach(Array(d.header.enumerated()), id: \.offset) { _, kv in
                            HStack(alignment: .firstTextBaseline) {
                                Text(kv.0).font(.system(size: 13)).foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text(kv.1).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    Section("\(d.lines.count) dòng hàng") {
                        ForEach(d.lines) { l in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(l.code.isEmpty ? "(không có mã)" : l.code).font(.system(size: 14, weight: .bold))
                                if !l.desc.isEmpty { Text(l.desc).font(.system(size: 13)).lineLimit(3) }
                                HStack(spacing: 10) {
                                    Text("\(kind == .rsi ? "Yêu cầu" : "Cần trả") \(fmt(l.req))\(l.unit.isEmpty ? "" : " " + l.unit)")
                                    Text("Đã \(kind.noun) \(fmt(l.done))")
                                    if let b = l.bal { Text("còn \(fmt(b))").foregroundStyle(b > 0 ? Color.red : Color.green) }
                                }.font(.system(size: 12, weight: .medium))
                                if !l.pkg.isEmpty { Label(l.pkg, systemImage: "shippingbox").font(.system(size: 12)) }
                                HStack(spacing: 10) {
                                    if !l.list.isEmpty { Text(l.list) }
                                    if !l.loc.isEmpty { Text(l.loc) }
                                    if !l.date.isEmpty { Text("\(kind == .rsi ? "Bàn giao" : "Trả") \(l.date)") }
                                }.font(.system(size: 11)).foregroundStyle(.secondary)
                                if !l.note.isEmpty { Text(l.note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3) }
                            }.padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ProgressView("Đang tải…")
            }
        }
        .navigationTitle(group.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
            }
        }
        .onAppear { if detail == nil && !loading { load() } }
    }
}


// MARK: - Tab "Xuất kho": tìm RSI, tích chọn dòng, xuất kho (đóng) từng dòng hoặc tất cả
//
// Làm theo web DESM (script đã gửi 2026-10-28):
//   Tìm dòng còn xuất được: POST /getDesmOutGoingCreationList.do  (popup "Creation" của Outgoing Control, menu 376)
//   Lưu xuất kho:           POST /saveDesmRsiOutSave.do  với updateList = JSON [{RSI_HEADER_ID, RSI_LINE_ID, HANDOVER_DATE "yyyy/MM/dd",
//                            HANDOVER_QTY, MATERIAL_CODE, PROJECT_NO, RECEIVER_NAME}]
//   Phản hồi: result.error == null là thành công; error == "QTY" kèm RSI_LINE_ID + HANDOVER_AVAILABLE_QTY là vượt số lượng; còn lại là thông báo lỗi.
// CHƯA kiểm chứng: tên các trường trả về của getDesmOutGoingCreationList (suy từ cột lưới trong script; log mới chỉ có kết quả rỗng),
// và máy chủ có đòi thêm gì ngoài các tham số trên cho lệnh lưu (ajaxSetup.js chưa xem). Đây là thao tác GHI lên DESM thật.

private func desmFormEnc(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
}

extension BrowserModel {
    /// POST updateList (chuỗi JSON) tới một endpoint lưu của DESM. Trả về phần JSON phản hồi.
    func desmWrite(_ path: String, updateList: String, done: @escaping (Any?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang DESM để gửi lệnh."); return }
        let js = #"""
        if (!/(^|\.)doosanenerbility\.com$/i.test(location.hostname)) return JSON.stringify({ err: 'Hãy mở DESM và đăng nhập trước.' });
        try {
          const r = await fetch(path, { method: 'POST', credentials: 'include', cache: 'no-store',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest' },
            body: 'updateList=' + encodeURIComponent(updateList) });
          const t = await r.text(); let s;
          try { s = JSON.parse(t); } catch (e) { return JSON.stringify({ err: 'HTTP ' + r.status + ': phản hồi không phải JSON. Hãy kiểm tra trên web xem đã lưu chưa trước khi thử lại.' }); }
          return JSON.stringify({ res: s });
        } catch (e) { return JSON.stringify({ err: String(e && e.message || e) }); }
        """#
        webView.callAsyncJavaScript(js, arguments: ["path": path, "updateList": updateList], in: nil, in: .page) { result in
            switch result {
            case .failure(let e): done(nil, "Không gửi được: \(e.localizedDescription)")
            case .success(let v):
                guard let text = v as? String, let data = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { done(nil, "Không đọc được phản hồi. Hãy kiểm tra trên web trước khi thử lại."); return }
                if let err = obj["err"] as? String { done(nil, err); return }
                done(obj["res"] ?? [String: Any](), "")
            }
        }
    }
}

struct DesmOutLine: Identifiable {
    let id: String
    var rsiNo = "", rsiName = "", subcon = "", reqDate = "", pkg = "", plist = "", desc = "", code = "", pending = "", project = ""
    var req = 0.0, avail = 0.0
    var headerId: Any = NSNull()
    var lineId: Any = NSNull()
    var valid = true
}

final class DesmOutgoingVM: ObservableObject {
    @Published var rsiNo = ""
    @Published var rsiName = ""
    @Published var pkg = ""
    @Published var code = ""
    @Published var lines: [DesmOutLine] = []
    @Published var selected = Set<String>()
    @Published var qty: [String: String] = [:]
    @Published var date = Date()
    @Published var receiver = ""
    @Published var loading = false
    @Published var saving = false
    @Published var searched = false
    @Published var error: String? = nil
    @Published var notice: String? = nil
    private var project = ""

    var groups: [(String, [DesmOutLine])] {
        var order: [String] = []; var map: [String: [DesmOutLine]] = [:]
        for l in lines { if map[l.rsiNo] == nil { order.append(l.rsiNo) }; map[l.rsiNo, default: []].append(l) }
        return order.map { ($0, map[$0] ?? []) }
    }
    var allSelected: Bool { !lines.isEmpty && selected.count == lines.filter { $0.valid }.count }

    func reset() { rsiNo = ""; rsiName = ""; pkg = ""; code = "" }

    func toggle(_ l: DesmOutLine) {
        guard l.valid else { return }
        if selected.contains(l.id) { selected.remove(l.id) }
        else { selected.insert(l.id); if (qty[l.id] ?? "").isEmpty { qty[l.id] = Self.fmt(l.avail) } }
    }
    func setGroup(_ items: [DesmOutLine], on: Bool) {
        for l in items where l.valid {
            if on { selected.insert(l.id); if (qty[l.id] ?? "").isEmpty { qty[l.id] = Self.fmt(l.avail) } }
            else { selected.remove(l.id) }
        }
    }
    func setAll(_ on: Bool) { setGroup(lines, on: on) }

    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }

    private static func str(_ r: [String: Any], _ k: String) -> String {
        if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = r[k] as? NSNumber { return n.stringValue }
        return ""
    }
    private static func num(_ r: [String: Any], _ k: String) -> Double {
        if let n = r[k] as? NSNumber { return n.doubleValue }
        if let s = r[k] as? String { return Double(s) ?? 0 }
        return 0
    }

    func search(_ model: BrowserModel) {
        loading = true; error = nil; notice = nil
        model.desmQuery("/getInitDefailProject.do", body: "") { rows, err in
            guard let rows = rows else { self.loading = false; self.error = err; return }
            guard let pj = rows.first?["SEGMENT1"] as? String, !pj.isEmpty else {
                self.loading = false; self.error = "Chưa có dự án mặc định trong DESM."; return
            }
            self.project = pj
            let e = desmFormEnc
            let body = "PROJECT_NO=\(e(pj))&PACKING_LIST_NO=&PACKAGE_NO=\(e(self.pkg))&RSI_NO=\(e(self.rsiNo))&MATERIAL_CODE=\(e(self.code))&REQUEST_START_DATE=&ATTRIBUTE10=&REQUEST_END_DATE=&DESCRIPTION=&DRAWING_NO=&TAG_NO=&RSI_NAME=\(e(self.rsiName))&TYPE=&CATEGORY=&SUBCON=&PENDING=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
            model.desmQuery("/getDesmOutGoingCreationList.do", body: body) { list, err2 in
                self.loading = false; self.searched = true
                guard let list = list else { self.error = err2; self.lines = []; return }
                var out: [DesmOutLine] = []
                for (i, r) in list.enumerated() {
                    let lineId = r["RSI_LINE_ID"]
                    let hasIds = lineId != nil && !(lineId is NSNull) && r["RSI_HEADER_ID"] != nil && !(r["RSI_HEADER_ID"] is NSNull)
                    var l = DesmOutLine(id: hasIds ? Self.str(r, "RSI_LINE_ID") : "row\(i)")
                    l.rsiNo = Self.str(r, "RSI_NO"); l.rsiName = Self.str(r, "RSI_NAME"); l.subcon = Self.str(r, "SUBCONTRACTOR")
                    l.reqDate = Self.str(r, "REQUEST_DATE"); l.pkg = Self.str(r, "PACKAGE_NO"); l.plist = Self.str(r, "PACKING_LIST_NO")
                    l.desc = Self.str(r, "DESCRIPTION"); l.code = Self.str(r, "MATERIAL_CODE"); l.pending = Self.str(r, "PENDING")
                    l.project = Self.str(r, "PROJECT_NO")
                    l.req = Self.num(r, "REQ_QTY"); l.avail = Self.num(r, "HANDOVER_AVAILABLE_QTY")
                    l.headerId = r["RSI_HEADER_ID"] ?? NSNull(); l.lineId = lineId ?? NSNull()
                    l.valid = hasIds
                    out.append(l)
                }
                self.lines = out
                let ids = Set(out.map { $0.id })
                self.selected = self.selected.intersection(ids)
            }
        }
    }

    /// Kiểm tra và gửi lệnh xuất kho cho các dòng đã tích.
    func save(_ model: BrowserModel) {
        let chosen = lines.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
        let day = f.string(from: date)
        var list: [[String: Any]] = []
        for l in chosen {
            let q = Double((qty[l.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
            if q <= 0 { error = "Số lượng xuất của \(l.code) phải lớn hơn 0."; return }
            if q > l.avail + 0.0005 { error = "\(l.code): số lượng xuất \(Self.fmt(q)) vượt quá số còn xuất được \(Self.fmt(l.avail))."; return }
            list.append(["RSI_HEADER_ID": l.headerId, "RSI_LINE_ID": l.lineId, "HANDOVER_DATE": day, "HANDOVER_QTY": q,
                         "MATERIAL_CODE": l.code, "PROJECT_NO": l.project.isEmpty ? project : l.project,
                         "RECEIVER_NAME": receiver.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list), let json = String(data: data, encoding: .utf8) else {
            error = "Không tạo được dữ liệu gửi đi."; return
        }
        saving = true; error = nil; notice = nil
        model.desmWrite("/saveDesmRsiOutSave.do", updateList: json) { res, err in
            self.saving = false
            if res == nil { self.error = err; return }
            guard let r = res as? [String: Any] else { self.error = "Phản hồi không rõ. Hãy kiểm tra trên web trước khi thử lại."; return }
            let e = r["error"]
            if e == nil || e is NSNull {
                self.notice = "Đã xuất kho \(chosen.count) dòng."
                self.selected.removeAll(); self.qty.removeAll()
                self.search(model)
            } else if (e as? String) == "QTY" {
                let id = Self.str(r, "RSI_LINE_ID")
                let av = Self.str(r, "HANDOVER_AVAILABLE_QTY")
                let name = chosen.first { Self.str(["x": $0.lineId], "x") == id }?.code ?? id
                self.error = "Vượt số lượng được xuất ở dòng \(name). Còn xuất được: \(av). Chưa có dòng nào được lưu nếu máy chủ báo lỗi; hãy tải lại danh sách để kiểm tra."
            } else {
                self.error = "\(e ?? "Lỗi không rõ")"
            }
        }
    }
}

struct DesmOutgoingSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void
    @StateObject private var vm = DesmOutgoingVM()
    @State private var showForm = true
    @State private var confirm = false

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).frame(width: 96, alignment: .leading)
            TextField("", text: text)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .submitLabel(.search).onSubmit { vm.search(model) }
        }
    }

    private func pill(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(.white).background(color, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private var searchCard: some View {
        VStack(spacing: 8) {
            if showForm {
                field("RSI No.", $vm.rsiNo)
                field("RSI Name", $vm.rsiName)
                field("Package No.", $vm.pkg)
                field("Material Code", $vm.code)
            }
            HStack(spacing: 8) {
                pill(showForm ? "Ẩn" : "Bộ lọc", showForm ? "chevron.up.2" : "chevron.down.2", Color(red: 0.07, green: 0.70, blue: 0.62)) {
                    withAnimation { showForm.toggle() }
                }
                pill("Đặt lại", "arrow.counterclockwise", Color(red: 0.42, green: 0.53, blue: 0.72)) { vm.reset() }
                pill("Tìm", "magnifyingglass", Color.tabBlue) { vm.search(model); withAnimation { showForm = false } }
            }
        }
        .padding(12)
        .background(Color(red: 0.95, green: 0.97, blue: 1.0))
    }

    private func lineRow(_ l: DesmOutLine) -> some View {
        let on = vm.selected.contains(l.id)
        return HStack(alignment: .top, spacing: 10) {
            Button { vm.toggle(l) } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24)).foregroundStyle(l.valid ? Color.tabBlue : Color.gray)
            }.buttonStyle(.plain).disabled(!l.valid)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(l.code.isEmpty ? "(không có mã)" : l.code).font(.system(size: 14, weight: .bold))
                    if l.pending.uppercased() == "Y" {
                        Text("Chưa duyệt").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(.orange).background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                if !l.desc.isEmpty { Text(l.desc).font(.system(size: 13)).lineLimit(3) }
                if !l.pkg.isEmpty { Label(l.pkg, systemImage: "shippingbox").font(.system(size: 12)) }
                HStack(spacing: 10) {
                    Text("Yêu cầu \(DesmOutgoingVM.fmt(l.req))")
                    Text("Còn xuất được \(DesmOutgoingVM.fmt(l.avail))").foregroundStyle(l.avail > 0 ? Color.tabBlue : Color.red)
                }.font(.system(size: 12, weight: .medium))
                if !l.plist.isEmpty { Text(l.plist).font(.system(size: 11)).foregroundStyle(.secondary) }
                if !l.valid { Text("Thiếu RSI_LINE_ID/RSI_HEADER_ID trong dữ liệu — không thể xuất dòng này.").font(.system(size: 11)).foregroundStyle(.red) }
            }
            Spacer(minLength: 4)
            if on {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SL xuất").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("0", text: Binding(get: { vm.qty[l.id] ?? "" }, set: { vm.qty[l.id] = $0 }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.red)
                        .frame(width: 78).padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color(red: 1, green: 1, blue: 0.88), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { vm.toggle(l) }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack {
                DatePicker("Ngày xuất", selection: $vm.date, displayedComponents: .date).font(.system(size: 14, weight: .semibold))
            }
            TextField("Người nhận / ghi chú (tuỳ chọn)", text: $vm.receiver)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            Button { confirm = true } label: {
                HStack {
                    if vm.saving { ProgressView().tint(.white) }
                    Text("Xuất kho \(vm.selected.count) dòng").font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white).background(Color(red: 0.16, green: 0.65, blue: 0.40), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain).disabled(vm.saving)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchCard
                Divider()
                if let e = vm.error {
                    Text(e).font(.system(size: 13)).foregroundStyle(.red).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                }
                if let n = vm.notice {
                    Text(n).font(.system(size: 13, weight: .semibold)).foregroundStyle(.green).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.10))
                }
                if vm.loading && vm.lines.isEmpty {
                    Spacer(); ProgressView("Đang tìm…"); Spacer()
                } else if vm.lines.isEmpty {
                    Spacer()
                    Text(vm.searched ? "Không có dòng nào còn xuất được theo điều kiện này (phiếu có thể đã xuất hết)."
                                     : "Nhập số RSI (hoặc để trống) rồi bấm Tìm.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    HStack {
                        Button { vm.setAll(!vm.allSelected) } label: {
                            Label(vm.allSelected ? "Bỏ chọn tất cả" : "Chọn tất cả (\(vm.lines.filter { $0.valid }.count))",
                                  systemImage: vm.allSelected ? "square" : "checkmark.square")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Spacer()
                        Text("\(vm.selected.count) đã chọn").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    List {
                        ForEach(vm.groups, id: \.0) { g in
                            Section {
                                ForEach(g.1) { l in lineRow(l) }
                            } header: {
                                let first = g.1.first
                                let allOn = g.1.allSatisfy { vm.selected.contains($0.id) || !$0.valid }
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.0).font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                                        Text([first?.rsiName, first?.subcon, first?.reqDate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(allOn ? "Bỏ chọn phiếu" : "Chọn cả phiếu") { vm.setGroup(g.1, on: !allOn) }
                                        .font(.system(size: 12, weight: .semibold)).textCase(nil)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
                if !vm.selected.isEmpty { bottomBar }
            }
            .navigationTitle("Xuất kho")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
            }
        }
        .desmAlert(isPresented: $confirm, icon: "exclamationmark.triangle.fill", title: "Xác nhận xuất kho",
                   message: "Ghi xuất kho \(vm.selected.count) dòng lên DESM. Thao tác này không tự hoàn tác được.",
                   actions: [DesmDialogAction(title: "Xuất kho", kind: .destructive) { vm.save(model) },
                             DesmDialogAction(title: "Huỷ", kind: .cancel)])
        .onAppear { if !vm.searched { vm.search(model) } }
    }
}


// MARK: - WIP Completion (mục "Thêm")
//
// Làm theo popup "WIP Creation" của web (plWipCreationPopup.js, 2026-10-28):
//   Tìm:  POST /material/getPlWipCreationList.do   (đã kiểm chứng bằng log: trả WIP_AVAILABLE_QTY, WIP_DATE, WIP_QTY, SHOP_UNIT, SHOP_BLDG, RSI_LINE_ID, RSI_HEADER_ID...)
//   Lưu:  POST /material/savePlWipQuantity.do  updateList = JSON [{PROJECT_NO, RSI_HEADER_ID, RSI_LINE_ID, WIP_DATE, WIP_QTY, SHOP_UNIT, SHOP_BLDG, MATERIAL_CODE}]
//   Bắt buộc mỗi dòng: WIP date, WIP qty, C.Unit và BLDG (web có nút batch gán Unit/Bldg cho các dòng đã chọn).
//   Phản hồi: error rỗng/null là thành công; error == "QTY" kèm RSI_LINE_ID là vượt số lượng WIP khả dụng.
// CHƯA kiểm chứng: lệnh lưu với máy chủ thật (thao tác GHI).

struct DesmWipLine: Identifiable {
    let id: String
    var rsiNo = "", rsiName = "", subcon = "", reqDate = "", pkg = "", desc = "", code = "", tag = "", unit = "", project = ""
    var shopUnit = "", shopBldg = ""
    var avail = 0.0, handover = 0.0, totWip = 0.0
    var headerId: Any = NSNull()
    var lineId: Any = NSNull()
    var valid = true
}

final class DesmWipVM: ObservableObject {
    @Published var rsiNo = ""
    @Published var rsiName = ""
    @Published var pkg = ""
    @Published var code = ""
    @Published var lines: [DesmWipLine] = []
    @Published var selected = Set<String>()
    @Published var qty: [String: String] = [:]
    @Published var unitIn: [String: String] = [:]
    @Published var bldgIn: [String: String] = [:]
    @Published var date = Date()
    @Published var batchUnit = ""
    @Published var batchBldg = ""
    @Published var loading = false
    @Published var saving = false
    @Published var searched = false
    @Published var error: String? = nil
    @Published var notice: String? = nil
    private var project = ""

    var groups: [(String, [DesmWipLine])] {
        var order: [String] = []; var map: [String: [DesmWipLine]] = [:]
        for l in lines { if map[l.rsiNo] == nil { order.append(l.rsiNo) }; map[l.rsiNo, default: []].append(l) }
        return order.map { ($0, map[$0] ?? []) }
    }
    var allSelected: Bool { !lines.isEmpty && selected.count == lines.filter { $0.valid }.count }

    func reset() { rsiNo = ""; rsiName = ""; pkg = ""; code = "" }
    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }

    private func pick(_ l: DesmWipLine) {
        selected.insert(l.id)
        if (qty[l.id] ?? "").isEmpty { qty[l.id] = Self.fmt(l.avail) }
        if (unitIn[l.id] ?? "").isEmpty { unitIn[l.id] = l.shopUnit }
        if (bldgIn[l.id] ?? "").isEmpty { bldgIn[l.id] = l.shopBldg }
    }
    func toggle(_ l: DesmWipLine) {
        guard l.valid else { return }
        if selected.contains(l.id) { selected.remove(l.id) } else { pick(l) }
    }
    func setGroup(_ items: [DesmWipLine], on: Bool) {
        for l in items where l.valid { if on { pick(l) } else { selected.remove(l.id) } }
    }
    func setAll(_ on: Bool) { setGroup(lines, on: on) }
    /// Gán C.Unit / BLDG cho các dòng đã chọn (giống nút batch của web).
    func applyBatch() {
        let u = batchUnit.trimmingCharacters(in: .whitespacesAndNewlines), b = batchBldg.trimmingCharacters(in: .whitespacesAndNewlines)
        for id in selected { if !u.isEmpty { unitIn[id] = u }; if !b.isEmpty { bldgIn[id] = b } }
    }

    private static func str(_ r: [String: Any], _ k: String) -> String {
        if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = r[k] as? NSNumber { return n.stringValue }
        return ""
    }
    private static func num(_ r: [String: Any], _ k: String) -> Double {
        if let n = r[k] as? NSNumber { return n.doubleValue }
        if let s = r[k] as? String { return Double(s) ?? 0 }
        return 0
    }

    func search(_ model: BrowserModel) {
        loading = true; error = nil; notice = nil
        model.desmQuery("/getInitDefailProject.do", body: "") { rows, err in
            guard let rows = rows else { self.loading = false; self.error = err; return }
            guard let pj = rows.first?["SEGMENT1"] as? String, !pj.isEmpty else {
                self.loading = false; self.error = "Chưa có dự án mặc định trong DESM."; return
            }
            self.project = pj
            let e = desmFormEnc
            let body = "PROJECT_NO=\(e(pj))&PACKING_LIST_NO=&PACKAGE_NO=\(e(self.pkg))&RSI_NO=\(e(self.rsiNo))&RSI_NAME=\(e(self.rsiName))&SUBCON=&MATERIAL_CODE=\(e(self.code))&ATTRIBUTE10=&DESCRIPTION=&DRAWING_NO=&TAG_NO=&TYPE=&CATEGORY=&SUB_CATEGORY=&SHOP_UNIT=&SHOP_BLDG="
            model.desmQuery("/material/getPlWipCreationList.do", body: body) { list, err2 in
                self.loading = false; self.searched = true
                guard let list = list else { self.error = err2; self.lines = []; return }
                var out: [DesmWipLine] = []
                for (i, r) in list.enumerated() {
                    let lineId = r["RSI_LINE_ID"], headerId = r["RSI_HEADER_ID"]
                    let hasIds = lineId != nil && !(lineId is NSNull) && headerId != nil && !(headerId is NSNull)
                    var l = DesmWipLine(id: hasIds ? Self.str(r, "RSI_LINE_ID") : "row\(i)")
                    l.rsiNo = Self.str(r, "RSI_NO"); l.rsiName = Self.str(r, "RSI_NAME"); l.subcon = Self.str(r, "SUBCONTRACTOR")
                    l.reqDate = Self.str(r, "REQUEST_DATE"); l.pkg = Self.str(r, "PACKAGE_NO"); l.desc = Self.str(r, "DESCRIPTION")
                    l.code = Self.str(r, "MATERIAL_CODE"); l.tag = Self.str(r, "TAG_NO"); l.unit = Self.str(r, "UNIT")
                    l.project = Self.str(r, "PROJECT_NO")
                    l.shopUnit = Self.str(r, "SHOP_UNIT"); l.shopBldg = Self.str(r, "SHOP_BLDG")
                    l.avail = Self.num(r, "WIP_AVAILABLE_QTY"); l.handover = Self.num(r, "TOT_HANDOVER_QTY"); l.totWip = Self.num(r, "TOT_WIP_QTY")
                    l.headerId = headerId ?? NSNull(); l.lineId = lineId ?? NSNull()
                    l.valid = hasIds
                    out.append(l)
                }
                self.lines = out
                self.selected = self.selected.intersection(Set(out.map { $0.id }))
            }
        }
    }

    func save(_ model: BrowserModel) {
        let chosen = lines.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
        let day = f.string(from: date)
        var list: [[String: Any]] = []
        for l in chosen {
            let q = Double((qty[l.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
            let u = (unitIn[l.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let b = (bldgIn[l.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if q <= 0 { error = "Số lượng WIP của \(l.code) phải lớn hơn 0."; return }
            if q > l.avail + 0.0005 { error = "\(l.code): WIP \(Self.fmt(q)) vượt quá số khả dụng \(Self.fmt(l.avail))."; return }
            if u.isEmpty || b.isEmpty { error = "\(l.code): chưa nhập C.Unit/BLDG. Nhập ở ô cuối trang rồi bấm “Áp dụng cho dòng đã chọn”."; return }
            list.append(["PROJECT_NO": l.project.isEmpty ? project : l.project, "RSI_HEADER_ID": l.headerId, "RSI_LINE_ID": l.lineId,
                         "WIP_DATE": day, "WIP_QTY": q, "SHOP_UNIT": u, "SHOP_BLDG": b, "MATERIAL_CODE": l.code])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list), let json = String(data: data, encoding: .utf8) else {
            error = "Không tạo được dữ liệu gửi đi."; return
        }
        saving = true; error = nil; notice = nil
        model.desmWrite("/material/savePlWipQuantity.do", updateList: json) { res, err in
            self.saving = false
            if res == nil { self.error = err; return }
            guard let r = res as? [String: Any] else { self.error = "Phản hồi không rõ. Hãy kiểm tra trên web trước khi thử lại."; return }
            let e = r["error"]
            if e == nil || e is NSNull {
                self.notice = "Đã hoàn tất WIP \(chosen.count) dòng."
                self.selected.removeAll(); self.qty.removeAll(); self.unitIn.removeAll(); self.bldgIn.removeAll()
                self.search(model)
            } else if (e as? String) == "QTY" {
                self.error = "Vượt số lượng WIP khả dụng ở một dòng (RSI_LINE_ID \(Self.str(r, "RSI_LINE_ID"))). Hãy tải lại danh sách rồi kiểm tra."
            } else {
                self.error = "\(e ?? "Lỗi không rõ")"
            }
        }
    }
}

struct DesmWipSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void
    @StateObject private var vm = DesmWipVM()
    @State private var showForm = true
    @State private var confirm = false

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).frame(width: 96, alignment: .leading)
            TextField("", text: text)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .submitLabel(.search).onSubmit { vm.search(model) }
        }
    }
    private func pill(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(.white).background(color, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
    private func mini(_ title: String, _ binding: Binding<String>, width: CGFloat, keyboard: UIKeyboardType = .default, red: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("", text: binding).keyboardType(keyboard).autocorrectionDisabled().textInputAutocapitalization(.characters)
                .font(.system(size: 14, weight: .bold)).foregroundStyle(red ? Color.red : Color.primary)
                .frame(width: width).padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color(red: 1, green: 1, blue: 0.88), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var searchCard: some View {
        VStack(spacing: 8) {
            if showForm {
                field("RSI No.", $vm.rsiNo)
                field("RSI Name", $vm.rsiName)
                field("Package No.", $vm.pkg)
                field("Material Code", $vm.code)
            }
            HStack(spacing: 8) {
                pill(showForm ? "Ẩn" : "Bộ lọc", showForm ? "chevron.up.2" : "chevron.down.2", Color(red: 0.07, green: 0.70, blue: 0.62)) {
                    withAnimation { showForm.toggle() }
                }
                pill("Đặt lại", "arrow.counterclockwise", Color(red: 0.42, green: 0.53, blue: 0.72)) { vm.reset() }
                pill("Tìm", "magnifyingglass", Color.tabBlue) { vm.search(model); withAnimation { showForm = false } }
            }
        }
        .padding(12)
        .background(Color(red: 0.95, green: 0.97, blue: 1.0))
    }

    private func lineRow(_ l: DesmWipLine) -> some View {
        let on = vm.selected.contains(l.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Button { vm.toggle(l) } label: {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24)).foregroundStyle(l.valid ? Color.tabBlue : Color.gray)
                }.buttonStyle(.plain).disabled(!l.valid)
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.code.isEmpty ? "(không có mã)" : l.code).font(.system(size: 14, weight: .bold))
                    if !l.desc.isEmpty { Text(l.desc).font(.system(size: 13)).lineLimit(3) }
                    HStack(spacing: 8) {
                        if !l.tag.isEmpty { Text("Tag \(l.tag)") }
                        if !l.pkg.isEmpty { Label(l.pkg, systemImage: "shippingbox") }
                    }.font(.system(size: 12))
                    HStack(spacing: 10) {
                        Text("Đã xuất \(DesmWipVM.fmt(l.handover))")
                        Text("WIP \(DesmWipVM.fmt(l.totWip))")
                        Text("Khả dụng \(DesmWipVM.fmt(l.avail))").foregroundStyle(l.avail > 0 ? Color.tabBlue : Color.red)
                    }.font(.system(size: 12, weight: .medium))
                    if !l.shopUnit.isEmpty || !l.shopBldg.isEmpty {
                        Text("C.Unit \(l.shopUnit) · BLDG \(l.shopBldg)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if !l.valid { Text("Thiếu RSI_LINE_ID/RSI_HEADER_ID — không thể xử lý dòng này.").font(.system(size: 11)).foregroundStyle(.red) }
                }
                Spacer(minLength: 0)
            }
            if on {
                HStack(spacing: 8) {
                    mini("SL WIP", Binding(get: { vm.qty[l.id] ?? "" }, set: { vm.qty[l.id] = $0 }), width: 70, keyboard: .decimalPad, red: true)
                    mini("C.Unit", Binding(get: { vm.unitIn[l.id] ?? "" }, set: { vm.unitIn[l.id] = $0 }), width: 70)
                    mini("BLDG", Binding(get: { vm.bldgIn[l.id] ?? "" }, set: { vm.bldgIn[l.id] = $0 }), width: 70)
                    Spacer(minLength: 0)
                }.padding(.leading, 34)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { vm.toggle(l) }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            DatePicker("Ngày WIP", selection: $vm.date, displayedComponents: .date).font(.system(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                mini("C.Unit (gán loạt)", $vm.batchUnit, width: 110)
                mini("BLDG (gán loạt)", $vm.batchBldg, width: 110)
                Button { vm.applyBatch() } label: {
                    Text("Áp dụng cho dòng đã chọn").font(.system(size: 12, weight: .bold)).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(.white).background(Color(red: 0.42, green: 0.53, blue: 0.72), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            Button { confirm = true } label: {
                HStack {
                    if vm.saving { ProgressView().tint(.white) }
                    Text("Completion \(vm.selected.count) dòng").font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white).background(Color(red: 0.16, green: 0.65, blue: 0.40), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain).disabled(vm.saving)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchCard
                Divider()
                if let e = vm.error {
                    Text(e).font(.system(size: 13)).foregroundStyle(.red).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                }
                if let n = vm.notice {
                    Text(n).font(.system(size: 13, weight: .semibold)).foregroundStyle(.green).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.10))
                }
                if vm.loading && vm.lines.isEmpty {
                    Spacer(); ProgressView("Đang tìm…"); Spacer()
                } else if vm.lines.isEmpty {
                    Spacer()
                    Text(vm.searched ? "Không có dòng nào theo điều kiện này." : "Nhập số RSI rồi bấm Tìm.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    HStack {
                        Button { vm.setAll(!vm.allSelected) } label: {
                            Label(vm.allSelected ? "Bỏ chọn tất cả" : "Chọn tất cả (\(vm.lines.filter { $0.valid }.count))",
                                  systemImage: vm.allSelected ? "square" : "checkmark.square")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Spacer()
                        Text("\(vm.selected.count) đã chọn").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    List {
                        ForEach(vm.groups, id: \.0) { g in
                            Section {
                                ForEach(g.1) { l in lineRow(l) }
                            } header: {
                                let first = g.1.first
                                let allOn = g.1.allSatisfy { vm.selected.contains($0.id) || !$0.valid }
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.0).font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                                        Text([first?.rsiName, first?.subcon, first?.reqDate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(allOn ? "Bỏ chọn phiếu" : "Chọn cả phiếu") { vm.setGroup(g.1, on: !allOn) }
                                        .font(.system(size: 12, weight: .semibold)).textCase(nil)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
                if !vm.selected.isEmpty { bottomBar }
            }
            .navigationTitle("WIP Completion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
            }
        }
        .desmAlert(isPresented: $confirm, icon: "exclamationmark.triangle.fill", title: "Xác nhận Completion",
                   message: "Ghi WIP \(vm.selected.count) dòng lên DESM. Thao tác này không tự hoàn tác được.",
                   actions: [DesmDialogAction(title: "Completion", kind: .destructive) { vm.save(model) },
                             DesmDialogAction(title: "Huỷ", kind: .cancel)])
    }
}


// MARK: - Tab "Trả hàng" (MRF): tìm MRF, tích chọn dòng còn phải trả
//
// Làm theo popup "Return Creation" của web (desmReturnCreationPopUp.js, 2026-10-28):
//   Tìm:  POST /getDesmReturnCreationList.do  (PROJECT_NO, PACKAGE_NO, MRF_NO, MATERIAL_CODE, REQUEST_START_DATE, ATTRIBUTE10, REQUEST_END_DATE, TYPE, CATEGORY)
//         trả MRF_NO, MRF_NAME, SUBCONTRACTOR, RETURN_REQ_DATE, MATERIAL_CODE, PACKAGE_NO, DESCRIPTION, REQ_RETURN_QTY, RETURN_AVAILABLE_QTY, MRF_HEADER_ID, MRF_LINE_ID, RSI_LINE_ID...
//   Lưu:  POST /saveDesmMrfReturnSave.do  updateList=[{MRF_HEADER_ID, MRF_LINE_ID, MATERIAL_CODE, PROJECT_NO, RETURN_DATE(yyyy/MM/dd), RETURN_QTY, RSI_LINE_ID}]
//         lỗi số lượng: {error:"QTY", MRF_LINE_ID, RETURN_AVAILABLE_QTY}. Phần lưu CHƯA thử trên DESM thật.

struct DesmMrfLine: Identifiable {
    let id: String
    var mrfNo = "", mrfName = "", status = "", returnType = "", reqDate = "", rsiNo = "", code = "", desc = "", pkg = "", loc = "", unit = ""
    var req = 0.0, done = 0.0, balance = 0.0
    var headerId: Any = NSNull()
    var lineId: Any = NSNull()
    var rsiLineId: Any = NSNull()
    var valid = true
}

final class DesmMrfReturnVM: ObservableObject {
    @Published var mrfNo = ""
    @Published var mrfName = ""
    @Published var pkg = ""
    @Published var code = ""
    @Published var onlyOpen = true
    @Published var saving = false
    @Published var notice: String? = nil
    private var project = ""
    @Published var lines: [DesmMrfLine] = []
    @Published var selected = Set<String>()
    @Published var qty: [String: String] = [:]
    @Published var date = Date()
    @Published var loading = false
    @Published var searched = false
    @Published var error: String? = nil

    var groups: [(String, [DesmMrfLine])] {
        var order: [String] = []; var map: [String: [DesmMrfLine]] = [:]
        for l in lines { if map[l.mrfNo] == nil { order.append(l.mrfNo) }; map[l.mrfNo, default: []].append(l) }
        return order.map { ($0, map[$0] ?? []) }
    }
    var allSelected: Bool { !lines.isEmpty && selected.count == lines.filter { $0.valid }.count }

    func reset() { mrfNo = ""; mrfName = ""; pkg = ""; code = "" }
    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }

    private func pick(_ l: DesmMrfLine) { selected.insert(l.id); if (qty[l.id] ?? "").isEmpty { qty[l.id] = Self.fmt(l.balance) } }
    func toggle(_ l: DesmMrfLine) { guard l.valid else { return }; if selected.contains(l.id) { selected.remove(l.id) } else { pick(l) } }
    func setGroup(_ items: [DesmMrfLine], on: Bool) { for l in items where l.valid { if on { pick(l) } else { selected.remove(l.id) } } }
    func setAll(_ on: Bool) { setGroup(lines, on: on) }

    private static func str(_ r: [String: Any], _ k: String) -> String {
        if let s = r[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = r[k] as? NSNumber { return n.stringValue }
        return ""
    }
    private static func num(_ r: [String: Any], _ k: String) -> Double {
        if let n = r[k] as? NSNumber { return n.doubleValue }
        if let s = r[k] as? String { return Double(s) ?? 0 }
        return 0
    }

    func search(_ model: BrowserModel) {
        loading = true; error = nil
        model.desmQuery("/getInitDefailProject.do", body: "") { rows, err in
            guard let rows = rows else { self.loading = false; self.error = err; return }
            guard let pj = rows.first?["SEGMENT1"] as? String, !pj.isEmpty else {
                self.loading = false; self.error = "Chưa có dự án mặc định trong DESM."; return
            }
            self.project = pj
            let e = desmFormEnc
            let body = "PROJECT_NO=\(e(pj))&PACKAGE_NO=\(e(self.pkg))&MRF_NO=\(e(self.mrfNo))&MATERIAL_CODE=\(e(self.code))&REQUEST_START_DATE=&ATTRIBUTE10=&REQUEST_END_DATE=&TYPE=&CATEGORY="
            model.desmQuery("/getDesmReturnCreationList.do", body: body) { list, err2 in
                self.loading = false; self.searched = true
                guard let list = list else { self.error = err2; self.lines = []; return }
                var out: [DesmMrfLine] = []
                for (i, r) in list.enumerated() {
                    let lid = r["MRF_LINE_ID"], hid = r["MRF_HEADER_ID"]
                    let ok = lid != nil && !(lid is NSNull) && hid != nil && !(hid is NSNull)
                    var l = DesmMrfLine(id: ok ? Self.str(r, "MRF_LINE_ID") + "-" + Self.str(r, "RSI_LINE_ID") : "row\(i)")
                    l.mrfNo = Self.str(r, "MRF_NO"); l.mrfName = Self.str(r, "MRF_NAME"); l.status = Self.str(r, "SUBCONTRACTOR")
                    l.returnType = Self.str(r, "TYPE"); l.reqDate = Self.str(r, "RETURN_REQ_DATE")
                    l.code = Self.str(r, "MATERIAL_CODE"); l.desc = Self.str(r, "DESCRIPTION"); l.pkg = Self.str(r, "PACKAGE_NO")
                    l.loc = Self.str(r, "CATEGORY")
                    l.req = Self.num(r, "REQ_RETURN_QTY"); l.balance = Self.num(r, "RETURN_AVAILABLE_QTY")
                    l.headerId = hid ?? NSNull(); l.lineId = lid ?? NSNull(); l.rsiLineId = r["RSI_LINE_ID"] ?? NSNull()
                    l.valid = ok
                    if self.onlyOpen && l.balance <= 0 { continue }
                    if !self.mrfName.isEmpty && !l.mrfName.localizedCaseInsensitiveContains(self.mrfName) { continue }
                    out.append(l)
                }
                out.sort { $0.reqDate > $1.reqDate }
                self.lines = out
                self.selected = self.selected.intersection(Set(out.map { $0.id }))
            }
        }
    }

    func save(_ model: BrowserModel) {
        let chosen = lines.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
        let day = f.string(from: date)
        var list: [[String: Any]] = []
        for l in chosen {
            let q = Double((qty[l.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
            if q <= 0 { error = "Số lượng trả của \(l.code) phải lớn hơn 0."; return }
            if q > l.balance + 0.0005 { error = "\(l.code): số lượng trả \(Self.fmt(q)) vượt quá số còn trả được \(Self.fmt(l.balance))."; return }
            list.append(["MRF_HEADER_ID": l.headerId, "MRF_LINE_ID": l.lineId, "MATERIAL_CODE": l.code, "PROJECT_NO": project,
                         "RETURN_DATE": day, "RETURN_QTY": q, "RSI_LINE_ID": l.rsiLineId])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list), let json = String(data: data, encoding: .utf8) else {
            error = "Không tạo được dữ liệu gửi đi."; return
        }
        saving = true; error = nil; notice = nil
        model.desmWrite("/saveDesmMrfReturnSave.do", updateList: json) { res, err in
            self.saving = false
            if res == nil { self.error = err; return }
            guard let r = res as? [String: Any] else { self.error = "Phản hồi không rõ. Hãy kiểm tra trên web trước khi thử lại."; return }
            let e = r["error"]
            if e == nil || e is NSNull {
                self.notice = "Đã trả hàng \(chosen.count) dòng."
                self.selected.removeAll(); self.qty.removeAll()
                self.search(model)
            } else if (e as? String) == "QTY" {
                let id = Self.str(r, "MRF_LINE_ID")
                let av = Self.str(r, "RETURN_AVAILABLE_QTY")
                let name = chosen.first { Self.str(["x": $0.lineId], "x") == id }?.code ?? id
                self.error = "Vượt số lượng được trả ở dòng \(name). Còn trả được: \(av). Hãy tải lại danh sách để kiểm tra."
            } else {
                self.error = "\(e ?? "Lỗi không rõ")"
            }
        }
    }
}

struct DesmMrfReturnSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void
    @StateObject private var vm = DesmMrfReturnVM()
    @State private var showForm = true
    @State private var confirm = false

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).frame(width: 96, alignment: .leading)
            TextField("", text: text)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .submitLabel(.search).onSubmit { vm.search(model) }
        }
    }
    private func pill(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(.white).background(color, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private var searchCard: some View {
        VStack(spacing: 8) {
            if showForm {
                field("MRF No.", $vm.mrfNo)
                field("MRF Name", $vm.mrfName)
                field("Package No.", $vm.pkg)
                field("Material Code", $vm.code)
                Toggle("Chỉ dòng còn phải trả", isOn: $vm.onlyOpen).font(.system(size: 13, weight: .semibold))
            }
            HStack(spacing: 8) {
                pill(showForm ? "Ẩn" : "Bộ lọc", showForm ? "chevron.up.2" : "chevron.down.2", Color(red: 0.07, green: 0.70, blue: 0.62)) {
                    withAnimation { showForm.toggle() }
                }
                pill("Đặt lại", "arrow.counterclockwise", Color(red: 0.42, green: 0.53, blue: 0.72)) { vm.reset() }
                pill("Tìm", "magnifyingglass", Color.tabBlue) { vm.search(model); withAnimation { showForm = false } }
            }
        }
        .padding(12)
        .background(Color(red: 0.95, green: 0.97, blue: 1.0))
    }

    private func lineRow(_ l: DesmMrfLine) -> some View {
        let on = vm.selected.contains(l.id)
        return HStack(alignment: .top, spacing: 10) {
            Button { vm.toggle(l) } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24)).foregroundStyle(l.valid ? Color.tabBlue : Color.gray)
            }.buttonStyle(.plain).disabled(!l.valid)
            VStack(alignment: .leading, spacing: 3) {
                Text(l.code.isEmpty ? "(không có mã)" : l.code).font(.system(size: 14, weight: .bold))
                if !l.desc.isEmpty { Text(l.desc).font(.system(size: 13)).lineLimit(3) }
                if !l.pkg.isEmpty { Label(l.pkg, systemImage: "shippingbox").font(.system(size: 12)) }
                HStack(spacing: 10) {
                    Text("Cần trả \(DesmMrfReturnVM.fmt(l.req))\(l.unit.isEmpty ? "" : " " + l.unit)")
                    Text("còn trả được \(DesmMrfReturnVM.fmt(l.balance))").foregroundStyle(l.balance > 0 ? Color.red : Color.green)
                }.font(.system(size: 12, weight: .medium))
                HStack(spacing: 10) {
                    if !l.rsiNo.isEmpty { Text(l.rsiNo) }
                    if !l.loc.isEmpty { Text(l.loc) }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if on {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SL trả").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("0", text: Binding(get: { vm.qty[l.id] ?? "" }, set: { vm.qty[l.id] = $0 }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.red)
                        .frame(width: 78).padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color(red: 1, green: 1, blue: 0.88), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { vm.toggle(l) }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            DatePicker("Ngày trả", selection: $vm.date, displayedComponents: .date).font(.system(size: 14, weight: .semibold))
            Button { vm.error = nil; confirm = true } label: {
                Text(vm.saving ? "Đang gửi…" : "Trả hàng \(vm.selected.count) dòng").font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white).background(Color(red: 0.16, green: 0.65, blue: 0.40), in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).disabled(vm.saving)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchCard
                Divider()
                if let n = vm.notice {
                    Text(n).font(.system(size: 13, weight: .semibold)).foregroundStyle(.green).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.10))
                }
                if let e = vm.error {
                    Text(e).font(.system(size: 13)).foregroundStyle(.red).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                }
                if vm.loading && vm.lines.isEmpty {
                    Spacer(); ProgressView("Đang tìm…"); Spacer()
                } else if vm.lines.isEmpty {
                    Spacer()
                    Text(vm.searched ? "Không có dòng nào còn trả được." : "Nhập số MRF (hoặc để trống) rồi bấm Tìm.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    HStack {
                        Button { vm.setAll(!vm.allSelected) } label: {
                            Label(vm.allSelected ? "Bỏ chọn tất cả" : "Chọn tất cả (\(vm.lines.filter { $0.valid }.count))",
                                  systemImage: vm.allSelected ? "square" : "checkmark.square")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Spacer()
                        Text("\(vm.selected.count) đã chọn").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    List {
                        ForEach(vm.groups, id: \.0) { g in
                            Section {
                                ForEach(g.1) { l in lineRow(l) }
                            } header: {
                                let first = g.1.first
                                let allOn = g.1.allSatisfy { vm.selected.contains($0.id) || !$0.valid }
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.0).font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                                        Text([first?.mrfName, first?.status, first?.returnType, first?.reqDate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(allOn ? "Bỏ chọn phiếu" : "Chọn cả phiếu") { vm.setGroup(g.1, on: !allOn) }
                                        .font(.system(size: 12, weight: .semibold)).textCase(nil)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
                if !vm.selected.isEmpty { bottomBar }
            }
            .navigationTitle("Trả hàng MRF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
            }
        }
        .desmAlert(isPresented: $confirm, icon: "exclamationmark.triangle.fill", title: "Xác nhận trả hàng",
                   message: "Ghi trả hàng \(vm.selected.count) dòng lên DESM. Thao tác này không tự hoàn tác được.",
                   actions: [DesmDialogAction(title: "Trả hàng", kind: .destructive) { vm.save(model) },
                             DesmDialogAction(title: "Huỷ", kind: .cancel)])
        .onAppear { if !vm.searched { vm.search(model) } }
    }
}


// MARK: - Hoạt động gần đây (mục "Thêm")
//
// Gom các hoạt động đọc được từ DESM trong 1/3/7 ngày: Packing List mới tải lên, phiếu RSI mới tạo, RSI đã bàn giao,
// phiếu MRF trả hàng mới tạo, MRF đã trả. Dùng đúng các truy vấn đã có ở `fetchDocs` / `fetchPackingHistory`.
// Nhãn "MỚI" = chưa thấy ở lần mở trước (danh sách đã thấy lưu ở UserDefaults `desmActivitySeen`; lần mở đầu tiên không gắn nhãn).
// Đổi vị trí / xác nhận kiện lấy từ `/getIdsmOsSummaryList.do` (LOC_UPDATE_DATE, LOC_UPDATED_BY, CONFIRM_DATE, CONFIRMED_BY): chỉ có lần cập nhật CUỐI của mỗi kiện,
// không phải toàn bộ Edit Log (chưa bắt được API Edit Log).
// "Phiếu mới tạo" suy từ ngày yêu cầu (REQUEST_DATE / RETURN_REQ_DATE) nên chỉ chính xác theo ngày, không theo giờ.

enum DesmActivityKind: String {
    case packingUpload, rsiNew, rsiHandover, mrfNew, mrfReturn, locationUpdate, pkgConfirm
    var label: String {
        switch self {
        case .packingUpload: return "Tải Packing List"
        case .rsiNew: return "RSI mới"
        case .rsiHandover: return "RSI bàn giao"
        case .mrfNew: return "MRF mới"
        case .mrfReturn: return "MRF đã trả"
        case .locationUpdate: return "Đổi vị trí"
        case .pkgConfirm: return "Xác nhận kiện"
        }
    }
    var symbol: String {
        switch self {
        case .packingUpload: return "doc.badge.arrow.up"
        case .rsiNew: return "doc.badge.plus"
        case .rsiHandover: return "shippingbox.and.arrow.backward"
        case .mrfNew: return "arrow.uturn.backward.circle"
        case .mrfReturn: return "checkmark.circle"
        case .locationUpdate: return "mappin.and.ellipse"
        case .pkgConfirm: return "checkmark.seal"
        }
    }
    var color: Color {
        switch self {
        case .packingUpload: return .blue
        case .rsiNew, .rsiHandover: return .orange
        case .mrfNew, .mrfReturn: return .purple
        case .locationUpdate: return .teal
        case .pkgConfirm: return .green
        }
    }
    /// 1 = Packing List, 2 = RSI, 3 = MRF, 4 = Kiện (vị trí/xác nhận) (khớp bộ lọc trong màn hình)
    var group: Int {
        switch self {
        case .packingUpload: return 1
        case .rsiNew, .rsiHandover: return 2
        case .mrfNew, .mrfReturn: return 3
        case .locationUpdate, .pkgConfirm: return 4
        }
    }
}

struct DesmActivity: Identifiable {
    let id: String
    let kind: DesmActivityKind
    let title: String
    let detail: String
    let date: String
    var isNew = false
}

extension BrowserModel {
    func fetchActivity(days: Int, done: @escaping ([DesmActivity], [String]) -> Void) {
        desmQuery("/getInitDefailProject.do", body: "") { rows, err in
            guard let rows = rows else { done([], [err]); return }
            guard let no = rows.first?["SEGMENT1"] as? String, !no.isEmpty else { done([], ["Chưa có dự án mặc định trong DESM."]); return }
            let P = Self.enc(no)
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy/MM/dd"
            let now = Date()
            let today = f.string(from: now)
            let cutoff = f.string(from: Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now)
            func num(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }
            func join(_ parts: [String]) -> String { parts.filter { !$0.isEmpty }.joined(separator: " · ") }

            var out: [DesmActivity] = []
            var errs: [String] = []
            typealias Step = (_ next: @escaping () -> Void) -> Void
            let steps: [Step] = [
                // Packing List đã tải lên
                { next in
                    self.fetchPackingHistory(days: days) { list, e in
                        if let list = list {
                            for r in list {
                                out.append(DesmActivity(id: "pl-\(r.id)", kind: .packingUpload,
                                                        title: r.invoice.isEmpty ? "(không có Invoice)" : r.invoice,
                                                        detail: join([r.file, r.result, r.user]), date: r.created))
                            }
                        } else { errs.append("Packing List: \(e)") }
                        next()
                    }
                },
                // RSI mới tạo (theo ngày yêu cầu)
                { next in
                    let body = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&ATTRIBUTE10=&MATERIAL_CODE=&START_REQUEST_DATE=\(Self.enc(cutoff))&END_REQUEST_DATE=\(Self.enc(today))&BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&PACKAGE_NO=&ITEM_DESC=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
                    self.desmQuery("/getDesmRsiViewList.do", body: body) { rows, e in
                        if let rows = rows {
                            for g in Self.groups(rows, doc: "RSI_NO", name: "RSI_NAME", date: "REQUEST_DATE", status: "STATUS", extra: "SUBCONTRACTOR",
                                                 qty: "REQ_QTY", done: "HANDOVER_QTY", bal: "BALANCE_QTY", close: nil) where g.date >= cutoff {
                                out.append(DesmActivity(id: "rsi-new-\(g.id)", kind: .rsiNew, title: g.id,
                                                        detail: join([g.name, g.extra, "\(g.lines) dòng", "SL \(num(g.qty))", g.status]), date: g.date))
                            }
                        } else { errs.append("RSI: \(e)") }
                        next()
                    }
                },
                // RSI đã bàn giao
                { next in
                    let body = "PAGE_NUM=1&PAGE_CNT=1000&PROJECT_NO=\(P)&START_HANDOVER_DATE=\(Self.enc(cutoff))&END_HANDOVER_DATE=\(Self.enc(today))&PACKAGE_NO=&SUBCONTRACTOR=&RSI_NO=&MATERIAL_CODE=&ATTRIBUTE10=&RSI_NAME=&TYPE=&CATEGORY=&SUB_CATEGORY=&COMMENTS=&PACKING_LIST_NO=&PENDING=&RECEIVER_REMARK=&MASTER_SHOP_UNIT=&MASTER_SHOP_BLDG=&SHOP_UNIT=&SHOP_BLDG="
                    self.desmQuery("/getDesmRsiOutGoingList.do", body: body) { rows, e in
                        if let rows = rows {
                            for g in Self.groups(rows, doc: "RSI_NO", name: "RSI_NAME", date: "REQUEST_DATE", status: "", extra: "SUBCONTRACTOR",
                                                 qty: "REQ_QTY", done: "HANDOVER_QTY", bal: nil, close: "HANDOVER_DATE") where g.closeDate >= cutoff {
                                out.append(DesmActivity(id: "rsi-out-\(g.id)-\(g.closeDate)", kind: .rsiHandover, title: g.id,
                                                        detail: join([g.name, g.extra, "Bàn giao SL \(num(g.done))"]), date: g.closeDate))
                            }
                        } else { errs.append("RSI bàn giao: \(e)") }
                        next()
                    }
                },
                // MRF mới tạo (máy chủ không lọc ngày ở truy vấn này nên lọc phía máy khách)
                { next in
                    let body = "PROJECT_NO=\(P)&RSI_NO=&RSI_NAME=&SUBCONTRACTOR=&MATERIAL_CODE=&RSI_START_REQUEST_DATE=&RSI_END_REQUEST_DATE=&ZIM_ATTRIBUTE10=&RSI_BALANCE_QTY=&TYPE=&CATEGORY=&SUB_CATEGORY=&PACKING_LIST_NO=&MRF_NO=&MRF_NAME=&PACKAGE_NO=&ITEM_DESC=&RETURN_TYPE=&MRF_BALANCE_QTY="
                    self.desmQuery("/getMrfSummaryList.do", body: body) { rows, e in
                        if let rows = rows {
                            for g in Self.groups(rows, doc: "MRF_NO", name: "MRF_NAME", date: "RETURN_REQ_DATE", status: "STATUS", extra: "RETURN_TYPE",
                                                 qty: "MRF_REQ_RETURN_QTY", done: "MRF_RETURN_QTY", bal: "MRF_BALANCE_QTY", close: nil) where g.date >= cutoff {
                                out.append(DesmActivity(id: "mrf-new-\(g.id)", kind: .mrfNew, title: g.id,
                                                        detail: join([g.name, g.extra, "\(g.lines) dòng", "SL \(num(g.qty))", g.status]), date: g.date))
                            }
                        } else { errs.append("MRF: \(e)") }
                        next()
                    }
                },
                // MRF đã trả
                { next in
                    let body = "PROJECT_NO=\(P)&START_HANDOVER_DATE=\(Self.enc(cutoff))&END_HANDOVER_DATE=\(Self.enc(today))&PACKAGE_NO=&SUBCONTRACTOR=&MRF_NO=&MATERIAL_CODE=&ATTRIBUTE10=&MRF_NAME=&TYPE=&CATEGORY="
                    self.desmQuery("/getDesmMrfReturnList.do", body: body) { rows, e in
                        if let rows = rows {
                            for g in Self.groups(rows, doc: "MRF_NO", name: "MRF_NAME", date: "RETURN_REQ_DATE", status: "", extra: "RETURN_TYPE",
                                                 qty: "REQ_RETURN_QTY", done: "RETURN_QTY", bal: nil, close: "RETURN_DATE") where g.closeDate >= cutoff {
                                out.append(DesmActivity(id: "mrf-ret-\(g.id)-\(g.closeDate)", kind: .mrfReturn, title: g.id,
                                                        detail: join([g.name, g.extra, "Đã trả SL \(num(g.done))"]), date: g.closeDate))
                            }
                        } else { errs.append("MRF đã trả: \(e)") }
                        next()
                    }
                },
                // Đổi vị trí / xác nhận kiện: lấy từ danh sách Package (LOC_UPDATE_DATE, LOC_UPDATED_BY, CONFIRM_DATE, CONFIRMED_BY).
                // Chỉ có LẦN CẬP NHẬT CUỐI của mỗi kiện (không phải toàn bộ lịch sử Edit Log). Máy chủ không lọc theo ngày này nên lọc phía máy khách.
                { next in
                    let body = "PROJECT_NO=\(P)&PACKAGE_LIST_NO=&PACKAGE_NO=&DESCRIPTION=&IS_CONFIRM_MATERIAL=&RECEIPTED=&ATTRIBUTE10=&REMARK=&VENDOR=&LOCATION=&START_RECEIPT_DATE=&END_RECEIPT_DATE=&MRR_VISUAL_CHECK=All&MRR_RECEIVED=&START_MRR_RECEIVED_DATE=&END_MRR_RECEIVED_DATE=&CUSTOMS_YN=&MIR_CATEGORY=&PACKAGE_STATUS="
                    self.desmQuery("/getIdsmOsSummaryList.do", body: body) { rows, e in
                        if let rows = rows {
                            for r in rows {
                                let pkg = Self.fstr(r, "PACKAGE_NO"); if pkg.isEmpty { continue }
                                let ld = Self.fstr(r, "LOC_UPDATE_DATE")
                                if ld >= cutoff {
                                    let loc = Self.fstr(r, "STORAGE_LOCATION")
                                    out.append(DesmActivity(id: "loc-\(pkg)-\(ld)-\(loc)", kind: .locationUpdate, title: pkg,
                                                            detail: join([loc.isEmpty ? "" : "→ \(loc)", Self.fstr(r, "LOC_UPDATED_BY"), Self.fstr(r, "DESCRIPTION")]), date: ld))
                                }
                                let cd = Self.fstr(r, "CONFIRM_DATE")
                                if cd >= cutoff {
                                    out.append(DesmActivity(id: "cfm-\(pkg)-\(cd)", kind: .pkgConfirm, title: pkg,
                                                            detail: join([Self.fstr(r, "CONFIRMED_BY"), Self.fstr(r, "DESCRIPTION")]), date: cd))
                                }
                            }
                        } else { errs.append("Kiện: \(e)") }
                        next()
                    }
                },
            ]
            func run(_ i: Int) {
                if i >= steps.count {
                    out.sort { $0.date > $1.date }   // "yyyy/MM/dd[ HH:mm]" so sánh chuỗi được
                    done(out, errs); return
                }
                let step = steps[i]
                step { run(i + 1) }
            }
            run(0)
        }
    }
}

struct DesmActivitySheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    private static let seenKey = "desmActivitySeen"
    @State private var days = 3
    @State private var filter = 0
    @State private var items: [DesmActivity] = []
    @State private var errors: [String] = []
    @State private var loading = false
    @State private var seenAtOpen: Set<String>? = nil   // nil = lần đầu: chưa có mốc nên không gắn "MỚI"
    @State private var started = false

    private var shown: [DesmActivity] { filter == 0 ? items : items.filter { $0.kind.group == filter } }
    private var newCount: Int { items.filter { $0.isNew }.count }

    private func load() {
        loading = true
        if !started {
            started = true
            if let a = UserDefaults.standard.stringArray(forKey: Self.seenKey) { seenAtOpen = Set(a) }
        }
        model.fetchActivity(days: days) { list, errs in
            loading = false
            errors = errs
            let seen = seenAtOpen
            items = list.map { var a = $0; a.isNew = seen.map { !$0.contains(a.id) } ?? false; return a }
            // Ghi nhớ đã thấy (giữ tối đa 600 mã gần nhất)
            var all = Array(seen ?? [])
            for a in list where !all.contains(a.id) { all.append(a.id) }
            if all.count > 600 { all = Array(all.suffix(600)) }
            UserDefaults.standard.set(all, forKey: Self.seenKey)
        }
    }

    private func row(_ a: DesmActivity) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: a.kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(a.kind.color)
                .frame(width: 34, height: 34)
                .background(a.kind.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(a.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    if a.isNew {
                        Text("MỚI").font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(.white).background(Color.red, in: Capsule())
                    }
                    Spacer(minLength: 4)
                    Text(a.kind.label).font(.system(size: 11, weight: .bold)).foregroundStyle(a.kind.color)
                }
                if !a.detail.isEmpty {
                    Text(a.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(a.date).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Khoảng ngày", selection: $days) {
                    Text("1 ngày").tag(1); Text("3 ngày").tag(3); Text("7 ngày").tag(7)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
                .onChange(of: days) { _ in load() }
                Picker("Loại", selection: $filter) {
                    Text("Tất cả").tag(0); Text("Packing").tag(1); Text("RSI").tag(2); Text("MRF").tag(3); Text("Kiện").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.bottom, 8)

                if newCount > 0 {
                    Text("\(newCount) hoạt động mới từ lần xem trước")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                        .padding(.bottom, 6)
                }
                if !errors.isEmpty {
                    Text("Một số nguồn không tải được: " + errors.joined(separator: " | "))
                        .font(.system(size: 11)).foregroundStyle(.orange)
                        .padding(.horizontal, 16).padding(.bottom, 6)
                }

                if loading && items.isEmpty {
                    Spacer(); ProgressView("Đang tải…"); Spacer()
                } else if shown.isEmpty {
                    Spacer()
                    Text("Không có hoạt động nào trong \(days) ngày gần đây.").font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    List(shown) { a in row(a) }.listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Hoạt động")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
        }
        .onAppear { if items.isEmpty && !loading { load() } }
    }
}


// MARK: - Tra Edit Log hạng mục (mục "Thêm")
//
// Nhập Material Code hoặc Package No -> tìm hạng mục bằng /getIdsmOsDetailList.do (Material Code: KEY1='material', VALUE1=<mã>; Package: PACKAGE_NO)
// -> chọn hạng mục -> /getDesmPlDetailEditLogList.do {PROJECT_NO, TRK_ITEM_NAME, MATERIAL_CODE} (như popup "Material record" của web).
// CHƯA kiểm chứng với DESM thật: tên trường trả về lấy theo desmPlDtlEditLogPopUp.js.

struct DesmLogItem: Identifiable, Hashable {
    let id: String
    let project: String
    let trk: String
    let pkg: String
    let material: String
    let desc: String
    let location: String
}

struct DesmLogEntry: Identifiable {
    let id: Int
    let date: String
    let by: String
    let location: String
    let locInfo: String
    let qty: String
    let remarks: String
    let reports: String
    let diffs: [String]
    let hasOlder: Bool
}

extension BrowserModel {
    func searchLogItems(byMaterial: Bool, term: String, done: @escaping ([DesmLogItem], String) -> Void) {
        desmQuery("/getInitDefailProject.do", body: "") { rows, err in
            guard let rows = rows else { done([], err); return }
            guard let no = rows.first?["SEGMENT1"] as? String, !no.isEmpty else { done([], "Chưa có dự án mặc định trong DESM."); return }
            let t = Self.enc(term.trimmingCharacters(in: .whitespacesAndNewlines))
            let pkg = byMaterial ? "" : t
            let key = byMaterial ? "material" : ""
            let val = byMaterial ? t : ""
            let body = "PAGE_NUM=1&PAGE_CNT=300&PROJECT_NO=\(Self.enc(no))&PACKAGE_LIST_NO=&PACKAGE_NO=\(pkg)&DESCRIPTION=&DRAWING_NO=&TAG_NO=&QTY_TYPE=rsi&QTY=&KEY1=\(key)&VALUE1=\(val)&LOCATION=&SEQUENCE=&VENDOR=&ATTRIBUTE10=&TYPE=&CATEGORY=&SUB_CATEGORY=&COMMENTS="
            self.desmQuery("/getIdsmOsDetailList.do", body: body) { list, e in
                guard let list = list else { done([], e); return }
                var out: [DesmLogItem] = []
                for (i, r) in list.enumerated() {
                    let trk = Self.fstr(r, "TRK_ITEM_NAME"), mat = Self.fstr(r, "MATERIAL_CODE")
                    if mat.isEmpty { continue }
                    out.append(DesmLogItem(id: "\(i)-\(mat)", project: Self.fstr(r, "PROJECT_NO").isEmpty ? no : Self.fstr(r, "PROJECT_NO"),
                                           trk: trk, pkg: Self.fstr(r, "PACKAGE_NO"), material: mat,
                                           desc: Self.fstr(r, "DESCRIPTION"), location: Self.fstr(r, "LOCATION")))
                }
                done(out, "")
            }
        }
    }

    func fetchEditLog(_ item: DesmLogItem, done: @escaping ([DesmLogEntry], String) -> Void) {
        let body = "PROJECT_NO=\(Self.enc(item.project))&TRK_ITEM_NAME=\(Self.enc(item.trk))&MATERIAL_CODE=\(Self.enc(item.material))"
        desmQuery("/getDesmPlDetailEditLogList.do", body: body) { list, e in
            guard var list = list else { done([], e); return }
            list.sort { Self.fstr($0, "CREATION_DATE_TXT") > Self.fstr($1, "CREATION_DATE_TXT") }
            let fields: [(String, String)] = [("LOCATION", "Location"), ("IN_QTY", "In Q'ty"), ("REMARKS", "Remarks"), ("DESCRIPTION", "Item"),
                                              ("DRAWING_NO", "DWG"), ("TAG_NO", "TAG"), ("UNIT", "Unit"), ("MATERIAL", "Material"),
                                              ("REPORT_SHORT_QTY", "Short"), ("REPORT_OVER_QTY", "Over"), ("REPORT_DMG_QTY", "DMG"), ("REPORT_MISSING_QTY", "Missing")]
            func norm(_ r: [String: Any], _ k: String) -> String {
                Self.fstr(r, k).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            }
            func num(_ r: [String: Any], _ k: String) -> String {
                let v = Self.fnum(r, k); return v == v.rounded() ? String(Int(v)) : String(format: "%.3g", v)
            }
            var out: [DesmLogEntry] = []
            for (i, r) in list.enumerated() {
                var diffs: [String] = []
                let older: [String: Any]? = i + 1 < list.count ? list[i + 1] : nil
                if let o = older {
                    for (k, label) in fields where norm(r, k) != norm(o, k) {
                        diffs.append("\(label): \(norm(o, k).isEmpty ? "-" : norm(o, k)) → \(norm(r, k).isEmpty ? "-" : norm(r, k))")
                    }
                }
                var rep: [String] = []
                for (k, label) in [("REPORT_SHORT_QTY", "Short"), ("REPORT_OVER_QTY", "Over"), ("REPORT_DMG_QTY", "DMG"), ("REPORT_MISSING_QTY", "Missing")] where Self.fnum(r, k) > 0 {
                    rep.append("\(label) \(num(r, k))")
                }
                let ld = norm(r, "LOC_UPDATE_DATE"), lb = norm(r, "LOC_UPDATED_BY")
                let info = [ld, lb].filter { !$0.isEmpty }.joined(separator: " · ")
                let qty = "In Q'ty \(num(r, "IN_QTY")) \(norm(r, "UNIT"))".trimmingCharacters(in: .whitespaces)
                out.append(DesmLogEntry(id: i, date: norm(r, "CREATION_DATE_TXT"), by: norm(r, "CREATED_BY"), location: norm(r, "LOCATION"),
                                        locInfo: info, qty: qty, remarks: norm(r, "REMARKS"), reports: rep.joined(separator: " · "),
                                        diffs: diffs, hasOlder: older != nil))
            }
            done(out, "")
        }
    }
}

struct DesmEditLogDetailView: View {
    @ObservedObject var model: BrowserModel
    let item: DesmLogItem
    @State private var entries: [DesmLogEntry] = []
    @State private var loading = true
    @State private var error: String? = nil

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.material).font(.system(size: 15, weight: .bold))
                    if !item.desc.isEmpty { Text(item.desc).font(.system(size: 13)) }
                    if !item.pkg.isEmpty { Text(item.pkg).font(.system(size: 12)).foregroundStyle(.secondary) }
                }
            }
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let error = error {
                Text(error).font(.callout).foregroundStyle(.orange)
            } else if entries.isEmpty {
                Text("Hạng mục này chưa có lịch sử chỉnh sửa.").font(.callout).foregroundStyle(.secondary)
            } else {
                Section("\(entries.count) bản ghi (mới nhất trước)") {
                    ForEach(entries) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(e.date.isEmpty ? "—" : e.date).font(.system(size: 14, weight: .bold))
                                Spacer()
                                Text(e.by).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            if e.hasOlder {
                                Text(e.diffs.isEmpty ? "Không đổi so với bản trước" : "Thay đổi — " + e.diffs.joined(separator: " · "))
                                    .font(.system(size: 12, weight: e.diffs.isEmpty ? .regular : .semibold))
                                    .foregroundStyle(e.diffs.isEmpty ? Color.secondary : Color.orange)
                            }
                            Text("📍 " + (e.location.isEmpty ? "—" : e.location) + (e.locInfo.isEmpty ? "" : "   (\(e.locInfo))"))
                                .font(.system(size: 12))
                            Text(e.qty + (e.remarks.isEmpty ? "" : "   Remarks: \(e.remarks)")).font(.system(size: 12)).foregroundStyle(.secondary)
                            if !e.reports.isEmpty { Text(e.reports).font(.system(size: 12)).foregroundStyle(.secondary) }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Edit Log")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard loading else { return }
            if item.trk.isEmpty { loading = false; error = "Thiếu TRK_ITEM_NAME của hạng mục nên chưa xem được Edit Log."; return }
            model.fetchEditLog(item) { list, err in
                loading = false
                if err.isEmpty { entries = list } else { error = err }
            }
        }
    }
}

struct DesmEditLogSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    @State private var byMaterial = true
    @State private var term = ""
    @State private var items: [DesmLogItem] = []
    @State private var loading = false
    @State private var error: String? = nil
    @State private var searched = false

    private func search() {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !loading else { return }
        loading = true; error = nil; searched = true
        model.searchLogItems(byMaterial: byMaterial, term: t) { list, err in
            loading = false
            if err.isEmpty { items = list } else { items = []; error = err }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tìm theo", selection: $byMaterial) {
                    Text("Material Code").tag(true)
                    Text("Package No").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 10)
                HStack(spacing: 8) {
                    TextField(byMaterial ? "Vd: OMN-009-001-00002" : "Vd: OM4-DE-IS-0009-002", text: $term)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder).submitLabel(.search).onSubmit { search() }
                    Button("Tìm") { search() }.buttonStyle(.borderedProminent).disabled(loading || term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16)

                if loading {
                    Spacer(); ProgressView("Đang tìm…"); Spacer()
                } else if let error = error {
                    Spacer(); Text(error).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center).padding(24); Spacer()
                } else if items.isEmpty {
                    Spacer()
                    Text(searched ? "Không tìm thấy hạng mục nào." : "Nhập Material Code hoặc Package No rồi bấm Tìm.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    Spacer()
                } else {
                    List(items) { it in
                        NavigationLink {
                            DesmEditLogDetailView(model: model, item: it)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(it.material).font(.system(size: 14, weight: .bold))
                                if !it.desc.isEmpty { Text(it.desc).font(.system(size: 12)).lineLimit(2) }
                                Text([it.pkg, it.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tra Edit Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } } }
        }
    }
}


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
    private static func c(_ la: Double, _ lo: Double) -> CLLocationCoordinate2D { .init(latitude: la, longitude: lo) }

    // Biển Đông ven bờ Việt Nam, từ vịnh Bắc Bộ xuống cửa sông Hậu / Vũng Tàu.
    private static let tonkinToSouth: [CLLocationCoordinate2D] = [
        c(20.60, 107.05), c(18.70, 106.90), c(16.30, 108.90), c(13.60, 109.55), c(11.40, 109.50), c(10.00, 108.30),
    ]
    private static let toDinhAn: [CLLocationCoordinate2D] = [
        c(9.30, 107.00), c(9.48, 106.55), // cửa Định An (sông Hậu)
        c(9.62, 106.28), c(9.80, 106.05), c(9.95, 105.88), c(10.04, 105.76),
    ]
    // Busan -> eo Đài Loan -> nam đảo Hải Nam -> ven bờ Việt Nam.
    private static let busanToVietnam: [CLLocationCoordinate2D] = [
        c(34.40, 129.30), c(32.80, 128.40), c(29.00, 125.80), c(25.30, 121.60), c(24.00, 119.60),
        c(22.00, 116.80), c(19.50, 113.80), c(17.60, 111.40), c(14.80, 110.30), c(11.40, 109.50), c(9.90, 108.20),
    ]
    // Vũng Tàu -> sông Lòng Tàu -> Cát Lái.
    private static let toCatLai: [CLLocationCoordinate2D] = [
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

extension BrowserModel {
    func fetchVessels(done: @escaping ([DesmVessel], String) -> Void) {
        desmQuery("/getInitDefailProject.do", body: "") { rows, err in
            guard let rows = rows else { done([], err); return }
            guard let no = rows.first?["SEGMENT1"] as? String, !no.isEmpty else { done([], "Chưa có dự án mặc định trong DESM."); return }
            let P = no.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? no
            self.desmQuery("/vessel/getVesselFinderList.do", body: "PROJECT_NO=\(P)") { list, e in
                guard let list = list else { done([], e); return }
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
                done(out, "")
            }
        }
    }
}

extension BrowserModel {
    /// Tiến trình vận chuyển của một chuyến: /selectDesmShippingStatusList.do (body như trang Shipping Status của DESM).
    /// Mã Invoice ở danh sách tàu (INV_NO) và ở Shipping Status (INVOICE_NO) có thể khác dạng, nên ghép theo INVOICE_NO hoặc tên tàu.
    func fetchShipInfo(_ v: DesmVessel, done: @escaping (DesmShipInfo?, String) -> Void) {
        func enc(_ x: String) -> String { x.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? x }
        // lần 1: theo mã Invoice đầy đủ; lần 2: theo nhóm số (vd "0002") mà web dùng làm VOYAGE/INVOICE tìm kiếm
        var tries = [v.invoice]
        if let g = v.invoice.split(separator: "-").first(where: { $0.count >= 3 && $0.allSatisfy { $0.isNumber } }) { tries.append(String(g)) }
        func norm(_ x: String) -> String { x.lowercased().filter { $0.isLetter || $0.isNumber } }
        func step(_ i: Int) {
            guard i < tries.count else { done(nil, "Chưa có dữ liệu tiến trình cho chuyến này."); return }
            desmQuery("/selectDesmShippingStatusList.do", body: "PROJECT_NO=\(enc(v.project))&VOYAGE_NO=&INVOICE_NO=\(enc(tries[i]))&SHIPPING_STATUS=&DATA_CREATED_YN=") { rows, err in
                guard let rows = rows else { done(nil, err); return }
                func str(_ r: [String: Any], _ k: String) -> String { (r[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                let hit = rows.first { norm(str($0, "INVOICE_NO")) == norm(v.invoice) }
                    ?? rows.first { !v.vessel.isEmpty && norm(str($0, "VESSEL_NAME")) == norm(v.vessel) }
                guard let r = hit else { step(i + 1); return }
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
                done(info, "")
            }
        }
        step(0)
    }
}

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
    private static let W: CGFloat = 104, H: CGFloat = 50, cy: CGFloat = 16, D: CGFloat = 24
    private let badge = UIView(), icon = UIImageView(), label = UILabel(), pill = UIView()
    private let ring = CAShapeLayer()

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
    private let ring = CAShapeLayer()
    private let hull = UIImageView()
    private var pulsing = false

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
    private func refreshLive(_ m: MKMapView, _ co: Coordinator) {
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

struct DesmVesselSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    @State private var vessels: [DesmVessel] = []
    @State private var ports: [String: CLLocationCoordinate2D] = DesmPorts.known
    @State private var selected: String? = nil
    @State private var loading = false
    @State private var error = ""
    @State private var tick = 0
    @State private var infos: [String: DesmShipInfo] = [:]
    @State private var infoMsg: [String: String] = [:]
    @State private var infoLoading: Set<String> = []
    private let geocoder = CLGeocoder()

    private func loadInfo(_ v: DesmVessel) {
        guard infos[v.id] == nil, !infoLoading.contains(v.id) else { return }
        infoLoading.insert(v.id); infoMsg[v.id] = nil
        model.fetchShipInfo(v) { info, err in
            infoLoading.remove(v.id)
            if let info = info { infos[v.id] = info } else { infoMsg[v.id] = err }
        }
    }

    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh"); return f }()

    @ViewBuilder private func detail(_ v: DesmVessel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !v.pl.isEmpty { Text("Packing List: " + v.pl).font(.system(size: 12, weight: .semibold)) }
            if !v.imo.isEmpty { Text("IMO: " + v.imo).font(.system(size: 12)).foregroundStyle(.secondary) }
            if let i = infos[v.id] {
                let extra = [i.status.isEmpty ? "" : "Trạng thái: " + i.status,
                             i.line.isEmpty ? "" : "Hãng tàu: " + i.line,
                             i.bl.isEmpty ? "" : "BL: " + i.bl,
                             i.mode.isEmpty ? "" : i.mode,
                             i.grossKg > 0 ? String(format: "%.0f kg", i.grossKg) : "",
                             i.volume > 0 ? String(format: "%.2f m³", i.volume) : ""].filter { !$0.isEmpty }
                if !extra.isEmpty { Text(extra.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(i.milestones.enumerated()), id: \.element.id) { idx, m in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 0) {
                                Circle().fill(m.done ? Color.green : (m.planned ? Color.orange : Color.gray.opacity(0.35)))
                                    .frame(width: 10, height: 10)
                                if idx < i.milestones.count - 1 {
                                    Rectangle().fill(m.done ? Color.green.opacity(0.6) : Color.gray.opacity(0.25)).frame(width: 2, height: 22)
                                }
                            }
                            HStack {
                                Text(m.title).font(.system(size: 12, weight: m.done ? .semibold : .regular))
                                    .foregroundStyle(m.done ? Color.primary : Color.secondary)
                                Spacer()
                                Text(m.date.map { Self.dayFmt.string(from: $0) + (m.planned ? " (dự kiến)" : "") } ?? "—")
                                    .font(.system(size: 11)).foregroundStyle(m.planned ? Color.orange : Color.secondary)
                            }
                            .padding(.top, -3)
                        }
                    }
                }
            } else if infoLoading.contains(v.id) {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Đang tải tiến trình…").font(.system(size: 11)).foregroundStyle(.secondary) }
            } else if let m = infoMsg[v.id], !m.isEmpty {
                Text(m).font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack(spacing: 14) {
                if !v.vessel.isEmpty, let u = URL(string: "https://www.vesselfinder.com/vessels?name=" + (v.vessel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v.vessel)) {
                    Link(destination: u) { Label("Theo dõi tàu", systemImage: "location.magnifyingglass").font(.system(size: 12, weight: .semibold)) }
                }
                if let i = infos[v.id], !i.bl.isEmpty,
                   let u = URL(string: "https://www.google.com/search?q=" + ((i.line + " " + i.bl + " tracking").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? i.bl)) {
                    Link(destination: u) { Label("Tra BL", systemImage: "shippingbox").font(.system(size: 12, weight: .semibold)) }
                }
            }
        }
        .padding(.top, 4)
    }

    private func load() {
        loading = true; error = ""
        model.fetchVessels { list, err in
            loading = false; error = err
            vessels = list
            if let s = selected, !list.contains(where: { $0.id == s }) { selected = nil }
            geocodeMissing(list)
        }
    }

    /// Cảng chưa có trong bảng: tra từng cái một bằng CLGeocoder (giới hạn tốc độ của hệ thống).
    private func geocodeMissing(_ list: [DesmVessel]) {
        var names: [String] = []
        for v in list { for n in [v.pol, v.pod] where !n.isEmpty && ports[DesmPorts.key(n)] == nil && !names.contains(n) { names.append(n) } }
        func step(_ i: Int) {
            guard i < names.count else { return }
            geocoder.geocodeAddressString(names[i] + " port") { marks, _ in
                if let c = marks?.first?.location?.coordinate { ports[DesmPorts.key(names[i])] = c }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { step(i + 1) }
            }
        }
        step(0)
    }

    private var hasPositions: Bool { vessels.contains { $0.lat != nil && $0.lon != nil } }

    private func row(_ v: DesmVessel) -> some View {
        let color: Color = v.arrived ? .gray : (v.departed ? .green : Color(red: 0.85, green: 0.65, blue: 0.0))   // xanh = ATD thật, vàng = dự kiến (như web)
        let state = v.arrived ? "Đã đến" : (v.departed ? "Đang đi" : "Chưa khởi hành")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "ferry.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                .frame(width: 34, height: 34).background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(v.invoice.isEmpty ? "(không có Invoice)" : v.invoice).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 4)
                    if v.arrivingSoon {
                        Text("Sắp đến").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.green, in: Capsule())
                    }
                    Text(state).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                }
                if !v.vessel.isEmpty { Text(v.vessel + (v.mfr.isEmpty ? "" : " · " + v.mfr)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
                Text("\(v.pol.isEmpty ? "—" : v.pol) → \(v.pod.isEmpty ? "—" : v.pod)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.tabBlue)
                Text("\(v.departed ? "ATD" : "ETD") \(v.etd.isEmpty ? "-" : v.etd)   ·   \(v.arrived ? "ATA" : "ETA") \(v.eta.isEmpty ? "-" : v.eta)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if !v.item.isEmpty { Text(v.item).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(selected == v.id ? 4 : 2) }
                if selected == v.id { detail(v) }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { selected = selected == v.id ? nil : v.id; if selected == v.id { loadInfo(v) } }
        .listRowBackground(selected == v.id ? Color.tabBlue.opacity(0.10) : (v.arrivingSoon ? Color.green.opacity(0.12) : Color(.secondarySystemGroupedBackground)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DesmVesselMap(vessels: vessels, ports: ports, selected: selected, tick: tick)
                    .frame(height: 290)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                if !error.isEmpty {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 16).padding(.bottom, 6)
                }
                if loading && vessels.isEmpty {
                    Spacer(); ProgressView("Đang tải…"); Spacer()
                } else if vessels.isEmpty {
                    Spacer()
                    Text(error.isEmpty ? "Chưa có chuyến tàu nào." : "").font(.callout).foregroundStyle(.secondary).padding(24)
                    Spacer()
                } else {
                    List(vessels) { v in row(v) }.listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Bản đồ tàu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
        }
        .onAppear { if vessels.isEmpty && !loading { load() } }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
    }
}


// MARK: - Thông báo DESM (mục "Thêm")
//
// Nguồn: trang chủ DESM (home.js). POST /getNotice.do (jobCode rỗng) -> danh sách: NOTICE_ID, TITLE, ATT_CNT (số file đính kèm),
// LAST_UPDATE_DATE, LAST_UPDATED_BY, FILE_GRP_CD. POST /getNoticeContents.do (jobCode = NOTICE_ID) -> results[0].CONTENTS (văn bản thuần, web nhét vào textarea).
// POST /getRealTimeNotice.do -> thông báo chạy trên đầu trang (TITLE, NOTICE_ID). File đính kèm chưa làm (cần /getIdsmSetupDlgItemScheduleFile.do + /getIdsmAttachDownload.do).
// "Mới" = NOTICE_ID chưa mở lần nào (lưu UserDefaults; lần đầu mở thì coi tất cả là đã xem). CHƯA kiểm chứng trên máy thật.

struct DesmNotice: Identifiable, Hashable {
    let id: String
    var title = "", by = "", date = "", fileGroup = ""
    var attach = 0
    var realtime = false
}

struct DesmAttach: Identifiable, Hashable {
    let id: String
    var name = "", ext = "", size = 0.0
}

struct DesmSharedFile: Identifiable { let id = UUID(); let url: URL }

/// Danh sách NOTICE_ID đã mở (UserDefaults). nil = chưa từng lưu: lần đầu coi mọi thông báo hiện có là đã xem.
enum DesmNoticeSeen {
    static let key = "desmSeenNotices"
    static func load() -> Set<String>? { (UserDefaults.standard.array(forKey: key) as? [String]).map(Set.init) }
    static func save(_ s: Set<String>) { UserDefaults.standard.set(Array(s), forKey: key) }
}

extension BrowserModel {
    func fetchNotices(done: @escaping ([DesmNotice], [DesmNotice], String) -> Void) {
        func str(_ r: [String: Any], _ k: String) -> String {
            if let v = r[k] as? String { return v.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = r[k] as? NSNumber { return n.stringValue }
            return ""
        }
        func parse(_ rows: [[String: Any]], rt: Bool) -> [DesmNotice] {
            let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
            return rows.map { r in
                var n = DesmNotice(id: str(r, "NOTICE_ID")); n.realtime = rt
                n.title = str(r, "TITLE"); n.by = str(r, "LAST_UPDATED_BY"); n.fileGroup = str(r, "FILE_GRP_CD")
                if let ms = r["LAST_UPDATE_DATE"] as? NSNumber { n.date = f.string(from: Date(timeIntervalSince1970: ms.doubleValue / 1000)) }
                else { n.date = str(r, "LAST_UPDATE_DATE") }
                n.attach = (r["ATT_CNT"] as? NSNumber)?.intValue ?? 0
                return n
            }
        }
        desmQuery("/getNotice.do", body: "jobCode=") { rows, err in
            guard let rows = rows else { done([], [], err); return }
            let list = parse(rows, rt: false)
            self.desmQuery("/getRealTimeNotice.do", body: "") { rt, _ in
                done(list, parse(rt ?? [], rt: true), "")
            }
        }
    }

    /// Đếm thông báo chưa mở, cập nhật chấm đỏ trên nút "Thêm" và số trên icon app.
    func refreshNoticeBadge() {
        guard inDesm else { return }
        fetchNotices { list, _, err in
            guard err.isEmpty else { return }
            var seen = DesmNoticeSeen.load()
            if seen == nil { seen = Set(list.map { $0.id }); DesmNoticeSeen.save(seen!) }
            self.setUnread(list.filter { !(seen ?? []).contains($0.id) }.count)
        }
    }
    func setUnread(_ n: Int) {
        unreadNotices = n
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.badge]) { ok, _ in
            if ok { c.setBadgeCount(n) { _ in } }
        }
    }

    /// File đính kèm của thông báo: lấy FILE_GRP_CD (từ danh sách, không có thì hỏi lại getNotice theo NOTICE_ID) rồi
    /// POST /getIdsmSetupDlgItemScheduleFile.do FILE_GRP_CD=... -> [{ID, NAME, EXT, FILE_SIZE}].
    func fetchNoticeFiles(_ n: DesmNotice, done: @escaping ([DesmAttach], String) -> Void) {
        func enc(_ x: String) -> String { x.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? x }
        func files(_ group: String) {
            guard !group.isEmpty else { done([], ""); return }
            desmQuery("/getIdsmSetupDlgItemScheduleFile.do", body: "FILE_GRP_CD=" + enc(group)) { rows, err in
                guard let rows = rows else { done([], err); return }
                done(rows.compactMap { r in
                    func s(_ k: String) -> String {
                        if let v = r[k] as? String { return v }
                        if let v = r[k] as? NSNumber { return v.stringValue }
                        return ""
                    }
                    let id = s("ID"); if id.isEmpty { return nil }
                    return DesmAttach(id: id, name: s("NAME"), ext: s("EXT"), size: (r["FILE_SIZE"] as? NSNumber)?.doubleValue ?? Double(s("FILE_SIZE")) ?? 0)
                }, "")
            }
        }
        if !n.fileGroup.isEmpty { files(n.fileGroup); return }
        guard n.attach > 0 else { done([], ""); return }
        desmQuery("/getNotice.do", body: "jobCode=" + enc(n.id)) { rows, err in
            guard let rows = rows else { done([], err); return }
            files((rows.first?["FILE_GRP_CD"] as? String) ?? "")
        }
    }

    /// Tải một file đính kèm: GET /getIdsmAttachDownload.do?code=<ID> bằng phiên đăng nhập, lưu vào thư mục tạm để chia sẻ/mở.
    func downloadAttachment(_ a: DesmAttach, done: @escaping (URL?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang DESM để tải."); return }
        let js = #"""
        try {
          const r = await fetch('/getIdsmAttachDownload.do?code=' + encodeURIComponent(code), { credentials: 'include', cache: 'no-store' });
          if (!r.ok) return JSON.stringify({ err: 'HTTP ' + r.status });
          const ct = (r.headers.get('content-type') || '').toLowerCase();
          const buf = new Uint8Array(await r.arrayBuffer());
          if (/text\/html|json/.test(ct) && buf.length < 4000) return JSON.stringify({ err: 'Máy chủ không trả file (có thể đã hết phiên hoặc không có quyền).' });
          let bin = '';
          for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000));
          return JSON.stringify({ b64: btoa(bin) });
        } catch (e) { return JSON.stringify({ err: String(e && e.message || e) }); }
        """#
        webView.callAsyncJavaScript(js, arguments: ["code": a.id], in: nil, in: .page) { result in
            switch result {
            case .failure(let e): done(nil, "Không tải được: \(e.localizedDescription)")
            case .success(let v):
                guard let text = v as? String, let d = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { done(nil, "Không đọc được phản hồi."); return }
                if let err = obj["err"] as? String { done(nil, err); return }
                guard let b64 = obj["b64"] as? String, let bytes = Data(base64Encoded: b64), !bytes.isEmpty else { done(nil, "File tải về rỗng."); return }
                var name = a.name.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { name = "dinh-kem-" + a.id }
                if (name as NSString).pathExtension.isEmpty, !a.ext.isEmpty { name += "." + a.ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("desm-notice-\(UUID().uuidString)", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(name)
                    try bytes.write(to: url)
                    done(url, "")
                } catch { done(nil, "Không lưu được file: \(error.localizedDescription)") }
            }
        }
    }

    func fetchNoticeContent(_ id: String, done: @escaping (String, String) -> Void) {
        desmQuery("/getNoticeContents.do", body: "jobCode=" + (id.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? id)) { rows, err in
            guard let rows = rows else { done("", err); return }
            done((rows.first?["CONTENTS"] as? String) ?? "", rows.isEmpty ? "Thông báo không có nội dung." : "")
        }
    }
}

struct DesmNoticeSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    @State private var notices: [DesmNotice] = []
    @State private var live: [DesmNotice] = []
    @State private var loading = false
    @State private var error = ""
    @State private var seen: Set<String> = []
    @State private var files: [DesmAttach] = []
    @State private var filesMsg = ""
    @State private var downloading: String? = nil
    @State private var shared: DesmSharedFile? = nil
    @State private var opened: DesmNotice? = nil
    @State private var content = ""
    @State private var contentErr = ""
    @State private var contentLoading = false

    private func load() {
        loading = true; error = ""
        model.fetchNotices { list, rt, err in
            loading = false; error = err
            notices = list; live = rt
            if let saved = DesmNoticeSeen.load() { seen = saved }
            else { seen = Set(list.map { $0.id }); DesmNoticeSeen.save(seen) }   // lần đầu: coi mọi thông báo hiện có là đã xem
            model.setUnread(list.filter { !seen.contains($0.id) }.count)
        }
    }

    private func show(_ n: DesmNotice) {
        opened = n; content = ""; contentErr = ""; contentLoading = true
        files = []; filesMsg = ""; downloading = nil
        seen.insert(n.id); DesmNoticeSeen.save(seen)
        model.setUnread(notices.filter { !seen.contains($0.id) }.count)
        model.fetchNoticeContent(n.id) { text, err in
            contentLoading = false; content = text; contentErr = err
        }
        if n.attach > 0 || !n.fileGroup.isEmpty {
            model.fetchNoticeFiles(n) { list, err in files = list; filesMsg = err }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !live.isEmpty {
                    Section("Thông báo khẩn") {
                        ForEach(live) { n in
                            Button { show(n) } label: {
                                Label(n.title, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.system(size: 14, weight: .semibold))
                            }
                        }
                    }
                }
                Section(notices.isEmpty ? "" : "Thông báo (\(notices.count))") {
                    ForEach(notices) { n in
                        Button { show(n) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    if !seen.contains(n.id) {
                                        Text("Mới").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.red, in: Capsule())
                                    }
                                    Text(n.title).font(.system(size: 14, weight: seen.contains(n.id) ? .regular : .bold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                    if n.attach > 0 { Image(systemName: "paperclip").font(.system(size: 11)).foregroundStyle(.secondary) }
                                }
                                Text([n.date, n.by].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
                if !loading && error.isEmpty && notices.isEmpty { Text("Chưa có thông báo.").foregroundStyle(.secondary) }
            }
            .overlay { if loading && notices.isEmpty { ProgressView("Đang tải…") } }
            .navigationTitle("Thông báo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading) }
            }
            .sheet(item: $opened) { n in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(n.title).font(.system(size: 17, weight: .bold))
                            Text([n.date, n.by].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(.secondary)
                            Divider()
                            if contentLoading { ProgressView() }
                            else if !contentErr.isEmpty { Text(contentErr).foregroundStyle(.orange) }
                            else { Text(content.isEmpty ? "(Không có nội dung)" : content).font(.system(size: 15)).textSelection(.enabled) }
                            if !files.isEmpty || !filesMsg.isEmpty {
                                Divider()
                                Text("Đính kèm").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                                if !filesMsg.isEmpty { Text(filesMsg).font(.system(size: 12)).foregroundStyle(.orange) }
                                ForEach(files) { f in
                                    Button {
                                        guard downloading == nil else { return }
                                        downloading = f.id; filesMsg = ""
                                        model.downloadAttachment(f) { url, err in
                                            downloading = nil
                                            if let url = url { shared = DesmSharedFile(url: url) } else { filesMsg = err }
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "doc.fill").foregroundStyle(Color.tabBlue)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(f.name.isEmpty ? "(file \(f.id))" : f.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                                if f.size > 0 { Text(ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file)).font(.system(size: 11)).foregroundStyle(.secondary) }
                                            }
                                            Spacer()
                                            if downloading == f.id { ProgressView() } else { Image(systemName: "arrow.down.circle").foregroundStyle(Color.tabBlue) }
                                        }
                                        .padding(10).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle("Chi tiết").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Xong") { opened = nil } } }
                    .sheet(item: $shared) { f in ShareSheet(url: f.url) }
                }
            }
        }
        .onAppear { if notices.isEmpty && !loading { load() } }
    }
}


// MARK: - Tải file / API cho AI (mục "Thêm")
//
// Để khi AI khác cần xem mã nguồn của DESM (file .js, .css, trang HTML) hoặc kết quả một API, người dùng chỉ cần dán link/địa chỉ vào đây,
// bấm tải rồi chia sẻ file lại cho AI. Chạy bằng phiên đăng nhập hiện có của trang DESM, chỉ tải được địa chỉ cùng domain.
// Mỗi dòng là một yêu cầu:
//   /resources/scripts/shippingStatus/vesselFinder.js?rv=bJ5Z2O2Jp5            (GET; có thể dán nguyên link https://desm...)
//   POST /vessel/getVesselFinderList.do PROJECT_NO=T25026                       (POST form: sau địa chỉ là phần body)
// Một dòng -> lưu đúng nội dung (đuôi .js/.json/.css/.html/.txt theo loại trả về); nhiều dòng -> gộp thành một file văn bản có tiêu đề từng phần.
// CHƯA kiểm chứng trên máy thật.

extension BrowserModel {
    /// Tải một yêu cầu ("[GET|POST] địa chỉ [body]"). done(kết quả, lỗi): lỗi rỗng = thành công.
    func fetchResource(_ spec: String, done: @escaping (DesmFetched?, String) -> Void) {
        guard let webView = webView else { done(nil, "Chưa có trang DESM để tải. Hãy mở DESM và đăng nhập trước."); return }
        let js = #"""
        var m = 'GET', u = String(spec || '').trim(), b = null;
        var mm = u.match(/^(GET|POST)\s+(\S+)(?:\s+([\s\S]*))?$/i);
        if (mm) { m = mm[1].toUpperCase(); u = mm[2]; b = mm[3] || ''; }
        var a;
        try { a = new URL(u, location.href); } catch (e) { return JSON.stringify({ err: 'Địa chỉ không hợp lệ' }); }
        if (a.origin !== location.origin) return JSON.stringify({ err: 'Chỉ tải được địa chỉ cùng domain với trang đang mở (' + location.origin + ')' });
        try {
          var o = { method: m, credentials: 'include', cache: 'no-store', headers: {} };
          if (m === 'POST') { o.headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8'; o.headers['X-Requested-With'] = 'XMLHttpRequest'; o.body = b || ''; }
          var r = await fetch(a.href, o);
          var t = await r.text();
          return JSON.stringify({ method: m, url: a.href, status: r.status, ct: (r.headers.get('content-type') || '').split(';')[0], text: t });
        } catch (e) { return JSON.stringify({ err: String(e && e.message || e) }); }
        """#
        webView.callAsyncJavaScript(js, arguments: ["spec": spec], in: nil, in: .page) { result in
            switch result {
            case .failure(let e): done(nil, "Không tải được: \(e.localizedDescription)")
            case .success(let v):
                guard let s = v as? String, let data = s.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { done(nil, "Không đọc được phản hồi."); return }
                if let err = o["err"] as? String { done(nil, err); return }
                done(DesmFetched(method: o["method"] as? String ?? "GET", url: o["url"] as? String ?? spec,
                                 status: (o["status"] as? NSNumber)?.intValue ?? 0,
                                 contentType: o["ct"] as? String ?? "", text: o["text"] as? String ?? ""), "")
            }
        }
    }
}

struct DesmFetched {
    var method: String, url: String, status: Int, contentType: String, text: String
    /// Đuôi file theo loại nội dung (rồi đến đuôi trong địa chỉ).
    var ext: String {
        let c = contentType.lowercased(), p = (URL(string: url)?.path ?? "").lowercased()
        if c.contains("json") || p.hasSuffix(".json") { return "json" }
        if c.contains("javascript") || p.hasSuffix(".js") { return "js" }
        if c.contains("css") || p.hasSuffix(".css") { return "css" }
        if c.contains("html") || p.hasSuffix(".html") || p.hasSuffix(".do") && c.contains("html") { return "html" }
        return "txt"
    }
    var baseName: String {
        let last = (URL(string: url)?.lastPathComponent ?? "").replacingOccurrences(of: ".\(ext)", with: "")
        let clean = last.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return clean.isEmpty ? "desm-fetch" : clean
    }
}

struct DesmFetchSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    private static let recentKey = "desmFetchRecent"
    @AppStorage("desmFetchLines") private var lines = ""
    @State private var loading = false
    @State private var progress = ""
    @State private var message = ""
    @State private var shareItem: ShareItem? = nil
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: DesmFetchSheet.recentKey) ?? []

    private var specs: [String] {
        lines.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func save(_ text: String, name: String, ext: String) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(f.string(from: Date())).\(ext)")
        do { try text.write(to: url, atomically: true, encoding: .utf8); shareItem = ShareItem(url: url) }
        catch { message = "Không lưu được file: \(error.localizedDescription)" }
    }

    private func run() {
        let list = specs
        guard !list.isEmpty else { message = "Hãy dán ít nhất một link hoặc địa chỉ."; return }
        loading = true; message = ""
        var results: [(String, DesmFetched?, String)] = []
        func step(_ i: Int) {
            if i >= list.count {
                loading = false; progress = ""
                // nhớ các dòng đã dùng (tối đa 12)
                var rc = recent
                for s in list.reversed() { rc.removeAll { $0 == s }; rc.insert(s, at: 0) }
                recent = Array(rc.prefix(12)); UserDefaults.standard.set(recent, forKey: DesmFetchSheet.recentKey)
                if list.count == 1 {
                    if let f = results[0].1 { save(f.text, name: f.baseName, ext: f.ext); if f.status >= 400 { message = "HTTP \(f.status) — nội dung có thể là trang lỗi." } }
                    else { message = results[0].2 }
                } else {
                    var out = "DESM — NỘI DUNG ĐÃ TẢI (\(list.count) yêu cầu)\n"
                    for (spec, f, err) in results {
                        if let f = f {
                            out += "\n\n===== \(f.method) \(f.url) =====\nHTTP \(f.status) · \(f.contentType.isEmpty ? "?" : f.contentType) · \(f.text.count) ký tự\n\n\(f.text)"
                        } else {
                            out += "\n\n===== \(spec) =====\nLỖI: \(err)"
                        }
                    }
                    save(out, name: "desm-fetch", ext: "txt")
                    let bad = results.filter { $0.1 == nil }.count
                    if bad > 0 { message = "\(bad)/\(list.count) yêu cầu bị lỗi (đã ghi trong file)." }
                }
                return
            }
            progress = "Đang tải \(i + 1)/\(list.count)…"
            model.fetchResource(list[i]) { f, err in
                results.append((list[i], f, err))
                step(i + 1)
            }
        }
        step(0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $lines)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .frame(minHeight: 140)
                    Button {
                        run()
                    } label: {
                        HStack { if loading { ProgressView() }; Text(loading ? progress : "Tải và chia sẻ file…").fontWeight(.semibold) }
                    }
                    .disabled(loading)
                    if !lines.isEmpty { Button("Xóa ô nhập", role: .destructive) { lines = "" } }
                } header: {
                    Text("Link / địa chỉ cần tải")
                } footer: {
                    Text("Mỗi dòng một yêu cầu. Dán nguyên link https://desm… hoặc chỉ đường dẫn /resources/…js. API dạng POST: POST /đường/dẫn.do PROJECT_NO=T25026. Một dòng lưu đúng file (.js/.json/.css/.html); nhiều dòng gộp thành một file văn bản. Dòng bắt đầu bằng # bị bỏ qua.")
                }
                if !message.isEmpty { Section { Text(message).font(.footnote).foregroundStyle(.orange) } }
                if !recent.isEmpty {
                    Section {
                        ForEach(recent, id: \.self) { s in
                            Button { lines = lines.isEmpty ? s : lines + "\n" + s } label: {
                                Text(s).font(.system(size: 12, design: .monospaced)).lineLimit(2).foregroundStyle(.primary)
                            }
                        }
                        Button("Xóa danh sách gần đây", role: .destructive) { recent = []; UserDefaults.standard.removeObject(forKey: DesmFetchSheet.recentKey) }
                    } header: { Text("Đã dùng gần đây (chạm để thêm lại)") }
                }
                Section {
                    Text("Khi AI cần xem code hoặc API của DESM, nó sẽ gửi bạn link hoặc dòng POST. Dán vào ô trên, bấm Tải, rồi chia sẻ file (Lưu vào Tệp, hoặc gửi thẳng cho AI). Cần đang đăng nhập DESM; file có thể chứa thông tin nội bộ nên hãy xem lại trước khi gửi.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Cách dùng") }
            }
            .navigationTitle("Tải file / API")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } } }
            .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
        }
    }
}


// MARK: - Mã nguồn trang đang mở (mục "Thêm")
//
// Đang ở trang DESM nào thì mở mục này: app tự quét danh sách file JS, CSS mà trang (và các khung iframe cùng domain) đang dùng,
// kèm HTML đã dựng của trang và nhật ký API đã ghi. Tích chọn thứ cần rồi bấm Tải: app tự tải bằng phiên đăng nhập hiện có và gộp thành một file để chia sẻ,
// không cần tự tìm link. API chỉ có khi đã bật "Ghi API" (bật ngay trong màn này) rồi thao tác trên trang (Search, mở chi tiết…).
// Mặc định chọn: HTML + CSS/JS của DESM (không gồm thư viện .min / ext như jQuery, Bootstrap; bật công tắc nếu cần).
// CHƯA kiểm chứng trên máy thật.

struct DesmRes: Identifiable, Hashable {
    enum Kind: String { case js, css }
    let url: String
    let kind: Kind
    var id: String { url }
    var path: String { URL(string: url)?.path ?? url }
    var label: String {
        let u = URL(string: url)
        let name = (u?.path ?? url).split(separator: "/").suffix(2).joined(separator: "/")
        return name.isEmpty ? url : name
    }
    /// Thư viện bên thứ ba (jQuery, Bootstrap, font…) — thường không cần cho việc sửa giao diện/logic DESM.
    var vendor: Bool {
        let p = path.lowercased()
        return p.contains(".min.") || p.contains("/ext/") || p.contains("/jquery") || p.contains("/node_modules/") || p.contains("/webfonts/") || p.contains("fontawesome")
    }
}

extension BrowserModel {
    /// Quét JS/CSS của trang đang mở (kể cả iframe cùng domain và tài nguyên đã tải qua Performance API).
    func listPageResources(done: @escaping (String, [DesmRes], String) -> Void) {
        guard let webView = webView else { done("", [], "Chưa có trang DESM để quét."); return }
        let js = #"""
        var seen = {}, out = [];
        function add(u, k) {
          try {
            var a = new URL(u, location.href);
            if (a.origin !== location.origin) return;
            var key = k + a.pathname + a.search;
            if (seen[key]) return; seen[key] = 1; out.push({ u: a.href, k: k });
          } catch (e) {}
        }
        function scan(doc, l) {
          [].forEach.call(doc.querySelectorAll('script[src]'), function(s) { add(s.src, 'js'); });
          [].forEach.call(doc.querySelectorAll('link[rel~="stylesheet"][href]'), function(s) { add(s.href, 'css'); });
          if (l > 3) return;
          [].forEach.call(doc.querySelectorAll('iframe,frame'), function(f) { try { if (f.contentDocument) scan(f.contentDocument, l + 1); } catch (e) {} });
        }
        scan(document, 0);
        try {
          performance.getEntriesByType('resource').forEach(function(e) {
            var p = String(e.name).split('?')[0];
            if (/\.js$/i.test(p)) add(e.name, 'js'); else if (/\.css$/i.test(p)) add(e.name, 'css');
          });
        } catch (e) {}
        return JSON.stringify({ page: location.href, items: out });
        """#
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure(let e): done("", [], "Không quét được: \(e.localizedDescription)")
            case .success(let v):
                guard let s = v as? String, let data = s.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { done("", [], "Không đọc được kết quả quét."); return }
                var items: [DesmRes] = []
                for it in (o["items"] as? [[String: Any]] ?? []) {
                    guard let u = it["u"] as? String, let k = it["k"] as? String, let kind = DesmRes.Kind(rawValue: k) else { continue }
                    items.append(DesmRes(url: u, kind: kind))
                }
                done(o["page"] as? String ?? "", items, "")
            }
        }
    }
}

struct DesmSourceSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    @AppStorage("desmNetLogOn") private var netLogOn = false
    @AppStorage("desmSourceVendor") private var includeVendor = false
    @State private var page = ""
    @State private var items: [DesmRes] = []
    @State private var selected: Set<String> = []
    @State private var wantHTML = true
    @State private var wantAPI = false
    @State private var scanning = false
    @State private var loading = false
    @State private var progress = ""
    @State private var message = ""
    @State private var shareItem: ShareItem? = nil

    private func shown(_ k: DesmRes.Kind) -> [DesmRes] { items.filter { $0.kind == k && (includeVendor || !$0.vendor) } }

    private func scan() {
        scanning = true; message = ""
        model.listPageResources { pg, list, err in
            scanning = false; page = pg; items = list; message = err
            selected = Set(list.filter { !$0.vendor }.map { $0.id })
        }
    }

    private func save(_ text: String, name: String, ext: String) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(f.string(from: Date())).\(ext)")
        do { try text.write(to: url, atomically: true, encoding: .utf8); shareItem = ShareItem(url: url) }
        catch { message = "Không lưu được file: \(error.localizedDescription)" }
    }

    private func run() {
        let css = shown(.css).filter { selected.contains($0.id) }, js = shown(.js).filter { selected.contains($0.id) }
        let jobs = css + js
        guard wantHTML || wantAPI || !jobs.isEmpty else { message = "Hãy chọn ít nhất một mục."; return }
        loading = true; message = ""
        var out = "DESM — MÃ NGUỒN TRANG ĐANG MỞ\nTrang: \(page)\n"
        var bad = 0
        func finish() {
            loading = false; progress = ""
            save(out, name: "desm-source", ext: "txt")
            if bad > 0 { message = "\(bad) mục không tải được (đã ghi lỗi trong file)." }
        }
        func apiStep() {
            guard wantAPI else { finish(); return }
            progress = "Đang lấy nhật ký API…"
            model.fetchNetLog(format: .json) { text, err in
                if let text = text { out += "\n\n===== NHẬT KÝ API (JSON) =====\n\(text)" }
                else { bad += 1; out += "\n\n===== NHẬT KÝ API =====\nLỖI: \(err.isEmpty ? "chưa ghi request nào — bật Ghi API rồi thao tác trên trang" : err)" }
                finish()
            }
        }
        func fileStep(_ i: Int) {
            if i >= jobs.count { apiStep(); return }
            progress = "Đang tải \(i + 1)/\(jobs.count)…"
            model.fetchResource(jobs[i].url) { f, err in
                if let f = f {
                    out += "\n\n===== \(jobs[i].kind == .css ? "CSS" : "JS") \(f.url) =====\nHTTP \(f.status) · \(f.contentType.isEmpty ? "?" : f.contentType) · \(f.text.count) ký tự\n\n\(f.text)"
                    if f.status >= 400 { bad += 1 }
                } else { bad += 1; out += "\n\n===== \(jobs[i].url) =====\nLỖI: \(err)" }
                fileStep(i + 1)
            }
        }
        if wantHTML {
            progress = "Đang lấy HTML trang…"
            model.fetchHTML(stripValues: false, stripScripts: false) { html, err in
                if let html = html { out += "\n\n===== HTML TRANG (đã dựng, gồm iframe cùng domain) =====\n\(html)" }
                else { bad += 1; out += "\n\n===== HTML TRANG =====\nLỖI: \(err)" }
                fileStep(0)
            }
        } else { fileStep(0) }
    }

    private func listSection(_ title: String, _ k: DesmRes.Kind) -> some View {
        let list = shown(k)
        let allSel = !list.isEmpty && list.allSatisfy { selected.contains($0.id) }
        return Section {
            if list.isEmpty { Text("Không thấy file nào.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(list) { r in
                Button {
                    if selected.contains(r.id) { selected.remove(r.id) } else { selected.insert(r.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected.contains(r.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(r.id) ? Color.tabBlue : Color.secondary)
                        Text(r.label).font(.system(size: 13, design: .monospaced)).foregroundStyle(.primary).lineLimit(1)
                    }
                }
            }
        } header: {
            HStack {
                Text("\(title) (\(list.count))")
                Spacer()
                if !list.isEmpty {
                    Button(allSel ? "Bỏ chọn" : "Chọn hết") {
                        if allSel { list.forEach { selected.remove($0.id) } } else { list.forEach { selected.insert($0.id) } }
                    }.font(.system(size: 12, weight: .semibold)).textCase(nil)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !page.isEmpty { Text(page).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3) }
                    Button { run() } label: {
                        HStack { if loading { ProgressView() }; Text(loading ? progress : "Tải mục đã chọn và chia sẻ file…").fontWeight(.semibold) }
                    }.disabled(loading || scanning)
                    if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.orange) }
                } header: { Text("Trang đang mở") }

                Section {
                    Toggle("HTML của trang (đã dựng, gồm iframe)", isOn: $wantHTML)
                    Toggle("Nhật ký API đã ghi", isOn: $wantAPI)
                    Toggle("Ghi lại API khi thao tác trang", isOn: $netLogOn).onChange(of: netLogOn) { model.setNetLog($0) }
                    Toggle("Gồm cả thư viện (.min, ext, jQuery…)", isOn: $includeVendor)
                } header: { Text("Chọn loại") } footer: {
                    Text("API: bật công tắc ghi, thao tác trên trang DESM (Search, mở chi tiết…) rồi quay lại mục này, bật \"Nhật ký API đã ghi\" và tải.")
                }

                if scanning { Section { HStack { ProgressView(); Text("Đang quét file của trang…") } } }
                else {
                    listSection("CSS", .css)
                    listSection("Script JS", .js)
                }
            }
            .navigationTitle("Mã nguồn trang này")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button { scan() } label: { Image(systemName: "arrow.clockwise") }.disabled(scanning || loading) }
            }
            .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
        }
        .onAppear { if items.isEmpty && !scanning { scan() } }
    }
}
