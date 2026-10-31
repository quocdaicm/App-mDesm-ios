// JSGenericCards.swift — phần JS "Thẻ cho lưới RSI/MRR/MRF/MPR (genericCards), sửa dòng MRR (mrrEditor)" của script giao diện tiêm vào trang DESM.
// Ghép lại ở UserScript.swift (makeScript) theo đúng thứ tự file gốc; các phần dùng chung một phạm vi hàm nên gọi chéo nhau được.
// Mỗi phần chỉ nên chứa trọn các khai báo hàm/biến ở mức trên cùng. Kiểm tra cú pháp: python3 tools/check_js.py (cần Node).
// Hàm trong phần này: genGridOf … genericCards

extension UserJS {
    static let genericCards = #"""
          // ===== Danh sách dạng thẻ cho các lưới khác (RSI, MRR, MRF, MPR...): mỗi dòng một thẻ, chạm thẻ để mở rộng toàn bộ cột,
          // chạm vùng ô tích bên trái để chọn dòng (các nút Confirm/Delete... của trang vẫn dùng dòng đã chọn).
          function genGridOf(win) {
            var best = null, bh = -1;
            try {
              for (var i = 0; win.TGGrids && i < win.TGGrids.length; i++) {
                var g = win.TGGrids[i];
                if (!g || !g.Cols || !g.Rows || !g.Rows.Header || !g.MainTag) continue;
                if (g.Cols.PACKAGE_NO && g.Cols.STORAGE_LOCATION) continue; // lưới Package đã có cardView riêng
                // Lưới Hạng mục chi tiết nằm trong khung ẩn desmDetailFrame (genericCards đã bỏ qua khung đó); màn hiện ra như
                // "RSI Summary" cũng có PACKAGE_NO + MATERIAL_CODE nên vẫn dựng thẻ. Bỏ điều kiện từ khoá RSI/MRR/MRF/MPR: mọi lưới còn lại đều thành thẻ.
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
            if (!$j || !$j.ajax) { try { $j = win.top.jQuery || win.top.$; } catch (e) {} }
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
          // Tìm khoá cột số phiếu thật (MRF_NO / MRF_NUMBER / RSINO ...) của lưới; trả '' nếu không có
          function docKey(G, kind) {
            if (!G || !G.Cols) return '';
            var re = new RegExp('^' + kind + '_?(NO|NUMBER)$', 'i');
            for (var k in G.Cols) { if (re.test(k)) return k; }
            return '';
          }
          function genDetail(win, doc, G, it) {
            function el(tag, cls, text) { var e = doc.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
            function dash(v) { return v == null || v === '' ? '-' : v; }
            function fn(v) {
              var s = String(v == null ? '' : v).replace(/,/g, ''), n = parseFloat(s);
              if (s === '' || isNaN(n)) return '-';
              return n.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 3 });
            }
            function same(a, b) { return String(a == null ? '' : a).replace(/\s+/g, ' ').trim() === String(b == null ? '' : b).replace(/\s+/g, ' ').trim(); }
            var mrfKey = docKey(G, 'MRF'), rsiKey = docKey(G, 'RSI');
            var isMrf = !!mrfKey, isRsi = !isMrf && !!rsiKey, isMrr = !!(G.Cols.MRR_NO);
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
              var proj = it.r.PROJECT_NO || diProj(doc);
              var hh = {}; for (var hk in it.r) hh[hk] = it.r[hk]; hh.PROJECT_NO = proj;
              function alive() { return !!ov.parentNode; }
              if (isRsi) {
                var rv = it.r[rsiKey]; if (rv == null || rv === '') rv = it.r.RSI_NO; hh.RSI_NO = rv != null && rv !== '' ? rv : it.title;
                rsiTickList(win, doc, doc, body, hh, alive, true);
              } else {
                var mv = it.r[mrfKey]; if (mv == null || mv === '') mv = it.r.MRF_NO; hh.MRF_NO = mv != null && mv !== '' ? mv : it.title;
                mrfTickList(win, doc, doc, body, hh, '', alive);
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
              box.__all = all; box.__q = q; box.__cnt = cnt; box.__tg = tg; box.__list = list; box.__bar = bar;
              q.addEventListener('input', function() { box.__sig = null; genericCards(doc); });
              // Vuốt lên xem danh sách thì tự ẩn TOÀN BỘ phần phía trên danh sách (hàng Bộ lọc/Search, ô Package No., hàng Cột/Number of Page)
              // và khung lọc dính (checkbox + lọc nhanh + Tất cả/Chưa đóng/Đã đóng + ô tìm) để thẻ chiếm cả màn hình.
              // Vuốt xuống một chút, về đầu danh sách, hoặc đang nhập vào ô lọc thì hiện lại.
              var lastY = 0;
              function topEls() {
                var out = [], n = box;
                while (n && n !== doc.body && n !== doc.documentElement) {
                  for (var p = n.previousElementSibling; p; p = p.previousElementSibling) {
                    if (/^(SCRIPT|STYLE|LINK|TEMPLATE)$/.test(p.tagName) || !p.offsetHeight) continue;
                    var ps = ''; try { ps = win.getComputedStyle(p).position; } catch (e) {}
                    if (ps === 'fixed' || ps === 'absolute') continue;
                    out.push(p);
                  }
                  n = n.parentElement;
                }
                return out;
              }
              function fitBox() {
                try { box.style.height = Math.max(160, win.innerHeight - box.getBoundingClientRect().top - 4) + 'px'; } catch (e) {}
              }
              function setHidden(on) {
                if (on === !!box.__tophid) return;
                if (on) {
                  var els = topEls(), total = 0;
                  els.forEach(function(x) { total += x.offsetHeight; });
                  // Chỉ ẩn khi sau khi ẩn danh sách vẫn còn đủ chỗ cuộn (tránh nhấp nháy ẩn/hiện liên tục)
                  if (box.scrollHeight - box.clientHeight < total + bar.offsetHeight + 140) return;
                  if (els.some(function(x) { return x.contains(doc.activeElement); })) return;
                  els.forEach(function(x) { x.classList.add('desm-tophide'); });
                  box.__tophid = els;
                  box.classList.add('desm-bar-hide');
                } else {
                  (box.__tophid || []).forEach(function(x) { x.classList.remove('desm-tophide'); });
                  box.__tophid = null;
                  box.classList.remove('desm-bar-hide');
                }
                fitBox();
              }
              box.__setHidden = setHidden;
              box.addEventListener('scroll', function() {
                var y = box.scrollTop, dy = y - lastY; lastY = y;
                if (box.classList.contains('desm-gtable')) { setHidden(false); return; }
                if (bar.contains(doc.activeElement) || y <= 8) { setHidden(false); return; }
                if (dy > 8) setHidden(true);
                else if (dy < -8) setHidden(false);
              }, { passive: true });
              bar.addEventListener('focusin', function() { setHidden(false); });
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
            box.__tg.textContent = on ? '▦ Thẻ' : '☰ Bảng';
            // Nút 'Lọc nhanh' cạnh nút 'Cột: Gọn': mở/đóng khung lọc nhanh (ô lọc, Dạng, Tất cả/Chưa đóng/Đã đóng) cho đỡ chiếm màn hình. Mặc định đóng.
            var colBtn = doc.getElementById('desmColToggle');
            if (win.__desmGenBar === undefined) {
              var sb = ''; try { sb = win.localStorage.getItem('desmGenBar') || ''; } catch (e) {}
              win.__desmGenBar = sb === '1';
            }
            if (colBtn && !doc.getElementById('desmBarToggle')) {
              var bb = doc.createElement('button');
              bb.type = 'button'; bb.id = 'desmBarToggle'; bb.className = colBtn.className; bb.style.marginLeft = '8px';
              bb.addEventListener('click', function(e) {
                e.preventDefault(); e.stopPropagation();
                win.__desmGenBar = !win.__desmGenBar;
                try { win.localStorage.setItem('desmGenBar', win.__desmGenBar ? '1' : '0'); } catch (e2) {}
                box.__sig = null; genericCards(doc);
              });
              if (colBtn.parentNode) colBtn.parentNode.insertBefore(bb, colBtn.nextSibling);
            }
            var barBtn = doc.getElementById('desmBarToggle');
            if (colBtn && colBtn.parentNode && colBtn.parentNode.classList) colBtn.parentNode.classList.add('desm-tb-compact');
            var barOpen = !barBtn || !!win.__desmGenBar;
            box.classList.toggle('desm-bar-collapsed', !barOpen);
            if (barBtn) barBtn.style.display = on ? '' : 'none';
            host.classList.toggle('desm-grid-off', on);
            box.classList.toggle('desm-gtable', !on);
            if (!on) {
              if (box.__setHidden) box.__setHidden(false);
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
            // Lưới có Package No.: thẻ hiện Package No. + Location trước; chạm thẻ = mở thông tin kiện đó (màn Package)
            var pkgCol = null, locCol = null;
            if (G.Cols.PACKAGE_NO) {
              cols.forEach(function(x) {
                if (x.c === 'PACKAGE_NO') pkgCol = x;
                else if (!locCol && (x.c === 'STORAGE_LOCATION' || x.c === 'LOCATION' || /^location$/i.test(x.h))) locCol = x;
              });
            }
            if (pkgCol) {
              [statCols, dateCols, restCols].forEach(function(arr) {
                [pkgCol, locCol].forEach(function(x) { var k = x ? arr.indexOf(x) : -1; if (k >= 0) arr.splice(k, 1); });
              });
              if (titleCol && titleCol !== pkgCol) restCols.unshift(titleCol);
              titleCol = pkgCol;
              if (locCol) restCols.unshift(locCol);
            }
            // Bộ lọc riêng: Tất cả / Chưa đóng / Đã đóng (theo số lượng còn lại, hoặc STATUS nếu không có cột còn lại) + ô tìm theo số phiếu / tên phiếu
            var F = box.__f = box.__f || { mode: 'all', no: '', name: '' };
            var fNo = null, fName = null, fBal = null;
            for (var kc in G.Cols) {
              if (!fNo && /^(RSI|MRR|MRF|MPR)_?(NO|NUMBER)$/i.test(kc)) fNo = kc;
              else if (!fName && /^(RSI|MRR|MRF|MPR)_?NAME$/i.test(kc)) fName = kc;
              else if (/BALANCE_?QTY$/i.test(kc) && (!fBal || kc === 'BALANCE_QTY')) fBal = kc;
            }
            if (fNo) {
              var fKind = (fNo.match(/^(RSI|MRR|MRF|MPR)/i) || [''])[0];
              var fNameRe = new RegExp('^' + fKind + '_?NAME$', 'i');
              fName = null;
              for (var kn in G.Cols) { if (fNameRe.test(kn)) { fName = kn; break; } }
            }
            var fSt = statCols.length ? statCols[0].c : null;
            // Cột dùng để lọc: theo cột đang HIỂN THỊ trên thẻ (đúng giá trị người dùng thấy) + khoá cột thật
            function colIdx(re) {
              var out = [];
              cols.forEach(function(x, i) { if (re.test(x.h) || re.test(x.c)) out.push(i); });
              return out;
            }
            var fKindRe = fNo ? (fNo.match(/^(RSI|MRR|MRF|MPR)/i) || [''])[0] : '';
            var noIdx = fKindRe ? colIdx(new RegExp('^' + fKindRe + '[\\s_]*(NO|NUMBER|#)\\.?$', 'i')) : [];
            var nameIdx = fKindRe ? colIdx(new RegExp('^' + fKindRe + '[\\s_]*NAME$', 'i')) : [];
            if (!box.__bar2 && (fBal || fSt)) {
              var b2 = el('div', 'desm-gbar2'); box.__bar2 = b2;
              if (fBal || fSt) {
                [['all', 'Tất cả'], ['open', 'Chưa đóng'], ['closed', 'Đã đóng']].forEach(function(m) {
                  var cb = el('button', 'desm-gchip', m[1]); cb.type = 'button'; cb.setAttribute('data-m', m[0]);
                  cb.addEventListener('click', function(e) { e.preventDefault(); e.stopPropagation(); F.mode = m[0]; box.__sig = null; genericCards(doc); });
                  b2.appendChild(cb);
                });
              }
              b2.appendChild(box.__cnt);   // số dòng nằm cuối hàng chip cho gọn
              box.__bar.appendChild(b2);
            }
            // Hai ô 'Tìm MRF No.' / 'Tìm MRF Name' nằm trong trang, ngay dưới hàng Packing List No / Package No
            if ((fNo || fName) && !box.__srow) {
              var sr = el('div', 'desm-gsearch'); box.__srow = sr;
              function mk(key, fld, fallback) {
                if (!key) return;
                var ht = ''; try { ht = gridText(G, G.Rows.Header, key); } catch (e) {}
                var inp = doc.createElement('input'); inp.type = 'search'; inp.className = 'desm-gq2';
                inp.placeholder = ht || ((key.match(/^(RSI|MRR|MRF|MPR)/i) || [''])[0].toUpperCase() + (fld === 'no' ? ' No.' : ' Name'));
                inp.setAttribute('autocomplete', 'off'); inp.setAttribute('autocapitalize', 'off'); inp.setAttribute('enterkeyhint', 'search');
                inp.value = F[fld] || '';
                var go = function() { if (F[fld] === inp.value) return; F[fld] = inp.value; box.__sig = null; genericCards(doc); };
                ['input', 'keyup', 'change', 'search'].forEach(function(ev) { inp.addEventListener(ev, go); });
                inp.addEventListener('keydown', function(e) { if (e.key === 'Enter') { try { inp.blur(); } catch (e2) {} } });
                sr.appendChild(inp);
              }
              mk(fNo, 'no', 'số phiếu'); mk(fName, 'name', 'tên phiếu');
              sr.addEventListener('focusin', function() { if (box.__setHidden) box.__setHidden(false); });
            }
            if (box.__srow) {
              var sr2 = box.__srow;
              sr2.style.display = on ? '' : 'none';
              if (on && !sr2.isConnected) {
                // Tìm hàng chứa ô Packing List No / Package No của trang để chèn ngay dưới
                var cand = [].filter.call(doc.querySelectorAll('input:not([type=hidden]):not([type=checkbox])'), function(i) {
                  return !box.contains(i) && !sr2.contains(i) && i.offsetHeight > 0 && /package|packing/i.test((i.placeholder || '') + ' ' + (i.id || '') + ' ' + (i.name || ''));
                });
                var anchor = cand.length ? cand[cand.length - 1] : null, row = null;
                if (anchor) {
                  var ah = anchor.getBoundingClientRect().height || 30;
                  row = anchor;
                  while (row.parentElement && row.parentElement !== doc.body) {
                    var pe = row.parentElement;
                    if (pe.contains(box) || pe.querySelector('#toolbar') || pe.getBoundingClientRect().height > ah * 1.8) break;
                    row = pe;
                  }
                }
                if (row && row.parentNode) {
                  row.parentNode.insertBefore(sr2, row.nextSibling);
                  // Căn lề + kiểu chữ theo ô native để nhìn đều
                  var fitRow = function() {
                    try {
                      var rr = sr2.getBoundingClientRect(), ins = cand.map(function(i) { return i.getBoundingClientRect(); });
                      var l = Math.min.apply(null, ins.map(function(x) { return x.left; })), r = Math.max.apply(null, ins.map(function(x) { return x.right; }));
                      sr2.style.paddingLeft = Math.max(0, l - rr.left) + 'px';
                      sr2.style.paddingRight = Math.max(0, rr.right - r) + 'px';
                      if (ins.length > 1) {
                        var srt = ins.slice().sort(function(a, b) { return a.left - b.left; });
                        var gp = srt[1].left - srt[0].right;
                        if (gp > 0 && gp < 60) sr2.style.gap = gp + 'px';
                      }
                      var cs = win.getComputedStyle(anchor);
                      [].forEach.call(sr2.querySelectorAll('input'), function(i) {
                        i.style.height = cs.height; i.style.borderRadius = cs.borderRadius; i.style.fontSize = cs.fontSize;
                        i.style.borderColor = cs.borderTopColor; i.style.borderWidth = cs.borderTopWidth; i.style.borderStyle = cs.borderTopStyle === 'none' ? 'solid' : cs.borderTopStyle;
                        i.style.boxShadow = cs.boxShadow; i.style.background = '#fff'; i.style.color = cs.color; i.style.fontFamily = cs.fontFamily;
                      });
                    } catch (e) {}
                  };
                  fitRow(); win.setTimeout(fitRow, 400);
                } else {
                  box.parentNode.insertBefore(sr2, box);
                }
              }
            }
            if (box.__bar2) [].forEach.call(box.__bar2.querySelectorAll('.desm-gchip'), function(cb) { cb.classList.toggle('desm-on', cb.getAttribute('data-m') === F.mode); });
            function isClosedRow(r) {
              if (fBal) {
                var t = String(gridText(G, r, fBal) || '').replace(/,/g, '').trim(), v = parseFloat(t);
                if (!isNaN(v)) return v <= 0;
              }
              return fSt ? /close|complet|cancel|done|finish|reject/i.test(String(gridText(G, r, fSt) || '')) : false;
            }
            var fNoV = pkgNorm(F.no), fNameV = pkgNorm(F.name);
            function hit(o, idxs, key, raw, norm) {
              var rawT = String(raw || '').trim().toLowerCase();
              if (!norm && !rawT) return true;
              var t = idxs.map(function(i) { return o.all[i] ? o.all[i].v : ''; }).join(' ');
              if (key) { t += ' ' + gridText(G, o.r, key); var rv = o.r[key]; if (rv != null) t += ' ' + String(rv).replace(/<[^>]*>/g, ''); }
              if (norm && pkgNorm(t).indexOf(norm) >= 0) return true;
              return !!rawT && t.toLowerCase().indexOf(rawT) >= 0;
            }
            // Cột tổng yêu cầu (RSI/MRF Q'ty...) để biết đã xuất/trả một phần chưa; Remaining = cột *BALANCE_QTY, chỉ hiện khi tổng ≠ còn lại
            var qtyTotCol = null;
            ['RSI_QTY', 'MRF_QTY', 'MPR_QTY', 'REQ_QTY', 'REQUEST_QTY', 'REQ_RETURN_QTY', 'RETURN_REQ_QTY'].some(function(k) { if (G.Cols[k]) { qtyTotCol = k; return true; } return false; });
            if (!qtyTotCol) cols.forEach(function(x) { if (!qtyTotCol && /(rsi|mrf|mpr|req|request).*q'?ty/i.test(x.h) && !/bal|cancel|remain/i.test(x.h + ' ' + x.c)) qtyTotCol = x.c; });
            function remOfRow(r) {
              if (!fBal || !qtyTotCol) return '';
              var tot = parseFloat(String(gridText(G, r, qtyTotCol) || '').replace(/,/g, '')), bal = parseFloat(String(gridText(G, r, fBal) || '').replace(/,/g, ''));
              if (isNaN(tot) || isNaN(bal) || tot - bal <= 0) return '';
              return bal;
            }
            var rows = diRows(G), qv = pkgNorm(box.__q.value);
            var items = rows.map(function(r) {
              var o = { r: r, id: r.id, sel: isSel(r), all: cols.map(function(x) { return { h: x.h, v: gridText(G, r, x.c) }; }) };
              o.title = titleCol ? gridText(G, r, titleCol.c) : '';
              o.pkg = pkgCol ? gridText(G, r, 'PACKAGE_NO') : '';
              o.stat = statCols.map(function(x) { return gridText(G, r, x.c); }).filter(function(v) { return v; })[0] || '';
              o.dates = dateCols.map(function(x) { return { h: x.h, v: gridText(G, r, x.c) }; }).filter(function(d) { return d.v; });
              o.rest = restCols.map(function(x) { return { h: x.h, v: gridText(G, r, x.c) }; }).filter(function(d) { return d.v; });
              o.hay = pkgNorm(o.all.map(function(d) { return d.v; }).join(' '));
              o.rem = remOfRow(r);
              return o;
            }).filter(function(o) {
              if (qv && o.hay.indexOf(qv) < 0) return false;
              if (!hit(o, noIdx, fNo, F.no, fNoV)) return false;
              if (!hit(o, nameIdx, fName, F.name, fNameV)) return false;
              if (F.mode !== 'all' && (fBal || fSt)) { var cl = isClosedRow(o.r); if ((F.mode === 'closed') !== cl) return false; }
              return true;
            });
            box.__rowsShown = items.map(function(o) { return o.r; });
            var nSel = items.filter(function(o) { return o.sel; }).length;
            var sig = items.map(function(o) { return [o.id, o.sel ? 1 : 0, o.title, o.stat, o.all.length, o.all.map(function(d) { return d.v; }).join('~'), win.__desmGenOpen[o.id] ? 1 : 0].join('|'); }).join('\n') + '#' + qv + '#' + F.mode + '#' + fNoV + '#' + fNameV;
            if (box.__sig === sig) return;
            box.__sig = sig;
            box.__all.checked = items.length > 0 && nSel === items.length;
            box.__all.indeterminate = nSel > 0 && nSel < items.length;
            box.__cnt.textContent = items.length + ' dòng' + (nSel ? ' · chọn ' + nSel : '');
            if (barBtn) barBtn.textContent = 'Lọc ' + (barOpen ? '▴' : '▾') + ' · ' + items.length + (nSel ? ' (chọn ' + nSel + ')' : '');
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
              var foot = null;
              if (it.dates.length) {
                foot = el('div', 'desm-card-foot');
                it.dates.slice(0, 2).forEach(function(d) { foot.appendChild(el('span', 'desm-card-ao', d.h + ': ' + d.v)); });
              }
              if (it.rem !== '') {
                if (!foot) foot = el('div', 'desm-card-foot');
                foot.appendChild(el('span', 'desm-card-rem ' + (it.rem > 0 ? 'desm-d-rem-open' : 'desm-d-rem-done'),
                  'Remaining ' + Number(it.rem).toLocaleString('en-US', { maximumFractionDigits: 3 })));
              }
              if (foot) card.appendChild(foot);
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
              // RSI / MRF Summary: chạm vào thông tin thẻ là mở RSI / MRF Detail, không cần nút riêng
              var isRM = !!(docKey(G, 'MRF') || docKey(G, 'RSI'));
              if (it.pkg && !isRM) {
                var ac = el('button', 'desm-detail-list desm-gall-cols', 'Xem tất cả cột của dòng này'); ac.type = 'button';
                ac.addEventListener('click', function(ev) { ev.stopPropagation(); genDetail(win, doc, G, it); });
                card.appendChild(ac);
              }
              card.appendChild(more);
              card.addEventListener('click', function(ev) {
                if (ev.target && ev.target.classList && ev.target.classList.contains('desm-card-hit')) {
                  try { G.SelectRow(it.r, it.sel ? 0 : 1); } catch (e) {}
                } else {
                  // Chạm thẻ = vào xem chi tiết bên trong (chạm ô vuông bên trái = chọn dòng)
                  if (it.pkg && !isRM && win.__desmFindPkg && !(ev.target && ev.target.classList && ev.target.classList.contains('desm-gall-cols'))) {
                    // Có Package No.: mở thông tin kiện (chuyển sang màn Package, tìm đúng kiện rồi mở chi tiết)
                    win.__desmFindPkg({ term: it.pkg, key: it.pkg, open: true });
                    return;
                  }
                  genDetail(win, doc, G, it);
                  return;
                }
                box.__sig = null; genericCards(doc);
              });
              list.appendChild(card);
            });
            box.scrollTop = keep;
          }
        """#
}
