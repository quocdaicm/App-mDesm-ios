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

    /// Gọi sau mỗi lần tải xong trang: vừa vào được DESM (không phải trang đăng nhập) thì tự ẩn thanh; rời DESM thì hiện lại.
    func updateBars(for url: URL?) {
        let host = url?.host?.lowercased() ?? ""
        let path = url?.path.lowercased() ?? ""
        let inDesm = BrowserModel.allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) } && !path.contains("login")
        if inDesm && !wasInDesm { withAnimation(.easeInOut(duration: 0.2)) { barsHidden = true } }
        if !inDesm && barsHidden { withAnimation(.easeInOut(duration: 0.2)) { barsHidden = false } }
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

    weak var webView: WKWebView?
    weak var contentController: WKUserContentController?

    init() {
        let ud = UserDefaults.standard
        layoutMode = LayoutMode(rawValue: ud.string(forKey: "desmLayoutMode") ?? "") ?? .mobile
        let w = ud.integer(forKey: "desmFitWidth")
        fitWidth = w == 0 ? 1280 : w
        scopeOnly = ud.object(forKey: "desmScopeOnly") as? Bool ?? true
        compactHeader = ud.object(forKey: "desmCompactHeader") as? Bool ?? true
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
            "css": MobileStyles.css + "\n" + customCSS
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
            var qp = pick(/^packing\s*list\s*no/i), qk = pick(/^package\s*no/i);
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
          // Lưới Package dạng thẻ (card): mỗi kiện hàng một thẻ gồm Package No, mô tả, loại kiện, A/O và Location.
          // Chạm thẻ = chọn dòng tương ứng trong lưới TreeGrid (ẩn bên dưới) để Location Update/Delete hoạt động.
          function cardView(doc) {
            var win = doc.defaultView; if (!win || !win.TGGrids || !win.TGGrids.length) return;
            var G = null;
            for (var gi = 0; gi < win.TGGrids.length; gi++) {
              var g = win.TGGrids[gi];
              if (g && g.Cols && g.Cols.PACKAGE_NO && g.Cols.STORAGE_LOCATION && g.Rows) { G = g; break; }
            }
            if (!G || !G.MainTag || !G.MainTag.parentNode) return;
            var host = G.MainTag.parentNode;
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
            var sig = items.map(function(i) { return [i.id, i.sel ? 1 : 0, i.no, i.desc, i.type, i.list, i.ao, i.loc, i.ok ? 1 : 0].join('|'); }).join('\n');
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
            items.forEach(function(it) {
              var card = el('div', 'desm-card' + (it.sel ? ' desm-sel' : '') + (it.ok ? ' desm-ok' : ''));
              var ck = doc.createElement('input'); ck.type = 'checkbox'; ck.className = 'desm-chk desm-card-chk';
              ck.checked = it.sel; card.appendChild(ck);
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
              card.addEventListener('click', function() {
                var r = G.Rows[it.id]; if (!r) return;
                try { G.SelectRow(r, isSel(r) ? 0 : 1); } catch (e) {}
                box.__sig = null; cardView(doc);
              });
              box.appendChild(card);
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
            try { cardView(doc); } catch (e) {}
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
              enhance(doc);
            } else {
              if (style) style.remove();
              if (root.classList.contains(CLS)) root.classList.remove(CLS);
              if (root.classList.contains('desm-nav-open')) root.classList.remove('desm-nav-open');
            }
            if (doc === document && w === w.top) setViewport(doc);
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

struct BrowserView: View {
    @StateObject private var model = BrowserModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var fabOffset: CGSize = .zero
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
            if !model.barsHidden { bottomBar }
        }
        .background(Color(.systemGroupedBackground))
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
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
                .presentationDetents([.medium, .large])
        }
    }

    /// Nút nổi duy nhất để ẩn/hiện cả thanh trên và thanh dưới; kéo để dời vị trí.
    private var barsToggleButton: some View {
        Image(systemName: model.barsHidden ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
            .font(.system(size: 30))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.blue)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .opacity(0.8)
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
        .padding(.top, 9).padding(.bottom, 5)
        .background(.ultraThinMaterial)
    }

    private func navButton(_ symbol: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(enabled ? Color.blue : Color.gray.opacity(0.4))
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .disabled(!enabled)
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
