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
                    var o = {}; ['PACKAGE_NO', 'DESCRIPTION', 'DRAWING_NO', 'TAG_NO', 'REMARKS', 'COMMENTS', 'MATERIAL_CODE', 'LOCATION'].forEach(function(c) { o[c] = gridText(G, r, c); });
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
                    var o = {}; ['PACKAGE_NO', 'DESCRIPTION', 'DRAWING_NO', 'TAG_NO', 'REMARKS', 'COMMENTS', 'MATERIAL_CODE', 'LOCATION'].forEach(function(c) { o[c] = nz(r[c]); });
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
              if (lu) lu.textContent = chosen.length ? 'Location Update (' + chosen.length + ' hạng mục)' : 'Location Update';
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
                c.appendChild(ck);
                c.appendChild(el('div', 'desm-ditem-no', x.PACKAGE_NO));
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
                c.addEventListener('click', function() {
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
            var LSK = 'desmDI:' + pkgNo, shown = null;
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
              var sv = ''; try { sv = win.localStorage.getItem('desmTapDetail') || ''; } catch (e) {}
              win.__desmTapDetail = sv === '1';
            }
            if (tb && !doc.getElementById('desmTapToggle')) {
              var tt = doc.createElement('button');
              tt.type = 'button'; tt.id = 'desmTapToggle'; tt.className = 'btn btn-secondary btn-sm';
              tt.addEventListener('click', function(e) {
                e.preventDefault(); e.stopPropagation();
                win.__desmTapDetail = !win.__desmTapDetail;
                try { win.localStorage.setItem('desmTapDetail', win.__desmTapDetail ? '1' : '0'); } catch (e2) {}
                box.__sig = null; cardView(doc);
              });
              tb.appendChild(tt);
            }
            var tt2 = doc.getElementById('desmTapToggle');
            if (tt2) tt2.textContent = win.__desmTapDetail ? 'Chạm: Chi tiết' : 'Chạm: Chọn';
            host.classList.toggle('desm-grid-off', on);
            box.style.display = on ? '' : 'none';
            if (!on) {
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
              card.appendChild(more);
              card.addEventListener('click', function(ev) {
                if (ev.target && ev.target.classList && ev.target.classList.contains('desm-card-hit')) {
                  try { G.SelectRow(it.r, it.sel ? 0 : 1); } catch (e) {}
                } else {
                  win.__desmGenOpen[it.id] = !win.__desmGenOpen[it.id];
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
            if (p.closest && p.closest('#desmCards, #desmDetail')) return;
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
            var b = D.querySelector('#desmDetailFrameBar .desm-detail-back') || D.querySelector('#desmDetail .desm-detail-back');
            if (b) { b.click(); return 1; }
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
    func runScan(_ c: PkgCandidate) {
        let open = UserDefaults.standard.object(forKey: "desmScanOpenDetail") as? Bool ?? true
        let cfg: [String: Any] = ["term": c.term, "key": c.key, "open": open]
        guard let d = try? JSONSerialization.data(withJSONObject: cfg),
              let js = String(data: d, encoding: .utf8) else { return }
        showToast("Đang tìm \(c.display)…")
        webView?.evaluateJavaScript("window.__desmFindPkg ? window.__desmFindPkg(\(js)) : 0;", completionHandler: nil)
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
    @State private var fabOffset: CGSize = .zero
    @State private var showScanner = false
    @State private var showScanChoice = false
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem? = nil
    @GestureState private var fabDrag: CGSize = .zero
    @State private var selectedTab: DesmTab = .package
    @State private var showMore = false

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
                .overlay(alignment: .bottomTrailing) { barsToggleButton }
                .overlay(alignment: .bottomLeading) { scanButton }
            // Trong DESM: footer 5 tab mới (luôn hiện). Ngoài DESM (trang đăng nhập...): thanh điều hướng cũ, ẩn thì chỉ còn dải an toàn.
            if model.inDesm {
                DesmTabBar(selected: $selectedTab,
                           onSelect: { tab in
                               if tab == .more { showMore = true }
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
            else { model.appBecameActive() }
        }
        .alert("Không mở được địa chỉ", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .fullScreenCover(isPresented: $showScanner) {
            PackageScannerView(onPick: { c in model.runScan(c) }, onQR: { d in model.runQRScan(d) })
        }
        .confirmationDialog("Quét mã", isPresented: $showScanChoice, titleVisibility: .visible) {
            Button("Quét bằng camera") { showScanner = true }
            Button("Chọn ảnh có sẵn") { showPhotoPicker = true }
            Button("Hủy", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
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
                    case .package(let c): model.runScan(c)
                    case .otherQR(let q):
                        UIPasteboard.general.string = q
                        model.showToast("QR chưa hỗ trợ, đã sao chép: \(q.prefix(60))")
                    case .none: model.showToast("Không thấy QR hoặc Package No trong ảnh")
                    }
                }
            }
        }
        .sheet(isPresented: $showMore) {
            MoreSheet(model: model, onClose: { showMore = false })
                .presentationDetents([.height(430)])
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $model.shotItem) { item in
            ShareSheet(url: item.url)
        }
    }

    /// Nút nổi mở camera quét Package No (chữ in hoặc viết tay)
    @ViewBuilder private var scanButton: some View {
        if model.inDesm {
            Button { showScanChoice = true } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(LinearGradient(colors: [Color(red: 0.20, green: 0.58, blue: 0.95),
                                                                      Color(red: 0.30, green: 0.72, blue: 0.98)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1.5))
                    .shadow(color: Color(red: 0.15, green: 0.40, blue: 0.80).opacity(0.30), radius: 6, y: 3)
            }
            .padding(12)
            .accessibilityLabel("Quét số kiện hàng bằng camera")
        }
    }

    /// Nút nổi duy nhất để ẩn/hiện cả thanh trên và thanh dưới; kéo để dời vị trí.
    private var barsToggleButton: some View {
        Image(systemName: model.barsHidden ? "chevron.down" : "chevron.up")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                Circle().fill(LinearGradient(colors: [Color(red: 0.14, green: 0.40, blue: 0.88),
                                                      Color(red: 0.20, green: 0.58, blue: 0.95)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1.5))
            .overlay(alignment: .bottom) {
                Capsule().fill(Color(red: 0.98, green: 0.75, blue: 0.14)).frame(width: 16, height: 3).offset(y: -5)
            }
            .shadow(color: Color(red: 0.15, green: 0.40, blue: 0.80).opacity(0.30), radius: 6, y: 3)
            .opacity(0.92)
            .padding(12)
            .offset(x: fabOffset.width + fabDrag.width, y: fabOffset.height + fabDrag.height)
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { model.barsHidden.toggle() } }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .updating($fabDrag) { v, state, _ in state = v.translation }
                    .onEnded { v in fabOffset.width += v.translation.width; fabOffset.height += v.translation.height }
            )
            .accessibilityLabel(model.barsHidden ? "Hiện thanh công cụ" : "Ẩn thanh công cụ")
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
        case .inbound: return "Nhập kho"
        case .outbound: return "Xuất kho"
        case .report: return "Báo cáo"
        case .more: return "Thêm"
        }
    }
    var symbol: String {
        switch self {
        case .package: return "shippingbox"
        case .inbound: return "square.and.arrow.down"
        case .outbound: return "square.and.arrow.up"
        case .report: return "chart.bar.xaxis"
        case .more: return "square.grid.2x2"
        }
    }
    /// id thẻ <a> trong menu (đã biết: 196 = Kiện hàng). nil = tìm theo tên.
    var menuId: String? { self == .package ? "196" : nil }
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
    var onSelect: (DesmTab) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DesmTab.allCases) { tab in
                let on = tab == selected
                Button { onSelect(tab) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: on ? .semibold : .regular))
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

/// Mục "Thêm": các nút điều hướng/công cụ cũ của thanh dưới + mở menu đầy đủ, Cài đặt.
struct MoreSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { model.applyStyles(); dismiss() } } }
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
            }
            .alert("Kết quả", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
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
            Text("Bấm nút camera ở góc dưới bên trái khi đang ở màn hình Package. App đọc Package No trên tem, điền ô Số kiện hàng rồi Search. Không có dòng khớp chính xác thì báo không tìm thấy, không mở nhầm kiện.")
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
