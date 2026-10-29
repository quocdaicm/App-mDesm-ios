// DodoBubble.swift — nút bong bóng chat Dodo (trợ lý AI của DESM) + khung chat vừa màn hình điện thoại.
// Dodo là widget có sẵn của web (/resources/scripts/util/Dodo.js → /dodo/chat/stream.do, sessions, history, reset, delete).
// Script này CHỈ chạy ở khung trên cùng (không chạy trong iframe), dùng lại Dodo.js của trang (hoặc tự nạp nếu thiếu).

import Foundation
import WebKit

extension BrowserModel {
    func makeDodoScript() -> String {
        let on = dodoBubble ? "true" : "false"
        let vi = dodoVi ? "true" : "false"
        let slow = dodoSlow ? "true" : "false"
        let data = dodoData ? "true" : "false"
        let engine = aiEngine == "ai" ? "ai" : "dodo"
        let hosts = (try? JSONSerialization.data(withJSONObject: BrowserModel.allowedHosts, options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return #"""
        (function() {
          var w = window;
          try { if (w !== w.top) return; } catch (e) { return; }
          w.__desmDodoOn = \#(on);
          w.__desmDodoVi = \#(vi);
          w.__desmDodoSlow = \#(slow);
          w.__desmDodoData = \#(data);
          w.__desmDodoEngine = '\#(engine)';
          if (w.__desmDodo) { try { w.__desmDodo.sync(); } catch (e) {} return; }
          var host = (location.hostname || '').toLowerCase();
          var okHost = \#(hosts).some(function(s) { return host === s || host.endsWith('.' + s); });
          if (!okHost) return;

          var BTN = 'desm-dodo-btn', STY = 'desm-dodo-style', TOAST = 'desm-dodo-toast';
          var AVATAR = '/resources/img/bear-assistant.png';
          var ST = { inited: false, loading: false, queue: [], pos: null, btn: null };
          var CSS = [
            '.dodo-fab{display:none!important}',
            '#' + BTN + '{position:fixed;width:56px;height:56px;padding:0;border-radius:50%;border:2px solid #fff;background:#fff;',
            ' box-shadow:0 6px 18px rgba(28,40,90,.35);z-index:2147483100;touch-action:none;-webkit-tap-highlight-color:transparent;',
            ' display:flex;align-items:center;justify-content:center;transition:transform .15s}',
            '#' + BTN + ':active{transform:scale(.93)}',
            '#' + BTN + ' img{width:100%;height:100%;border-radius:50%;object-fit:cover;pointer-events:none;-webkit-user-drag:none}',
            '#' + BTN + ' .dd-fb{font-size:26px;line-height:1;pointer-events:none}',
            '#' + BTN + ' .dd-dot{position:absolute;right:0;top:0;width:13px;height:13px;border-radius:50%;background:#22c55e;border:2px solid #fff;pointer-events:none}',
            '.dodo-win.dodo-open{left:0!important;right:0!important;width:100%!important;max-width:100%!important;',
            ' top:calc(var(--dd-top,0px) + env(safe-area-inset-top,0px) + 6px)!important;',
            ' height:calc(var(--dd-h,100%) - env(safe-area-inset-top,0px) - 6px)!important;max-height:none!important;',
            ' border-radius:16px 16px 0 0!important;z-index:2147483150!important}',
            '.dodo-rz{display:none!important}',
            '.dodo-head{cursor:default!important}',
            '.dodo-input{font-size:16px!important}',
            '.dodo-input-row{padding-bottom:calc(14px + env(safe-area-inset-bottom,0px))!important}',
            'html.desm-dd-kb .dodo-input-row{padding-bottom:14px!important}',
            '#' + TOAST + '{position:fixed;left:50%;transform:translateX(-50%);bottom:calc(env(safe-area-inset-bottom,0px) + 90px);max-width:86%;',
            ' padding:9px 16px;border-radius:999px;background:rgba(30,42,74,.94);color:#fff;font:13px/1.4 -apple-system,sans-serif;',
            ' z-index:2147483300;text-align:center}'
          ].join('');

          function on() { return !!w.__desmDodoOn && !/login/i.test(location.pathname); }
          function loadPos() {
            try { var p = JSON.parse(w.localStorage.getItem('desmDodoPos') || 'null'); if (p && (p.side === 'l' || p.side === 'r') && isFinite(p.y)) return p; } catch (e) {}
            return { side: 'r', y: Math.max(80, w.innerHeight - 150) };
          }
          function savePos() { try { w.localStorage.setItem('desmDodoPos', JSON.stringify(ST.pos)); } catch (e) {} }
          function place() {
            var b = ST.btn; if (!b) return;
            if (!ST.pos) ST.pos = loadPos();
            var y = Math.min(Math.max(ST.pos.y, 8), Math.max(8, w.innerHeight - 64));
            b.style.top = y + 'px'; b.style.bottom = 'auto';
            if (ST.pos.side === 'l') { b.style.left = '10px'; b.style.right = 'auto'; }
            else { b.style.right = '10px'; b.style.left = 'auto'; }
          }
          function toast(msg) {
            try {
              var old = document.getElementById(TOAST); if (old) old.remove();
              var t = document.createElement('div'); t.id = TOAST; t.textContent = msg;
              (document.body || document.documentElement).appendChild(t);
              w.setTimeout(function() { try { t.remove(); } catch (e) {} }, 3200);
            } catch (e) {}
          }
          function vv() {
            var v = w.visualViewport, r = document.documentElement; if (!v || !r) return;
            r.style.setProperty('--dd-top', v.offsetTop + 'px');
            r.style.setProperty('--dd-h', v.height + 'px');
            r.classList.toggle('desm-dd-kb', w.innerHeight - v.height > 120);
          }
          function dodoInit() {
            if (ST.inited) return;
            ST.inited = true;
            if (document.querySelector('.dodo-root')) return;   // trang đã tự khởi tạo Dodo
            try {
              w.Dodo.init({
                launcher: false,
                title: 'Dodo AI',
                subtitle: 'Trợ lý DESM',
                welcome: 'Xin chào! Mình là Dodo, trợ lý AI của DESM. Bạn cần hỏi gì?',
                placeholder: 'Hỏi Dodo bất cứ điều gì',
                onUnauthorized: function() {
                  try { w.Dodo.close(); } catch (e) {}
                  toast('Phiên đã hết hạn — hãy đăng nhập lại rồi mở Dodo.');
                }
              });
            } catch (e) { ST.inited = false; }
          }
          function ensure(cb) {
            if (w.Dodo) { dodoInit(); cb(); return; }
            ST.queue.push(cb);
            if (ST.loading) return;
            ST.loading = true;
            var s = document.createElement('script');
            s.src = '/resources/scripts/util/Dodo.js';
            s.onload = function() {
              ST.loading = false;
              var q = ST.queue.splice(0);
              if (!w.Dodo) { toast('Không dùng được Dodo trên trang này.'); return; }
              dodoInit(); q.forEach(function(f) { try { f(); } catch (e) {} });
            };
            s.onerror = function() { ST.loading = false; ST.queue = []; toast('Không tải được Dodo. Kiểm tra kết nối.'); };
            (document.head || document.documentElement).appendChild(s);
          }
          function openChat() {
            if (w.__desmDodoEngine === 'ai') {
              try { w.webkit.messageHandlers.desmAI.postMessage({}); } catch (e) { toast('Không mở được khung AI.'); }
              return;
            }
            ensure(function() { try { w.Dodo.open(); } catch (e) {} sync(); });
          }
          function mount() {
            var root = document.documentElement, body = document.body;
            if (!root || !body) return false;
            if (!document.getElementById(STY)) {
              var st = document.createElement('style'); st.id = STY; st.textContent = CSS; root.appendChild(st);
            }
            if (ST.btn && body.contains(ST.btn)) return true;
            var b = document.createElement('button');
            b.id = BTN; b.type = 'button'; b.setAttribute('aria-label', 'Chat với Dodo');
            var img = document.createElement('img'); img.alt = ''; img.src = AVATAR;
            img.onerror = function() { img.remove(); var f = document.createElement('span'); f.className = 'dd-fb'; f.textContent = '💬'; b.insertBefore(f, b.firstChild); };
            b.appendChild(img);
            var dot = document.createElement('span'); dot.className = 'dd-dot'; b.appendChild(dot);
            var drag = null;
            b.addEventListener('pointerdown', function(e) {
              var r = b.getBoundingClientRect();
              drag = { sx: e.clientX, sy: e.clientY, x0: r.left, y0: r.top, moved: false };
              try { b.setPointerCapture(e.pointerId); } catch (x) {}
            });
            b.addEventListener('pointermove', function(e) {
              if (!drag) return;
              var dx = e.clientX - drag.sx, dy = e.clientY - drag.sy;
              if (!drag.moved && Math.abs(dx) + Math.abs(dy) > 8) drag.moved = true;
              if (drag.moved) {
                b.style.left = (drag.x0 + dx) + 'px'; b.style.right = 'auto';
                b.style.top = (drag.y0 + dy) + 'px'; b.style.bottom = 'auto';
                e.preventDefault();
              }
            });
            b.addEventListener('pointerup', function() {
              if (!drag) return;
              var d = drag; drag = null;
              if (d.moved) {
                var r = b.getBoundingClientRect();
                ST.pos = { side: (r.left + r.width / 2 < w.innerWidth / 2) ? 'l' : 'r', y: r.top };
                savePos(); place();
              } else openChat();
            });
            b.addEventListener('pointercancel', function() { drag = null; place(); });
            body.appendChild(b);
            ST.btn = b; place();
            return true;
          }
          function sync() {
            try {
              if (!on()) { if (ST.btn) ST.btn.style.display = 'none'; return; }
              if (!mount()) return;
              var open = !!(w.Dodo && w.Dodo.isOpen && w.Dodo.isOpen());
              ST.btn.style.display = open ? 'none' : '';
              vv();
            } catch (e) {}
          }
          // Tìm dữ liệu kiện đang hiển thị (dạng thẻ) ở khung đang mở: cardView lưu vào window.__desmItems của khung đó
          function findItems(doc, depth) {
            try { var x = doc.defaultView.__desmItems; if (x && x.items && x.items.length) return x; } catch (e) {}
            if (depth > 4) return null;
            var fs = doc.querySelectorAll('iframe');
            for (var i = 0; i < fs.length; i++) {
              try {
                if (fs[i].id === 'desmDetailFrame' || !fs[i].contentDocument || fs[i].getClientRects().length === 0) continue;
                var r = findItems(fs[i].contentDocument, depth + 1); if (r) return r;
              } catch (e) {}
            }
            return null;
          }
          function cut(v, n) { v = String(v == null ? '' : v).replace(/[\r\n|]+/g, ' ').trim(); return v.length > n ? v.slice(0, n) : v; }
          function screenText() {
            var x = findItems(document, 0); if (!x) return '';
            var L = x.items.slice(0, 300);
            var lines = ['[Dữ liệu đang hiển thị trên màn hình Package: ' + x.items.length + ' kiện' + (x.items.length > L.length ? ' (chỉ gửi ' + L.length + ' kiện đầu)' : '') + ']',
              'Package No | Mô tả | Loại | Packing List | A/O | Vị trí | Xác nhận VL | Đang chọn'];
            L.forEach(function(i) { lines.push([cut(i.no, 40), cut(i.desc, 60), cut(i.type, 20), cut(i.list, 30), cut(i.ao, 12), cut(i.loc, 40), i.ok ? 'Y' : 'N', i.sel ? 'Y' : ''].join(' | ')); });
            return lines.join('\n');
          }
          // Đọc CẢ TRANG cho AI riêng: mọi khung đang hiện (kể cả iframe), toàn bộ dòng của các lưới TreeGrid đã tải (kể cả cột đang ẩn), ô nhập đang có giá trị, rồi văn bản trang. Cắt theo giới hạn ký tự.
          function pageText(limit) {
            limit = limit || 40000;
            var out = [], used = 0, cut0 = false;
            function push(s) { if (used >= limit) { cut0 = true; return false; } if (used + s.length > limit) { s = s.slice(0, limit - used); cut0 = true; } out.push(s); used += s.length + 1; return true; }
            function clean(v, n) { v = String(v == null ? '' : v).replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').replace(/[\r\n|]+/g, ' ').replace(/\s+/g, ' ').trim(); return v.length > n ? v.slice(0, n) : v; }
            function gtext(G, row, c) {
              var t = '';
              try { if (G.GetString) t = G.GetString(row, c); } catch (e) {}
              if (!t) { try { t = G.GetValue ? G.GetValue(row, c) : row[c]; } catch (e) {} }
              return clean(t, 80);
            }
            function grids(win, tag) {
              var n = 0;
              try {
                for (var i = 0; win.TGGrids && i < win.TGGrids.length; i++) {
                  var G = win.TGGrids[i];
                  if (!G || !G.Cols || !G.Rows || !G.Rows.Header || !G.MainTag || G.__desmFail) continue;
                  try { if (!G.MainTag.isConnected) continue; } catch (e) {}
                  var cols = [], heads = [];
                  for (var c in G.Cols) { var h = gtext(G, G.Rows.Header, c); if (h && c !== 'Panel' && c !== 'Select') { cols.push(c); heads.push(h); } }
                  if (!cols.length) continue;
                  var rows = [];
                  for (var id in G.Rows) { var r = G.Rows[id]; if (r && r.Kind === 'Data') rows.push(r); }
                  n++;
                  if (!push('[' + tag + ' — Lưới ' + n + ': ' + rows.length + ' dòng đã tải]')) return n;
                  if (!push(heads.join(' | '))) return n;
                  for (var k = 0; k < rows.length; k++) {
                    var cells = []; for (var j = 0; j < cols.length; j++) cells.push(gtext(G, rows[k], cols[j]));
                    if (!push(cells.join(' | '))) return n;
                  }
                }
              } catch (e) {}
              return n;
            }
            function fields(doc, tag) {
              var res = [];
              try {
                var els = doc.querySelectorAll('input,select,textarea');
                for (var i = 0; i < els.length && res.length < 60; i++) {
                  var el = els[i], ty = (el.type || '').toLowerCase();
                  if (ty === 'password' || ty === 'hidden' || ty === 'button' || ty === 'submit' || ty === 'file' || ty === 'checkbox' || ty === 'radio') continue;
                  if (!el.getClientRects || el.getClientRects().length === 0) continue;
                  var v = el.tagName === 'SELECT' ? (el.options[el.selectedIndex] ? el.options[el.selectedIndex].text : '') : el.value;
                  v = clean(v, 80); if (!v) continue;
                  var lb = ''; try { if (el.id) { var l = doc.querySelector('label[for="' + el.id + '"]'); if (l) lb = l.textContent; } } catch (e) {}
                  res.push(clean(lb || el.placeholder || el.getAttribute('title') || el.name || el.id || '?', 40) + '=' + v);
                }
              } catch (e) {}
              if (res.length) push('[' + tag + ' — Ô lọc/nhập đang có giá trị] ' + res.join(' ; '));
            }
            var frames = [];
            function collect(doc, depth, tag) {
              frames.push({ doc: doc, tag: tag });
              if (depth > 4) return;
              var fs = doc.querySelectorAll('iframe,frame');
              for (var i = 0; i < fs.length; i++) {
                try {
                  if (fs[i].id === 'desmDetailFrame' || !fs[i].contentDocument || fs[i].getClientRects().length === 0) continue;
                  collect(fs[i].contentDocument, depth + 1, 'Khung ' + (fs[i].id || fs[i].name || (i + 1)));
                } catch (e) {}
              }
            }
            collect(document, 0, 'Trang chính');
            try { var dt0 = detailText(); if (dt0) push(dt0); } catch (e) {}
            push('[Nội dung trang DESM đang mở: ' + clean(document.title, 80) + ' — ' + location.pathname + ']');
            var gridCount = 0;
            frames.forEach(function(f) { try { fields(f.doc, f.tag); gridCount += grids(f.doc.defaultView, f.tag); } catch (e) {} });
            // Văn bản trang (tiêu đề, nhãn, thông báo...). Nếu đã có lưới thì chỉ lấy ít để dành chỗ cho dữ liệu.
            var budget = gridCount ? Math.min(4000, Math.max(0, limit - used)) : Math.max(0, limit - used);
            frames.forEach(function(f) {
              try {
                if (budget <= 0) return;
                var b = f.doc.body; if (!b) return;
                var t = clean(b.innerText || '', budget); if (!t) return;
                push('[' + f.tag + ' — Văn bản] ' + t); budget -= t.length;
              } catch (e) {}
            });
            if (cut0) out.push('[Đã cắt bớt vì vượt giới hạn dữ liệu gửi AI; có thể còn dòng chưa gửi hoặc chưa tải hết trên trang]');
            return out.join('\n');
          }
          // Màn CHI TIẾT một kiện (overlay #desmDetail do UserScript dựng) và các màn con (.desm-sub: RSI & MRF List, RSI Detail...): đọc chữ đang hiển thị
          function detailText() {
            var parts = [];
            function walk(doc, depth) {
              try {
                var ns = doc.querySelectorAll('#desmDetail, .desm-sub');
                for (var i = 0; i < ns.length; i++) {
                  var n = ns[i]; if (!n.getClientRects || n.getClientRects().length === 0) continue;
                  var t = String(n.innerText || n.textContent || '').replace(/[ \t\u00a0]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim();
                  var fl = [].map.call(n.querySelectorAll('.desm-dband-c'), function(c) { var k = c.querySelector('input[type=checkbox]'); return String(c.textContent || '').trim() + '=' + (k && k.checked ? 'Y' : 'N'); }).join(', ');
                  if (t) parts.push('[' + (n.classList.contains('desm-sub') ? 'Màn con' : 'Màn chi tiết kiện') + (fl ? ' — ' + fl : '') + ']\n' + t.slice(0, 8000));
                }
              } catch (e) {}
              if (depth > 4) return;
              try {
                var fs = doc.querySelectorAll('iframe');
                for (var j = 0; j < fs.length; j++) {
                  try { if (fs[j].id === 'desmDetailFrame' || !fs[j].contentDocument || fs[j].getClientRects().length === 0) continue; walk(fs[j].contentDocument, depth + 1); } catch (e) {}
                }
              } catch (e) {}
            }
            walk(document, 0);
            return parts.length ? '[Dữ liệu đang hiển thị trên màn CHI TIẾT một kiện hàng — gồm thông tin kiện và Detail Item List]\n' + parts.join('\n\n') : '';
          }
          // Đọc BẤT KỲ màn nào đang chạy: màn chi tiết kiện/màn con (overlay) > danh sách thẻ Package (+ ô lọc) > mọi màn khác (lưới, ô nhập, chữ trên trang)
          function allText(limit) {
            limit = limit || 20000;
            var dt = ''; try { dt = detailText(); } catch (e) {}
            if (dt) return dt.slice(0, limit);
            var sc = ''; try { sc = screenText(); } catch (e) {}
            if (sc) {
              var pt = ''; try { pt = pageText(Math.min(3000, limit)); } catch (e) {}
              return (sc + (pt ? '\n\n' + pt : '')).slice(0, limit);
            }
            return pageText(limit);
          }
          // Gắn vào câu hỏi gửi Dodo: dữ liệu màn hình (nếu bật) + yêu cầu trả lời tiếng Việt (nếu bật). Khung chat vẫn hiện nguyên câu bạn gõ.
          try {
            var f0 = w.fetch;
            if (f0) w.fetch = function(inp, init) {
              try {
                var u = typeof inp === 'string' ? inp : (inp && inp.url);
                if ((w.__desmDodoVi || w.__desmDodoData || w.__desmDodoSlow) && /\/dodo\/chat\/stream/.test(String(u)) && init && init.body instanceof URLSearchParams) {
                  var q = init.body.get('user_prompt') || '', add = '';
                  if (w.__desmDodoSlow) init.body.set('mode', 'slow');
                  if (q && q.indexOf('[Dữ liệu đang hiển thị') < 0 && w.__desmDodoData) { var tx = ''; try { tx = allText(12000); } catch (e2) { tx = ''; } if (tx) add += '\n\n' + tx; }
                  if (q && q.indexOf('[Trả lời bằng tiếng Việt]') < 0 && w.__desmDodoVi) add += '\n\n[Trả lời bằng tiếng Việt]';
                  if (add) init.body.set('user_prompt', q + add);
                }
              } catch (e) {}
              return f0.apply(this, arguments);
            };
          } catch (e) {}
          w.__desmDodo = { sync: sync, open: openChat, screenText: screenText, pageText: allText };
          try { w.addEventListener('resize', function() { place(); vv(); }); } catch (e) {}
          try { if (w.visualViewport) { w.visualViewport.addEventListener('resize', vv); w.visualViewport.addEventListener('scroll', vv); } } catch (e) {}
          try { w.setInterval(sync, 400); } catch (e) {}
          document.addEventListener('DOMContentLoaded', sync);
          sync();
        })();
        """#
    }
}
