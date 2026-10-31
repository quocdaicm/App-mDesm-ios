// JSGridItems.swift — phần JS "Lưới TreeGrid (gridText, colShown, compactGrid) + nạp/lưu hạng mục của kiện (diLoad, diLoadFast, diSelect, diShow, diWarm…)" của script giao diện tiêm vào trang DESM.
// Ghép lại ở UserScript.swift (makeScript) theo đúng thứ tự file gốc; các phần dùng chung một phạm vi hàm nên gọi chéo nhau được.
// Mỗi phần chỉ nên chứa trọn các khai báo hàm/biến ở mức trên cùng. Kiểm tra cú pháp: python3 tools/check_js.py (cần Node).
// Hàm trong phần này: gridText … diShow

extension UserJS {
    static let gridItems = #"""
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
              if (!G.Cols.STORAGE_LOCATION) {
                var fe0 = null; try { fe0 = win.frameElement; } catch (e) {}
                if (!fe0 || fe0.id !== 'desmDetailFrame') continue;   // màn khác (vd Tổng hợp RSI) hiện đủ cột dạng thẻ
              }
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
            // TẮT (2026-10-30): mở sẵn khung ẩn làm DESM hiện thêm vòng xoay "đang nạp" sau khi màn Package đã hiện xong.
            // Khung ẩn giờ chỉ nạp khi người dùng mở một kiện (diFrame được gọi theo yêu cầu).
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
        """#
}
