// DodoBubble.swift — nút bong bóng chat Dodo (trợ lý AI của DESM) + khung chat vừa màn hình điện thoại.
// Dodo là widget có sẵn của web (/resources/scripts/util/Dodo.js → /dodo/chat/stream.do, sessions, history, reset, delete).
// Script này CHỈ chạy ở khung trên cùng (không chạy trong iframe), dùng lại Dodo.js của trang (hoặc tự nạp nếu thiếu).

import Foundation
import WebKit

extension BrowserModel {
    func makeDodoScript() -> String {
        let on = dodoBubble ? "true" : "false"
        let vi = dodoVi ? "true" : "false"
        let hosts = (try? JSONSerialization.data(withJSONObject: BrowserModel.allowedHosts, options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return #"""
        (function() {
          var w = window;
          try { if (w !== w.top) return; } catch (e) { return; }
          w.__desmDodoOn = \#(on);
          w.__desmDodoVi = \#(vi);
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
          // Gắn yêu cầu trả lời tiếng Việt vào câu hỏi gửi Dodo (khung chat vẫn hiện nguyên câu bạn gõ)
          try {
            var f0 = w.fetch;
            if (f0) w.fetch = function(inp, init) {
              try {
                var u = typeof inp === 'string' ? inp : (inp && inp.url);
                if (w.__desmDodoVi && /\/dodo\/chat\/stream/.test(String(u)) && init && init.body instanceof URLSearchParams) {
                  var q = init.body.get('user_prompt');
                  if (q && q.indexOf('[Trả lời bằng tiếng Việt]') < 0) init.body.set('user_prompt', q + '\n\n[Trả lời bằng tiếng Việt]');
                }
              } catch (e) {}
              return f0.apply(this, arguments);
            };
          } catch (e) {}
          w.__desmDodo = { sync: sync, open: openChat };
          try { w.addEventListener('resize', function() { place(); vv(); }); } catch (e) {}
          try { if (w.visualViewport) { w.visualViewport.addEventListener('resize', vv); w.visualViewport.addEventListener('scroll', vv); } } catch (e) {}
          try { w.setInterval(sync, 400); } catch (e) {}
          document.addEventListener('DOMContentLoaded', sync);
          sync();
        })();
        """#
    }
}
