// JSDetail.swift — phần JS "Màn chi tiết kiện: danh sách tích RSI/MRF (rsiTickList, mrfTickList) và openDetail" của script giao diện tiêm vào trang DESM.
// Ghép lại ở UserScript.swift (makeScript) theo đúng thứ tự file gốc; các phần dùng chung một phạm vi hàm nên gọi chéo nhau được.
// Mỗi phần chỉ nên chứa trọn các khai báo hàm/biến ở mức trên cùng. Kiểm tra cú pháp: python3 tools/check_js.py (cần Node).
// Hàm trong phần này: rsiTickList … openDetail

extension UserJS {
    static let detail = #"""
          // Danh sách hạng mục có ô tích + số lượng + ALL + OUT.G / RETURN, dùng chung cho mọi màn RSI Detail / MRF Detail.
          // RSI: /getDesmOutGoingCreationList.do + /saveDesmRsiOutSave.do (Sheets/Outgoing.swift) · MRF: /getDesmReturnCreationList.do + /saveDesmMrfReturnSave.do (Sheets/MrfReturn.swift)
          function rsiTickList(win, doc, idoc, b, h, alive, noInfo) {
              function el(tag, cls, text) { var e = doc.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
              function dash(v) { return v ? v : '-'; }
              function fnum(v) {
                var t = String(v == null ? '' : v).replace(/,/g, ''), n = parseFloat(t);
                if (t === '' || isNaN(n)) return '-';
                return n.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 3 });
              }
              function sameStr(a, b2) { return String(a == null ? '' : a).replace(/\s+/g, ' ').trim() === String(b2 == null ? '' : b2).replace(/\s+/g, ' ').trim(); }
              function rsiParam(over) {
                var p = { PAGE_NUM: 1, PAGE_CNT: 5000, PROJECT_NO: '', RSI_NO: '', RSI_NAME: '', SUBCONTRACTOR: '', ATTRIBUTE10: '', MATERIAL_CODE: '',
                  START_REQUEST_DATE: '', END_REQUEST_DATE: '', BALANCE_QTY: '', TYPE: '', CATEGORY: '', SUB_CATEGORY: '', PACKING_LIST_NO: '',
                  PACKAGE_NO: '', ITEM_DESC: '', MASTER_SHOP_UNIT: '', MASTER_SHOP_BLDG: '', SHOP_UNIT: '', SHOP_BLDG: '' };
                for (var k in over) p[k] = over[k];
                if (!p.PROJECT_NO) p.PROJECT_NO = diProj(idoc);
                return p;
              }
              // Thông tin đầu phiếu: Remarks + Requested/Checked/Confirmed/Approved by (+ giờ). Tên trường CHƯA kiểm chứng: dò theo mẫu tên.
              var infoEl = el('div', 'desm-dcard desm-rsi-info'); infoEl.style.display = 'none'; if (!noInfo) b.appendChild(infoEl);
              function prettyDate(v) {
                var t = String(v == null ? '' : v).trim(), m = /^(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?/.exec(t);
                if (!m) return t;
                function p2(n) { return ('0' + n).slice(-2); }
                var d = p2(m[3]) + '/' + p2(m[2]) + '/' + m[1].slice(-2);
                return m[4] != null ? p2(m[4]) + ':' + m[5] + ' ' + d : d;
              }
              function showInfo(r) {
                if (noInfo || !r || !alive()) return;
                var keys = Object.keys(r), rows = [], rem = '';
                function val(k) { var v = r[k]; return v == null ? '' : String(v).trim(); }
                ['RSI_REMARKS', 'RSI_REMARK', 'HEADER_REMARK', 'REMARK', 'REMARKS'].forEach(function(k) { if (!rem) rem = val(k); });
                [['Requested', ['REQUEST', 'PREPARED', 'CREATED']], ['Checked', ['CHECK']], ['Confirmed', ['CONFIRM']], ['Approved', ['APPROV']]].forEach(function(st) {
                  function has(k) { return st[1].some(function(x) { return k.indexOf(x) >= 0; }); }
                  var by = '', dt = '';
                  keys.forEach(function(k) {
                    var u = k.toUpperCase(); if (!has(u) || !val(k)) return;
                    if (!by && /BY$|_BY_/.test(u)) by = val(k);
                    else if (!dt && u.indexOf('DATE') >= 0 && !/START|END|HANDOVER/.test(u)) dt = prettyDate(val(k));
                  });
                  if (by || dt) rows.push([st[0] + ' by :', by || '-', dt]);
                });
                keys.forEach(function(k) { if (/CCB/i.test(k) && val(k)) rows.push([k + ' :', val(k), '']); });
                if (!rem && !rows.length) return;
                infoEl.appendChild(el('div', 'desm-d-h', 'REMARKS'));
                infoEl.appendChild(el('div', 'desm-d-l', rem || '-'));
                rows.forEach(function(x) {
                  var row = el('div', 'desm-rsi-row'); row.appendChild(el('span', '', x[0] + ' ' + x[1])); row.appendChild(el('span', '', x[2])); infoEl.appendChild(row);
                });
                infoEl.style.display = '';
              }
              var fb = el('div', 'desm-sub-filter');
              var fp = doc.createElement('input'); fp.placeholder = 'PKG.'; fp.className = 'desm-sub-in';
              var fs = doc.createElement('input'); fs.placeholder = 'SCH.'; fs.className = 'desm-sub-in';
              fb.appendChild(fp); fb.appendChild(fs); b.appendChild(fb);
              // Ngày xuất + người nhận (như phần tuỳ chọn của tab Xuất kho)
              var ob = el('div', 'desm-sub-filter');
              var od = doc.createElement('input'); od.type = 'date'; od.className = 'desm-sub-in';
              var tdy = new Date(); od.value = tdy.getFullYear() + '-' + ('0' + (tdy.getMonth() + 1)).slice(-2) + '-' + ('0' + tdy.getDate()).slice(-2);
              var orc = doc.createElement('input'); orc.placeholder = 'Người nhận / ghi chú'; orc.className = 'desm-sub-in';
              ob.appendChild(od); ob.appendChild(orc); b.appendChild(ob);
              // Thanh ALL + OUT.G
              var bar = el('div', 'desm-ditems-bar desm-out-bar');
              var allCb = doc.createElement('input'); allCb.type = 'checkbox'; allCb.className = 'desm-chk desm-out-chk';
              var barTxt = el('span', 'desm-cards-count', 'ALL');
              var outBtn = el('button', 'desm-out-btn', 'OUT.G'); outBtn.type = 'button'; outBtn.disabled = true;
              bar.appendChild(allCb); bar.appendChild(barTxt); bar.appendChild(outBtn); b.appendChild(bar);
              var rn = el('div', 'desm-detail-note', 'Đang tải…'), rl = el('div', 'desm-ditems');
              var msg = el('div', 'desm-detail-note', '');
              b.appendChild(msg); b.appendChild(rn); b.appendChild(rl);
              var all = [], out = [], items = [], sel = {}, qty = {}, outOk = false, pending = 2, saving = false;
              function nz(v) { return String(v == null ? '' : v).replace(/\s+/g, ' ').trim().toLowerCase(); }
              function qn(v) { var n = parseFloat(String(v == null ? '' : v).replace(/,/g, '')); return isNaN(n) ? 0 : n; }
              function fq(v) { return v === Math.round(v) ? String(Math.round(v)) : String(Math.round(v * 1000) / 1000); }
              function say(t, c) { msg.textContent = t || ''; msg.style.color = c || ''; }
              function validOut(o) { return o && o.RSI_LINE_ID != null && o.RSI_LINE_ID !== '' && o.RSI_HEADER_ID != null && o.RSI_HEADER_ID !== ''; }
              // Ghép dòng của phiếu (getDesmRsiViewList) với dòng còn xuất được (getDesmOutGoingCreationList)
              function build() {
                var pool = {}, used = [], outs = out.filter(function(o) { return sameStr(o.RSI_NO, h.RSI_NO); });
                outs.forEach(function(o) { var k = nz(o.PACKAGE_NO) + '|' + nz(o.MATERIAL_CODE); (pool[k] = pool[k] || []).push(o); });
                items = all.map(function(r) {
                  var o = null;
                  if (r.RSI_LINE_ID != null && r.RSI_LINE_ID !== '') {
                    for (var i = 0; i < outs.length; i++) if (used.indexOf(outs[i]) < 0 && String(outs[i].RSI_LINE_ID) === String(r.RSI_LINE_ID)) { o = outs[i]; break; }
                  }
                  if (!o) { var arr = pool[nz(r.PACKAGE_NO) + '|' + nz(r.MATERIAL_CODE)] || []; for (var j = 0; j < arr.length; j++) if (used.indexOf(arr[j]) < 0) { o = arr[j]; break; } }
                  if (o) used.push(o);
                  return { r: r, o: o, id: validOut(o) ? String(o.RSI_LINE_ID) : '' };
                });
                // Dòng còn xuất được nhưng không ghép được với danh sách phiếu: vẫn hiện để không bỏ sót
                outs.forEach(function(o) { if (used.indexOf(o) < 0) items.push({ r: o, o: o, id: validOut(o) ? String(o.RSI_LINE_ID) : '' }); });
                var ids = {}; items.forEach(function(it) { if (it.id) ids[it.id] = 1; });
                for (var k in sel) if (!ids[k]) delete sel[k];
              }
              function shownItems() {
                var p = fp.value.trim().toLowerCase(), s = fs.value.trim().toLowerCase();
                return items.filter(function(it) {
                  var r = it.r;
                  return (!p || String(r.PACKAGE_NO || '').toLowerCase().indexOf(p) >= 0) &&
                    (!s || (String(r.DESCRIPTION || '') + ' ' + String(r.MATERIAL_CODE || '')).toLowerCase().indexOf(s) >= 0);
                });
              }
              function toggle(it) {
                if (!it.id || saving) return;
                if (sel[it.id]) delete sel[it.id];
                else { sel[it.id] = 1; if (qty[it.id] == null || qty[it.id] === '') qty[it.id] = fq(qn(it.o.HANDOVER_AVAILABLE_QTY)); }
                draw();
              }
              function refreshBar(shown) {
                var n = Object.keys(sel).length, v = shown.filter(function(it) { return it.id; });
                allCb.checked = v.length > 0 && v.every(function(it) { return sel[it.id]; });
                outBtn.textContent = n ? 'OUT.G (' + n + ')' : 'OUT.G';
                outBtn.disabled = saving || !n;
                barTxt.textContent = 'ALL' + (v.length ? ' · ' + v.length + ' dòng xuất được' : '');
              }
              function draw() {
                while (rl.firstChild) rl.removeChild(rl.firstChild);
                var rows = shownItems();
                rn.textContent = all.length || items.length ? rows.length + ' / ' + items.length + ' hạng mục' : 'RSI này không có hạng mục.';
                if (!outOk && !pending) rn.textContent += ' · chưa tải được dữ liệu xuất kho nên chưa tích chọn được';
                rows.forEach(function(it) {
                  var r = it.r, on = !!(it.id && sel[it.id]);
                  var c = el('div', 'desm-rsi-card' + (on ? ' desm-sel' : ''));
                  var t1 = el('div', 'desm-rsi-top'); t1.appendChild(el('span', 'desm-ditem-no', dash(r.PACKAGE_NO)));
                  if (it.id) {
                    var cb = doc.createElement('input'); cb.type = 'checkbox'; cb.className = 'desm-chk desm-out-chk'; cb.checked = on; t1.appendChild(cb);
                  }
                  c.appendChild(t1);
                  var t2 = el('div', 'desm-rsi-top'); t2.appendChild(el('span', 'desm-ditem-l', dash(r.DESCRIPTION)));
                  if (it.id) {
                    var qi = doc.createElement('input'); qi.type = 'text'; qi.setAttribute('inputmode', 'decimal'); qi.className = 'desm-sub-in desm-out-qty';
                    qi.value = qty[it.id] != null ? qty[it.id] : fq(qn(it.o.HANDOVER_AVAILABLE_QTY));
                    qi.addEventListener('click', function(e) { e.stopPropagation(); });
                    qi.addEventListener('input', (function(id) { return function() { qty[id] = qi.value; }; })(it.id));
                    t2.appendChild(qi);
                  }
                  c.appendChild(t2);
                  var ft = el('div', 'desm-rsi-row'); ft.appendChild(el('span', '', dash(r.MATERIAL_CODE)));
                  if (it.o) {
                    var av = qn(it.o.HANDOVER_AVAILABLE_QTY), dn = Math.max(0, qn(it.o.REQ_QTY) - av);
                    var q = el('span', ''); var a1 = el('b', 'desm-out-av', av.toFixed(3)), a2 = el('b', 'desm-out-done', dn.toFixed(3));
                    q.appendChild(a1); q.appendChild(doc.createTextNode(' / ')); q.appendChild(a2); ft.appendChild(q);
                  } else {
                    ft.appendChild(el('span', '', fnum(r.REQ_QTY) + ' / ' + fnum(r.HANDOVER_QTY) + ' ' + (r.UNIT || '')));
                  }
                  c.appendChild(ft);
                  if (it.o) {
                    var hint = el('div', 'desm-ditem-l desm-out-hint', 'đỏ = còn xuất được · xanh = đã xuất' + (String(it.o.PENDING || '').toUpperCase() === 'Y' ? ' · Chưa duyệt' : ''));
                    c.appendChild(hint);
                  }
                  c.addEventListener('click', function() { toggle(it); });
                  rl.appendChild(c);
                });
                refreshBar(rows);
              }
              fp.addEventListener('input', draw); fs.addEventListener('input', draw);
              allCb.addEventListener('click', function(e) { e.preventDefault(); });
              bar.addEventListener('click', function(e) {
                if (e.target === outBtn || saving) return;
                var v = shownItems().filter(function(it) { return it.id; }), on = !(v.length && v.every(function(it) { return sel[it.id]; }));
                v.forEach(function(it) {
                  if (on) { sel[it.id] = 1; if (qty[it.id] == null || qty[it.id] === '') qty[it.id] = fq(qn(it.o.HANDOVER_AVAILABLE_QTY)); }
                  else delete sel[it.id];
                });
                draw();
              });
              function settled() { if (!alive()) return; pending--; if (pending <= 0) { pending = 0; build(); draw(); } }
              function loadOut(done) {
                diAjax(idoc, '/getDesmOutGoingCreationList.do', { PROJECT_NO: h.PROJECT_NO || diProj(idoc), PACKING_LIST_NO: '', PACKAGE_NO: '', RSI_NO: h.RSI_NO,
                  MATERIAL_CODE: '', REQUEST_START_DATE: '', ATTRIBUTE10: '', REQUEST_END_DATE: '', DESCRIPTION: '', DRAWING_NO: '', TAG_NO: '', RSI_NAME: '',
                  TYPE: '', CATEGORY: '', SUBCON: '', PENDING: '', MASTER_SHOP_UNIT: '', MASTER_SHOP_BLDG: '', SHOP_UNIT: '', SHOP_BLDG: '' },
                  function(list) { out = [].slice.call(list); outOk = true; done(); },
                  function() { out = []; outOk = false; done(); });
              }
              // OUT.G: kiểm tra giống tab Xuất kho rồi POST /saveDesmRsiOutSave.do
              outBtn.addEventListener('click', function() {
                if (saving) return;
                var chosen = items.filter(function(it) { return it.id && sel[it.id]; });
                if (!chosen.length) return;
                var day = od.value; if (!day) { say('Chọn ngày xuất.', '#dc2626'); return; }
                day = day.replace(/-/g, '/');
                var list = [], bad = '';
                chosen.forEach(function(it) {
                  var o = it.o, q = qn(qty[it.id]), av = qn(o.HANDOVER_AVAILABLE_QTY);
                  if (bad) return;
                  if (q <= 0) { bad = 'Số lượng xuất của ' + o.MATERIAL_CODE + ' phải lớn hơn 0.'; return; }
                  if (q > av + 0.0005) { bad = o.MATERIAL_CODE + ': số lượng xuất ' + fq(q) + ' vượt quá số còn xuất được ' + fq(av) + '.'; return; }
                  list.push({ RSI_HEADER_ID: o.RSI_HEADER_ID, RSI_LINE_ID: o.RSI_LINE_ID, HANDOVER_DATE: day, HANDOVER_QTY: q,
                    MATERIAL_CODE: o.MATERIAL_CODE, PROJECT_NO: o.PROJECT_NO || h.PROJECT_NO || diProj(idoc), RECEIVER_NAME: orc.value.trim() });
                });
                if (bad) { say(bad, '#dc2626'); return; }
                if (win.confirm && !win.confirm('Ghi xuất kho ' + list.length + ' dòng lên DESM ngày ' + day + '? Thao tác này không tự hoàn tác được.')) return;
                saving = true; say('Đang lưu…', ''); refreshBar(shownItems());
                var json = JSON.stringify(list);
                function fin(text, color) { saving = false; say(text, color); refreshBar(shownItems()); }
                mrrPost(win, '/saveDesmRsiOutSave.do', { updateList: json }, function(d) {
                  if (!d || typeof d !== 'object') { fin('Phản hồi không rõ. Hãy kiểm tra trên web trước khi thử lại.', '#dc2626'); return; }
                  if (d.error == null) {
                    sel = {}; qty = {}; say('Đã xuất kho ' + list.length + ' dòng ✓', '#15803d'); saving = false;
                    pending = 1; loadOut(settled);
                  } else if (d.error === 'QTY') {
                    fin('Vượt số lượng được xuất ở một dòng (còn xuất được: ' + (d.HANDOVER_AVAILABLE_QTY == null ? '?' : d.HANDOVER_AVAILABLE_QTY) + '). Tải lại màn hình để kiểm tra.', '#dc2626');
                  } else fin(String(d.error), '#dc2626');
                }, function(e) { fin('Không lưu được: ' + e + '. Kiểm tra trên web xem đã xuất chưa trước khi thử lại.', '#dc2626'); },
                { label: 'Xuất kho (RSI Detail)', payload: json, before: '' });
              });
              diAjax(idoc, '/getDesmRsiViewList.do', rsiParam({ PROJECT_NO: h.PROJECT_NO, RSI_NO: h.RSI_NO }), function(list) {
                all = [].filter.call(list, function(r) { return sameStr(r.RSI_NO, h.RSI_NO); }); showInfo(all[0]); settled();
              }, function() { if (alive()) { rn.textContent = 'Không tải được danh sách hạng mục của RSI.'; all = []; settled(); } });
              loadOut(settled);
          }
          function mrfTickList(win, doc, idoc, b, h, unit, alive) {
              function el(tag, cls, text) { var e = doc.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
              function dash(v) { return v ? v : '-'; }
              function fnum(v) {
                var t = String(v == null ? '' : v).replace(/,/g, ''), n = parseFloat(t);
                if (t === '' || isNaN(n)) return '-';
                return n.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 3 });
              }
              function sameStr(a, b2) { return String(a == null ? '' : a).replace(/\s+/g, ' ').trim() === String(b2 == null ? '' : b2).replace(/\s+/g, ' ').trim(); }
              function mrfParam(over) {
                var p = { PROJECT_NO: '', RSI_NO: '', RSI_NAME: '', SUBCONTRACTOR: '', MATERIAL_CODE: '', RSI_START_REQUEST_DATE: '', RSI_END_REQUEST_DATE: '',
                  ZIM_ATTRIBUTE10: '', RSI_BALANCE_QTY: '', TYPE: '', CATEGORY: '', SUB_CATEGORY: '', PACKING_LIST_NO: '', MRF_NO: '', MRF_NAME: '',
                  PACKAGE_NO: '', ITEM_DESC: '', RETURN_TYPE: '', MRF_BALANCE_QTY: '' };
                for (var k in over) p[k] = over[k];
                if (!p.PROJECT_NO) p.PROJECT_NO = diProj(idoc);
                return p;
              }
              var fb = el('div', 'desm-sub-filter');
              var fp = doc.createElement('input'); fp.placeholder = 'PKG.'; fp.className = 'desm-sub-in';
              var fs = doc.createElement('input'); fs.placeholder = 'SCH.'; fs.className = 'desm-sub-in';
              fb.appendChild(fp); fb.appendChild(fs); b.appendChild(fb);
              var ob = el('div', 'desm-sub-filter');
              var od = doc.createElement('input'); od.type = 'date'; od.className = 'desm-sub-in';
              var tdy = new Date(); od.value = tdy.getFullYear() + '-' + ('0' + (tdy.getMonth() + 1)).slice(-2) + '-' + ('0' + tdy.getDate()).slice(-2);
              ob.appendChild(od); b.appendChild(ob);
              var bar = el('div', 'desm-ditems-bar desm-out-bar');
              var allCb = doc.createElement('input'); allCb.type = 'checkbox'; allCb.className = 'desm-chk desm-out-chk';
              var barTxt = el('span', 'desm-cards-count', 'ALL');
              var outBtn = el('button', 'desm-out-btn', 'RETURN'); outBtn.type = 'button'; outBtn.disabled = true;
              bar.appendChild(allCb); bar.appendChild(barTxt); bar.appendChild(outBtn); b.appendChild(bar);
              var rn = el('div', 'desm-detail-note', 'Đang tải…'), rl = el('div', 'desm-ditems');
              var msg = el('div', 'desm-detail-note', '');
              b.appendChild(msg); b.appendChild(rn); b.appendChild(rl);
              var all = [], out = [], items = [], sel = {}, qty = {}, outOk = false, pending = 2, saving = false;
              function nz(v) { return String(v == null ? '' : v).replace(/\s+/g, ' ').trim().toLowerCase(); }
              function qn(v) { var n = parseFloat(String(v == null ? '' : v).replace(/,/g, '')); return isNaN(n) ? 0 : n; }
              function fq(v) { return v === Math.round(v) ? String(Math.round(v)) : String(Math.round(v * 1000) / 1000); }
              function say(t, c) { msg.textContent = t || ''; msg.style.color = c || ''; }
              function has(v) { return v != null && v !== ''; }
              function validOut(o) { return o && has(o.MRF_LINE_ID) && has(o.MRF_HEADER_ID); }
              function oid(o) { return validOut(o) ? String(o.MRF_LINE_ID) + '-' + (has(o.RSI_LINE_ID) ? String(o.RSI_LINE_ID) : '') : ''; }
              // Ghép dòng của MRF (getMrfSummaryList) với dòng còn trả được (getDesmReturnCreationList)
              function build() {
                var used = [], outs = out.filter(function(o) { return sameStr(o.MRF_NO, h.MRF_NO); });
                function free(f) { for (var i = 0; i < outs.length; i++) if (used.indexOf(outs[i]) < 0 && f(outs[i])) return outs[i]; return null; }
                items = all.map(function(r) {
                  var o = null;
                  if (has(r.MRF_LINE_ID)) o = free(function(x) { return String(x.MRF_LINE_ID) === String(r.MRF_LINE_ID) && (!has(r.RSI_LINE_ID) || !has(x.RSI_LINE_ID) || String(x.RSI_LINE_ID) === String(r.RSI_LINE_ID)); });
                  if (!o) o = free(function(x) { return nz(x.PACKAGE_NO) === nz(r.PACKAGE_NO) && nz(x.MATERIAL_CODE) === nz(r.MATERIAL_CODE) && (!has(r.RSI_NO) || !has(x.RSI_NO) || nz(x.RSI_NO) === nz(r.RSI_NO)); });
                  if (o) used.push(o);
                  return { r: r, o: o, id: oid(o) };
                });
                // Dòng còn trả được nhưng không ghép được: vẫn hiện để không bỏ sót
                outs.forEach(function(o) { if (used.indexOf(o) < 0) items.push({ r: o, o: o, id: oid(o) }); });
                var ids = {}; items.forEach(function(it) { if (it.id) ids[it.id] = 1; });
                for (var k in sel) if (!ids[k]) delete sel[k];
              }
              function shownItems() {
                var p = fp.value.trim().toLowerCase(), s = fs.value.trim().toLowerCase();
                return items.filter(function(it) {
                  var r = it.r;
                  return (!p || String(r.PACKAGE_NO || '').toLowerCase().indexOf(p) >= 0) &&
                    (!s || (String(r.DESCRIPTION || r.RSI_DESCRIPTION || '') + ' ' + String(r.MATERIAL_CODE || '')).toLowerCase().indexOf(s) >= 0);
                });
              }
              function avail(it) { return qn(it.o.RETURN_AVAILABLE_QTY); }
              function toggle(it) {
                if (!it.id || saving) return;
                if (sel[it.id]) delete sel[it.id];
                else { sel[it.id] = 1; if (qty[it.id] == null || qty[it.id] === '') qty[it.id] = fq(avail(it)); }
                draw();
              }
              function refreshBar(shown) {
                var n = Object.keys(sel).length, v = shown.filter(function(it) { return it.id; });
                allCb.checked = v.length > 0 && v.every(function(it) { return sel[it.id]; });
                outBtn.textContent = n ? 'RETURN (' + n + ')' : 'RETURN';
                outBtn.disabled = saving || !n;
                barTxt.textContent = 'ALL' + (v.length ? ' · ' + v.length + ' dòng trả được' : '');
              }
              function draw() {
                while (rl.firstChild) rl.removeChild(rl.firstChild);
                var rows = shownItems();
                rn.textContent = items.length ? rows.length + ' / ' + items.length + ' dòng' : 'MRF này không có dòng nào.';
                if (!outOk && !pending) rn.textContent += ' · chưa tải được dữ liệu trả hàng nên chưa tích chọn được';
                rows.forEach(function(it) {
                  var r = it.r, on = !!(it.id && sel[it.id]);
                  var c = el('div', 'desm-rsi-card desm-mrf-card' + (on ? ' desm-sel' : ''));
                  var t1 = el('div', 'desm-rsi-top'); t1.appendChild(el('span', 'desm-ditem-no', dash(r.RSI_NO)));
                  var tr = el('span', 'desm-mrf-type', dash(r.RETURN_TYPE || r.TYPE)); t1.appendChild(tr);
                  if (it.id) {
                    var cb = doc.createElement('input'); cb.type = 'checkbox'; cb.className = 'desm-chk desm-out-chk'; cb.checked = on; t1.appendChild(cb);
                  }
                  c.appendChild(t1);
                  if (r.RSI_NAME) c.appendChild(el('div', 'desm-ditem-no', dash(r.RSI_NAME)));
                  c.appendChild(el('div', 'desm-ditem-no', dash(r.PACKAGE_NO)));
                  var t2 = el('div', 'desm-rsi-top'); t2.appendChild(el('span', 'desm-ditem-l', dash(r.DESCRIPTION || r.RSI_DESCRIPTION)));
                  if (it.id) {
                    var qi = doc.createElement('input'); qi.type = 'text'; qi.setAttribute('inputmode', 'decimal'); qi.className = 'desm-sub-in desm-out-qty';
                    qi.value = qty[it.id] != null ? qty[it.id] : fq(avail(it));
                    qi.addEventListener('click', function(e) { e.stopPropagation(); });
                    qi.addEventListener('input', (function(id) { return function() { qty[id] = qi.value; }; })(it.id));
                    t2.appendChild(qi);
                  }
                  c.appendChild(t2);
                  c.appendChild(el('div', 'desm-ditem-l', 'DWG : ' + (r.DRAWING_NO || 'N/A') + '   TAG : ' + (r.TAG_NO || 'N/A')));
                  var ft = el('div', 'desm-rsi-row'); ft.appendChild(el('span', '', dash(r.MATERIAL_CODE)));
                  if (it.o) {
                    var av = avail(it), dn = Math.max(0, qn(it.o.REQ_RETURN_QTY) - av);
                    var q = el('span', ''); q.appendChild(el('b', 'desm-out-av', av.toFixed(3))); q.appendChild(doc.createTextNode(' / ')); q.appendChild(el('b', 'desm-out-done', dn.toFixed(3)));
                    ft.appendChild(q);
                  } else {
                    ft.appendChild(el('span', 'desm-mrf-type', fnum(r.MRF_REQ_RETURN_QTY) + ' / ' + fnum(r.MRF_RETURN_QTY) + ' ' + (r.UNIT || unit || '')));
                  }
                  c.appendChild(ft);
                  c.appendChild(el('div', 'desm-ditem-l', '📍 ' + dash(r.LOCATION) + '   Req : ' + dash(r.RETURN_REQ_DATE)));
                  if (it.o) c.appendChild(el('div', 'desm-ditem-l desm-out-hint', 'đỏ = còn trả được · xanh = đã trả'));
                  c.addEventListener('click', function() { toggle(it); });
                  rl.appendChild(c);
                });
                refreshBar(rows);
              }
              fp.addEventListener('input', draw); fs.addEventListener('input', draw);
              allCb.addEventListener('click', function(e) { e.preventDefault(); });
              bar.addEventListener('click', function(e) {
                if (e.target === outBtn || saving) return;
                var v = shownItems().filter(function(it) { return it.id; }), on = !(v.length && v.every(function(it) { return sel[it.id]; }));
                v.forEach(function(it) {
                  if (on) { sel[it.id] = 1; if (qty[it.id] == null || qty[it.id] === '') qty[it.id] = fq(avail(it)); }
                  else delete sel[it.id];
                });
                draw();
              });
              function settled() { if (!alive()) return; pending--; if (pending <= 0) { pending = 0; build(); draw(); } }
              function loadOut(done) {
                diAjax(idoc, '/getDesmReturnCreationList.do', { PROJECT_NO: h.PROJECT_NO || diProj(idoc), PACKAGE_NO: '', MRF_NO: h.MRF_NO, MATERIAL_CODE: '',
                  REQUEST_START_DATE: '', ATTRIBUTE10: '', REQUEST_END_DATE: '', TYPE: '', CATEGORY: '' },
                  function(list) { out = [].slice.call(list); outOk = true; done(); },
                  function() { out = []; outOk = false; done(); });
              }
              // RETURN: kiểm tra giống tab Trả hàng rồi POST /saveDesmMrfReturnSave.do
              outBtn.addEventListener('click', function() {
                if (saving) return;
                var chosen = items.filter(function(it) { return it.id && sel[it.id]; });
                if (!chosen.length) return;
                var day = od.value; if (!day) { say('Chọn ngày trả.', '#dc2626'); return; }
                day = day.replace(/-/g, '/');
                var list = [], bad = '';
                chosen.forEach(function(it) {
                  var o = it.o, q = qn(qty[it.id]), av = avail(it);
                  if (bad) return;
                  if (q <= 0) { bad = 'Số lượng trả của ' + o.MATERIAL_CODE + ' phải lớn hơn 0.'; return; }
                  if (q > av + 0.0005) { bad = o.MATERIAL_CODE + ': số lượng trả ' + fq(q) + ' vượt quá số còn trả được ' + fq(av) + '.'; return; }
                  list.push({ MRF_HEADER_ID: o.MRF_HEADER_ID, MRF_LINE_ID: o.MRF_LINE_ID, MATERIAL_CODE: o.MATERIAL_CODE,
                    PROJECT_NO: o.PROJECT_NO || h.PROJECT_NO || diProj(idoc), RETURN_DATE: day, RETURN_QTY: q, RSI_LINE_ID: o.RSI_LINE_ID == null ? null : o.RSI_LINE_ID });
                });
                if (bad) { say(bad, '#dc2626'); return; }
                if (win.confirm && !win.confirm('Ghi trả hàng ' + list.length + ' dòng lên DESM ngày ' + day + '? Thao tác này không tự hoàn tác được.')) return;
                saving = true; say('Đang lưu…', ''); refreshBar(shownItems());
                var json = JSON.stringify(list);
                function fin(text, color) { saving = false; say(text, color); refreshBar(shownItems()); }
                mrrPost(win, '/saveDesmMrfReturnSave.do', { updateList: json }, function(d) {
                  if (!d || typeof d !== 'object') { fin('Phản hồi không rõ. Hãy kiểm tra trên web trước khi thử lại.', '#dc2626'); return; }
                  if (d.error == null) {
                    sel = {}; qty = {}; say('Đã trả hàng ' + list.length + ' dòng ✓', '#15803d'); saving = false;
                    pending = 1; loadOut(settled);
                  } else if (d.error === 'QTY') {
                    fin('Vượt số lượng được trả ở một dòng (còn trả được: ' + (d.RETURN_AVAILABLE_QTY == null ? '?' : d.RETURN_AVAILABLE_QTY) + '). Tải lại màn hình để kiểm tra.', '#dc2626');
                  } else fin(String(d.error), '#dc2626');
                }, function(e) { fin('Không lưu được: ' + e + '. Kiểm tra trên web xem đã trả chưa trước khi thử lại.', '#dc2626'); },
                { label: 'Trả hàng MRF (MRF Detail)', payload: json, before: '' });
              });
              diAjax(idoc, '/getMrfSummaryList.do', mrfParam({ PROJECT_NO: h.PROJECT_NO, MRF_NO: h.MRF_NO }), function(list) {
                all = [].filter.call(list, function(r) { return sameStr(r.MRF_NO, h.MRF_NO); }); settled();
              }, function() { if (alive()) { rn.textContent = 'Không tải được chi tiết MRF.'; all = []; settled(); } });
              loadOut(settled);
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
            var stDone = (function() {
              var pr = g('OUT_STATUS_QTY').split('/').map(function(x) { return parseFloat(String(x).replace(/,/g, '')); });
              return pr.length > 1 && !isNaN(pr[0]) && !isNaN(pr[1]) && pr[0] > 0 && pr[0] - pr[1] <= 0;
            })();
            tri.appendChild(el('span', '', g('PACKAGE_STATUS') || (stDone ? 'CLOSE' : 'N/A')));
            tri.appendChild(el('span', '', ao || '-'));
            tri.appendChild(el('span', '', pair('OUT_STATUS_QTY') || '-'));
            m.appendChild(tri);
            // Hàng Remarks + ô "Remaining" (số lượng còn lại = tổng - đã xuất, từ cột OUT_STATUS_QTY, vd 1060/60 -> 1000)
            var remRow = el('div', 'desm-d-remrow');
            remRow.appendChild(el('span', 'desm-d-remtxt', 'S/C & Excel Remarks ' + g('REMARKS')));
            (function() {
              var pr = g('OUT_STATUS_QTY').split('/').map(function(x) { return parseFloat(String(x).replace(/,/g, '')); });
              if (pr.length < 2 || isNaN(pr[0]) || isNaN(pr[1]) || pr[1] <= 0) return;   // chưa xuất gì -> không hiện Remaining
              var left = Math.round((pr[0] - pr[1]) * 1000) / 1000;
              var box2 = el('span', 'desm-d-rembox' + (left > 0 ? ' desm-d-rem-open' : ' desm-d-rem-done'));
              box2.appendChild(el('span', 'desm-d-remlbl', 'Remaining'));
              box2.appendChild(el('span', 'desm-d-remval', left.toLocaleString('en-US', { maximumFractionDigits: 3 })));
              remRow.appendChild(box2);
            })();
            m.appendChild(remRow);
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
            // Màn "MRF Detail" / "RSI Detail" (từ Detail Item): phần danh sách dùng chung mrfTickList / rsiTickList
            function openMrfDetail(h, unit, back) {
              var S = subScreen('MRF Detail', back || 'Detail Item'), b = S.body;
              var m = el('div', 'desm-dcard desm-mrf-head');
              m.appendChild(el('div', 'desm-d-h', dash(h.MRF_NO)));
              m.appendChild(el('div', 'desm-d-l', dash(h.SUBCONTRACTOR) + ' · ' + dash(h.STATUS)));
              m.appendChild(el('div', 'desm-d-l', dash(h.MRF_NAME)));
              if (h.RETURN_REQ_DATE) m.appendChild(el('div', 'desm-d-l', 'Ngày yêu cầu trả : ' + h.RETURN_REQ_DATE));
              b.appendChild(m);
              mrfTickList(win, doc, idoc, b, h, unit, function() { return !!S.ov.parentNode; });
            }
            function openRsiDetail(h, back) {
              var S = subScreen('RSI Detail', back || 'Detail Item'), b = S.body;
              var m = el('div', 'desm-dcard');
              m.appendChild(el('div', 'desm-d-h', dash(h.RSI_NO)));
              m.appendChild(el('div', 'desm-d-l', dash(h.SUBCONTRACTOR) + ' · ' + dash(h.STATUS)));
              m.appendChild(el('div', 'desm-d-l', dash(h.RSI_NAME)));
              m.appendChild(el('div', 'desm-d-l', dash(h.RSI_APPROVED_DATE || h.REQUEST_DATE)));
              b.appendChild(m);
              rsiTickList(win, doc, idoc, b, h, function() { return !!S.ov.parentNode; });
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
                // Số lượng từng hạng mục: In/Out (vd 50/30) + Remaining (còn lại = REMAIN_QTY, thiếu thì In - Out)
                (function() {
                  function pn(v) { return parseFloat(String(v == null ? '' : v).replace(/,/g, '')); }
                  var inQ = pn(x.IN_QTY), outQ = pn(x.OUT_QTY), remQ = pn(x.REMAIN_QTY);
                  if (isNaN(inQ)) return;
                  if (isNaN(outQ)) outQ = 0;
                  if (isNaN(remQ)) remQ = Math.round((inQ - outQ) * 1000) / 1000;
                  var qr = el('div', 'desm-ditem-l desm-ditem-qty');
                  qr.appendChild(el('span', 'desm-ditem-qtxt', "Q'ty : " + fnum(inQ) + '/' + fnum(outQ) + (x.UNIT ? ' ' + x.UNIT : '')));
                  if (outQ > 0) qr.appendChild(el('span', 'desm-d-rembox2 ' + (remQ > 0 ? 'desm-d-rem-open' : 'desm-d-rem-done'), 'Remaining ' + fnum(remQ)));   // chỉ khi đã xuất
                  c.appendChild(qr);
                })();
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
            // RSI & MRF List của cả kiện: chỉ hiện khi kiện có phiếu RSI hoặc MRF; chạm để mở danh sách, chạm một phiếu để xem RSI Detail / MRF Detail
            var prb = el('button', 'desm-detail-list', 'RSI & MRF List  ↓'); prb.type = 'button'; prb.style.display = 'none';
            var prl = el('div', 'desm-ditems'), prl1 = el('div', ''), prl2 = el('div', ''), prOpen = false, prCnt = 0;
            prl.appendChild(prl1); prl.appendChild(prl2); prl.style.display = 'none';
            prb.addEventListener('click', function() { prOpen = !prOpen; prl.style.display = prOpen ? '' : 'none'; prb.textContent = 'RSI & MRF List  ' + (prOpen ? '↑' : '↓'); });
            body.appendChild(prb); body.appendChild(prl);
            (function() {
              // Gom các dòng của kiện theo số phiếu (một phiếu có thể có nhiều dòng của cùng kiện)
              function groupBy(list, key, qtyKey) {
                var m = {}, order = [];
                [].forEach.call(list, function(r) {
                  if (!r || !sameStr(r.PACKAGE_NO, pkgNo)) return;
                  var k = String(r[key] == null ? '' : r[key]).trim(); if (!k) return;
                  if (!m[k]) { m[k] = { h: r, n: 0, q: 0 }; order.push(k); }
                  m[k].n++; var q = parseFloat(String(r[qtyKey] == null ? '' : r[qtyKey]).replace(/,/g, '')); if (!isNaN(q)) m[k].q += q;
                });
                return order.map(function(k) { return m[k]; });
              }
              function reveal() { if (prCnt > 0) prb.style.display = ''; }
              diAjax(idoc, '/getDesmRsiViewList.do', rsiParam({ PACKAGE_NO: pkgNo }), function(list) {
                if (!ov.parentNode) return;
                var gs = groupBy(list, 'RSI_NO', 'REQ_QTY'); prCnt += gs.length;
                gs.forEach(function(g) {
                  var r = g.h, c = el('div', 'desm-rsi-card');
                  var t1 = el('div', 'desm-rsi-row'); t1.appendChild(el('span', 'desm-ditem-no', dash(r.RSI_NO))); t1.appendChild(el('span', '', dash(r.STATUS))); c.appendChild(t1);
                  c.appendChild(el('div', 'desm-ditem-l', dash(r.SUBCONTRACTOR) + ' · ' + dash(r.RSI_NAME)));
                  var t3 = el('div', 'desm-rsi-row'); t3.appendChild(el('span', '', dash(r.RSI_APPROVED_DATE || r.REQUEST_DATE)));
                  t3.appendChild(el('span', '', g.n + ' dòng · ' + fnum(g.q) + ' ' + (r.UNIT || ''))); c.appendChild(t3);
                  c.addEventListener('click', function() { openRsiDetail(r, 'Package'); });
                  prl1.appendChild(c);
                });
                reveal();
              }, function() {});
              diAjax(idoc, '/getMrfSummaryList.do', mrfParam({ PACKAGE_NO: pkgNo }), function(list) {
                if (!ov.parentNode) return;
                var gs = groupBy(list, 'MRF_NO', 'MRF_REQ_RETURN_QTY'); prCnt += gs.length;
                gs.forEach(function(g) {
                  var r = g.h, c = el('div', 'desm-rsi-card desm-mrf-card');
                  var t1 = el('div', 'desm-rsi-row'); t1.appendChild(el('span', 'desm-ditem-no', dash(r.MRF_NO))); t1.appendChild(el('span', '', dash(r.STATUS))); c.appendChild(t1);
                  c.appendChild(el('div', 'desm-ditem-l', dash(r.SUBCONTRACTOR) + ' · ' + dash(r.MRF_NAME)));
                  var t3 = el('div', 'desm-rsi-row'); t3.appendChild(el('span', '', dash(r.RETURN_REQ_DATE)));
                  t3.appendChild(el('span', '', g.n + ' dòng · ' + fnum(g.q) + ' ' + (r.UNIT || ''))); c.appendChild(t3);
                  c.addEventListener('click', function() { openMrfDetail(r, r.UNIT, 'Package'); });
                  prl2.appendChild(c);
                });
                reveal();
              }, function() {});
            })();
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
        """#
}
