# DESM Mobile — Ghi chú cho người/AI tiếp tục phát triển

> Đọc file này trước khi sửa mã. Tài liệu mô tả app đang làm gì, mã nằm ở đâu, những điều đã biết về web DESM và những điều CHƯA kiểm chứng.

## 1. App làm gì
Ứng dụng iOS (SwiftUI, iOS 16+) bọc website nội bộ **DESM** của Doosan Enerbility (`https://desm.doosanenerbility.com`, giao diện SB Admin 2 trên desktop, dự án O Mon 4) trong một `WKWebView`, rồi **tiêm CSS/JS** để biến trang desktop thành giao diện dùng được trên điện thoại cho người làm kho/hiện trường: tra kiện hàng (Package), hạng mục chi tiết (Detail Item), cập nhật vị trí (Location Update), quét mã bằng camera, v.v.
App KHÔNG có backend riêng và không gọi dịch vụ ngoài; mọi dữ liệu đi qua chính phiên đăng nhập DESM của người dùng.

## 2. Bản đồ file
| File | Vai trò |
|---|---|
| `DESMMobileApp.swift` | Điểm vào, hiện `BrowserView`. |
| `BrowserView.swift` | File lớn nhất. `BrowserModel` (trạng thái, cài đặt, tạo script tiêm), toàn bộ **JS tiêm vào trang** (chuỗi `#"""` trong `makeScript()`), `BrowserView` (thanh địa chỉ/nút), `SettingsView` (Cài đặt), các tiện ích lấy HTML/script/nhật ký API. |
| `WebView.swift` | `UIViewRepresentable` bọc WKWebView, `Coordinator` (điều hướng, alert/confirm thật, nhận message từ JS), `SessionStore` (lưu cookie phiên vào Keychain), `CredStore` (tài khoản tự điền, Keychain). |
| `MobileStyles.swift` | CSS chế độ Mobile (chuỗi lớn, gồm SVG header/footer nhúng). |
| `Translations.swift` | Từ điển Anh→Việt (khớp nguyên chuỗi) để Việt hoá giao diện DESM phía máy khách. |
| `PackageScanner.swift` | Quét Package No/QR bằng camera (AVFoundation + Vision), nhận diện `OM4-xx-xx-0000-000`, parse QR `DETAIL!!!...`, quét từ ảnh thư viện. |
| `Branding/`, `Assets.xcassets` | Logo, icon, nền SVG header/footer. |

## 3. Luồng chạy chính
1. `WebView.makeUIView` nạp cookie từ Keychain (`SessionStore.restore`) rồi mở DESM.
2. `BrowserModel.installUserScript()` cài 2 `WKUserScript` (document start, mọi frame): script giao diện (`makeScript()`) và bộ ghi API (`netRecorderSource`). Sau mỗi lần tải xong, `evaluateNow()` áp lại.
3. Script giao diện chạy trong **từng frame** (DESM dựng màn hình trong iframe bằng `page_crt.do?MENU_SEQ=<n>`). Nó tự áp lại khi trang xoá style hoặc tạo iframe mới (vòng `applyAll`).
4. JS gọi ngược Swift qua `webkit.messageHandlers`: `desmCred` (tài khoản), `desmLang` (ngôn ngữ), `desmScanResult` (kết quả quét → toast).
5. Swift gọi JS qua `evaluateJavaScript` / `callAsyncJavaScript`: `__desmFindPkg`, `__desmFindDetail` (quét), `__desmApplyAll`...

### Tự kết nối lại khi hết phiên (đăng nhập)
Vấn đề đã gặp: qua đêm phiên DESM hết hạn nhưng app nạp lại địa chỉ cũ với cookie cũ nên trang không chạy thay vì về `login.do`. Xử lý (extension "Tự kết nối lại" trong `BrowserView.swift`, hook trong `WebView.swift`):
1. Mở app: `SessionStore.restore` rồi `BrowserModel.startLoad` thăm dò `main.do` bằng URLSession (hết phiên = chuyển về login / 401 / có ô mật khẩu); hết phiên hoặc chưa có phiên thì xoá cookie DESM và mở `https://desm.doosanenerbility.com/login.do`.
2. App quay lại từ nền > 10 phút: thăm dò lại (`appBecameActive`).
3. Đang dùng: JS ở `netRecorderSource` (`checkXhr`) phát hiện XHR bị đẩy về login/401/HTML đăng nhập → message `desmSession` → `reconnectSession`. Ngoài ra `Coordinator.checkLoginForm` bắt trường hợp trang thường mà hiện ô mật khẩu.
4. Ở trang đăng nhập: tự điền (`__desmFill`) rồi nếu đang kết nối lại thì tự bấm Login (`__desmSubmitLogin`).
Chống lặp: ≤3 lần kết nối lại/5 phút, ≤2 lần tự bấm Login mỗi lần. Công tắc: Cài đặt > "Tự đăng nhập lại khi hết phiên" (`desmAutoReconnect`, mặc định bật). CHƯA kiểm chứng: máy chủ DESM xử lý phiên hết hạn thế nào (redirect hay trả trang rỗng) và cấu trúc trang `login.do` (nút Login) — nếu tự bấm không chạy, dùng ghi API/lưu HTML trang đăng nhập để chỉnh `__desmSubmitLogin`.

