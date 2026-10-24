import SwiftUI
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
    @Published var errorMessage: String?
    @Published var toast: String?
    /// Ẩn thanh trên + thanh dưới (tự ẩn khi vào được trang DESM, bấm nút nổi để hiện lại)
    @Published var barsHidden = false
    private var wasInDesm = false
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
    func goBack() { if webView?.canGoBack == true { webView?.goBack() } }
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
              setTimeout(poll, 400);
            })();
          }
          function diLoad(idoc, pkg, cb) {
            var top = diTop(idoc), cache = top.__desmDI = top.__desmDI || {};
            if (cache[pkg]) { cb(cache[pkg]); return; }
            function run(done) {
              diFrame(top, function(w) {
                var G = w && diGrid(w);
                if (!G) { done(null); return; }
                var d = w.document, inp = d.getElementById('txtPackageNo'), pl = d.getElementById('txtPackingListNo');
                function setv(x, v) { x.value = v; ['input', 'change'].forEach(function(n) { x.dispatchEvent(new w.Event(n, { bubbles: true })); }); }
                setv(inp, pkg); if (pl && pl.value) setv(pl, '');
                d.getElementById('btnSearch').click();
                var t0 = Date.now(), last = '', stable = 0;
                (function poll() {
                  var all = diRows(G), hit = all.filter(function(r) { return gridText(G, r, 'PACKAGE_NO') === pkg; });
                  var sig = all.length + '|' + hit.length; stable = sig === last ? stable + 1 : 0; last = sig;
                  var el = Date.now() - t0;
                  if ((hit.length && stable >= 3 && el > 1500) || (!all.length && stable >= 6 && el > 4000) || el > 20000) {
                    done(hit.map(function(r) {
                      var o = {}; ['PACKAGE_NO', 'DESCRIPTION', 'DRAWING_NO', 'TAG_NO', 'REMARKS', 'COMMENTS', 'MATERIAL_CODE', 'LOCATION'].forEach(function(c) { o[c] = gridText(G, r, c); });
                      o._id = r.id;
                      return o;
                    }));
                    return;
                  }
                  setTimeout(poll, 400);
                })();
              });
            }
            top.__desmDIq = (top.__desmDIq || Promise.resolve()).then(function() {
              return new Promise(function(res) { run(function(rows) { if (rows) cache[pkg] = rows; cb(rows); res(); }); });
            });
          }
          var DI_HIDE = 'position:fixed;left:-200vw;top:0;width:100vw;height:80vh;border:0;opacity:0;pointer-events:none;';
          // Chọn đúng các hạng mục trong lưới ẩn (xs = mảng) rồi bấm nút Location Update gốc của trang "Hạng mục chi tiết"
          function diSelect(idoc, pkg, xs, cb) {
            var top = diTop(idoc);
            function same(G, r, x) {
              return gridText(G, r, 'PACKAGE_NO') === pkg && gridText(G, r, 'MATERIAL_CODE') === x.MATERIAL_CODE &&
                gridText(G, r, 'TAG_NO') === x.TAG_NO && gridText(G, r, 'DESCRIPTION') === x.DESCRIPTION;
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
              });
            }
            attempt(false);
          }
          // Đưa khung ẩn lên toàn màn hình (để thao tác hộp thoại cập nhật vị trí của DESM), có thanh "Xong" để quay lại
          function diShow(idoc, onClose) {
            var top = diTop(idoc), D = top.document, fr = D.getElementById('desmDetailFrame'); if (!fr) { onClose(); return; }
            var bar = D.createElement('div'); bar.id = 'desmDetailFrameBar';
            bar.className = 'desm-detail-top desm-frame-bar';
            bar.style.cssText = 'position:fixed;left:0;top:0;right:0;z-index:2147483200;';
            var b = D.createElement('button'); b.type = 'button'; b.className = 'desm-detail-back'; b.textContent = '‹  Xong';
            var t = D.createElement('div'); t.className = 'desm-detail-title'; t.textContent = 'Cập nhật vị trí hạng mục';
            bar.appendChild(b); bar.appendChild(t); D.body.appendChild(bar);
            fr.style.cssText = 'position:fixed;left:0;top:calc(59px + env(safe-area-inset-top));width:100vw;height:calc(100vh - 59px - env(safe-area-inset-top));' +
              'border:0;opacity:1;pointer-events:auto;z-index:2147483100;background:#fff;';
            b.addEventListener('click', function() {
              if (bar.parentNode) bar.parentNode.removeChild(bar);
              fr.style.cssText = DI_HIDE;
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
            function loadItems() {
              note.textContent = 'Đang tải danh sách hạng mục…';
              diLoad(idoc, pkgNo, function(rows) {
                if (!ov.parentNode) return;
                if (!rows) { note.textContent = 'Không tải được danh sách hạng mục (trang "Hạng mục chi tiết" chưa sẵn sàng). Đóng rồi mở lại để thử lần nữa.'; return; }
                renderItems(rows);
              });
            }
            // Cập nhật vị trí cho một hoặc nhiều hạng mục (như nút Location Update ở trang Hạng mục chi tiết)
            function updateItemsLoc(xs) {
              note.textContent = 'Đang mở cập nhật vị trí…';
              diSelect(idoc, pkgNo, xs, function(ok) {
                if (!ok) { note.textContent = 'Không chọn được hạng mục (lưới chưa sẵn sàng). Thử lại sau vài giây.'; return; }
                note.textContent = '';
                diShow(idoc, function() {
                  try { delete (diTop(idoc).__desmDI || {})[pkgNo]; } catch (e) {}
                  if (ov.parentNode) loadItems();
                });
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
          w.__desmFindPkg = function(cfg) {
            var d = pkgDoc(document, 0);
            if (!d) { scanMsg({ status: 'nopage' }); return; }
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
          };
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

struct BrowserView: View {
    @StateObject private var model = BrowserModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var fabOffset: CGSize = .zero
    @State private var showScanner = false
    @GestureState private var fabDrag: CGSize = .zero

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
            if !model.barsHidden { bottomBar }
            // Khi thanh dưới ẩn: vẽ footer SVG ngay vùng an toàn dưới cùng (thanh Home), cùng kiểu header
            if model.barsHidden {
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
        .tint(.blue)
        .onChange(of: scenePhase) { phase in
            if phase != .active { model.saveSession() }
        }
        .alert("Không mở được địa chỉ", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .fullScreenCover(isPresented: $showScanner) {
            PackageScannerView { c in model.runScan(c) }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
                .presentationDetents([.medium, .large])
        }
    }

    /// Nút nổi mở camera quét Package No (chữ in hoặc viết tay)
    @ViewBuilder private var scanButton: some View {
        if model.inDesm {
            Button { showScanner = true } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(LinearGradient(colors: [Color(red: 0.11, green: 0.31, blue: 0.85),
                                                                      Color(red: 0.05, green: 0.65, blue: 0.91)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1.5))
                    .shadow(color: Color(red: 0.09, green: 0.15, blue: 0.33).opacity(0.45), radius: 6, y: 3)
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
                Circle().fill(LinearGradient(colors: [Color(red: 0.09, green: 0.15, blue: 0.33),
                                                      Color(red: 0.11, green: 0.31, blue: 0.85),
                                                      Color(red: 0.05, green: 0.65, blue: 0.91)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1.5))
            .overlay(alignment: .bottom) {
                Capsule().fill(Color(red: 0.98, green: 0.75, blue: 0.14)).frame(width: 16, height: 3).offset(y: -5)
            }
            .shadow(color: Color(red: 0.09, green: 0.15, blue: 0.33).opacity(0.45), radius: 6, y: 3)
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
        .background(Color(.systemBackground))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            navButton("chevron.left", title: "Quay lại", enabled: model.canGoBack) { model.goBack() }
            navButton("chevron.right", title: "Tiến", enabled: model.canGoForward) { model.goForward() }
            navButton("house.fill", title: "DESM", enabled: true) { model.home() }
            navButton("arrow.clockwise", title: "Tải lại", enabled: true) { model.reload() }
            navButton("safari", title: "Safari", enabled: true) {
                if let url = model.webView?.url { UIApplication.shared.open(url) }
            }
        }
        .padding(.top, 10).padding(.bottom, 5)
        .background(FooterBackground().ignoresSafeArea(edges: .bottom))
    }

    private func navButton(_ symbol: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.38))
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .disabled(!enabled)
    }
}

/// Footer vẽ bằng Canvas theo Branding/footer-bg.svg: gradient xanh, chấm mờ, hai lớp sóng, đường nhấn vàng-xanh ở mép trên.
struct FooterBackground: View {
    private let c1 = Color(red: 23 / 255, green: 37 / 255, blue: 84 / 255)
    private let c2 = Color(red: 29 / 255, green: 78 / 255, blue: 216 / 255)
    private let c3 = Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255)

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 400 * w, y: y / 28 * h) }
            // nền gradient ngang
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(stops: [.init(color: c1, location: 0), .init(color: c2, location: 0.55), .init(color: c3, location: 1)]),
                                           startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
            // chấm mờ
            var dots = Path()
            var y: CGFloat = 2
            while y < h {
                var x: CGFloat = 2
                while x < w { dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)); x += 12 }
                y += 12
            }
            ctx.fill(dots, with: .color(.white.opacity(0.14)))
            // sóng 1
            var a = Path()
            a.move(to: pt(0, 12))
            a.addCurve(to: pt(205, 11), control1: pt(70, 2), control2: pt(130, 20))
            a.addCurve(to: pt(400, 10), control1: pt(280, 2), control2: pt(335, 3))
            a.addLine(to: pt(400, 28)); a.addLine(to: pt(0, 28)); a.closeSubpath()
            ctx.fill(a, with: .color(.white.opacity(0.10)))
            // sóng 2
            var b = Path()
            b.move(to: pt(0, 19))
            b.addCurve(to: pt(230, 18), control1: pt(80, 10), control2: pt(150, 25))
            b.addCurve(to: pt(400, 17), control1: pt(310, 11), control2: pt(350, 11))
            b.addLine(to: pt(400, 28)); b.addLine(to: pt(0, 28)); b.closeSubpath()
            ctx.fill(b, with: .color(.white.opacity(0.08)))
            // đường nhấn vàng -> xanh -> trong suốt ở mép trên
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: 2.5)),
                     with: .linearGradient(Gradient(stops: [
                        .init(color: Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255), location: 0),
                        .init(color: Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255), location: 0.5),
                        .init(color: Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255).opacity(0), location: 1)]),
                                           startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
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

