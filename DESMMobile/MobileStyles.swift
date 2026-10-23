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
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button .icon { padding:0 8px!important; }
      html.desm-mobile-mode.desm-mobile-mode #toolbar > button .text { padding:0 10px 0 0!important; }

      /* Thanh bộ lọc (JS tạo): nút Bộ lọc thu/mở + Search/Reset luôn thấy */
      html.desm-mobile-mode.desm-mobile-mode .desm-filter-bar {
        display:flex; align-items:center; gap:8px; padding:8px 10px; background:#fff;
        border-bottom:1px solid #e3e6f0; position:sticky; top:0; z-index:20;
      }
      html.desm-mobile-mode.desm-mobile-mode .desm-filter-toggle {
        flex:1 1 auto; min-width:0; height:40px; display:flex; align-items:center; justify-content:space-between;
        padding:0 12px; border:1px solid #cdd5e4; border-radius:10px; background:#f3f6fb; color:#2d4a8a;
        font-weight:600; font-size:14px;
      }
      html.desm-mobile-mode.desm-mobile-mode .desm-filter-bar { flex-wrap:wrap; }
      html.desm-mobile-mode.desm-mobile-mode .desm-quick { flex:1 0 100%; display:flex; gap:6px; }
      html.desm-mobile-mode.desm-mobile-mode .desm-quick input {
        flex:1 1 0; min-width:0; height:36px!important; min-height:36px!important; padding:0 10px!important;
        border:1px solid #cdd5e4!important; border-radius:9px!important; background:#fff; font-size:14px!important;
      }
      html.desm-mobile-mode.desm-mobile-mode table[data-desm-form] tr.desm-field.desm-dup { display:none!important; }
      html.desm-mobile-mode.desm-mobile-mode .desm-btns { display:flex; gap:6px; flex:0 0 auto; }
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
        position:sticky!important; top:0; z-index:1030; height:3rem!important; min-height:0; padding:0 .5rem!important; margin:0!important;
      }
      html.desm-mobile-mode nav.topbar select { height:36px!important; min-height:36px; padding:0 8px!important; font-size:14px!important; line-height:1.2!important; }
      html.desm-mobile-mode #tabs { margin-top:0!important; padding:0!important; border:0!important; }
      html.desm-mobile-mode #tabs > ul.ui-tabs-nav {
        display:flex!important; flex-wrap:nowrap!important; overflow-x:auto; -webkit-overflow-scrolling:touch; padding:4px 6px 0!important;
      }
      html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li { float:none!important; flex:0 0 auto; white-space:nowrap; margin:0 4px 0 0!important; }
      html.desm-mobile-mode #tabs > ul.ui-tabs-nav > li > a { padding:.5em .8em!important; font-size:13px!important; }
      html.desm-mobile-mode #tabs iframe {
        width:100%!important;
        height:calc(100vh - 6.4rem)!important;
        height:calc(100dvh - 6.4rem)!important;
      }
      html.desm-mobile-mode footer.sticky-footer, html.desm-mobile-mode a.scroll-to-top { display:none!important; }
    }

    /* Menu trái -> ngăn kéo (mở bằng nút ≡ trên thanh trên) */
    @media(max-width:767.98px) {
      html.desm-mobile-mode #accordionSidebar {
        position:fixed!important; top:0; left:0; bottom:0; z-index:2000;
        width:min(84vw, 320px)!important; min-height:0!important; max-width:none;
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
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link i { font-size:1rem; margin-right:.7rem; }
      html.desm-mobile-mode #accordionSidebar .nav-item .nav-link span { display:inline!important; font-size:.9rem!important; }
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
    """#
}