## 4. Chỉ mục JS tiêm vào trang (trong `makeScript()`)
- **Giao diện:** `allowed`, `setViewport`, `navHandlers` (menu ngăn kéo), `addFilterBar`/`buildForm`/`formify` (form tìm kiếm 2 cột + thanh Bộ lọc), `fixMaps`, `slimHeader`, `defaultToolbar`, `modalLock`.
- **Lưới TreeGrid (`GridE.js`, biến `TGGrids`):** `gridText`, `colShown`, `compactGrid` (chỉ giữ cột chọn + Package No + Location), `pkgGridOf`, `genGridOf`, `genericCards` (thẻ RSI/MRR/MRF/MPR), `cardView` (thẻ Package), `openDetail` (màn chi tiết kiện), `colToggle`.
- **Danh sách hạng mục của kiện (Detail Item):** `diLoadFast` (gọi thẳng API — xem §5), `diLoad` (cách cũ: khung ẩn `#desmDetailFrame` nạp `page_crt.do?MENU_SEQ=197`, điền Package No, bấm Search, đọc lưới), `diFrame`, `diProject` (đợi/chép ô Dự án), `diSelect` (chọn hạng mục trong lưới ẩn rồi bấm `btnLocationSetup`), `diShow` (đưa khung ẩn lên toàn màn hình để dùng hộp thoại cập nhật vị trí), `diWarm` (mở sẵn khung ẩn).
- **Quét:** `__desmFindPkg`/`findPkgIn` (tìm kiện theo Package No), `__desmFindDetail`/`findDetailIn` (tra Material Code từ QR → Package No → mở kiện), `ensurePkgDoc`, `pkgNorm`, `scanMsg`.
- **Việt hoá:** `viNorm`, `viMap`, `viLookup`, `viMiss`, `viText`, `viAttrs`, `viWalk`, `viPost`, `viLangSel`, `viInit`, `viApply`.
- **Đăng nhập:** `findUser`, `setVal`, `__desmFill`, `credHook`.

## 5. Những gì đã biết về web DESM
Nguồn: dump trang + file `plDetail.js` do người dùng gửi (2026-10-27).
- Server dạng `.do`; màn hình nạp trong iframe: `/page_crt.do?MENU_SEQ=<n>`. `MENU_SEQ=197` = **Hạng mục chi tiết** (đã xác nhận). `196` xuất hiện trong dump nhưng chưa xác nhận là màn hình nào.
- Lưới là **TreeGrid**; cột dùng tên như `PACKAGE_NO`, `MATERIAL_CODE`, `DESCRIPTION`, `DRAWING_NO`, `TAG_NO`, `REMARKS`, `COMMENTS`, `LOCATION`. Dòng dữ liệu: `r.Kind === 'Data'`.
- ID phần tử trang Hạng mục chi tiết: `txtProjectCode`, `txtProjectName`, `txtPackageNo`, `txtPackingListNo`, `txtSearchValue1`, `selSearchKey1` (giá trị `reamrks`/`size`/`material`), `btnSearch`, `btnLocationSetup`.
- **API lấy hạng mục:** `GET /getIdsmOsDetailList.do` (qua `$.ajax`, kế thừa `ajaxSetup.js`) với tham số `PAGE_NUM, PAGE_CNT, PROJECT_NO, PACKAGE_LIST_NO, PACKAGE_NO, DESCRIPTION, DRAWING_NO, TAG_NO, QTY_TYPE, QTY, KEY1, VALUE1, LOCATION, SEQUENCE, VENDOR, ATTRIBUTE10, TYPE, CATEGORY, SUB_CATEGORY, COMMENTS`. Phản hồi: `results.list` (mảng dòng, khoá = tên cột), `results.length` (tổng). Lỗi: `results == 'Err'`. Tra theo Material Code: `KEY1='material'`, `VALUE1=<mã>`.
- Các endpoint khác thấy trong `plDetail.js` (chưa dùng, chưa kiểm chứng ngữ nghĩa): `saveIdsmOsDetailList.do`, `getLocationCodeList.do`, `getVoyageList.do`, `getIsSubon.do`, `getIdsmSetupProject.do`, `desmLocationPopUp.do`, `desmLocationSearchPopUp.do`, `qrCodeMrd.do`, `saveIdsmQrCodeList.do`, `deleteDesmLocation.do`, `desmPlDtlEditLogPopUp.do`, `desmAttListPopUp.do`.
- Các màn hình Package, RSI, MRR, MRF, MPR hiện vẫn đọc dữ liệu từ lưới trên trang (chưa gọi API trực tiếp).

