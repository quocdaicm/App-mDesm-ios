// NetRecorder.swift — JS ghi request XHR/fetch của trang (nhật ký API).

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

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
