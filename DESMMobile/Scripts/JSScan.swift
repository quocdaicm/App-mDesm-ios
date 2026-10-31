// JSScan.swift — phần JS "Quét Package No / QR, mở menu, tìm kiện/Packing List/hạng mục (__desmFindPkg, __desmFindDetail, __desmOpenMenu…)" của script giao diện tiêm vào trang DESM.
// Ghép lại ở UserScript.swift (makeScript) theo đúng thứ tự file gốc; các phần dùng chung một phạm vi hàm nên gọi chéo nhau được.
// Mỗi phần chỉ nên chứa trọn các khai báo hàm/biến ở mức trên cùng. Kiểm tra cú pháp: python3 tools/check_js.py (cần Node).
// Hàm trong phần này: pkgGridOf … findDetailIn

extension UserJS {
    static let scan = #"""
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
          w.__desmOpenMenu = function(id, pattern, soft) {
            var D; try { D = diTop(document).document; } catch (e) { D = document; }
            // soft = mở tự động lúc vào app: màn Package đã hiện (hoặc đã bấm 1 lần) thì KHÔNG bấm lại, tránh nạp lại trang nhiều lần
            if (soft) {
              try { if (pkgDoc(document, 0)) return 1; } catch (e) {}
              if (w.__desmSoftOpened && Date.now() - w.__desmSoftOpened < 20000) return 1;
            }
            // Mở mục menu khác khi đang xem chi tiết kiện / màn con / khung ẩn phủ toàn màn hình: đóng hết lớp phủ trước, nếu không màn mới nằm dưới lớp phủ
            if (!soft) {
              try {
                for (var n = 0; n < 8; n++) {
                  var bks = D.querySelectorAll('.desm-sub .desm-detail-back'), bk = D.querySelector('#desmDetailFrameBar .desm-detail-back') ||
                    (bks.length ? bks[bks.length - 1] : null) || D.querySelector('#desmDetail .desm-detail-back');
                  if (!bk) break;
                  bk.click();
                }
                [].forEach.call(D.querySelectorAll('.desm-sub, #desmDetail'), function(x) { if (x.parentNode) x.parentNode.removeChild(x); });
                D.documentElement.classList.remove('desm-detail-open');
              } catch (e) {}
            }
            var rx = null; try { rx = pattern ? new RegExp(pattern, 'i') : null; } catch (e) {}
            function txt(x) { return ((x && x.textContent) || '').replace(/\s+/g, ' ').trim(); }
            var a = id ? D.getElementById(id) : null;
            // id chưa kiểm chứng có thể trỏ nhầm mục: tên mục không khớp thì bỏ, tìm theo tên
            if (a && rx && id !== '196' && !rx.test(txt(a))) a = null;
            if (!a && rx) {
              var L = D.querySelectorAll('#accordionSidebar a, .sidebar a, nav a');
              for (var i = 0; i < L.length; i++) {
                if (L[i].hasAttribute('data-toggle')) continue;
                var tx = txt(L[i]);
                if (tx && rx.test(tx)) { a = L[i]; break; }
              }
            }
            // Mục nằm trong nhóm menu đang thu gọn: mở nhóm cha trước khi bấm
            if (a) {
              try {
                var pc = a.closest ? a.closest('.collapse') : null;
                while (pc) { pc.classList.add('show'); pc = pc.parentElement && pc.parentElement.closest ? pc.parentElement.closest('.collapse') : null; }
              } catch (e) {}
            }
            if (!a) return 0;
            try { if (soft) w.__desmSoftOpened = Date.now(); a.click(); D.documentElement.classList.remove('desm-nav-open'); return 1; } catch (e) { return 0; }
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
        """#
}