## 6. Quy ước và cạm bẫy khi sửa
- JS nằm trong chuỗi Swift **thô** `#"""..."""#`: viết `\s`, `\n` như JS bình thường (KHÔNG nhân đôi `\`); nội suy Swift là `\#(...)`. Giữ thụt lề dòng JS ≥ thụt lề của `"""#`. Sau khi sửa JS nên trích riêng đoạn và chạy `node --check` để bắt lỗi cú pháp.
- Mọi script tiêm phải **idempotent** và tự áp lại (trang DESM hay xoá style/DOM và tạo iframe mới).
- Chỉ áp cho domain `*.doosanenerbility.com` (`BrowserModel.allowedHosts`).
- Đường nhanh (API) luôn phải có **đường lui** về cách cũ (`diLoad`, `slowRun`) vì tham số/phản hồi chưa kiểm chứng hết.
- `diSelect` cần lưới ẩn có đúng dữ liệu kiện: đường nhanh chỉ cho danh sách hiển thị; sau khi hiện, app tự `diLoad` ở nền để lưới ẩn sẵn sàng. So khớp hạng mục dùng chuẩn hoá khoảng trắng (`nz`).
- Không lưu mật khẩu ngoài Keychain; nhật ký API che giá trị tên `pass/token/secret/auth*` nhưng **phần phản hồi có thể chứa dữ liệu nội bộ** — nhắc người dùng kiểm tra trước khi gửi đi.
- Khoá `@AppStorage` đáng chú ý: `desmCustomCSS`, `desmCustomDict`, `desmRememberLogin`, `desmAutofill`, `desmExportStripValues2` và `desmExportStripScripts2` (mặc định tắt), `desmScanOpenDetail`, `desmNetLogOn`, `desmAutoReconnect` (mặc định bật), `desmLastActive` (thời điểm tải trang DESM gần nhất). Bộ nhớ danh sách hạng mục: `localStorage['desmDI:<PackageNo>']`; nhật ký API: `localStorage['desmNetLog']`, cờ bật `desmNetOn`.

## 7. Công cụ tinh chỉnh có sẵn trong Cài đặt
- "Sao chép cấu trúc trang đang mở" (sơ đồ DOM, không gồm dữ liệu nhập).
- "Mã HTML của trang": sao chép/lưu HTML (gồm iframe cùng domain), "Lưu script của trang" (tải các file `/resources/scripts/...`).
- "Công cụ lấy mã & API": ghi nhật ký request XHR/fetch, tải nội dung một địa chỉ cùng domain.
- Ngôn ngữ: "Sao chép chuỗi chưa dịch" để bổ sung từ điển.
**Quy trình tinh chỉnh một màn hình mới:** bật ghi API → mở màn hình, bấm Search/thao tác → lưu nhật ký API → tìm địa chỉ gọi dữ liệu → thêm đường nhanh có đường lui.

## 8. Trạng thái và việc nên làm tiếp
- Mã chưa được build bằng Xcode trong môi trường tạo ra nó và chưa thử với tài khoản DESM thật; JS đã qua kiểm tra cú pháp bằng Node.
- Cần thử thật: đường nhanh danh sách hạng mục (tham số `PAGE_CNT`, `QTY_TYPE`), tra QR bằng `KEY1='material'`, chạm ghim/Location Update sau khi tải nhanh.
- Việc tiếp theo hợp lý: ghi API ở màn Package/RSI/MRR/MRF/MPR để thêm đường nhanh tương tự; cân nhắc làm lưới Package nhanh hơn.

## Sửa lỗi: vừa đăng nhập xong lại báo "Phiên đã hết hạn" và về trang đăng nhập
Nguyên nhân: `checkLoginForm` (WebView.swift) và thăm dò `probeSession` coi MỌI ô `input[type=password]` là trang đăng nhập, mà `main.do`
của DESM có sẵn form/ô đổi mật khẩu (tài khoản ngoài @doosan.com) -> vào được main.do vẫn bị đẩy về login.do (lặp tối đa 3 lần/5 phút).
Đã sửa: chỉ tính là trang đăng nhập khi có ĐÚNG MỘT ô mật khẩu đang hiển thị; bỏ dò ô mật khẩu trong HTML ở `probeSession`.

## Nhật ký API nâng cấp (để làm màn tra cứu hàng gọi API trực tiếp)
- Trang gửi từng request sang app qua message `desmNet`; app ghi vào file `Caches/desm-netlog.jsonl` (NetLogStore ở cuối BrowserView.swift), tối đa ~40 MB.
- API dữ liệu lưu ĐỦ phản hồi (≤400 000 ký tự/request) và body (≤30 000); js/css/ảnh/font chỉ một dòng. Có thêm `ct` (content-type) và `len`.
- Xuất 3 dạng trong Cài đặt: văn bản, JSON đầy đủ (`desm-api-full.json`), tóm tắt endpoint (`desm-api-summary.txt`: số lần gọi, query/body mẫu, tên trường phản hồi).
- Quy trình: bật ghi -> thao tác tra cứu hàng -> lưu JSON + tóm tắt -> dựa vào đó viết client gọi thẳng `URLSession` với cookie phiên (xem `probeSession`).

## Cài đặt sắp xếp lại
Màn chính: Hiển thị, Ngôn ngữ, Quét Package No, Đăng nhập, rồi "Nâng cao & công cụ phát triển" (CSS bổ sung, từ điển bổ sung, nhật ký API, mã nguồn trang, tải địa chỉ).
Đã bỏ trùng lặp: 2 nút xóa đăng nhập -> 1; 2 đoạn giải thích tự đăng nhập -> 1; nút "Áp dụng CSS/từ điển" (đã có "Xong"); "Sao chép" nhật ký API/HTML (quá dài, dùng lưu file);
3 mục công cụ -> 1 màn "Nâng cao"; ô độ rộng thu nhỏ chỉ hiện khi chọn chế độ "Vừa màn hình".

## Tự lưu cấu trúc & CSS từng màn hình
Nâng cao > "Ghi từng màn hình". Script `snapRecorderSource` (trang chính) quét trang + iframe cùng domain mỗi 2,5 giây; màn nào nội dung ổn định (2 lần đo bằng nhau) thì gửi message `desmSnap`
(path, HTML đã làm sạch, cây cấu trúc, danh sách + nội dung CSS). `SnapStore` lưu trong Caches/desm-snap; nút "Lưu tất cả màn hình" xuất 1 file: mục lục -> từng màn -> toàn bộ CSS.

## Chụp ảnh toàn trang
Nút "Chụp" ở thanh dưới -> `BrowserModel.captureFullPage()`: mở rộng khung cuộn/iframe, `createPDF` toàn bộ contentSize, vẽ PNG (≤12 000 px, ≤80 triệu điểm), khôi phục trang, mở bảng chia sẻ (Lưu vào Ảnh / Tệp). Quá dài -> xuất PDF.
Hạn chế: bảng TreeGrid cuộn ảo chỉ có các dòng đang hiển thị.

## Vuốt mép màn hình để quay lại/tiến
`WebView.swift`: hai `UIScreenEdgePanGestureRecognizer` (trái = goBack, phải = goForward; ngưỡng 60 pt hoặc vận tốc 500) thay cho `allowsBackForwardNavigationGestures` (đã tắt để không chuyển hai lần). Công tắc: Cài đặt > Hiển thị (`desmEdgeSwipe`, mặc định bật).

## Giao diện Header/Footer mới (2026-10-27)
- Header (CSS, `MobileStyles.swift`): gradient `#173eae → #1761e8 → #27a8ed`, chấm + sóng sáng, bo đáy 26px, nút ≡ và ô Language dạng kính mờ 44px; thẻ tab bo 16px, viền trên xanh 4px. Chiều cao iframe tab đã trừ `7.2rem`.
- Footer (SwiftUI, `BrowserView.swift`): `DesmTabBar` – 5 tab Kiện hàng / Nhập kho / Xuất kho / Báo cáo / Thêm, thẻ trắng nổi trên nền sóng xanh nhạt; luôn hiện khi đang ở DESM (`model.inDesm`). Ngoài DESM (đăng nhập) vẫn dùng thanh điều hướng cũ.
- Tab mở menu DESM bằng JS `__desmOpenMenu(id, pattern)`; ánh xạ tab → mục menu nằm ở `enum DesmTab` (`menuId`, `pattern`). Chỉ `196` (Kiện hàng) là đã xác nhận; 3 tab còn lại đang khớp theo tên: Nhập kho = "Material Receiving", Xuất kho = "Outgoing Control", Báo cáo = "RSI Summary" — CHƯA kiểm chứng trên máy thật. Không khớp thì app mở ngăn kéo menu và báo toast.
- "Thêm" (`MoreSheet`) chứa các nút cũ: Menu đầy đủ, Quay lại, Tiến, Tải lại, Về DESM, Chụp trang, Chế độ hiển thị, Ẩn/hiện thanh địa chỉ, Cài đặt.
- Chưa build bằng Xcode trong môi trường tạo ra; JS đã `node --check`, SVG đã kiểm tra hợp lệ.

## Sửa: không nhập được Package No khi có footer mới
Bàn phím làm SwiftUI đẩy footer lên và ép WebView thấp → TreeGrid báo "Too small space for the grid" làm ô mất focus. Đã thêm `.ignoresSafeArea(.keyboard, edges: .bottom)` ở `BrowserView`. Trang đăng nhập/hết phiên (ngoài DESM) nay cũng dùng thanh dưới + thanh địa chỉ màu sáng (`FooterBackground`, `bottomBar`, `header`).

## Sửa: vuốt mép trái ở màn chi tiết kiện báo "Không còn trang trước"
Màn chi tiết kiện / khung Cập nhật vị trí là lớp phủ JS, không phải trang mới nên WebView không có lịch sử. Thêm `__desmBack()` (đóng lớp phủ rồi mới tính tới lịch sử); `edgeSwipe` (WebView.swift) và `BrowserModel.goBack` gọi nó trước. Trong DESM không còn toast "Không còn trang trước".

## Ngăn kéo menu trái (sáng)
CSS cuối `MobileStyles.swift`: nền gradient xanh nhạt, bo phải 28px, mục menu bo 16px, mục đang chọn nền trắng chữ xanh, lớp mờ phía sau xanh nhạt.

## Nút SAVE ở màn Detail Item (2026-10-28)
- `showItemDetail` (BrowserView.swift): SHORT/OVER/DMG/MISSING (+ô số lượng) và Remarks sửa được, nút SAVE gọi `diSave` -> `GET/POST /saveIdsmOsDetailList.do` (phương thức theo ajaxSetup của trang) với `list` = JSON mảng 1 dòng, giống `btnSaveClick` trong `plDetail.js`.
- Dòng gửi: PROJECT_NO, TRK_ITEM_NAME, PACKAGE_NO, MATERIAL_CODE, ITEM_SIZE, DESCRIPTION, DRAWING_NO, LOCATION, TAG_NO, UNIT, IN_QTY, MATERIAL, REMARKS, REPORT_SHORT/OVER/DMG/MISSING ("1"/"0" theo số lượng > 0) và REPORT_*_QTY. Lỗi khi `result.error != null`.
- Chỉ sửa được khi `IS_CONFIRM_MATERIAL = 'Y'` (như lưới web) và đã có `TRK_ITEM_NAME` (openItemDetail luôn nạp lại dòng đầy đủ bằng API). Chặn lưu khi In Q'ty < RSI Q'ty − MRF Q'ty (như web).
- App mDESM (Android, React Native) dùng API khác: `POST https://api.doosan.mzgcp.net/mobile/custom/saveMobileDetailItemInfo` + Bearer idToken Oracle IDCS; body USER_AD, PROJECT_NO, TRK_ITEM_NAME, PACKAGE_NO, MATERIAL_CODE, REMARKS, REPORT_* ('Y'/'N'). KHÔNG dùng ở đây vì cần OAuth.
- CHƯA thử với DESM thật: nên lưu thử một hạng mục không quan trọng trước.

## Sửa dòng MRR: Received Date / Visual Check hàng loạt (2026-10-28)
- Nguồn: `desmMrrCreationPopUp.js`, `plMrr.js` (người dùng gửi). Web POST (ajaxSetup mặc định POST).
- Thẻ MRR (genericCards, lưới có cột MRR_NO + INSPECTION_DATE_FROM, dòng có MRR_HEADER_ID) mở rộng ra có nút "Sửa dòng MRR" -> `mrrEditor` (BrowserView.swift, ngay trước `genericCards`).
- Đọc: `/getDesmMrrInfoList.do {MRR_HEADER_ID}` -> `results.headerList[0]`, `results.lineList`.
- Chỉ sửa khi STATUS = Incomplete hoặc Rejected (như web: Pre-Confirmed/Confirmed là chỉ xem).
- Chọn nhiều dòng -> đặt Received Date (yyyy/MM/dd) hoặc Visual Check (Good/Defect) -> SAVE = `/saveDesmMrrSave.do` với TRANS_TYPE='Incomplete', `updateList` = JSON các dòng đã sửa (MRR_LINE_ID, TRK_ITEM_NAME, PACKING_LIST_NO, PACKAGE_NO, DESCRIPTION, SHIPMENT_NO, PACKAGE_TYPE, VISUAL_CHECK, VISUAL_CHECK_DATE, STORAGE_LOCATION, RECEIVED_DATE, REMARKS, ATTACH_GRP_CD, FILE_PATH, QTY) cùng trường header (MRR_HEADER_ID, MRR_NO, MRR_NAME, STATUS, RECEIVED/INSPECTION_DATE_FROM/TO, REMARK, ATTACH_GRP_CD, PREPARED_BY, CHECKED_BY, CONFIRMED_BY, APPROVED_BY='', PROJECT_NO). Lỗi khi `result.error != null`.
- Kiểm tra như web: From <= To; Received Date mọi dòng nằm trong [From, To]; header phải có From/To (web trả lỗi nếu trống).
- KHÔNG làm các bước chuyển trạng thái (Request/Check/Confirm/Reject) và thêm/xoá dòng.
- Đã chạy thử trong Chromium với API giả (payload đúng); CHƯA thử với DESM thật. Định dạng ngày server trả về chưa kiểm chứng (mrrFmt đoán yyyy/MM/dd, yy/MM/dd, timestamp; không parse được thì gửi nguyên chuỗi gốc).

## Mục "Lịch sử Packing List" (Thêm)
- Thêm ô "Lịch sử Packing List" vào `MoreSheet` -> mở `PackingHistorySheet` (cuối `BrowserView.swift`), tương ứng khung "Packing List Upload History (Last 3 days)" ở `home.do`.
- Dữ liệu: `POST /getInitDefailProject.do` (lấy `SEGMENT1` = mã dự án) rồi `POST /dashboard/getHomeSummary.do` với `PROJECT_NO`, `DAY_TERM` (mặc định 3). Trường dùng: `INVOICE_NO, SHIPMENT_NO, ORGINAL_FILE, RESULT, CREATION_DATE, LAST_UPDATED_BY, ATT_ID`.
- CHƯA kiểm chứng: `DAY_TERM` = 1/7 có được máy chủ chấp nhận; chưa build bằng Xcode (JS đã qua `node --check`).

## Mục "RSI chưa đóng / vừa đóng" và "MRF trả hàng" (Thêm)
- `DesmDocSheet` + `BrowserModel.fetchDocs` (cuối `BrowserView.swift`). API: RSI = `getDesmRsiViewList.do` + `getDesmRsiOutGoingList.do`; MRF = `getMrfSummaryList.do` + `getDesmMrfReturnList.do` (đều POST, xem log 2026-10-28).
- "Chưa đóng" = tổng BALANCE_QTY (RSI) / MRF_BALANCE_QTY (MRF) > 0. "Vừa đóng" = có HANDOVER_DATE / RETURN_DATE trong N ngày và không còn số lượng còn lại. Đây là QUY ƯỚC suy từ dữ liệu, chưa xác nhận với nghiệp vụ; chưa biết hết giá trị STATUS.
- Chưa kiểm chứng: máy chủ lọc đúng theo START/END_*_DATE khi để trống số phiếu (đã lọc thêm phía máy khách); RSI chưa đóng chỉ xét phiếu có ngày yêu cầu trong 180 ngày gần nhất.
- Chi tiết phiếu: bấm một phiếu trong `DesmDocSheet` -> `DesmDocDetailView` (`fetchDocDetail`): tải lại theo số phiếu (không giới hạn ngày), ghép dòng yêu cầu/tồn với ngày bàn giao (RSI: theo Package No + Material Code; MRF: theo MRF_LINE_ID). Dùng đúng các truy vấn đã có trong log nên tham số đã kiểm chứng.
