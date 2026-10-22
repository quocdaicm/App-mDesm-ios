import Foundation

enum MobileStyles {
    static let css = #"""
    html.desm-mobile-mode { color-scheme: light; }
    html.desm-mobile-mode, html.desm-mobile-mode body {
      width:100%!important; min-width:0!important; max-width:100%!important;
      overflow-x:hidden!important; -webkit-text-size-adjust:100%;
    }
    html.desm-mobile-mode body {
      margin:0!important; background:#f3f6fb!important;
      font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif!important;
      color:#1f2937!important;
    }
    html.desm-mobile-mode * { box-sizing:border-box; }
    html.desm-mobile-mode img, html.desm-mobile-mode video { max-width:100%; }
    @media(max-width:800px) {
      html.desm-mobile-mode #wrapper, html.desm-mobile-mode #content,
      html.desm-mobile-mode #main, html.desm-mobile-mode .container,
      html.desm-mobile-mode .container-fluid, html.desm-mobile-mode .content-wrapper,
      html.desm-mobile-mode .page-content, html.desm-mobile-mode .main-content,
      html.desm-mobile-mode .tab-content, html.desm-mobile-mode .content,
      html.desm-mobile-mode form {
        width:auto!important; min-width:0!important; max-width:100%!important;
      }
      html.desm-mobile-mode input:not([type=checkbox]):not([type=radio]):not([type=hidden]),
      html.desm-mobile-mode select, html.desm-mobile-mode textarea {
        min-width:0!important; max-width:100%!important; min-height:42px;
        font-size:16px!important; border-radius:9px!important;
      }
      html.desm-mobile-mode button, html.desm-mobile-mode input[type=button],
      html.desm-mobile-mode input[type=submit], html.desm-mobile-mode .btn {
        min-height:42px; max-width:100%; border-radius:9px!important;
        white-space:normal!important; touch-action:manipulation;
      }
      html.desm-mobile-mode fieldset, html.desm-mobile-mode .panel,
      html.desm-mobile-mode .card, html.desm-mobile-mode .well {
        max-width:100%!important; border-radius:12px!important;
      }
      html.desm-mobile-mode table {
        width:max-content!important; min-width:100%!important; max-width:none!important;
        border-collapse:separate; border-spacing:0;
      }
      html.desm-mobile-mode table th, html.desm-mobile-mode table td {
        padding:9px 10px!important; font-size:13px!important; line-height:1.3!important;
        white-space:nowrap;
      }
      html.desm-mobile-mode .table-responsive, html.desm-mobile-mode .dataTables_wrapper,
      html.desm-mobile-mode .table-wrap, html.desm-mobile-mode .grid-container,
      html.desm-mobile-mode .ui-jqgrid, html.desm-mobile-mode .ag-root-wrapper {
        max-width:100%!important; overflow-x:auto!important; -webkit-overflow-scrolling:touch;
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
    """#
}
