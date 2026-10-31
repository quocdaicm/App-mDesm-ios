// JSViet.swift — phần JS "Việt hoá giao diện (vi*)" của script giao diện tiêm vào trang DESM.
// Ghép lại ở UserScript.swift (makeScript) theo đúng thứ tự file gốc; các phần dùng chung một phạm vi hàm nên gọi chéo nhau được.
// Mỗi phần chỉ nên chứa trọn các khai báo hàm/biến ở mức trên cùng. Kiểm tra cú pháp: python3 tools/check_js.py (cần Node).
// Hàm trong phần này: viNorm … viApply

extension UserJS {
    static let viet = #"""
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
        """#
}
