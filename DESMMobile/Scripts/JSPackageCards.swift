// JSPackageCards.swift — phần JS "Danh sách thẻ Package (cardView)" của script giao diện tiêm vào trang DESM.
// Ghép lại ở UserScript.swift (makeScript) theo đúng thứ tự file gốc; các phần dùng chung một phạm vi hàm nên gọi chéo nhau được.
// Mỗi phần chỉ nên chứa trọn các khai báo hàm/biến ở mức trên cùng. Kiểm tra cú pháp: python3 tools/check_js.py (cần Node).
// Hàm trong phần này: cardView

extension UserJS {
    static let pkgCards = #"""
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
              if (box.__setHidden) box.__setHidden(false);
              if (tb) tb.classList.remove('desm-tb-nosel');
              var chip0 = doc.getElementById('desmSelAllChip'); if (chip0 && chip0.parentNode) chip0.parentNode.removeChild(chip0);
              if (box.__wasOn) { box.__wasOn = false; try { win.dispatchEvent(new win.Event('resize')); } catch (e) {} }
              return;
            }
            box.__wasOn = true;
            try {
              var top = box.getBoundingClientRect().top;
              box.style.height = Math.max(160, win.innerHeight - top - 4) + 'px';
            } catch (e) {}
            // Vuốt lên xem danh sách kiện thì tự ẩn TOÀN BỘ phần phía trên danh sách (hàng Bộ lọc/Search, ô Package No., thanh nút "...")
            // để thẻ chiếm cả màn hình. Vuốt xuống một chút, về đầu danh sách, hoặc đang nhập vào ô lọc thì hiện lại. (Giống màn RSI/MRR/MRF.)
            if (!box.__hideInit) {
              box.__hideInit = true;
              var pLastY = 0;
              var pTopEls = function() {
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
              };
              var pFit = function() {
                try { box.style.height = Math.max(160, win.innerHeight - box.getBoundingClientRect().top - 4) + 'px'; } catch (e) {}
              };
              box.__setHidden = function(on) {
                if (on === !!box.__tophid) return;
                if (on) {
                  var els = pTopEls(), total = 0;
                  els.forEach(function(x) { total += x.offsetHeight; });
                  // Chỉ ẩn khi sau khi ẩn danh sách vẫn còn đủ chỗ cuộn (tránh nhấp nháy ẩn/hiện liên tục)
                  if (box.scrollHeight - box.clientHeight < total + 140) return;
                  if (els.some(function(x) { return x.contains(doc.activeElement); })) return;
                  els.forEach(function(x) { x.classList.add('desm-tophide'); });
                  box.__tophid = els;
                } else {
                  (box.__tophid || []).forEach(function(x) { x.classList.remove('desm-tophide'); });
                  box.__tophid = null;
                }
                pFit();
              };
              box.addEventListener('scroll', function() {
                var y = box.scrollTop, dy = y - pLastY; pLastY = y;
                // Đang chụp toàn trang (cuộn-ghép): giữ nguyên bố cục, không ẩn/hiện thanh trên — nếu không vùng thẻ đổi chiều cao giữa các đoạn → ghép lệch, mất/che kiện
                try { if (win.top.__desmShotBusy || win.__desmShotBusy) return; } catch (e) { if (win.__desmShotBusy) return; }
                if (y <= 8) { box.__setHidden(false); return; }
                if (dy > 8) box.__setHidden(true);
                else if (dy < -8) box.__setHidden(false);
              }, { passive: true });
              doc.addEventListener('focusin', function(e) {
                if (box.__tophid && !box.contains(e.target)) box.__setHidden(false);
              }, true);
            }
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
            function pairQ(t) { // "1,060.000/0.000" -> "1060/0" (giống ô trong màn chi tiết kiện)
              return String(t || '').split('/').map(function(x) {
                var v = parseFloat(String(x).replace(/,/g, '')); return isNaN(v) ? String(x).trim() : String(v);
              }).join('/');
            }
            function stockOf(t) { // 'open' = còn hàng (tổng - đã xuất > 0), 'done' = đã xuất hết, '' = không đọc được
              var pr = String(t || '').split('/').map(function(x) { return parseFloat(String(x).replace(/,/g, '')); });
              if (pr.length < 2 || isNaN(pr[0]) || isNaN(pr[1])) return '';
              if (pr[0] - pr[1] > 0) return 'open';
              return pr[0] > 0 ? 'done' : '';
            }
            function remOf(t) { // "1,060.000/60.000" -> 1000 (tổng - đã xuất); không đọc được -> ''
              var pr = String(t || '').split('/').map(function(x) { return parseFloat(String(x).replace(/,/g, '')); });
              if (pr.length < 2 || isNaN(pr[0]) || isNaN(pr[1]) || pr[1] <= 0) return '';   // chưa xuất gì -> không hiện Remaining
              return Math.round((pr[0] - pr[1]) * 1000) / 1000;
            }
            var allItems = rows.map(function(r) {
              return {
                id: r.id, sel: isSel(r), locDate: gridText(G, r, 'LOC_UPDATE_DATE'),
                no: gridText(G, r, 'PACKAGE_NO'), desc: gridText(G, r, 'DESCRIPTION'),
                type: gridText(G, r, 'PACKAGE_TYPE'), list: gridText(G, r, 'PACKAGE_LIST_NO'),
                ao: gridText(G, r, 'OUT_STATUS'), qty: pairQ(gridText(G, r, 'OUT_STATUS_QTY')), rem: remOf(gridText(G, r, 'OUT_STATUS_QTY')), stk: stockOf(gridText(G, r, 'OUT_STATUS_QTY')), st: gridText(G, r, 'PACKAGE_STATUS'), loc: gridText(G, r, 'STORAGE_LOCATION'),
                ok: gridText(G, r, 'IS_CONFIRM_MATERIAL').toUpperCase() === 'Y'
              };
            });
            // Ô lọc Packing List khớp kiểu 'chứa' (vd 0002 lấy cả DE-LS-0002 lẫn DE-IS-0002): cho thu hẹp theo từng list
            var listCnt = {}, listOrder = [];
            allItems.forEach(function(i) {
              var lk = i.list || '(trống)';
              if (!listCnt[lk]) { listCnt[lk] = 0; listOrder.push(lk); }
              listCnt[lk]++;
            });
            var listSel = box.__listSel || '';
            if (listSel && !listCnt[listSel]) { listSel = ''; box.__listSel = ''; }
            var byList = listSel ? allItems.filter(function(i) { return (i.list || '(trống)') === listSel; }) : allItems;
            var stockSel = box.__stockSel || '';
            var nOpen = 0, nDone = 0;
            byList.forEach(function(i) { if (i.stk === 'open') nOpen++; else if (i.stk === 'done') nDone++; });
            if (stockSel && !(nOpen + nDone)) { stockSel = ''; box.__stockSel = ''; }
            var items = stockSel ? byList.filter(function(i) { return i.stk === stockSel; }) : byList;
            // Lọc "chưa có vị trí" + sắp xếp (Số kiện A→Z / Z→A / cập nhật vị trí mới nhất). Chỉ đổi cách hiển thị, không đổi dữ liệu lưới.
            var locSel = box.__locSel || '';
            var nNoLoc = items.filter(function(i) { return !i.loc; }).length;
            if (locSel === 'none' && !nNoLoc) { locSel = ''; box.__locSel = ''; }
            if (locSel === 'none') items = items.filter(function(i) { return !i.loc; });
            var sortSel = box.__sortSel || '';
            if (sortSel) {
              items = items.slice();
              var nat = function(a, b) { return String(a.no).localeCompare(String(b.no), undefined, { numeric: true, sensitivity: 'base' }); };
              if (sortSel === 'no_asc') items.sort(nat);
              else if (sortSel === 'no_desc') items.sort(function(a, b) { return nat(b, a); });
              else if (sortSel === 'date_desc') items.sort(function(a, b) {
                if (!a.locDate && !b.locDate) return nat(a, b);
                if (!a.locDate) return 1; if (!b.locDate) return -1;
                return a.locDate < b.locDate ? 1 : (a.locDate > b.locDate ? -1 : nat(a, b));
              });
            }
            try { win.__desmItems = { t: Date.now(), items: allItems }; } catch (e) {}   // Dodo: dữ liệu đang hiển thị trên màn hình
            // Mặc định ẩn nút Xóa vị trí / Cập nhật vị trí; chỉ hiện khi đã tích chọn ít nhất một kiện
            if (tb) tb.classList.toggle('desm-tb-nosel', !allItems.some(function(i) { return i.sel; }));
            // Thanh nút đổi chiều cao (thu/mở) nên tính lại chiều cao vùng thẻ cho vừa màn hình
            try { box.style.height = Math.max(160, win.innerHeight - box.getBoundingClientRect().top - 4) + 'px'; } catch (e) {}
            try { diWarm(box.ownerDocument); } catch (e) {}
            var sig = listSel + '@' + stockSel + '@' + locSel + '@' + sortSel + '@' + items.map(function(i) { return [i.id, i.sel ? 1 : 0, i.no, i.desc, i.type, i.list, i.ao, i.qty, i.rem, i.st, i.stk, i.loc, i.ok ? 1 : 0].join('|'); }).join('\n') + '#' + (win.__desmTapDetail ? 1 : 0);
            if (box.__sig === sig && (!tb || doc.getElementById('desmSelAllChip'))) return;
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
            bar.appendChild(el('span', 'desm-cards-count', nSel ? (nSel + '/' + items.length + ' kiện') : ('Chọn tất cả · ' + items.length + ' kiện')));
            // Đặt chung hàng với nút ⋯ ở thanh nút (cố định phía trên) để không đè lên thẻ khi cuộn
            if (tb) {
              var oldChip = doc.getElementById('desmSelAllChip'); if (oldChip && oldChip.parentNode) oldChip.parentNode.removeChild(oldChip);
              bar.id = 'desmSelAllChip'; bar.className = 'desm-selall-chip';
              tb.insertBefore(bar, tb.firstChild);
            } else box.appendChild(bar);
            // Nhiều Packing List trong kết quả: hàng nút chọn list. Chọn một list thì BỎ CHỌN các kiện ngoài list đó
            // (Location Delete/Update chạy trên mọi kiện đã chọn nên không để sót kiện của list khác).
            if (listOrder.length > 1) {
              var lrow = el('div', 'desm-cards-lists');
              var addChip = function(label, key) {
                var b = el('button', 'desm-list-chip' + (listSel === key ? ' on' : ''), label); b.type = 'button';
                b.addEventListener('click', function(ev) {
                  ev.preventDefault(); ev.stopPropagation();
                  if (key) {
                    allItems.forEach(function(it) {
                      if ((it.list || '(trống)') === key && (!stockSel || it.stk === stockSel) && (locSel !== 'none' || !it.loc)) return;
                      var r = G.Rows[it.id];
                      if (r && isSel(r)) { try { G.SelectRow(r, 0); } catch (e) {} }
                    });
                  }
                  box.__listSel = key; box.__sig = null; cardView(doc);
                });
                lrow.appendChild(b);
              };
              addChip('Tất cả (' + allItems.length + ')', '');
              listOrder.forEach(function(lk) { addChip(lk + ' (' + listCnt[lk] + ')', lk); });
              box.appendChild(lrow);
            }
            // Lọc theo tồn: Tất cả / Còn hàng / Đã xuất hết. Chọn một nhóm thì BỎ CHỌN các kiện bị ẩn (Location Delete/Update chạy trên kiện đã chọn)
            if (nOpen + nDone > 0) {
              var srow = el('div', 'desm-cards-lists desm-cards-stock');
              var addSt = function(label, key) {
                var b = el('button', 'desm-list-chip' + (key ? ' stk-' + key : '') + (stockSel === key ? ' on' : ''), label); b.type = 'button';
                b.addEventListener('click', function(ev) {
                  ev.preventDefault(); ev.stopPropagation();
                  allItems.forEach(function(it) {
                    var shown = (!listSel || (it.list || '(trống)') === listSel) && (!key || it.stk === key) && (locSel !== 'none' || !it.loc);
                    if (shown) return;
                    var r = G.Rows[it.id];
                    if (r && isSel(r)) { try { G.SelectRow(r, 0); } catch (e) {} }
                  });
                  box.__stockSel = key; box.__sig = null; cardView(doc);
                });
                srow.appendChild(b);
              };
              addSt('Tất cả (' + byList.length + ')', '');
              addSt('Còn hàng (' + nOpen + ')', 'open');
              addSt('Đã xuất hết (' + nDone + ')', 'done');
              box.appendChild(srow);
            }
            // Hàng công cụ: lọc vị trí, sắp xếp, xuất CSV
            var trow = el('div', 'desm-cards-lists desm-cards-tools');
            var addTool = function(label, cls, fn) {
              var b = el('button', 'desm-list-chip' + (cls ? ' ' + cls : ''), label); b.type = 'button';
              b.addEventListener('click', function(ev) { ev.preventDefault(); ev.stopPropagation(); fn(); });
              trow.appendChild(b);
            };
            if (nNoLoc > 0 || locSel) {
              addTool('Chưa có vị trí (' + nNoLoc + ')', locSel === 'none' ? 'on stk-open' : 'stk-open', function() {
                var key = locSel === 'none' ? '' : 'none';
                if (key === 'none') {   // ẩn kiện có vị trí -> bỏ chọn chúng (Location Delete/Update chạy trên kiện đã chọn)
                  allItems.forEach(function(it) {
                    if (!it.loc) return;
                    var r = G.Rows[it.id]; if (r && isSel(r)) { try { G.SelectRow(r, 0); } catch (e) {} }
                  });
                }
                box.__locSel = key; box.__sig = null; cardView(doc);
              });
            }
            [['', 'Thứ tự gốc'], ['no_asc', 'Số kiện ↑'], ['no_desc', 'Số kiện ↓'], ['date_desc', 'Mới cập nhật']].forEach(function(o) {
              addTool(o[1], sortSel === o[0] ? 'on' : '', function() { box.__sortSel = o[0]; box.__sig = null; cardView(doc); });
            });
            addTool('⬇ Xuất CSV (' + (nSel || items.length) + ')', '', function() {
              var out = nSel ? items.filter(function(i) { return i.sel; }) : items;
              if (!out.length) return;
              var q = function(v) { v = String(v == null ? '' : v); return /[",;\r\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
              var head = ['Package No', 'Mô tả', 'Loại', 'Packing List', 'Trạng thái', 'Tồn kho', 'SL tổng', 'SL đã xuất', 'Vị trí', 'Cập nhật vị trí', 'Đã xác nhận'];
              var lines = [head.map(q).join(',')];
              out.forEach(function(it) {
                var pr = String(it.qty || '').split('/');
                lines.push([it.no, it.desc, it.type, it.list, it.st, it.stk === 'open' ? 'Còn hàng' : (it.stk === 'done' ? 'Đã xuất hết' : ''),
                            pr[0] || '', pr[1] || '', it.loc, it.locDate, it.ok ? 'Y' : ''].map(q).join(','));
              });
              try { win.webkit.messageHandlers.desmExport.postMessage({ name: 'kien-hang' + (listSel ? '-' + listSel : ''), csv: lines.join('\r\n') }); } catch (e) {}
            });
            box.appendChild(trow);
            var pkgSeen = {}, nUniq = 0;
            items.forEach(function(i) { if (i.no && !pkgSeen[i.no]) { pkgSeen[i.no] = 1; nUniq++; } });
            if (items.length && nUniq < items.length) {
              box.appendChild(el('div', 'desm-cards-note', items.length + ' dòng = ' + nUniq + ' kiện khác nhau'));
            }
            if (!items.length) box.appendChild(el('div', 'desm-cards-empty', allItems.length ? 'Không có kiện nào khớp bộ lọc này.' : 'Chưa có kiện hàng nào. Hãy nhập điều kiện lọc rồi bấm Search.'));
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
              var stats = el('span', 'desm-card-stats');
              // Nhãn = trạng thái kiện như màn chi tiết: CLOSE khi đã xuất hết, còn lại N/A (hoặc giá trị PACKAGE_STATUS của DESM)
              var stLbl = (it.st && String(it.st).trim()) || (it.stk === 'done' ? 'CLOSE' : 'N/A');
              stats.appendChild(el('span', 'desm-card-ao' + (/^close/i.test(stLbl) ? ' desm-st-close' : ''), it.ao ? stLbl + ' : ' + it.ao : stLbl));
              if (it.qty) stats.appendChild(el('span', 'desm-card-qty', it.qty));   // vd 1060/0: giống dòng số lượng trong chi tiết kiện
              foot.appendChild(stats);
              // Còn lại: viên thuốc ở góc phải hàng A/O (cam = còn hàng, xanh = đã xuất hết)
              if (it.rem !== '') {
                foot.appendChild(el('span', 'desm-card-rem ' + (it.rem > 0 ? 'desm-d-rem-open' : 'desm-d-rem-done'),
                  'Remaining ' + Number(it.rem).toLocaleString('en-US', { maximumFractionDigits: 3 })));
              }
              var loc = el('span', 'desm-card-loc');
              var NS = 'http://www.w3.org/2000/svg';
              var svg = doc.createElementNS(NS, 'svg'); svg.setAttribute('viewBox', '0 0 24 24');
              svg.setAttribute('width', '16'); svg.setAttribute('height', '16');
              var pth = doc.createElementNS(NS, 'path');
              pth.setAttribute('d', 'M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9.5a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5z');
              pth.setAttribute('fill', 'none'); pth.setAttribute('stroke', 'currentColor'); pth.setAttribute('stroke-width', '2');
              svg.appendChild(pth); loc.appendChild(svg);
              loc.appendChild(el('span', 'desm-card-loctxt', it.loc || '—'));
              card.appendChild(foot);
              var locRow = el('div', 'desm-card-locrow'); locRow.appendChild(loc); card.appendChild(locRow);   // vị trí xuống hàng riêng, đủ chỗ hiện hết
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
            // Báo cho app (màn khởi động) biết màn Package đã dựng xong lần đầu
            try { var tw = win; try { tw = win.top; void tw.document; } catch (e0) { tw = win; } if (!tw.__desmReadySent) { tw.__desmReadySent = 1; win.webkit.messageHandlers.desmReady.postMessage(1); } } catch (e) {}
          }
        """#
}
