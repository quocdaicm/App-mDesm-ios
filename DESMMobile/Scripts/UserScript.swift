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
          // Nhật ký thao tác ghi (Thêm > Nhật ký thao tác ghi): báo cho app trước và sau mỗi lệnh lưu. Lỗi ở đây KHÔNG được làm hỏng thao tác lưu.
          function auditJson(v) { try { return JSON.stringify(v); } catch (e) { return ''; } }
          function auditBegin(label, path, payload, before) {
            var id = 'j' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
            try { w.webkit.messageHandlers.desmAudit.postMessage({ op: 'begin', id: id, label: label, path: path, payload: String(payload == null ? '' : payload), before: String(before == null ? '' : before) }); } catch (e) {}
            return id;
          }
          function auditEnd(id, status, resp, err) {
            try { w.webkit.messageHandlers.desmAudit.postMessage({ op: 'end', id: id, status: status, resp: String(resp == null ? '' : resp).slice(0, 6000), err: String(err == null ? '' : err) }); } catch (e) {}
          }

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
                // Trang có thể dựng lại lưới sau khi tìm: áp lại dạng thẻ để không lộ khung bảng xanh
                [700, 1600, 3500].forEach(function(ms) { setTimeout(function() { try { cardView(doc); } catch (e) {} }, ms); });
              }
              setTimeout(refresh, 120);
            }, false);
            setCollapsed(true);   // mặc định gọn: chỉ hiện hàng tìm nhanh + nút Bộ lọc; bấm "Bộ lọc" để xổ ra
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
          function diSave(idoc, list, ok, bad, before) {
            var top = diTop(idoc), W = idoc.defaultView, $j = null;
            try { $j = W.jQuery || W.$ || top.jQuery || top.$; } catch (e) {}
            var aid = auditBegin('Hạng mục chi tiết (Save)', '/saveIdsmOsDetailList.do', auditJson(list), auditJson(before));
            if (!$j || !$j.ajax) { auditEnd(aid, 'notsent', '', 'không tìm thấy jQuery của trang'); bad('không tìm thấy jQuery của trang'); return; }
            try {
              $j.ajax({ url: '/saveIdsmOsDetailList.do', data: { list: JSON.stringify(list) }, timeout: 30000,
                success: function(r) {
                  if (r && r.error != null) { auditEnd(aid, 'rejected', auditJson(r), String(r.error)); bad(String(r.error)); }
                  else { auditEnd(aid, 'ok', auditJson(r), ''); ok(r); }
                },
                error: function(x, st) { auditEnd(aid, 'unknown', 'HTTP ' + (x && x.status) + ' ' + String((x && x.responseText) || '').slice(0, 1500), st); bad('lỗi mạng hoặc hết phiên (' + st + '). Kiểm tra trên web xem đã lưu chưa.'); } });
            } catch (e) { auditEnd(aid, 'notsent', '', 'không gửi được yêu cầu'); bad('không gửi được yêu cầu'); }
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
                var before = { PACKAGE_NO: x.PACKAGE_NO, MATERIAL_CODE: x.MATERIAL_CODE, TRK_ITEM_NAME: x.TRK_ITEM_NAME, REMARKS: x.REMARKS == null ? '' : x.REMARKS };
                ['REPORT_SHORT', 'REPORT_OVER', 'REPORT_DMG', 'REPORT_MISSING'].forEach(function(c) { before[c] = x[c] == null ? '' : x[c]; before[c + '_QTY'] = x[c + '_QTY'] == null ? '' : x[c + '_QTY']; });
                diSave(idoc, [row], function() {
                  svBtn.disabled = false; svMsg.style.color = '#15803d'; svMsg.textContent = 'Đã lưu ✓';
                  x.REMARKS = row.REMARKS;
                  ['REPORT_SHORT', 'REPORT_OVER', 'REPORT_DMG', 'REPORT_MISSING'].forEach(function(c) { x[c] = row[c]; x[c + '_QTY'] = row[c + '_QTY']; });
                  flds.forEach(function(f) { f.orig = row[f.col + '_QTY']; });
                  try { delete (diTop(idoc).__desmDI || {})[pkgNo]; } catch (e) {}
                  try { if (ov.parentNode) loadItems(true); } catch (e) {}
                }, function(msg) {
                  svBtn.disabled = false; svMsg.style.color = '#dc2626'; svMsg.textContent = 'Lưu thất bại: ' + msg;
                }, before);
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
            // Lấy lưới MỚI NHẤT còn gắn trong trang: sau khi bấm Search trang có thể dựng lại lưới, lưới cũ còn nằm trong TGGrids nhưng đã bị gỡ khỏi DOM
            for (var gi = win.TGGrids.length - 1; gi >= 0; gi--) {
              var g = win.TGGrids[gi];
              if (g && g.Cols && g.Cols.PACKAGE_NO && g.Cols.STORAGE_LOCATION && g.Rows && g.MainTag && doc.documentElement.contains(g.MainTag)) { G = g; break; }
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
              try { win.__desmItems = null; } catch (e) {}
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
            try { win.__desmItems = { t: Date.now(), items: items }; } catch (e) {}   // Dodo: dữ liệu đang hiển thị trên màn hình
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
          // au (tuỳ chọn) = { label, payload, before }: chỉ truyền cho lệnh LƯU để ghi nhật ký thao tác ghi
          function mrrPost(win, url, data, ok, bad, au) {
            var aid = au ? auditBegin(au.label, url, au.payload, au.before) : null;
            function end(s, r, e) { if (aid) auditEnd(aid, s, r, e); }
            var $j = null; try { $j = win.jQuery || win.$; } catch (e) {}
            if (!$j || !$j.ajax) { end('notsent', '', 'không tìm thấy jQuery của trang'); bad('không tìm thấy jQuery của trang'); return; }
            try {
              $j.ajax({ url: url, data: data, timeout: 30000,
                success: function(d) {
                  if (aid) { if (d && d.error != null) end('rejected', auditJson(d), String(d.error)); else end('ok', auditJson(d), ''); }
                  ok(d);
                },
                error: function(x, st) { end('unknown', 'HTTP ' + (x && x.status) + ' ' + String((x && x.responseText) || '').slice(0, 1500), st); bad('lỗi mạng hoặc hết phiên (' + st + ')'); } });
            } catch (e) { end('notsent', '', 'không gửi được yêu cầu'); bad('không gửi được yêu cầu'); }
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
                  lines.forEach(function(l, i) { if (sel[i]) { if (!l.__orig) l.__orig = { RECEIVED_DATE: l.RECEIVED_DATE, VISUAL_CHECK: l.VISUAL_CHECK, VISUAL_CHECK_DATE: l.VISUAL_CHECK_DATE }; l.RECEIVED_DATE = v; l.__chg = 1; } });
                  msgEl.style.color = ''; msgEl.textContent = 'Đã đặt Received Date ' + v + ' (chưa lưu).'; refreshCards();
                });
                var vs = doc.createElement('select'); vs.className = 'desm-sub-in desm-mrr-in';
                ['Good', 'Defect'].forEach(function(o) { var op = doc.createElement('option'); op.value = o; op.textContent = o; vs.appendChild(op); });
                var vb = el('button', 'desm-detail-list', 'Đặt Visual Check cho dòng đã chọn'); vb.type = 'button';
                vb.addEventListener('click', function() {
                  if (!nSel()) { msgEl.style.color = '#dc2626'; msgEl.textContent = 'Chưa chọn dòng nào.'; return; }
                  lines.forEach(function(l, i) { if (sel[i]) { if (!l.__orig) l.__orig = { RECEIVED_DATE: l.RECEIVED_DATE, VISUAL_CHECK: l.VISUAL_CHECK, VISUAL_CHECK_DATE: l.VISUAL_CHECK_DATE }; l.VISUAL_CHECK = vs.value; l.__chg = 1; } });
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
                  var beforeRows = chg.map(function(l) { var o = { MRR_LINE_ID: l.MRR_LINE_ID, PACKAGE_NO: l.PACKAGE_NO }, g = l.__orig || {}; for (var k in g) o[k] = g[k] == null ? '' : g[k]; return o; });
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
                  }, function(m) { sv.disabled = false; err('Lưu thất bại: ' + m); },
                  { label: 'MRR ' + (H.MRR_NO || hid) + ' (sửa dòng)', payload: auditJson(Object.assign({}, pd, { updateList: list })), before: auditJson(beforeRows) });
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
            try { if (base.closest && base.closest('.dodo-msgs')) return; } catch (e) {}   // không dịch câu trả lời của Dodo
            viAttrs(base);
            var els = base.querySelectorAll('[placeholder],[title],[alt],input[type=button],input[type=submit],input[type=reset]');
            for (var i = 0; i < els.length; i++) viAttrs(els[i]);
            var tw = doc.createTreeWalker(base, 4, null), n;
            while ((n = tw.nextNode())) { if (n.parentNode && n.parentNode.closest && n.parentNode.closest('.dodo-msgs')) continue; viText(n); }
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
}
