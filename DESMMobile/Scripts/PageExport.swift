// PageExport.swift — đọc cấu trúc trang, lấy HTML và script của trang (phục vụ tinh chỉnh).

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

extension BrowserModel {
    // MARK: - Đọc cấu trúc trang để tinh chỉnh CSS

    static let diagScript = #"""
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

    func exportScript(stripValues: Bool, stripScripts: Bool) -> String {
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
