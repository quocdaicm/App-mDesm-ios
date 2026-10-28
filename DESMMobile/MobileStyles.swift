// MobileStyles.swift — CSS của chế độ "Mobile" (tiêm vào trang DESM, mọi selector bắt đầu bằng html.desm-mobile-mode).
// Gồm: ngăn kéo menu, form tìm kiếm lưới 2 cột, thanh Bộ lọc, thẻ Package/RSI..., header/footer SVG nhúng.
// Muốn chỉnh nhanh không cần build lại: Cài đặt > CSS bổ sung (lưu ở desmCustomCSS, nối sau CSS này).
// Xem DEV_NOTES.md.
import Foundation

enum MobileStyles {
    static let css = #"""
    html.desm-mobile-mode { color-scheme: light; -webkit-text-size-adjust:100%; }
    html.desm-mobile-mode, html.desm-mobile-mode body {
      width:100%!important; min-width:0!important; max-width:100%!important;
    }
    html.desm-mobile-mode body {
      margin:0!important; background:#f3f6fb!important;
      font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif!important;
      color:#1f2937!important;
    }
    html.desm-mobile-mode * { box-sizing:border-box; }
    html.desm-mobile-mode :is(img, video, canvas):not(:is(.modal, .ui-dialog) *) { max-width:100%; }
    @media(max-width:800px) {
      html.desm-mobile-mode #wrapper, html.desm-mobile-mode #content,
      html.desm-mobile-mode #main, html.desm-mobile-mode .container,
      html.desm-mobile-mode .container-fluid, html.desm-mobile-mode .content-wrapper,
      html.desm-mobile-mode .page-content, html.desm-mobile-mode .main-content,
      html.desm-mobile-mode .tab-content, html.desm-mobile-mode .content,
      html.desm-mobile-mode form {
        width:auto!important; min-width:0!important; max-width:100%!important;
      }
      html.desm-mobile-mode input:not([type=checkbox]):not([type=radio]):not([type=hidden]):not(.GridMain *),
      html.desm-mobile-mode select:not(.GridMain *), html.desm-mobile-mode textarea:not(.GridMain *) {
        min-width:0!important; max-width:100%!important; min-height:40px;
        font-size:16px!important; border-radius:9px!important;
      }
      html.desm-mobile-mode button, html.desm-mobile-mode input[type=button],
      html.desm-mobile-mode input[type=submit], html.desm-mobile-mode .btn {
        min-height:40px; max-width:100%; border-radius:9px!important;
        white-space:normal!important; touch-action:manipulation;
      }
      html.desm-mobile-mode fieldset, html.desm-mobile-mode .panel,
      html.desm-mobile-mode .card, html.desm-mobile-mode .well {
        max-width:100%!important; border-radius:12px!important;
      }

      /* Bảng dữ liệu (có th): giữ dạng bảng, cho cuộn ngang */
      html.desm-mobile-mode table:not(.GridMain *) {
        max-width:none; border-collapse:separate; border-spacing:0;
      }
      html.desm-mobile-mode :is(th, td):not(.GridMain *) {
        padding:8px 9px!important; font-size:13px!important; line-height:1.3!important;
      }
      html.desm-mobile-mode .table-responsive, html.desm-mobile-mode .dataTables_wrapper,
      html.desm-mobile-mode .table-wrap, html.desm-mobile-mode .grid-container,
      html.desm-mobile-mode .ui-jqgrid, html.desm-mobile-mode .ag-root-wrapper {
        max-width:100%!important; overflow-x:auto!important; -webkit-overflow-scrolling:touch;
      }

      /* Bảng dạng biểu mẫu/tìm kiếm (có ô nhập, không có th): xếp dọc, nhãn trên - ô nhập dưới */
      html.desm-mobile-mode table:has(select, textarea, input:not([type=hidden])):not(:has(th)):not([data-desm-form]) {
        display:block!important; width:100%!important; min-width:0!important; max-width:100%!important; height:auto!important;
      }
      html.desm-mobile-mode table:has(select, textarea, input:not([type=hidden])):not(:has(th)):not([data-desm-form]) :is(tbody,thead,tfoot,tr,td) {
        display:block!important; width:100%!important; min-width:0!important; max-width:100%!important;
        height:auto!important; text-align:left!important; white-space:normal!important;
      }
      html.desm-mobile-mode table:has(select, textarea, input:not([type=hidden])):not(:has(th)):not([data-desm-form]) td {
        padding:4px 6px!important;
      }
      html.desm-mobile-mode table:has(select, textarea, input:not([type=hidden])):not(:has(th)):not([data-desm-form]) select,
      html.desm-mobile-mode table:has(select, textarea, input:not([type=hidden])):not(:has(th)):not([data-desm-form]) textarea,
      html.desm-mobile-mode table:has(select, textarea, input:not([type=hidden])):not(:has(th)):not([data-desm-form]) input:not([type=checkbox]):not([type=radio]):not([type=hidden]) {
        width:100%!important;
      }

      html.desm-mobile-mode .row { margin-left:0!important; margin-right:0!important; }
      html.desm-mobile-mode [class*=col-] { min-width:0; }
      html.desm-mobile-mode .modal-dialog {
        width:calc(100% - 24px)!important; max-width:100%!important; margin:12px auto!important;
      }
      html.desm-mobile-mode .modal-content { border-radius:14px!important; }
    }
    html.desm-mobile-mode a, html.desm-mobile-mode button,
    html.desm-mobile-mode input, html.desm-mobile-mode select {
      -webkit-tap-highlight-color:transparent;
    }
    html.desm-mobile-mode :focus-visible { outline:2px solid #2878e5!important; outline-offset:2px; }

    /* ===== Riêng cho DESM (SB Admin 2) ===== */
    @media(max-width:800px) {
      /* Biểu mẫu tìm kiếm đã được JS dựng lại: lưới 2 cột, nhãn trên - ô nhập dưới */
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] {
        display:block!important; width:100%!important; min-width:0!important; max-width:100%!important; border:0!important; height:auto!important;
      }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] > colgroup { display:none!important; }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] > tbody.desm-orig { display:none!important; }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] > tbody.desm-tb {
        display:flex!important; flex-direction:column; gap:6px; padding:8px 10px; width:100%!important;
      }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] tr.desm-field {
        display:flex!important; flex-direction:row; align-items:center; gap:8px; min-width:0; width:100%!important; height:auto!important;
      }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] tr.desm-field > td {
        display:block!important; flex:1 1 0; width:auto!important; min-width:0!important; height:auto!important;
        padding:0!important; text-align:left!important; border:0!important; white-space:normal!important;
      }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] tr.desm-field > td.desm-lbl { flex:0 0 36%!important; max-width:36%; }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] :is(select, input:not([type=checkbox]):not([type=radio]):not([type=hidden])) {
        height:34px!important; min-height:34px!important; padding:0 8px!important; font-size:14px!important;
      }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] textarea { min-height:34px!important; font-size:14px!important; }
      html.desm-mobile-mode.desm-mobile-mode .SumoSelect > .CaptionCont { height:34px!important; min-height:34px!important; overflow:hidden; }
      html.desm-mobile-mode.desm-mobile-mode .SumoSelect > .CaptionCont > span { line-height:32px!important; padding-right:24px; }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] td.desm-empty { display:none!important; }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] td.desm-lbl,
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] td.desm-lbl label {
        font-size:13px!important; font-weight:600!important; color:#4a5468!important; margin:0!important; line-height:1.2!important;
      }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] select,
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] textarea,
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] input:not([type=checkbox]):not([type=radio]):not([type=hidden]) {
        width:100%!important;
      }
      html.desm-mobile-mode .SumoSelect { width:100%!important; }
      html.desm-mobile-mode .SumoSelect > .CaptionCont { min-height:40px; }

      /* Hàng nút Search/Reset: xếp ngang, rộng đều */
      html.desm-mobile-mode.desm-mobile-mode table:has(> tbody > tr > td > button):not(:has(select, textarea, input:not([type=hidden]))) {
        display:block!important; width:100%!important; height:auto!important;
      }
      html.desm-mobile-mode.desm-mobile-mode table:has(> tbody > tr > td > button):not(:has(select, textarea, input:not([type=hidden]))) > tbody {
        display:flex!important; gap:8px; padding:0 10px 10px;
      }
      html.desm-mobile-mode.desm-mobile-mode table:has(> tbody > tr > td > button):not(:has(select, textarea, input:not([type=hidden]))) tr {
        display:block!important; flex:1 1 0; height:auto!important;
      }
      html.desm-mobile-mode.desm-mobile-mode table:has(> tbody > tr > td > button):not(:has(select, textarea, input:not([type=hidden]))) td {
        display:block!important; width:100%!important; padding:0!important; text-align:center!important;
      }
      html.desm-mobile-mode.desm-mobile-mode table:has(> tbody > tr > td > button):not(:has(select, textarea, input:not([type=hidden]))) button {
        width:100%!important; height:40px!important; margin:0!important;
      }

      /* Thanh nút chức năng (Save, Update...): xuống dòng, nút dễ chạm */
      html.desm-mobile-mode.desm-mobile-mode #toolbar {
        display:flex!important; flex-wrap:nowrap; align-items:center; gap:6px; overflow-x:auto;
        -webkit-overflow-scrolling:touch; padding:8px 10px!important; background:#fff; border-bottom:1px solid #e3e6f0;
      }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > span { flex:0 0 auto; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button {
        flex:0 0 auto; float:none!important; margin:0!important; height:34px!important; white-space:nowrap!important; font-size:12px!important;
      }
      /* Thanh nút gọn: chỉ chừa Location Delete + Location Update (nút "⋯" mở ra các nút còn lại) */
      html.desm-mobile-mode.desm-mobile-mode #toolbar.desm-tb-slim:not(.desm-tb-all) > :not(#btnLocationDelete):not(#btnLocationSetup):not(#desmMoreToggle):not(#desmViewToggle):not(#desmTapToggle) { display:none!important; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar.desm-tb-slim > #desmMoreToggle { order:99; min-width:40px; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > #desmViewToggle { order:98; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > #desmTapToggle { order:97; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar:not(.desm-tb-slim) > #desmMoreToggle { display:none!important; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button .icon { padding:0 8px!important; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button .text { padding:0 10px 0 0!important; }

      /* Thanh bộ lọc (JS tạo): nút Bộ lọc thu/mở + Search/Reset luôn thấy. Dùng grid minmax(0,1fr) để tự co theo màn hình */
      html.desm-mobile-mode.desm-mobile-mode .desm-filter-bar {
        display:grid; grid-template-columns:minmax(0,1fr) auto; align-items:center; gap:8px;
        width:100%; max-width:100%; min-width:0; padding:8px 10px; background:#fff;
        border-bottom:1px solid #e3e6f0; position:sticky; top:0; z-index:20;
      }
      html.desm-mobile-mode.desm-mobile-mode .desm-filter-toggle {
        width:100%; min-width:0; height:40px; display:flex; align-items:center; justify-content:space-between;
        padding:0 12px; border:1px solid #cdd5e4; border-radius:10px; background:#f3f6fb; color:#2d4a8a;
        font-weight:600; font-size:14px; overflow:hidden; white-space:nowrap;
      }
      /* 2 ô tìm nhanh: chia đều chiều ngang, không bao giờ rộng hơn màn hình */
      html.desm-mobile-mode.desm-mobile-mode .desm-quick {
        grid-column:1 / -1; display:grid; grid-template-columns:repeat(2, minmax(0,1fr)); gap:6px;
        width:100%; max-width:100%; min-width:0;
      }
      html.desm-mobile-mode.desm-mobile-mode .desm-quick input {
        display:block; width:100%!important; min-width:0!important; max-width:100%!important;
        height:36px!important; min-height:36px!important; padding:0 10px!important;
        border:1px solid #cdd5e4!important; border-radius:9px!important; background:#fff; font-size:14px!important;
        text-overflow:ellipsis;
      }
      /* Màn hình rất hẹp: xếp 2 ô thành 2 hàng */
      @media(max-width:359px) {
        html.desm-mobile-mode.desm-mobile-mode .desm-quick { grid-template-columns:minmax(0,1fr); }
        html.desm-mobile-mode.desm-mobile-mode .desm-filter-bar { grid-template-columns:minmax(0,1fr); }
        html.desm-mobile-mode.desm-mobile-mode .desm-btns { justify-content:flex-end; }
      }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] tr.desm-field.desm-dup { display:none!important; }
      html.desm-mobile-mode.desm-mobile-mode .desm-btns { display:flex; gap:6px; flex:0 0 auto; min-width:0; }
      html.desm-mobile-mode.desm-mobile-mode .desm-btns button {
        height:40px!important; width:auto!important; min-width:44px; margin:0!important; padding:0!important;
        display:inline-flex!important; align-items:center; justify-content:center; border-radius:10px!important;
      }
      html.desm-mobile-mode.desm-mobile-mode .desm-btns button .icon { padding:0 12px!important; background:transparent!important; }
      html.desm-mobile-mode.desm-mobile-mode .desm-btns button .text { padding:0 14px 0 0!important; }
      html.desm-mobile-mode.desm-mobile-mode .desm-btns button:not(:first-child) .text { display:none; }
      html.desm-mobile-mode.desm-mobile-mode .desm-btns button:not(:first-child) .icon { padding:0 12px!important; }
      html.desm-mobile-mode.desm-mobile-mode .table-responsive:has(> .desm-filter-bar) { overflow:visible!important; }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form].desm-collapsed > tbody.desm-tb { display:none!important; }
      html.desm-mobile-mode.desm-mobile-mode table.desm-outer { border:0!important; margin:0!important; }
      html.desm-mobile-mode.desm-mobile-mode table.desm-outer.desm-collapsed { display:none!important; }
      html.desm-mobile-mode .card.shadow { margin:0!important; border-radius:0!important; }
      html.desm-mobile-mode .card-body-grid { padding:0!important; }
      html.desm-mobile-mode .modal-dialog { max-width:calc(100% - 16px)!important; }

      /* Thanh trên + tab + vùng nội dung */
      html.desm-mobile-mode #content-wrapper { width:100%!important; min-width:0!important; }
      html.desm-mobile-mode nav.topbar {
        position:sticky!important; top:0; z-index:1030; height:3.75rem!important; min-height:0; padding:0 .75rem!important; margin:0!important;
      }
      html.desm-mobile-mode nav.topbar select { height:44px!important; min-height:44px; padding:0 8px!important; font-size:14px!important; line-height:1.2!important; }
      html.desm-mobile-mode #tabs { margin-top:0!important; padding:0!important; border:0!important; }
      html.desm-mobile-mode #tabs > ul.ui-tabs-nav {
        display:flex!important; flex-wrap:nowrap!important; overflow-x:auto; -webkit-overflow-scrolling:touch; padding:4px 6px 0!important;
      }
      html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li { float:none!important; flex:0 0 auto; white-space:nowrap; margin:0 4px 0 0!important; }
      html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li > a { padding:.5em .8em!important; font-size:13px!important; }
      html.desm-mobile-mode #tabs iframe {
        width:100%!important;
        height:calc(100vh - 7.2rem)!important;
        height:calc(100dvh - 7.2rem)!important;
      }
      html.desm-mobile-mode footer.sticky-footer, html.desm-mobile-mode a.scroll-to-top { display:none!important; }
    }

    /* Menu trái -> ngăn kéo (mở bằng nút ≡ trên thanh trên) */
    @media(max-width:767.98px) {
      html.desm-mobile-mode #accordionSidebar {
        position:fixed!important; top:0; left:0; bottom:0; z-index:2000;
        width:min(68vw, 250px)!important; min-height:0!important; max-width:none;
        overflow-y:auto!important; overflow-x:hidden!important; -webkit-overflow-scrolling:touch;
        transform:translateX(-105%); transition:transform .22s ease; box-shadow:4px 0 18px rgba(0,0,0,.3);
        padding-bottom:env(safe-area-inset-bottom);
      }
      html.desm-mobile-mode.desm-nav-open #accordionSidebar { transform:none; }
      html.desm-mobile-mode.desm-nav-open { overflow:hidden!important; }
      html.desm-mobile-mode.desm-nav-open body { cursor:pointer; }
      html.desm-mobile-mode.desm-nav-open body::after {
        content:""; position:fixed; top:0; right:0; bottom:0; left:0; background:rgba(0,0,0,.45); z-index:1999;
      }
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link {
        width:auto!important; display:flex!important; align-items:center; text-align:left!important; padding:.8rem 1rem!important;
      }
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link i { font-size:1rem; margin-right:.55rem; }
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link span { display:inline!important; font-size:.85rem!important; }
      html.desm-mobile-mode #accordionSidebar .nav-item .collapse,
      html.desm-mobile-mode #accordionSidebar .nav-item .collapsing {
        position:static!important; left:auto!important; top:auto!important; margin:0 .75rem!important; animation:none!important;
      }
      html.desm-mobile-mode #accordionSidebar .collapse-inner { min-width:0!important; }
      html.desm-mobile-mode #accordionSidebar .collapse-item { white-space:normal!important; padding:.65rem 1rem!important; font-size:.9rem!important; }
    }

    /* ===== TreeGrid (lưới DESM): trả lại kích thước gốc, không để CSS chung chen vào ===== */
    html.desm-mobile-mode .GridMain, html.desm-mobile-mode .GridMain * { -webkit-text-size-adjust:100%; }
    html.desm-mobile-mode .GridMain :is(th, td) { font-size:inherit!important; line-height:inherit!important; }
    html.desm-mobile-mode .GridMain button, html.desm-mobile-mode .GridMain .btn { min-height:0; }

    /* ===== Toàn trang co giãn theo màn hình (không cuộn ngang, không bị rộng cố định) ===== */
    @media(max-width:800px) {
      html.desm-mobile-mode, html.desm-mobile-mode body { overflow-x:clip; }
      html.desm-mobile-mode :is(.card, .card-body, .card-body-grid, .table-responsive, #tabs, #content-wrapper) {
        width:100%!important; max-width:100%!important; min-width:0!important;
      }
      html.desm-mobile-mode .card-body-grid > .table-responsive { overflow-x:visible!important; }
      html.desm-mobile-mode table[width="100%"], html.desm-mobile-mode table[style*="width:100%"] { max-width:100%; }
      /* Khung chứa lưới TreeGrid: bỏ bề rộng cố định (vd 378px), lấy theo màn hình */
      html.desm-mobile-mode div[id^="grid"]:has(> .GridMain) {
        width:100%!important; max-width:100%!important; min-width:0!important;
      }
      html.desm-mobile-mode div[id^="grid"]:has(> .GridMain) > .GridMain { max-width:100%; }
      /* Ảnh/iframe/video tự co */
      html.desm-mobile-mode :is(iframe, embed, object) { max-width:100%!important; }
    }

    /* ===== Lưới Package dạng thẻ ===== */
    html:not(.desm-mobile-mode) #desmCards { display:none!important; }
    /* Ẩn lưới gốc nhưng vẫn giữ kích thước thật (không dùng display:none để TreeGrid còn tính toán được) */
    html.desm-mobile-mode.desm-mobile-mode div.desm-grid-off[id] {
      position:absolute!important; left:-200vw!important; top:0!important; width:100vw!important;
      height:70vh!important; overflow:hidden!important; pointer-events:none!important;
    }
    html.desm-mobile-mode .desm-cards-empty { padding:24px 12px; text-align:center; color:#6b7686; font-size:14px; }
    html.desm-mobile-mode #desmCards {
      overflow-y:auto; -webkit-overflow-scrolling:touch; padding:8px 10px 14px; background:#f3f6fb; max-width:100%;
    }
    html.desm-mobile-mode .desm-cards-bar {
      display:flex; align-items:center; gap:10px; margin:0 0 8px; padding:8px 12px; background:#fff;
      border-radius:10px; box-shadow:0 1px 3px rgba(0,0,0,.1); position:sticky; top:0; z-index:5; cursor:pointer;
    }
    html.desm-mobile-mode .desm-cards-count { font-size:13px; font-weight:600; color:#374151; }
    html.desm-mobile-mode input.desm-chk { width:22px!important; height:22px!important; min-width:22px!important; min-height:22px!important; flex:0 0 22px; margin:0!important; accent-color:#2878e5; }
    html.desm-mobile-mode .desm-card { position:relative; padding-left:44px!important; }
    html.desm-mobile-mode .desm-card-chk { position:absolute; left:12px; top:12px; pointer-events:none; }
    html.desm-mobile-mode .desm-card {
      background:#fff; border-radius:10px; box-shadow:0 1px 3px rgba(0,0,0,.14); padding:10px 12px 10px 14px;
      margin-bottom:8px; border-left:4px solid #f59e0b; cursor:pointer; touch-action:manipulation;
      -webkit-tap-highlight-color:transparent;
    }
    html.desm-mobile-mode .desm-card.desm-ok { border-left-color:#22c55e; }
    html.desm-mobile-mode .desm-card.desm-sel { outline:2px solid #2878e5; outline-offset:-2px; background:#eef5ff; }
    html.desm-mobile-mode .desm-card-no { font-weight:700; font-size:15px; color:#111827; word-break:break-all; line-height:1.3; }
    html.desm-mobile-mode .desm-card-desc { font-size:14px; color:#1f2937; line-height:1.35; }
    html.desm-mobile-mode .desm-card-sub { font-size:13px; color:#6b7686; line-height:1.35; }
    html.desm-mobile-mode .desm-card-foot {
      display:flex; justify-content:space-between; align-items:center; gap:8px; margin-top:6px; font-size:13px; font-weight:600;
    }
    html.desm-mobile-mode .desm-card-ao { color:#1e88e5; }
    html.desm-mobile-mode .desm-card-loc { display:inline-flex; align-items:center; gap:4px; min-width:0; color:#111827; }
    html.desm-mobile-mode .desm-card-loctxt { text-decoration:underline; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }

    /* ===== Danh sách dạng thẻ cho RSI / MRR / MRF / MPR ===== */
    html:not(.desm-mobile-mode) #desmGenCards { display:none!important; }
    html.desm-mobile-mode #desmGenCards { overflow-y:auto; -webkit-overflow-scrolling:touch; padding:8px 10px 14px; background:#f3f6fb; max-width:100%; }
    html.desm-mobile-mode #desmGenCards.desm-gtable { padding-bottom:4px; }
    html.desm-mobile-mode #desmGenCards.desm-gtable .desm-gall,
    html.desm-mobile-mode #desmGenCards.desm-gtable .desm-gq,
    html.desm-mobile-mode #desmGenCards.desm-gtable .desm-gcnt,
    html.desm-mobile-mode #desmGenCards.desm-gtable .desm-glist { display:none!important; }
    html.desm-mobile-mode .desm-gbar {
      display:flex; align-items:center; gap:8px; margin:0 0 8px; padding:8px 10px; background:#fff;
      border-radius:10px; box-shadow:0 1px 3px rgba(0,0,0,.1); position:sticky; top:0; z-index:5;
    }
    html.desm-mobile-mode .desm-gq { flex:1 1 auto; min-width:0; height:34px; border:1px solid #d5dbe5; border-radius:8px; padding:0 10px; font-size:14px; }
    html.desm-mobile-mode .desm-gcnt { flex:0 0 auto; font-size:12px; font-weight:600; color:#374151; white-space:nowrap; }
    html.desm-mobile-mode .desm-gbtn { flex:0 0 auto; height:34px; padding:0 12px; border:0; border-radius:8px; background:#e8f0fe; color:#1d4ed8; font-weight:600; font-size:13px; }
    html.desm-mobile-mode .desm-gcard.desm-g-ok { border-left-color:#22c55e; }
    html.desm-mobile-mode .desm-gcard.desm-g-bad { border-left-color:#ef4444; }
    html.desm-mobile-mode .desm-gtop { display:flex; justify-content:space-between; align-items:flex-start; gap:8px; }
    html.desm-mobile-mode .desm-gpill { flex:0 0 auto; font-size:12px; font-weight:700; padding:2px 8px; border-radius:999px; background:#e5e7eb; color:#374151; }
    html.desm-mobile-mode .desm-gpill.desm-gp-ok { background:#dcfce7; color:#166534; }
    html.desm-mobile-mode .desm-gpill.desm-gp-wait { background:#fef3c7; color:#92400e; }
    html.desm-mobile-mode .desm-gpill.desm-gp-bad { background:#fee2e2; color:#991b1b; }
    html.desm-mobile-mode .desm-gkv { display:flex; gap:8px; margin-top:3px; font-size:13px; line-height:1.35; }
    html.desm-mobile-mode .desm-gk { flex:0 0 38%; max-width:38%; color:#6b7686; }
    html.desm-mobile-mode .desm-gv { flex:1 1 auto; min-width:0; color:#111827; word-break:break-word; }
    html.desm-mobile-mode .desm-gmore { display:none; margin-top:8px; padding-top:6px; border-top:1px dashed #d5dbe5; }
    html.desm-mobile-mode .desm-gcard.desm-gopen .desm-gmore { display:block; }

    /* ===== Màn hình chi tiết kiện hàng ===== */
    html.desm-mobile-mode .desm-card-hit { position:absolute; left:0; top:0; bottom:0; width:46px; z-index:2; }
    html.desm-detail-open, html.desm-detail-open body { overflow:hidden!important; }
    html.desm-mobile-mode .desm-detail {
      position:fixed; left:0; top:0; right:0; bottom:0; z-index:2147483000; background:#f3f6fb; color:#111827;
      display:flex; flex-direction:column; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
    }
    /* Thanh trên cùng màn hình chi tiết: cùng nền SVG với header DESM (gradient xanh, sóng, chấm, đường nhấn vàng) */
    html.desm-mobile-mode .desm-detail-top {
      position:relative; display:flex; align-items:center; justify-content:center; min-height:60px; padding-top:env(safe-area-inset-top);
      box-sizing:content-box; color:#12306b; flex:0 0 auto; z-index:2;
      background-color:#d6e9fc; background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 64' preserveAspectRatio='xMidYMid slice'%3E%3Cdefs%3E%3ClinearGradient id='g' x1='0' y1='0' x2='1' y2='1'%3E%3Cstop offset='0' stop-color='%23cfe5fc'/%3E%3Cstop offset='.5' stop-color='%23e2f0fe'/%3E%3Cstop offset='1' stop-color='%23c3dffb'/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width='400' height='64' fill='url(%23g)'/%3E%3Ccircle cx='350' cy='4' r='46' fill='%23fff' fill-opacity='.35'/%3E%3Cpath d='M0 40 C70 24 130 54 210 36 S340 22 400 34 L400 64 L0 64Z' fill='%23fff' fill-opacity='.35'/%3E%3Cpath d='M0 52 C80 40 150 64 230 50 S350 42 400 50 L400 64 L0 64Z' fill='%23fff' fill-opacity='.4'/%3E%3Crect y='60' width='400' height='4' rx='2' fill='%23fff' fill-opacity='.7' transform='scale(.45 1) translate(60 0)'/%3E%3C/svg%3E")!important;
      background-size:cover!important; background-position:center!important; background-repeat:no-repeat!important;
      border:0!important; box-shadow:0 6px 18px rgba(60,120,200,.16)!important;
      border-radius:0 0 26px 26px; padding-bottom:0!important;
    }
    html.desm-mobile-mode nav.topbar #sidebarToggleTop {
      display:inline-flex!important; align-items:center; justify-content:center;
      width:44px; height:44px; padding:0!important; margin:0 8px 0 0!important; border-radius:15px!important;
      background:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Crect x='4' y='6' width='16' height='2.4' rx='1.2' fill='%231761e8'/%3E%3Crect x='4' y='10.8' width='11' height='2.4' rx='1.2' fill='%231761e8'/%3E%3Crect x='4' y='15.6' width='16' height='2.4' rx='1.2' fill='%231761e8'/%3E%3C/svg%3E") center/24px 24px no-repeat, rgba(255,255,255,.85)!important; -webkit-backdrop-filter:blur(12px); backdrop-filter:blur(12px);
      border:1px solid rgba(255,255,255,.95)!important; box-shadow:inset 0 1px 0 rgba(255,255,255,.9), 0 3px 8px rgba(23,97,232,.14)!important;
      -webkit-tap-highlight-color:transparent; outline:none!important;
    }
    html.desm-mobile-mode nav.topbar #sidebarToggleTop i { display:none!important; }
    html.desm-mobile-mode nav.topbar #sidebarToggleTop:active { transform:scale(.94); filter:brightness(1.1); }
    html.desm-mobile-mode nav.topbar select#selLang {
      -webkit-appearance:none!important; appearance:none!important;
      min-width:148px; height:44px!important; padding:0 34px 0 40px!important; margin:0!important;
      border-radius:999px!important; border:1px solid rgba(255,255,255,.95)!important; -webkit-backdrop-filter:blur(12px); backdrop-filter:blur(12px);
      background:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%231761e8' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'%3E%3Ccircle cx='12' cy='12' r='9'/%3E%3Cpath d='M3 12h18'/%3E%3Cpath d='M12 3c2.8 2.6 4.2 5.6 4.2 9s-1.4 6.4-4.2 9c-2.8-2.6-4.2-5.6-4.2-9S9.2 5.6 12 3z'/%3E%3C/svg%3E") 13px center/22px 22px no-repeat, url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%231761e8' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E") right 12px center/14px 14px no-repeat,
        linear-gradient(rgba(255,255,255,.85),rgba(255,255,255,.85))!important;
      color:#1761e8!important; font:650 15px/1.2 -apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif!important;
      box-shadow:inset 0 1px 0 rgba(255,255,255,.9), 0 3px 8px rgba(23,97,232,.14)!important; outline:none!important;
    }
    html.desm-mobile-mode nav.topbar select#selLang option { color:#0f172a; background:#fff; }
    html.desm-mobile-mode nav.topbar .nav-item { padding-right:4px!important; }

    /* Thanh tab */
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav {
      position:relative; z-index:2; min-height:42px; align-items:flex-end;
      background:linear-gradient(180deg,#dbeafe,#eff6ff)!important; border:0!important; border-bottom:1px solid #bfdbfe!important;
      border-radius:0!important; padding:8px 8px 0!important;
    }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li {
      margin:0 5px 0 0!important; padding:0!important; border:1px solid #bfdbfe!important; border-bottom:0!important;
      border-radius:16px 16px 0 0!important; background:rgba(255,255,255,.62)!important; display:flex; align-items:center;
      height:38px; padding-right:8px!important;
    }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li > a {
      display:flex; align-items:center; gap:6px; color:#475569!important; font-weight:600!important; padding:0 4px 0 10px!important; line-height:38px;
    }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li > a::before {
      content:""; width:17px; height:17px; flex:0 0 17px; background:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2364748b' stroke-width='1.9' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 8l-9-5-9 5v8l9 5 9-5z'/%3E%3Cpath d='M3 8l9 5 9-5'/%3E%3Cpath d='M12 13v8'/%3E%3C/svg%3E") center/17px 17px no-repeat;
    }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li.ui-tabs-active {
      background:#fff!important; border-color:#bfdbfe!important; border-top:4px solid #1761e8!important;
      box-shadow:0 -3px 10px rgba(23,97,232,.16); height:40px;
    }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li.ui-tabs-active > a { color:#1d4ed8!important; }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li.ui-tabs-active > a::before { background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%231d4ed8' stroke-width='1.9' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 8l-9-5-9 5v8l9 5 9-5z'/%3E%3Cpath d='M3 8l9 5 9-5'/%3E%3Cpath d='M12 13v8'/%3E%3C/svg%3E");
      background-size:cover; background-position:center; background-repeat:no-repeat;
      border:0; border-radius:0 0 18px 18px; padding-bottom:3px; box-shadow:0 4px 14px rgba(23,37,84,.35);
    }
    html.desm-mobile-mode .desm-detail-back {
      position:absolute; left:10px; top:calc(50% + env(safe-area-inset-top) / 2); transform:translateY(-50%);
      display:inline-flex; align-items:center; gap:4px; height:40px; padding:0 14px 0 10px!important; margin:0;
      color:#1761e8!important; font-size:16px; font-weight:600; border-radius:15px!important;
      background:rgba(255,255,255,.85)!important; -webkit-backdrop-filter:blur(12px); backdrop-filter:blur(12px);
      border:1px solid rgba(255,255,255,.95)!important; box-shadow:inset 0 1px 0 rgba(255,255,255,.9), 0 3px 8px rgba(23,97,232,.14)!important;
      -webkit-tap-highlight-color:transparent; outline:none!important;
    }
    html.desm-mobile-mode .desm-detail-back:active { transform:translateY(-50%) scale(.94); filter:brightness(1.1); }
    html.desm-mobile-mode .desm-detail-title { font-size:18px; font-weight:800; color:#12306b; letter-spacing:.3px; }
    html.desm-mobile-mode .desm-detail-body { flex:1 1 auto; overflow-y:auto; -webkit-overflow-scrolling:touch; padding:12px 10px 14px; }
    html.desm-mobile-mode .desm-dcard { background:#fff; border-radius:14px; padding:14px 14px 12px; margin-bottom:10px; box-shadow:0 1px 4px rgba(15,23,42,.1); }
    html.desm-mobile-mode .desm-d-h { font-size:19px; font-weight:800; line-height:1.3; word-break:break-word; margin-bottom:4px; }
    html.desm-mobile-mode .desm-d-l { font-size:17px; line-height:1.5; word-break:break-word; }
    html.desm-mobile-mode .desm-d-red { color:#dc2626; font-weight:700; }
    html.desm-mobile-mode .desm-d-tri, html.desm-mobile-mode .desm-d-two { display:flex; justify-content:space-between; gap:8px; font-size:17px; line-height:1.5; }
    html.desm-mobile-mode .desm-d-tri span:nth-child(2) { text-align:center; flex:1; }
    html.desm-mobile-mode .desm-d-hr { border:0; border-top:1px solid #d9dee7; margin:8px 0; }
    html.desm-mobile-mode .desm-d-loc { display:inline-flex; align-items:center; gap:4px; font-weight:700; text-decoration:underline; min-width:0; }
    html.desm-mobile-mode .desm-dband { display:grid; background:#e5e7eb; border-radius:12px; padding:10px 6px; margin-bottom:10px; text-align:center; }
    html.desm-mobile-mode .desm-dband3 { grid-template-columns:repeat(3,1fr); }
    html.desm-mobile-mode .desm-dband6 { grid-template-columns:repeat(6,auto); gap:0 2px; }
    html.desm-mobile-mode .desm-dband4 { grid-template-columns:repeat(4,1fr); }
    html.desm-mobile-mode .desm-dband-k { font-size:13px; color:#4b5563; }
    html.desm-mobile-mode .desm-dband-v { font-size:15px; font-weight:600; }
    html.desm-mobile-mode .desm-dband3 .desm-dband-v { font-size:16px; font-weight:700; }
    html.desm-mobile-mode .desm-dband6 .desm-dband-v { font-size:12.5px; font-weight:700; white-space:nowrap; }
    html.desm-mobile-mode .desm-u { text-decoration:underline; }
    html.desm-mobile-mode .desm-dband4 input.desm-chk { margin:6px auto 0!important; display:block; }
    html.desm-mobile-mode .desm-detail-list {
      width:100%; background:#fff!important; color:#111827!important; border:1.5px solid #111827!important; border-radius:8px!important;
      font-size:19px; font-weight:700; padding:10px; margin-bottom:8px;
    }
    html.desm-mobile-mode .desm-ditem { background:#fff; border-radius:8px; border-left:5px solid #facc15; padding:10px 12px; margin-bottom:8px; box-shadow:0 1px 3px rgba(0,0,0,.12); }
    html.desm-mobile-mode .desm-ditem-no { font-size:19px; font-weight:800; text-decoration:underline; word-break:break-all; }
    html.desm-mobile-mode .desm-ditem-l { font-size:17px; line-height:1.45; word-break:break-word; }
    html.desm-mobile-mode .desm-ditem-foot { display:flex; justify-content:space-between; gap:8px; font-size:16px; margin-top:2px; }
    html.desm-mobile-mode .desm-ditem { position:relative; padding-left:48px!important; cursor:pointer; }
    html.desm-mobile-mode .desm-ditem.desm-sel { outline:2px solid #2878e5; outline-offset:-2px; background:#eef5ff; }
    html.desm-mobile-mode .desm-ditem-chk { position:absolute; left:12px; top:12px; pointer-events:none; }
    html.desm-mobile-mode .desm-ditems-bar { display:flex; align-items:center; gap:10px; margin:0 0 8px; padding:8px 12px; background:#fff; border-radius:10px; box-shadow:0 1px 3px rgba(0,0,0,.1); cursor:pointer; }
    html.desm-mobile-mode .desm-ditem-locbtn { padding:6px 0 6px 12px; cursor:pointer; }
    html.desm-mobile-mode .desm-sub { z-index:2147483010; }
    html.desm-mobile-mode .desm-rsi-card { background:#fff; border-radius:8px; border-left:5px solid #2878e5; padding:10px 12px; margin-bottom:8px; box-shadow:0 1px 3px rgba(0,0,0,.12); cursor:pointer; }
    html.desm-mobile-mode .desm-mrf-card { border-left-color:#12b3a0; }
    html.desm-mobile-mode .desm-mrf-type { color:#dc2626; font-weight:700; }
    html.desm-mobile-mode .desm-mrf-head { border-left:5px solid #12b3a0; }
    html.desm-mobile-mode .desm-rsi-row { display:flex; justify-content:space-between; gap:8px; font-size:16px; line-height:1.5; }
    html.desm-mobile-mode .desm-sub-filter { display:flex; gap:8px; margin-bottom:8px; }
    html.desm-mobile-mode .desm-sub-in { flex:1; min-width:0; height:42px; border:1px solid #cbd5e1; border-radius:10px; padding:0 12px; font-size:16px; background:#fff; color:#111827; }
    html.desm-mobile-mode .desm-mrr-in { display:block; width:100%; box-sizing:border-box; margin:0 0 8px; }
    html.desm-mobile-mode .desm-fqty { margin-top:-4px; }
    html.desm-mobile-mode .desm-fqty input.desm-sub-in { width:100%; height:38px; text-align:center; padding:0 4px; font-size:15px; }
    html.desm-mobile-mode .desm-fqty input.desm-sub-in:disabled { background:#f1f5f9; color:#94a3b8; }
    html.desm-mobile-mode textarea.desm-rmk { display:block; width:100%; box-sizing:border-box; height:auto; padding:8px 12px; margin:0 0 8px; }
    html.desm-mobile-mode .desm-detail-list:disabled { opacity:.45; }
    html.desm-mobile-mode .desm-detail-note { font-size:13px; color:#b45309; padding:0 4px 8px; }
    /* Nút gọn dạng viên thuốc, canh giữa */
    html.desm-mobile-mode .desm-detail-lu {
      flex:0 0 auto; align-self:center; box-sizing:border-box; width:calc(100% - 48px); min-width:190px; max-width:320px;
      margin:6px 0 calc(14px + env(safe-area-inset-bottom)); padding:0 16px; min-height:46px;
      background:linear-gradient(135deg,#1e88f5,#0ea5e9)!important; color:#fff!important;
      border:1.5px solid rgba(255,255,255,.55)!important; border-radius:999px!important;
      font-size:16px; font-weight:700; line-height:1.15; letter-spacing:.2px; text-align:center;
      box-shadow:0 4px 12px rgba(30,136,245,.38), inset 0 1px 0 rgba(255,255,255,.9);
      -webkit-tap-highlight-color:transparent; transition:transform .12s ease, box-shadow .12s ease;
    }
    html.desm-mobile-mode .desm-detail-lu:active { transform:scale(.96); box-shadow:0 2px 6px rgba(30,136,245,.35); }

    /* ===== Nút + icon SVG vẽ riêng (thay icon font) ===== */
    html.desm-mobile-mode :is(#toolbar, .desm-btns) i[class*="fa-"]::before { content:none!important; }
    html.desm-mobile-mode :is(#toolbar, .desm-btns) i[class*="fa-"] {
      display:inline-block!important; width:18px; height:18px; font-size:0!important; line-height:0; vertical-align:middle;
      background-color:currentColor; -webkit-mask-repeat:no-repeat; mask-repeat:no-repeat;
      -webkit-mask-position:center; mask-position:center; -webkit-mask-size:contain; mask-size:contain;
    }
    html.desm-mobile-mode :is(#toolbar, .desm-btns) i.fa-trash { -webkit-mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v6M14 11v6'/></svg>"); mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v6M14 11v6'/></svg>"); }
    html.desm-mobile-mode :is(#toolbar, .desm-btns) i.fa-pencil-alt { -webkit-mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z'/></svg>"); mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z'/></svg>"); }
    html.desm-mobile-mode :is(#toolbar, .desm-btns) i.fa-search { -webkit-mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='11' cy='11' r='7'/><path d='M21 21l-4.3-4.3'/></svg>"); mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='11' cy='11' r='7'/><path d='M21 21l-4.3-4.3'/></svg>"); }
    html.desm-mobile-mode :is(#toolbar, .desm-btns) i.fa-sync { -webkit-mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M21 12a9 9 0 0 0-15-6.7L3 8M3 3v5h5M3 12a9 9 0 0 0 15 6.7L21 16M16 16h5v5'/></svg>"); mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M21 12a9 9 0 0 0-15-6.7L3 8M3 3v5h5M3 12a9 9 0 0 0 15 6.7L21 16M16 16h5v5'/></svg>"); }
    html.desm-mobile-mode :is(#toolbar, .desm-btns) i.fa-save { -webkit-mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2ZM17 21v-8H7v8M7 3v5h8'/></svg>"); mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2ZM17 21v-8H7v8M7 3v5h8'/></svg>"); }
    html.desm-mobile-mode :is(#toolbar, .desm-btns) i.fa-times-circle { -webkit-mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='12' cy='12' r='10'/><path d='M15 9l-6 6M9 9l6 6'/></svg>"); mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='12' cy='12' r='10'/><path d='M15 9l-6 6M9 9l6 6'/></svg>"); }
    html.desm-mobile-mode :is(#toolbar, .desm-btns) i.fa-file { -webkit-mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8ZM14 2v6h6'/></svg>"); mask-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8ZM14 2v6h6'/></svg>"); }
    @media(max-width:800px) {
      /* Thanh nút chức năng: nút bo tròn dạng viên thuốc, màu phẳng + đổ bóng nhẹ */
      html.desm-mobile-mode.desm-mobile-mode #toolbar { gap:8px; padding:8px 10px!important; background:#f8fafc; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button {
        height:38px!important; display:inline-flex!important; align-items:center; gap:6px;
        padding:0 14px 0 10px!important; border:0!important; border-radius:999px!important;
        color:#fff!important; font-size:13px!important; font-weight:600; letter-spacing:.1px;
        background-image:linear-gradient(180deg,rgba(255,255,255,.2),rgba(255,255,255,0))!important;
        box-shadow:0 2px 6px rgba(15,23,42,.18)!important; transition:transform .08s ease, filter .15s ease;
      }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button:active { transform:scale(.96); filter:brightness(.94); }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button .icon,
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button .text {
        padding:0!important; background:transparent!important; display:inline-flex!important; align-items:center; color:inherit!important; opacity:1!important;
      }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button.btn-danger { background-color:#e5484d!important; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button.btn-success { background-color:#12a37a!important; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button.btn-primary { background-color:#3b6fe0!important; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button.btn-info { background-color:#1b9fbd!important; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button.btn-secondary {
        background-color:#e9edf3!important; color:#334155!important; box-shadow:inset 0 0 0 1px #cfd7e3!important; background-image:none!important;
      }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > #desmMoreToggle { width:40px; padding:0!important; justify-content:center; font-size:18px!important; line-height:1; }
      /* Nút Search / Reset */
      html.desm-mobile-mode.desm-mobile-mode .desm-btns button {
        border:0!important; border-radius:12px!important; color:#fff;
        background-image:linear-gradient(180deg,rgba(255,255,255,.2),rgba(255,255,255,0))!important;
        box-shadow:0 2px 6px rgba(15,23,42,.18)!important; transition:transform .08s ease;
      }
      html.desm-mobile-mode.desm-mobile-mode .desm-btns button:active { transform:scale(.95); }
      html.desm-mobile-mode.desm-mobile-mode .desm-btns button .icon i { width:20px; height:20px; }
      html.desm-mobile-mode.desm-mobile-mode .desm-filter-toggle { box-shadow:inset 0 0 0 1px #d5deee; border:0!important; }
      html.desm-mobile-mode .desm-card { border-radius:14px!important; box-shadow:0 2px 8px rgba(15,23,42,.1)!important; }
      html.desm-mobile-mode .desm-cards-bar { border-radius:14px!important; }
    }

    html.desm-mobile-mode.desm-modal-open, html.desm-mobile-mode.desm-modal-open body { overflow:hidden!important; }
    /* ===== Hộp thoại có bản đồ (Location Update): giữ kích thước thật để bấm đúng ô vị trí ===== */
    html.desm-mobile-mode :is(.modal-body, .ui-dialog-content) {
      overflow:auto!important; -webkit-overflow-scrolling:touch; max-width:100%;
    }
    html.desm-mobile-mode :is(.modal, .ui-dialog) :is(area, [usemap], [data-desm-map], [data-desm-map] *) {
      cursor:pointer; touch-action:manipulation; -webkit-user-select:none; user-select:none;
      -webkit-touch-callout:none;
    }
    /* Canvas bản đồ (#canvasDlgDesmLocation, 1200x700): giữ đúng kích thước gốc để toạ độ bấm khớp, vùng chứa cuộn ngang/dọc */
    html.desm-mobile-mode #canvasDlgDesmLocation {
      width:1200px!important; height:700px!important; max-width:none!important; display:block;
      touch-action:manipulation; -webkit-tap-highlight-color:transparent;
    }
    html.desm-mobile-mode #dlgDesmLocation .table-responsive {
      overflow:auto!important; -webkit-overflow-scrolling:touch; max-width:100%!important;
      max-height:calc(100dvh - 190px);
    }
    html.desm-mobile-mode #dlgDesmLocation .modal-dialog { max-width:calc(100% - 16px)!important; margin:8px auto!important; }
    html.desm-mobile-mode [data-desm-map] { overflow:auto!important; max-width:100%!important; }

    /* ===== Giao diện header SVG: nền, nút ≡, ô Language, thẻ tab ===== */
    html.desm-mobile-mode nav.topbar.topbar {
      background-color:#d6e9fc!important;
      background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 64' preserveAspectRatio='xMidYMid slice'%3E%3Cdefs%3E%3ClinearGradient id='g' x1='0' y1='0' x2='1' y2='1'%3E%3Cstop offset='0' stop-color='%23cfe5fc'/%3E%3Cstop offset='.5' stop-color='%23e2f0fe'/%3E%3Cstop offset='1' stop-color='%23c3dffb'/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width='400' height='64' fill='url(%23g)'/%3E%3Ccircle cx='350' cy='4' r='46' fill='%23fff' fill-opacity='.35'/%3E%3Cpath d='M0 40 C70 24 130 54 210 36 S340 22 400 34 L400 64 L0 64Z' fill='%23fff' fill-opacity='.35'/%3E%3Cpath d='M0 52 C80 40 150 64 230 50 S350 42 400 50 L400 64 L0 64Z' fill='%23fff' fill-opacity='.4'/%3E%3Crect y='60' width='400' height='4' rx='2' fill='%23fff' fill-opacity='.7' transform='scale(.45 1) translate(60 0)'/%3E%3C/svg%3E")!important;
      background-size:cover!important; background-position:center!important; background-repeat:no-repeat!important;
      border:0!important; box-shadow:0 6px 18px rgba(60,120,200,.16)!important;
      border-radius:0 0 26px 26px; padding-bottom:0!important;
    }
    html.desm-mobile-mode nav.topbar #sidebarToggleTop {
      display:inline-flex!important; align-items:center; justify-content:center;
      width:44px; height:44px; padding:0!important; margin:0 8px 0 0!important; border-radius:15px!important;
      background:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Crect x='4' y='6' width='16' height='2.4' rx='1.2' fill='%231761e8'/%3E%3Crect x='4' y='10.8' width='11' height='2.4' rx='1.2' fill='%231761e8'/%3E%3Crect x='4' y='15.6' width='16' height='2.4' rx='1.2' fill='%231761e8'/%3E%3C/svg%3E") center/24px 24px no-repeat, rgba(255,255,255,.85)!important; -webkit-backdrop-filter:blur(12px); backdrop-filter:blur(12px);
      border:1px solid rgba(255,255,255,.95)!important; box-shadow:inset 0 1px 0 rgba(255,255,255,.9), 0 3px 8px rgba(23,97,232,.14)!important;
      -webkit-tap-highlight-color:transparent; outline:none!important;
    }
    html.desm-mobile-mode nav.topbar #sidebarToggleTop i { display:none!important; }
    html.desm-mobile-mode nav.topbar #sidebarToggleTop:active { transform:scale(.94); filter:brightness(1.1); }
    html.desm-mobile-mode nav.topbar select#selLang {
      -webkit-appearance:none!important; appearance:none!important;
      min-width:148px; height:44px!important; padding:0 34px 0 40px!important; margin:0!important;
      border-radius:999px!important; border:1px solid rgba(255,255,255,.95)!important; -webkit-backdrop-filter:blur(12px); backdrop-filter:blur(12px);
      background:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%231761e8' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'%3E%3Ccircle cx='12' cy='12' r='9'/%3E%3Cpath d='M3 12h18'/%3E%3Cpath d='M12 3c2.8 2.6 4.2 5.6 4.2 9s-1.4 6.4-4.2 9c-2.8-2.6-4.2-5.6-4.2-9S9.2 5.6 12 3z'/%3E%3C/svg%3E") 13px center/22px 22px no-repeat, url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%231761e8' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E") right 12px center/14px 14px no-repeat,
        linear-gradient(rgba(255,255,255,.85),rgba(255,255,255,.85))!important;
      color:#1761e8!important; font:650 15px/1.2 -apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif!important;
      box-shadow:inset 0 1px 0 rgba(255,255,255,.9), 0 3px 8px rgba(23,97,232,.14)!important; outline:none!important;
    }
    html.desm-mobile-mode nav.topbar select#selLang option { color:#0f172a; background:#fff; }
    html.desm-mobile-mode nav.topbar .nav-item { padding-right:4px!important; }

    /* Thanh tab */
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav {
      position:relative; z-index:2; min-height:42px; align-items:flex-end;
      background:linear-gradient(180deg,#dbeafe,#eff6ff)!important; border:0!important; border-bottom:1px solid #bfdbfe!important;
      border-radius:0!important; padding:8px 8px 0!important;
    }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li {
      margin:0 5px 0 0!important; padding:0!important; border:1px solid #bfdbfe!important; border-bottom:0!important;
      border-radius:16px 16px 0 0!important; background:rgba(255,255,255,.62)!important; display:flex; align-items:center;
      height:38px; padding-right:8px!important;
    }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li > a {
      display:flex; align-items:center; gap:6px; color:#475569!important; font-weight:600!important; padding:0 4px 0 10px!important; line-height:38px;
    }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li > a::before {
      content:""; width:17px; height:17px; flex:0 0 17px; background:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2364748b' stroke-width='1.9' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 8l-9-5-9 5v8l9 5 9-5z'/%3E%3Cpath d='M3 8l9 5 9-5'/%3E%3Cpath d='M12 13v8'/%3E%3C/svg%3E") center/17px 17px no-repeat;
    }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li.ui-tabs-active {
      background:#fff!important; border-color:#bfdbfe!important; border-top:4px solid #1761e8!important;
      box-shadow:0 -3px 10px rgba(23,97,232,.16); height:40px;
    }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li.ui-tabs-active > a { color:#1d4ed8!important; }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li.ui-tabs-active > a::before { background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%231d4ed8' stroke-width='1.9' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 8l-9-5-9 5v8l9 5 9-5z'/%3E%3Cpath d='M3 8l9 5 9-5'/%3E%3Cpath d='M12 13v8'/%3E%3C/svg%3E"); }
    html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li .ui-icon-close {
      position:static!important; flex:0 0 18px; width:18px!important; height:18px!important; margin:0 0 0 2px!important;
      background:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Ccircle cx='12' cy='12' r='10' fill='%23e2e8f0'/%3E%3Cpath d='M8.5 8.5l7 7M15.5 8.5l-7 7' stroke='%23475569' stroke-width='2.2' stroke-linecap='round'/%3E%3C/svg%3E") center/18px 18px no-repeat!important; text-indent:-9999px; overflow:hidden; cursor:pointer;
    }
    html.desm-mobile-mode #tabs .ui-tabs-panel2 { position:relative; z-index:1; }

    /* ===== Ngăn kéo menu: giao diện sáng đồng bộ với header/footer ===== */
    @media(max-width:767.98px) {
      html.desm-mobile-mode #accordionSidebar, html.desm-mobile-mode #accordionSidebar.sidebar {
        background:linear-gradient(180deg,#d3e7fc 0%,#e6f1ff 50%,#f5f9ff 100%)!important;
        border-radius:0 28px 28px 0!important; box-shadow:8px 0 28px rgba(40,90,170,.22)!important;
        padding:calc(env(safe-area-inset-top) + 14px) 0 calc(env(safe-area-inset-bottom) + 90px)!important;
      }
      html.desm-mobile-mode.desm-nav-open body::after { background:rgba(20,50,100,.30)!important; -webkit-backdrop-filter:blur(2px); backdrop-filter:blur(2px); }
      html.desm-mobile-mode #accordionSidebar .sidebar-divider { border-top:1px solid rgba(47,125,224,.16)!important; margin:.5rem 1.25rem!important; }
      html.desm-mobile-mode #accordionSidebar .sidebar-heading { color:#7d9cc8!important; }
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link {
        color:#35507a!important; margin:3px 8px!important; padding:.75rem .8rem!important; border-radius:16px!important;
        transition:background .15s ease;
      }
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link span { color:inherit!important; font-weight:600; letter-spacing:.2px; }
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link i { color:#7d9cc8!important; }
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link:active { background:rgba(255,255,255,.7)!important; }
      html.desm-mobile-mode #accordionSidebar .nav-item.active > .nav-link,
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link:not(.collapsed)[data-toggle] {
        background:#fff!important; color:#1761e8!important; box-shadow:0 4px 12px rgba(47,125,224,.16)!important;
      }
      html.desm-mobile-mode #accordionSidebar .nav-item.active > .nav-link i,
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link:not(.collapsed)[data-toggle] i { color:#1761e8!important; }
      html.desm-mobile-mode #accordionSidebar .collapse-inner {
        background:rgba(255,255,255,.85)!important; border-radius:16px!important; padding:.4rem!important;
        box-shadow:0 2px 10px rgba(47,125,224,.12)!important;
      }
      html.desm-mobile-mode #accordionSidebar .collapse-item { color:#35507a!important; border-radius:12px!important; margin:2px 0!important; }
      html.desm-mobile-mode #accordionSidebar .collapse-item:active,
      html.desm-mobile-mode #accordionSidebar .collapse-item.active { background:#e8f1ff!important; color:#1761e8!important; font-weight:700; }
      html.desm-mobile-mode #accordionSidebar .collapse-header { color:#7d9cc8!important; }
    }

    """#
}