struct SettingsView: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var shareItem: ShareItem?
    @AppStorage("desmExportStripValues") private var stripValues = true
    @AppStorage("desmRememberLogin") private var rememberLogin = true
    @AppStorage("desmAutofill") private var autofill = true
    @AppStorage("desmExportStripScripts") private var stripScripts = true
    @AppStorage("desmScanOpenDetail") private var scanOpenDetail = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Chế độ hiển thị") {
                    Picker("Chế độ", selection: Binding(
                        get: { model.layoutMode },
                        set: { model.setMode($0) }
                    )) {
                        ForEach(LayoutMode.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Stepper("Độ rộng khi thu nhỏ: \(model.fitWidth)px", value: Binding(
                        get: { model.fitWidth },
                        set: { model.fitWidth = $0; model.applyStyles() }
                    ), in: 700...1800, step: 100)

                    Toggle("Chỉ áp dụng cho DESM", isOn: Binding(
                        get: { model.scopeOnly },
                        set: { model.scopeOnly = $0; model.applyStyles() }
                    ))
                    Toggle("Thu gọn thanh trên", isOn: $model.compactHeader)

                    Text("Mobile: sắp xếp lại bố cục bằng CSS. Vừa màn hình: hiển thị bản desktop thu nhỏ vừa màn hình, có thể phóng to bằng hai ngón. Gốc: không can thiệp.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Ngôn ngữ") {
                    Toggle("Giao diện DESM bằng tiếng Việt", isOn: Binding(
                        get: { model.viLang },
                        set: { model.setVietnamese($0) }
                    ))
                    Text("Dịch nhãn, nút, menu, tiêu đề cột, hộp thoại của trang DESM sang tiếng Việt (dữ liệu như mã kiện, mô tả hàng, vị trí giữ nguyên). Cũng có thể chọn \"Tiếng Việt\" ngay ở ô Language trên trang. Nên để ngôn ngữ gốc của trang là English.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Từ điển bổ sung (mỗi dòng: English = Tiếng Việt)").font(.footnote.weight(.semibold))
                    TextEditor(text: $model.customDict)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 100)
                    Button("Áp dụng từ điển") { model.applyStyles(); model.showToast("Đã áp dụng từ điển"); dismiss() }
                    Button("Sao chép chuỗi chưa dịch") {
                        model.copyMissingStrings { message = $0 }
                    }
                }
                Section("Quét Package No (camera)") {
                    Toggle("Quét xong mở luôn chi tiết kiện", isOn: $scanOpenDetail)
                    Text("Bấm nút camera ở góc dưới bên trái khi đang ở màn hình Package. App đọc số Package No trên tem (chữ in hoặc viết tay, kể cả viết tắt kiểu DE-LS-01-07), điền ô Số kiện hàng rồi Search. Tắt công tắc này để chỉ tìm và chọn dòng, không mở chi tiết. Nếu không có dòng khớp chính xác thì app báo không tìm thấy, không mở nhầm kiện.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Đăng nhập") {
                    Toggle("Ghi nhớ phiên đăng nhập", isOn: $rememberLogin)
                    Toggle("Tự điền tài khoản ở trang đăng nhập", isOn: $autofill)
                    Button("Xóa tài khoản đã lưu", role: .destructive) {
                        CredStore.clear()
                        model.showToast("Đã xóa tài khoản đã lưu")
                    }
                    Button("Xóa phiên đã lưu", role: .destructive) {
                        SessionStore.clear()
                        model.showToast("Đã xóa phiên đã lưu")
                    }
                    Text("Phiên đăng nhập và tài khoản (chỉ khi bạn đồng ý lưu) được giữ trong Keychain của máy này, không gửi đi đâu khác. Nếu máy chủ DESM đã hết hạn phiên thì app hiện lại trang đăng nhập và tự điền sẵn tài khoản; bạn bấm Login để vào.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("CSS bổ sung") {
                    TextEditor(text: $model.customCSS)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 120)
                    Button("Áp dụng CSS") { model.applyStyles(); dismiss() }
                    Button("Xóa CSS bổ sung", role: .destructive) {
                        model.customCSS = ""
                        model.applyStyles()
                    }
                }
                Section("Hỗ trợ tinh chỉnh") {
                    Button("Sao chép cấu trúc trang đang mở") {
                        model.copyDiagnostics { message = $0 }
                    }
                    Text("Mở trang cần chỉnh (ví dụ màn hình Package), vào đây bấm nút trên rồi dán vào khung chat. Dữ liệu nhập trong ô không được sao chép.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Mã HTML của trang") {
                    Button("Sao chép HTML trang đang mở") {
                        model.fetchHTML(stripValues: stripValues, stripScripts: stripScripts) { html, error in
                            if let html = html {
                                UIPasteboard.general.string = html
                                message = "Đã sao chép \(html.count) ký tự HTML. Nếu quá dài để dán vào chat, hãy dùng \"Lưu HTML thành file\"."
                            } else {
                                message = error
                            }
                        }
                    }
                    Button("Lưu HTML thành file…") {
                        model.fetchHTML(stripValues: stripValues, stripScripts: stripScripts) { html, error in
                            guard let html = html else { message = error; return }
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyyMMdd-HHmmss"
                            let url = FileManager.default.temporaryDirectory
                                .appendingPathComponent("desm-page-\(formatter.string(from: Date())).html")
                            do {
                                try html.write(to: url, atomically: true, encoding: .utf8)
                                shareItem = ShareItem(url: url)
                            } catch {
                                message = "Không lưu được file: \(error.localizedDescription)"
                            }
                        }
                    }
                    Toggle("Ẩn giá trị trong ô nhập", isOn: $stripValues)
                    Toggle("Bỏ mã script nội tuyến", isOn: $stripScripts)
                    Text("Lấy HTML hiện tại của trang đang hiển thị (đã chạy script), gồm cả iframe cùng domain, không gồm CSS do app tiêm. HTML có thể chứa thông tin nội bộ, hãy kiểm tra trước khi chia sẻ. Giá trị bạn đang gõ trong ô nhập không nằm trong HTML.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cài đặt giao diện")
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
}
