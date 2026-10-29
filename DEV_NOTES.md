# DESM Mobile — Ghi chú cho người/AI tiếp tục phát triển

> Đọc file này trước khi sửa mã. Tài liệu mô tả app đang làm gì, mã nằm ở đâu, những điều đã biết về web DESM và những điều CHƯA kiểm chứng.

## 1. App làm gì
Ứng dụng iOS (SwiftUI, iOS 16+) bọc website nội bộ **DESM** của Doosan Enerbility (`https://desm.doosanenerbility.com`, giao diện SB Admin 2 trên desktop, dự án O Mon 4) trong một `WKWebView`, rồi **tiêm CSS/JS** để biến trang desktop thành giao diện dùng được trên điện thoại cho người làm kho/hiện trường: tra kiện hàng (Package), hạng mục chi tiết (Detail Item), cập nhật vị trí (Location Update), quét mã bằng camera, v.v.
App KHÔNG có backend riêng và không gọi dịch vụ ngoài; mọi dữ liệu đi qua chính phiên đăng nhập DESM của người dùng.

## 2. Bản đồ file
| File | Vai trò |
|---|---|
| `DESMMobileApp.swift` | Điểm vào, hiện `BrowserView`. |
| `Core/` | `BrowserModel.swift` (trạng thái, @AppStorage, tham chiếu WKWebView, `installUserScript`/`evaluateNow`), `LayoutMode.swift`. |
| `Scripts/` | JS và CSS tiêm vào trang: `DodoBubble.swift` (nút chat Dodo), `UserScript.swift` (`makeScript()` — toàn bộ JS giao diện), `NetRecorder.swift` (ghi API), `PageExport.swift` (đọc cấu trúc/HTML/script trang), `ScanActions.swift` (kết quả quét → JS), `MobileStyles.swift`, `Translations.swift`. |
| `Networking/DesmAPI.swift` | `desmQueryAsync` (URLSession + cookie), `desmProjectNo()`, `desmQuery` (bản callback), đường lui `desmQueryViaWebView`. |
| `Session/SessionReconnect.swift` | Thăm dò phiên, tự đăng nhập lại (`probeSession`, `openLogin`, `appBecameActive`). |
| `UI/` | `BrowserView.swift` (màn chính), `DesmTabBar`, `DesmDialog`, `MoreSheet`, `ShareSheet`. |
| `Settings/SettingsView.swift` | Màn Cài đặt. |
| `Sheets/` | Các màn native mở từ "Thêm"/tab: `PackingHistory`, `DocSheet`, `DocDetail`, `Outgoing`, `WipCompletion`, `MrfReturn`, `Activity`, `EditLog`, `Notices`. |
| `Vessel/` | Bản đồ tàu: `VesselData`, `VesselLoader`, `VesselMap`, `VesselSheet`. |
| `Background/BackgroundRefresh.swift` | Kiểm tra nền + thông báo cục bộ (thông báo DESM mới, tàu sắp đến). |
| `AI/` | "AI riêng" (chuyển từ app LiveTranslate): `AIProviders` (8 nhà, key trong Keychain `DESMMobile.AI`, thứ tự ưu tiên), `AIClient` (Gemini/Claude/OpenAI-compatible, `listModels`, `pickWorkingModel`, `run` có chuyển nhà khi lỗi), `AISettingsView` (nhập key, dò model, tự chọn model), `AIChatView` (khung chat native + đổi nhanh nhà/model). |
| `Tools/` | Công cụ tinh chỉnh: `NetLogStore`, `SnapStore`, `PageSnapshot`, `DesmFetch`, `DesmSource`, `WriteAudit`. |
| `Scanner/PackageScanner.swift` | Quét Package No/QR bằng camera. |
| `Web/WebView.swift` | `UIViewRepresentable` bọc WKWebView, `Coordinator` (điều hướng, alert/confirm thật, nhận message từ JS), `SessionStore` (lưu cookie phiên vào Keychain), `CredStore` (tài khoản tự điền, Keychain). |
| `Branding/`, `Assets.xcassets` | Logo, icon, nền SVG header/footer. |

## 3. Luồng chạy chính
1. `WebView.makeUIView` nạp cookie từ Keychain (`SessionStore.restore`) rồi mở DESM.
2. `BrowserModel.installUserScript()` cài 2 `WKUserScript` (document start, mọi frame): script giao diện (`makeScript()`) và bộ ghi API (`netRecorderSource`). Sau mỗi lần tải xong, `evaluateNow()` áp lại.
3. Script giao diện chạy trong **từng frame** (DESM dựng màn hình trong iframe bằng `page_crt.do?MENU_SEQ=<n>`). Nó tự áp lại khi trang xoá style hoặc tạo iframe mới (vòng `applyAll`).
4. JS gọi ngược Swift qua `webkit.messageHandlers`: `desmCred` (tài khoản), `desmLang` (ngôn ngữ), `desmScanResult` (kết quả quét → toast).
5. Swift gọi JS qua `evaluateJavaScript` / `callAsyncJavaScript`: `__desmFindPkg`, `__desmFindDetail` (quét), `__desmApplyAll`...

### Tự kết nối lại khi hết phiên (đăng nhập)
Vấn đề đã gặp: qua đêm phiên DESM hết hạn nhưng app nạp lại địa chỉ cũ với cookie cũ nên trang không chạy thay vì về `login.do`. Xử lý (extension "Tự kết nối lại" trong `Session/SessionReconnect.swift`, hook trong `Web/WebView.swift`):
1. Mở app: `SessionStore.restore` rồi `BrowserModel.startLoad` thăm dò `main.do` bằng URLSession (hết phiên = chuyển về login / 401 / có ô mật khẩu); hết phiên hoặc chưa có phiên thì xoá cookie DESM và mở `https://desm.doosanenerbility.com/login.do`.
2. App quay lại từ nền > 10 phút: thăm dò lại (`appBecameActive`).
3. Đang dùng: JS ở `netRecorderSource` (`checkXhr`) phát hiện XHR bị đẩy về login/401/HTML đăng nhập → message `desmSession` → `reconnectSession`. Ngoài ra `Coordinator.checkLoginForm` bắt trường hợp trang thường mà hiện ô mật khẩu.
4. Ở trang đăng nhập: tự điền (`__desmFill`) rồi nếu đang kết nối lại thì tự bấm Login (`__desmSubmitLogin`).
Chống lặp: ≤3 lần kết nối lại/5 phút, ≤2 lần tự bấm Login mỗi lần. Công tắc: Cài đặt > "Tự đăng nhập lại khi hết phiên" (`desmAutoReconnect`, mặc định bật). CHƯA kiểm chứng: máy chủ DESM xử lý phiên hết hạn thế nào (redirect hay trả trang rỗng) và cấu trúc trang `login.do` (nút Login) — nếu tự bấm không chạy, dùng ghi API/lưu HTML trang đăng nhập để chỉnh `__desmSubmitLogin`.

## 4. Chỉ mục JS tiêm vào trang (trong `makeScript()`, `Scripts/UserScript.swift`)
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
- Trang gửi từng request sang app qua message `desmNet`; app ghi vào file `Caches/desm-netlog.jsonl` (`Tools/NetLogStore.swift`), tối đa ~40 MB.
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
- Footer (SwiftUI, `UI/DesmTabBar.swift`): `DesmTabBar` – 5 tab Kiện hàng / Nhập kho / Xuất kho / Báo cáo / Thêm, thẻ trắng nổi trên nền sóng xanh nhạt; luôn hiện khi đang ở DESM (`model.inDesm`). Ngoài DESM (đăng nhập) vẫn dùng thanh điều hướng cũ.
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
- `showItemDetail` (JS trong `Scripts/UserScript.swift`): SHORT/OVER/DMG/MISSING (+ô số lượng) và Remarks sửa được, nút SAVE gọi `diSave` -> `GET/POST /saveIdsmOsDetailList.do` (phương thức theo ajaxSetup của trang) với `list` = JSON mảng 1 dòng, giống `btnSaveClick` trong `plDetail.js`.
- Dòng gửi: PROJECT_NO, TRK_ITEM_NAME, PACKAGE_NO, MATERIAL_CODE, ITEM_SIZE, DESCRIPTION, DRAWING_NO, LOCATION, TAG_NO, UNIT, IN_QTY, MATERIAL, REMARKS, REPORT_SHORT/OVER/DMG/MISSING ("1"/"0" theo số lượng > 0) và REPORT_*_QTY. Lỗi khi `result.error != null`.
- Chỉ sửa được khi `IS_CONFIRM_MATERIAL = 'Y'` (như lưới web) và đã có `TRK_ITEM_NAME` (openItemDetail luôn nạp lại dòng đầy đủ bằng API). Chặn lưu khi In Q'ty < RSI Q'ty − MRF Q'ty (như web).
- App mDESM (Android, React Native) dùng API khác: `POST https://api.doosan.mzgcp.net/mobile/custom/saveMobileDetailItemInfo` + Bearer idToken Oracle IDCS; body USER_AD, PROJECT_NO, TRK_ITEM_NAME, PACKAGE_NO, MATERIAL_CODE, REMARKS, REPORT_* ('Y'/'N'). KHÔNG dùng ở đây vì cần OAuth.
- CHƯA thử với DESM thật: nên lưu thử một hạng mục không quan trọng trước.

## Sửa dòng MRR: Received Date / Visual Check hàng loạt (2026-10-28)
- Nguồn: `desmMrrCreationPopUp.js`, `plMrr.js` (người dùng gửi). Web POST (ajaxSetup mặc định POST).
- Thẻ MRR (genericCards, lưới có cột MRR_NO + INSPECTION_DATE_FROM, dòng có MRR_HEADER_ID) mở rộng ra có nút "Sửa dòng MRR" -> `mrrEditor` (`Scripts/UserScript.swift`, ngay trước `genericCards`).
- Đọc: `/getDesmMrrInfoList.do {MRR_HEADER_ID}` -> `results.headerList[0]`, `results.lineList`.
- Chỉ sửa khi STATUS = Incomplete hoặc Rejected (như web: Pre-Confirmed/Confirmed là chỉ xem).
- Chọn nhiều dòng -> đặt Received Date (yyyy/MM/dd) hoặc Visual Check (Good/Defect) -> SAVE = `/saveDesmMrrSave.do` với TRANS_TYPE='Incomplete', `updateList` = JSON các dòng đã sửa (MRR_LINE_ID, TRK_ITEM_NAME, PACKING_LIST_NO, PACKAGE_NO, DESCRIPTION, SHIPMENT_NO, PACKAGE_TYPE, VISUAL_CHECK, VISUAL_CHECK_DATE, STORAGE_LOCATION, RECEIVED_DATE, REMARKS, ATTACH_GRP_CD, FILE_PATH, QTY) cùng trường header (MRR_HEADER_ID, MRR_NO, MRR_NAME, STATUS, RECEIVED/INSPECTION_DATE_FROM/TO, REMARK, ATTACH_GRP_CD, PREPARED_BY, CHECKED_BY, CONFIRMED_BY, APPROVED_BY='', PROJECT_NO). Lỗi khi `result.error != null`.
- Kiểm tra như web: From <= To; Received Date mọi dòng nằm trong [From, To]; header phải có From/To (web trả lỗi nếu trống).
- KHÔNG làm các bước chuyển trạng thái (Request/Check/Confirm/Reject) và thêm/xoá dòng.
- Đã chạy thử trong Chromium với API giả (payload đúng); CHƯA thử với DESM thật. Định dạng ngày server trả về chưa kiểm chứng (mrrFmt đoán yyyy/MM/dd, yy/MM/dd, timestamp; không parse được thì gửi nguyên chuỗi gốc).

## Mục "Lịch sử Packing List" (Thêm)
- Thêm ô "Lịch sử Packing List" vào `MoreSheet` -> mở `PackingHistorySheet` (`Sheets/PackingHistory.swift`), tương ứng khung "Packing List Upload History (Last 3 days)" ở `home.do`.
- Dữ liệu: `POST /getInitDefailProject.do` (lấy `SEGMENT1` = mã dự án) rồi `POST /dashboard/getHomeSummary.do` với `PROJECT_NO`, `DAY_TERM` (mặc định 3). Trường dùng: `INVOICE_NO, SHIPMENT_NO, ORGINAL_FILE, RESULT, CREATION_DATE, LAST_UPDATED_BY, ATT_ID`.
- CHƯA kiểm chứng: `DAY_TERM` = 1/7 có được máy chủ chấp nhận; chưa build bằng Xcode (JS đã qua `node --check`).

## Mục "RSI chưa đóng / vừa đóng" và "MRF trả hàng" (Thêm)
- `DesmDocSheet` + `BrowserModel.fetchDocs` (`Sheets/DocSheet.swift`). API: RSI = `getDesmRsiViewList.do` + `getDesmRsiOutGoingList.do`; MRF = `getMrfSummaryList.do` + `getDesmMrfReturnList.do` (đều POST, xem log 2026-10-28).
- "Chưa đóng" = tổng BALANCE_QTY (RSI) / MRF_BALANCE_QTY (MRF) > 0. "Vừa đóng" = có HANDOVER_DATE / RETURN_DATE trong N ngày và không còn số lượng còn lại. Đây là QUY ƯỚC suy từ dữ liệu, chưa xác nhận với nghiệp vụ; chưa biết hết giá trị STATUS.
- Chưa kiểm chứng: máy chủ lọc đúng theo START/END_*_DATE khi để trống số phiếu (đã lọc thêm phía máy khách); RSI chưa đóng chỉ xét phiếu có ngày yêu cầu trong 180 ngày gần nhất.
- Chi tiết phiếu: bấm một phiếu trong `DesmDocSheet` -> `DesmDocDetailView` (`fetchDocDetail`): tải lại theo số phiếu (không giới hạn ngày), ghép dòng yêu cầu/tồn với ngày bàn giao (RSI: theo Package No + Material Code; MRF: theo MRF_LINE_ID). Dùng đúng các truy vấn đã có trong log nên tham số đã kiểm chứng.

## Tab "Xuất kho" (native): `DesmOutgoingSheet` / `DesmOutgoingVM` (`Sheets/Outgoing.swift`)
- Thay cho việc mở màn Outgoing Control (menu 376) của web khi bấm tab Xuất kho (web vẫn mở được qua "Menu đầy đủ").
- Tìm: `POST /getDesmOutGoingCreationList.do` (popup Creation, tham số theo log 2026-10-28). Lưu: `POST /saveDesmRsiOutSave.do`, body `updateList=<JSON>` gồm `RSI_HEADER_ID, RSI_LINE_ID, HANDOVER_DATE (yyyy/MM/dd), HANDOVER_QTY, MATERIAL_CODE, PROJECT_NO, RECEIVER_NAME` (đọc từ `desmOutGoingCreationPopUp.js`). Thành công khi `error` rỗng/null; `error == "QTY"` kèm `RSI_LINE_ID`, `HANDOVER_AVAILABLE_QTY` là vượt số lượng.
- WIP Completion (`/material/savePlWipQuantity.do`, cần SHOP_UNIT + SHOP_BLDG) là chức năng khác, chưa làm.
- CHƯA kiểm chứng: tên trường dữ liệu trả về của danh sách (suy từ cột lưới), và máy chủ có yêu cầu thêm gì cho lệnh lưu. Thử với 1 dòng trước.

## "WIP Completion" (Thêm): `DesmWipSheet` / `DesmWipVM` (`Sheets/WipCompletion.swift`)
- Tìm `POST /material/getPlWipCreationList.do` (đã có trong log), lưu `POST /material/savePlWipQuantity.do` với `updateList` JSON `{PROJECT_NO, RSI_HEADER_ID, RSI_LINE_ID, WIP_DATE, WIP_QTY, SHOP_UNIT, SHOP_BLDG, MATERIAL_CODE}` (từ `plWipCreationPopup.js`). Mỗi dòng bắt buộc có ngày, số lượng, C.Unit và BLDG; có nút gán loạt như web. Chưa kiểm chứng lệnh lưu với máy chủ thật.

## Tab "Trả hàng" (MRF) thay tab "Nhập kho": `DesmMrfReturnSheet` / `DesmMrfReturnVM` (`Sheets/MrfReturn.swift`)
- Làm theo popup "Return Creation" (`desmReturnCreationPopUp.js`, menu 479). Tìm: `POST /getDesmReturnCreationList.do` (PROJECT_NO, PACKAGE_NO, MRF_NO, MATERIAL_CODE, ...). Dòng dùng: MRF_NO, MRF_NAME, SUBCONTRACTOR, RETURN_REQ_DATE, MATERIAL_CODE, PACKAGE_NO, DESCRIPTION, REQ_RETURN_QTY, RETURN_AVAILABLE_QTY, MRF_HEADER_ID, MRF_LINE_ID, RSI_LINE_ID.
- Lưu: `POST /saveDesmMrfReturnSave.do`, `updateList` = JSON `{MRF_HEADER_ID, MRF_LINE_ID, MATERIAL_CODE, PROJECT_NO, RETURN_DATE (yyyy/MM/dd), RETURN_QTY, RSI_LINE_ID}`. `error == "QTY"` kèm `MRF_LINE_ID`, `RETURN_AVAILABLE_QTY` là vượt số lượng.
- CHƯA kiểm chứng với DESM thật: tên trường danh sách (suy từ cột lưới; log mới chỉ trả rỗng) và lệnh lưu. Thử 1 dòng trước. Ô "MRF Name" lọc phía máy khách.

## Lịch sử Packing List: bấm dòng để vào kiện + tải xlsx (2026-10-28)
- Bấm một dòng -> `PackingHistorySheet.onOpen(invoice)` -> đóng sheet, `BrowserModel.openPackingList` gọi JS `__desmFindPackingList`: mở màn Kiện hàng (`ensurePkgDoc`), điền `txtPackingListNo` = Invoice (xoá `txtPackageNo`), bấm Search.
- Nút mũi tên tải (có `ATT_ID`) -> `BrowserModel.downloadPackingFile`: dò địa chỉ chứa "download" trong `home.do` + script của nó, thử thêm vài địa chỉ phổ biến với `?ATT_ID=` / `?attId=`, chỉ nhận phản hồi là file (zip `PK` hoặc không phải HTML/JSON). Lưu vào thư mục tạm theo tên `ORGINAL_FILE`, mở bảng chia sẻ (Lưu vào Tệp...).
- CHƯA kiểm chứng: địa chỉ/tham số tải thật của DESM. Nếu báo "Không tìm được địa chỉ tải file", bật ghi API, bấm tên file ở khung Packing List Upload History trên home.do rồi gửi log để cố định đúng địa chỉ.

## Mục "Hoạt động" (Thêm) — `DesmActivitySheet` / `BrowserModel.fetchActivity` (`Sheets/Activity.swift`)
- Gom trong 1/3/7 ngày: Packing List tải lên (`fetchPackingHistory`), RSI mới tạo (`getDesmRsiViewList.do`, theo REQUEST_DATE), RSI bàn giao (`getDesmRsiOutGoingList.do`), MRF mới (`getMrfSummaryList.do`, lọc RETURN_REQ_DATE phía máy khách), MRF đã trả (`getDesmMrfReturnList.do`). Đều là truy vấn đã có trong log.
- Nhãn "MỚI" = mã hoạt động chưa có trong `UserDefaults['desmActivitySeen']` (tối đa 600 mã); lần mở đầu tiên không gắn nhãn. Chỉ cập nhật khi mở màn hình, KHÔNG có thông báo đẩy khi app đóng (cần backend hoặc background fetch).
- "Mới tạo" suy từ ngày yêu cầu nên chỉ chính xác theo ngày. Chưa có lịch sử cập nhật vị trí (cần ghi API khi mở "Edit Log" của hạng mục: `desmPlDtlEditLogPopUp.do`).

## Hoạt động: thêm "Đổi vị trí" và "Xác nhận kiện" (2026-10-28, theo log người dùng gửi)
- `POST /getIdsmOsSummaryList.do` (body như log, bỏ PACKAGE_LIST_NO) trả mỗi kiện: `LOC_UPDATE_DATE` (yyyy/MM/dd), `LOC_UPDATED_BY`, `STORAGE_LOCATION`, `CONFIRM_DATE`, `CONFIRMED_BY`. Chỉ có lần cập nhật cuối; lọc ngày phía máy khách. CHƯA kiểm chứng: gọi không lọc số Packing List có bị giới hạn số dòng/chậm không.
- Lưu vị trí thật (đã thấy trong log): `POST /saveDesmLocationCheck.do` rồi `/saveDesmLocation.do`, body `list=[{PROJECT_NO,TRK_ITEM_NAME,PACKAGE_NO,CODE_TYPE:"SUMMARY"}]&MAP_MST_ID=<id>&MAP_DTL_ID=<id>`; phản hồi `{"success":"OK"}`. Bản đồ: `getDesmMapCreationList.do`, `getDesmMapInfoList.do`.
- Log gửi lên KHÔNG có request Edit Log (chưa mở popup đó).

## Edit Log của hạng mục (2026-10-28, từ `plDetail.js` + `desmPlDtlEditLogPopUp.js` người dùng gửi)
- Web: bấm ô MATERIAL_CODE ở lưới "Hạng mục chi tiết" -> `openModal` -> popup `/desmPlDtlEditLogPopUp.do` -> `$.ajax('/getDesmPlDetailEditLogList.do', {PROJECT_NO, TRK_ITEM_NAME, MATERIAL_CODE})` (phương thức theo ajaxSetup), `data.results` = mảng dòng. Cột: DESCRIPTION, DRAWING_NO, TAG_NO, UNIT, NOS, IN_QTY, MATERIAL_CODE, MATERIAL, LOCATION, LOC_UPDATE_DATE, LOC_UPDATED_BY, REMARKS, REPORT_SHORT/OVER/DMG/MISSING(+_QTY), CREATION_DATE_TXT (ngày sửa), CREATED_BY (người sửa).
- App: nút "Lịch sử thay đổi (Edit Log)" ở màn Detail Item (`openEditLog` cạnh `openMrfDetail`, trong `makeScript()`): sắp mới nhất trước, so từng bản với bản cũ hơn để hiện trường thay đổi (Location, In Q'ty, Remarks...). Cần `TRK_ITEM_NAME` của hạng mục.
- CHƯA kiểm chứng với DESM thật (JS đã `node --check`). Chưa có Edit Log toàn dự án (API cần từng hạng mục), nên mục "Hoạt động" vẫn chỉ có lần đổi vị trí cuối của mỗi kiện.
- Các endpoint khác thấy trong plDetail.js: `deleteDesmLocation.do` (xoá vị trí, body `deleteList`), `saveIdsmQrCodeList.do`, `desmAttListPopUp.do`.

## Mục "Tra Edit Log" (Thêm) — `DesmEditLogSheet` / `DesmEditLogDetailView` (`Sheets/EditLog.swift`)
- Nhập Material Code (KEY1='material') hoặc Package No -> `/getIdsmOsDetailList.do` -> chọn hạng mục -> `/getDesmPlDetailEditLogList.do`; bản ghi mới nhất trước, so với bản cũ hơn để hiện trường thay đổi. Cùng API với nút Edit Log ở màn Detail Item. Chưa kiểm chứng với DESM thật.

## Đồng bộ giao diện các màn native (2026-10-28)
- Mọi màn native mở từ "Thêm" (Packing List, RSI/MRF, Xuất kho, WIP, Trả hàng MRF, Hoạt động, Tra Edit Log, Cài đặt) dùng chung `.desmSheet()` (cuối khối `.sheet` trong `BrowserView.body`): sheet toàn chiều cao + thanh kéo + `.tint(Color.tabBlue)`. Xuất kho/WIP/Trả hàng trước đây là `fullScreenCover`, nay là sheet.
- Danh sách thống nhất `.insetGrouped`, nền `systemGroupedBackground` (các màn có thanh lọc phía trên danh sách). Máy quét camera vẫn `fullScreenCover`.
- Màn mới nên dùng `.desmSheet()` và `Color.tabBlue` thay vì màu hệ thống.

## Hộp thoại tự vẽ ở đáy màn hình (2026-10-28)
- `DesmDialogCard` / `DesmDialogState` / `DesmDialogAction` + `.desmDialog(...)`, `.desmAlert(isPresented:...)` (`UI/DesmDialog.swift`). Thẻ bo 30pt sát đáy (tầm ngón cái tay phải), nút cao 52pt, màu `Color.tabBlue`; chạm nền mờ = chạy nút cancel (hoặc nút duy nhất).
- Thay: hộp "Quét mã" (trước là confirmationDialog), "Không mở được địa chỉ", Kết quả (Cài đặt), lỗi tải xlsx, 3 xác nhận (Xuất kho / WIP / Trả hàng).
- Alert/confirm JS của trang và hỏi "Lưu tài khoản?" (`WebView.swift`) đi qua `BrowserModel.presentDialog` (hàng đợi `dialogQueue`, hiện ở `BrowserView`). Nếu đang có sheet/camera phủ lên (`useOverlayDialog()` = false) thì dùng `UIAlertController` như cũ để `completionHandler` luôn được gọi. Prompt có ô nhập vẫn dùng alert hệ thống.
- Chưa build Xcode.


## Tải file / API cho AI (Thêm > "Tải file / API cho AI")
- Mục đích: khi AI cần xem mã nguồn DESM (.js, .css, HTML) hoặc kết quả một API mà app chưa có, AI đưa link/địa chỉ, người dùng dán vào màn này, bấm Tải rồi chia sẻ file lại.
- Mỗi dòng một yêu cầu: `/resources/scripts/....js?rv=xxx` hoặc nguyên link https://desm... (GET); `POST /duong/dan.do KEY=VALUE&...` (POST form, có X-Requested-With). Chỉ cùng domain với trang đang mở, dùng phiên đăng nhập hiện có.
- Một dòng -> file đúng loại (.js/.json/.css/.html/.txt); nhiều dòng -> gộp một file .txt có tiêu đề `===== METHOD url =====` và `HTTP status · content-type · số ký tự`. Dòng bắt đầu bằng # bị bỏ qua. Có danh sách "đã dùng gần đây".
- Code: `BrowserModel.fetchResource`, `DesmFetched`, `DesmFetchSheet` (`Tools/DesmFetch.swift`). CHƯA kiểm chứng trên máy thật. Ô cũ "Tải địa chỉ" trong Cài đặt > Nâng cao vẫn còn.
- Dành cho AI: nếu cần file JS/API của DESM, hãy bảo người dùng mở Thêm > "Tải file / API cho AI", dán đúng dòng cần tải (ví dụ `/resources/scripts/shippingStatus/vesselFinder.js?rv=bJ5Z2O2Jp5`) và gửi file lại.

## Bản đồ tàu (Thêm > "Bản đồ tàu")
- Dữ liệu `POST /vessel/getVesselFinderList.do` (PROJECT_NO). LATITUDE/LONGITUDE/IMO hiện null nên bản đồ vẽ tuyến POL -> POD (toạ độ cảng gần đúng trong `DesmPorts.known`, cảng lạ tra CLGeocoder). Trang web gốc: `/page_crt.do?MENU_SEQ=1057` (script `/resources/scripts/shippingStatus/vesselFinder.js`, chưa đọc được). CSS đồng bộ app cho trang đó nằm cuối MobileStyles.swift.

- (2026-10-29) `DesmRoutes`: tuyến biển/sông gần đúng qua điểm mốc (Haiphong/Busan -> Hochiminh/CatLai/OM4 Jetty, tự đảo chiều); khác tuyến thì đoạn thẳng. Khi LATITUDE/LONGITUDE null và tàu đang đi, ghim cam (con tàu có hiệu ứng sóng/nhấp nhô, `DesmShipView`; cảng đến là ghim mappin, không còn cờ) = vị trí ƯỚC TÍNH theo tỉ lệ thời gian ATD->ETA. Thêm tuyến: sửa `DesmRoutes.via`. CHƯA kiểm chứng trên máy thật/chưa build.

- (2026-10-29, từ file nguồn người dùng gửi) `vesselFinder.js`: web vẽ ghim bằng LATITUDE/LONGITUDE của `getVesselFinderList.do` (cùng API; hiện null, IMO null). API này còn trả ATD/ETD/ETA/ATA dạng epoch ms (app dùng cho ước tính vị trí), PL_NO, IMO. Màu web: xanh = ATD thật, vàng = dự kiến, dòng nổi khi ETA < 7 ngày (app: nhãn \"Sắp đến\"). Tiến trình chuyến: `POST /selectDesmShippingStatusList.do` body `PROJECT_NO=&VOYAGE_NO=&INVOICE_NO=&SHIPPING_STATUS=&DATA_CREATED_YN=` -> BL_NO, SHIPPING_LINE, SHIPPING_MODE, CARGO_READY_DATE, ATD/ETD, ATA/ETA, DISCHARGING_AT_PORT, PULLING_OUT_FROM_PORT, ON_SITE (app: `fetchShipInfo`, dòng thời gian khi bấm vào chuyến). CHƯA kiểm chứng: INV_NO ở bản đồ tàu (vd OM4-DE-LS-0002-2) có khớp INVOICE_NO ở Shipping Status (vd OM4-DE-IS-0002) không; app ghép theo INVOICE_NO hoặc tên tàu.

- (2026-10-29) Bản đồ tàu mở thì tàu ước tính tự trượt dọc tuyến: sheet đếm `tick` mỗi 30 giây -> `DesmVesselMap.refreshLive` chỉ vẽ lại tuyến + dời ghim tàu (không dựng lại toàn bản đồ). CHƯA kiểm chứng trên máy thật.

- (2026-10-29) Thông báo (Thêm > \"Thông báo\", `DesmNoticeSheet`): `POST /getNotice.do jobCode=` (danh sách), `/getNoticeContents.do jobCode=<NOTICE_ID>` (CONTENTS), `/getRealTimeNotice.do` (thông báo khẩn). File đính kèm: `/getIdsmSetupDlgItemScheduleFile.do FILE_GRP_CD=` -> [{ID,NAME,EXT,FILE_SIZE}], tải `GET /getIdsmAttachDownload.do?code=<ID>` (`downloadAttachment`, lưu file tạm rồi mở ShareSheet). Chấm đỏ: `BrowserModel.unreadNotices` (nút Thêm + badge icon app qua `UNUserNotificationCenter.setBadgeCount`, xin quyền .badge), cập nhật khi vào DESM, khi app active và mỗi 5 phút; app KHÔNG chạy nền nên không tự báo khi đang đóng. CHƯA kiểm chứng trên máy thật.

- Mục \"Mã nguồn trang này\" (Thêm): quét JS/CSS của trang đang mở (`BrowserModel.listPageResources`, cả iframe cùng domain + Performance API), mặc định bỏ thư viện (.min, /ext/, jQuery...). Tải JS/CSS bằng `fetchResource`, HTML bằng `fetchHTML`, API bằng `fetchNetLog(.json)` (cần bật Ghi API trước). CHƯA kiểm chứng trên máy thật.

## Quét thông minh: Package No / Packing List No (2026-10-29)
- `PackageScanner.swift` nhận diện **2 loại số** trên tem: **Package No** (`OM4-P2-LS-0006-050`, `OM4-MG-GEN1-KOB-0009`) và **Packing List No** = *Shipment No* / *Shipping Invoice No* (`OM4-DE-IS-0016`, `OM4-P2-LS-0006`). Mỗi `PkgCandidate` có `kind` (`.package` / `.packingList`), `derived` (số suy ra từ số kia, không thấy trực tiếp), `printed` (đọc rõ, không phải sửa chữ nào).
- Vision giờ trả `OCRObs` (3 cách đọc + toạ độ). `PkgParser.textLines` ghép các dòng **cùng hàng** (nhãn "PACKAGE NO.:" + giá trị) để biết giá trị thuộc loại nào.
- Quy tắc loại: có đuôi `-NNN` → Package. Không đuôi: nhãn Shipment/Invoice/Packing List → Packing List; nhãn Package/"Số kiện" → Package; không nhãn → 2 đoạn mã (DE-IS) là Packing List, từ 3 đoạn (MG-GEN1-KOB) là Package.
- Chữ viết tay/viết tắt (mẫu `mã-loại-số-số`, bỏ `OM4`): `P2-LS-06-51` → `OM4-P2-LS-0006-051` (tự điền số 0 đủ 4 và 3 chữ số, sửa O/0, I/1, S/5, B/8, Z/2, G/6). Loại `IS` (`shipTypes`) viết tay `DE-IS-05-01` hiểu là Shipment `OM4-DE-IS-0005` + số thứ tự → Packing List là lựa chọn chính, Package suy ra là lựa chọn phụ. Viết tay luôn hiện để chạm chọn (không tự mở).
- "Hít" mã giữa về từ vựng (`baseVocab`: DE, P2, MG, MPW, GEN1, GEN2, KOB, MAR, GT1, TGO, LS, IS): đọc nhầm `GTI`→`GT1`, `TG0`→`TGO`, `6EN1`→`GEN1`. Tem **in rõ** được học thêm mã giữa/loại mới (`PkgParser.learn`, lưu `UserDefaults` khoá `desmScanVocab`, `desmScanTypes`) nên mã mới tự quen dần.
- Loại số nhiễu: dòng chứa GOI/THAU/NMND/CONSIGNEE/NOTIFY/HD/PVN/CONTRACT bị bỏ (số hợp đồng `06/2025/HĐ-PVN/OM4-06`, gói thầu `OM4-EPC-HHO-06`); mã giữa EPC/HHO... không nhận. Đuôi `-NNN` sau Packing List không nhận (tránh dính số cân nặng cùng hàng).
- `ScanState` có trí nhớ ngắn 2 giây (`seen`, đếm số lần thấy): 2 số đọc ở 2 khung khác nhau vẫn ghép được. **Thấy cả 2 loại** → `choice` (khung `ScanChoiceCard`, 2 ô lớn: Package No / Packing List No, chạm 1 ô để mở). **Chỉ 1 loại, đọc rõ**, ổn định ≥ 3 lần thấy và ≥ 1 giây → tự mở. Quét từ ảnh: `.choose` mở `ScanChoiceSheet`.
- Mở: Package → `__desmFindPkg` như cũ. Packing List → `__desmFindPackingList({pl, open})`: điền `txtPackingListNo`, xoá `txtPackageNo`, Search, đợi lưới ổn định; **đúng 1 kiện thì mở luôn** (`__desmOpenPkg`), nhiều kiện thì toast "n kiện thuộc …" để chọn, không có thì `plempty`. Gọi từ Lịch sử Packing List (không có `open`) giữ hành vi cũ.
- CHƯA kiểm chứng trên máy thật: Vision có đọc được chữ viết tay trắng trên thép mạ kẽm / chữ stencil xoay dọc hay không (xoay máy cho chữ nằm ngang); toạ độ `boundingBox` dùng để ghép hàng; ô Packing List của DESM có tìm khớp chuỗi `OM4-DE-IS-0016` hay không.
- Kiểm thử logic phân tích (bản đối chiếu Python) trên dữ liệu 10 ảnh tem: nhãn tiếng Việt, Shipping Mark Hàn/Nhật, Shipping Invoice LS-0006/0001, stencil, viết tay `DE-IS-05-01`, `P2-LS-06-51`, `GTI-TGO-0009`.

## Nhật ký thao tác ghi (2026-10-29) — Thêm > "Nhật ký thao tác ghi"
- Mọi lệnh LƯU do app gửi đều ghi vào `Application Support/desm-write-audit.json` (tối đa 500 bản ghi, chỉ trên máy): thời điểm, nhãn, địa chỉ, dữ liệu gửi, giá trị trước khi sửa (Detail Item, MRR), phản hồi, kết luận.
- Trạng thái: `sending` (đã gửi, chưa có kết quả; quá 2 phút hiển thị là "không rõ") · `ok` · `rejected` (máy chủ trả `error`) · `unknown` (đã gửi nhưng không có phản hồi JSON hợp lệ: có thể đã lưu -> kiểm tra trên web trước khi lưu lại) · `notsent`.
- Bản ghi `begin` được ghi ĐỒNG BỘ trước khi lệnh đi (kể cả khi app bị tắt ngay sau đó); `end` ghi bất đồng bộ.
- Swift: `BrowserModel.desmWrite(path, updateList:, label:)` tự ghi (Xuất kho, WIP, Trả hàng MRF). JS: `auditBegin/auditEnd` ở đầu `makeScript()`, dùng trong `diSave` (Detail Item) và `mrrPost` (tham số `au`, chỉ truyền cho lệnh lưu MRR) -> message `desmAudit` -> `WriteAuditStore.handle`.
- Lệnh ghi mới PHẢI đi qua `desmWrite` hoặc gọi `auditBegin/End`. Chưa ghi: `saveDesmLocation.do` (do chính nút của web gửi) — muốn ghi thì dùng chỗ `__desmU` ở `netRecorderSource`.
- Xuất toàn bộ ra .txt bằng nút chia sẻ trên màn hình nhật ký. Chưa build Xcode; JS đã `node --check`.

## Tách BrowserView.swift + API bằng URLSession (2026-10-29)
- `BrowserView.swift` (8.207 dòng) đã tách thành ~30 file theo thư mục (bảng §2). Nội dung giữ nguyên; chỉ đổi `private`/`fileprivate` ở mức thành viên thành internal để các extension `BrowserModel` ở file khác dùng được. File project (`project.pbxproj`) đã khai báo nhóm thư mục tương ứng — thêm file mới phải thêm vào Xcode/pbxproj.
- `desmQuery` giờ chạy bằng **URLSession**, không còn cần trang DESM đang mở: cookie lấy từ kho cookie của WebView, hoặc từ Keychain (`SessionStore.storedCookies()`) khi không có WebView. Hết phiên (HTTP 401 / bị chuyển về `login.do`) → `DesmAPIError.expired`. Lỗi khác → tự lùi về cách cũ (`desmQueryViaWebView`, fetch trong WebView). CHƯA kiểm chứng trên máy thật: máy chủ có chấp nhận request từ URLSession (header Referer/Origin đã gửi) hay không — nếu không, log sẽ thấy "phản hồi không phải JSON" rồi tự dùng đường lui.
- Async/await: `desmQueryAsync`, `desmProjectNo()`, `fetchDocsAsync`, `fetchDocDetailAsync`, `fetchActivityAsync`, `fetchVesselsAsync`, `fetchShipInfoAsync`. Các hàm callback cũ (`fetchDocs`, `fetchDocDetail`, `fetchActivity`, `fetchVessels`, `fetchShipInfo`, `desmQuery`) vẫn còn như lớp bọc mỏng nên các View không phải sửa. Còn dạng callback: `Outgoing`, `WipCompletion`, `MrfReturn`, `EditLog`, `Notices`, các hàm `callAsyncJavaScript` (PackingHistory, DesmFetch, PageSnapshot…) — chuyển dần khi động tới.
- Đã chuyển thêm sang async: `Outgoing`/`WipCompletion`/`MrfReturn` (`search`), `EditLog`, `Notices` (`fetchNoticesAsync`). Còn dạng callback: các hàm `callAsyncJavaScript` (PackingHistory, DesmFetch, PageSnapshot, `downloadAttachment`...).
- Chưa làm: unit test `PkgParser`.

## Thông báo khi app đóng (2026-10-29) — `Background/BackgroundRefresh.swift`
- `BGAppRefreshTask` (id `com.desm.mobile.refresh`, khai báo trong `Info.plist` cùng `UIBackgroundModes=fetch`; `project.pbxproj` đã trỏ `INFOPLIST_FILE`). Đăng ký ở `DESMMobileApp.init`, xin lịch khi app xuống nền (`BrowserView` onChange scenePhase) và sau mỗi lượt chạy nền; sớm nhất 30 phút/lần, iOS quyết định giờ thực tế (không đảm bảo). Cần thông báo đúng lúc → phải có backend đẩy tin.
- Mỗi lượt: `fetchNoticesAsync` (báo thông báo DESM mới, lần đầu chỉ ghi mốc `desmNotifiedNotices`) và `fetchVesselsAsync` (báo tàu `arrivingSoon`, chống báo lặp bằng `desmNotifiedVessels` = invoice|ngày ETA). Cập nhật số badge. Hết phiên → bỏ qua lặng lẽ.
- Công tắc: Cài đặt > Đăng nhập > "Thông báo khi app đóng" (`desmBgNotify`, mặc định bật); bật lên sẽ xin quyền thông báo. Cookie lấy từ Keychain nên cần bật "Ghi nhớ phiên đăng nhập" (`desmRememberLogin`).
- Thử nhanh bằng Xcode: tạm dừng app, trong lldb: `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.desm.mobile.refresh"]`. CHƯA kiểm chứng trên máy thật.

## Nút chat Dodo — trợ lý AI của web (2026-10-29) — `Scripts/DodoBubble.swift`
- Web DESM có widget **Dodo** (`/resources/scripts/util/Dodo.js`, "PMS AI 두두"): gửi `POST /dodo/chat/stream.do` (form: `user_prompt`, `menu_context`, `session_id`, `mode` fast|slow), nhận SSE (token/section/choices/error/done); lịch sử: `sessions.do`, `history.do`, `delete.do`, `reset.do`. Có đọc ngữ cảnh màn hình qua `ScreenContext.snapshot()`.
- Trong dump HTML (đã dựng) trang chỉ nạp `Dodo.js`, KHÔNG thấy lệnh `Dodo.init(...)`; vì vậy app tự gọi `Dodo.init({launcher:false,...})`, nếu trang đã có `.dodo-root` thì dùng lại.
- `makeDodoScript()` cài thành `WKUserScript` thứ 4 (chỉ khung chính, document start) và chạy lại trong `evaluateNow()`. Idempotent: `window.__desmDodo`.
- Bong bóng `#desm-dodo-btn` (ảnh gấu `/resources/img/bear-assistant.png`, kéo được, nhớ vị trí ở `localStorage['desmDodoPos']`); ẩn ở trang login và khi khung chat đang mở. CSS ép `.dodo-win` thành tấm gần toàn màn hình, theo `visualViewport` để né bàn phím; `.dodo-input` 16px chống iOS tự phóng to.
- Công tắc: Cài đặt > "Nút chat Dodo" (`desmDodoBubble`, mặc định bật).
- Va chạm đã xử lý: `viWalk` bỏ qua `.dodo-msgs` (không dịch câu trả lời AI); `NetRecorder` không `clone()` luồng `/dodo/chat/stream`.
- CHƯA kiểm chứng (chưa chạy trên máy thật): tài khoản có quyền dùng `/dodo/chat/*` hay không (401/403 → hiện thông báo), SSE qua `fetch` stream trong WKWebView, vị trí bong bóng so với thanh tab native, `ScreenContext` trong khung chính có gom được nội dung iframe không.
- Trả lời tiếng Việt: `DodoBubble.swift` bọc `fetch`, thêm "[Trả lời bằng tiếng Việt]" vào `user_prompt` gửi `/dodo/chat/stream` (khung chat vẫn hiện câu gốc; lịch sử tải từ máy chủ có thể hiện kèm dòng này). Công tắc: Cài đặt > "Dodo trả lời bằng tiếng Việt" (`desmDodoVi`, mặc định bật). Chưa kiểm chứng Dodo có tuân theo hay không.

## Trang "Thêm" chia nhóm + cuộn được (2026-10-29)
`UI/MoreSheet.swift`: `webItems` (MENU WEB DESM) và `toolItems` (CÔNG CỤ APP), vẽ bằng `group(_:_:)` trong `ScrollView`; khung mở ở 70% màn hình, kéo lên được toàn màn hình. Đã bỏ nút Quay lại / Tiến / Tải lại (vuốt mép màn hình vẫn quay lại/tiến). `model.goBack/goForward/reload` vẫn còn trong code.

## Màn hình chính = Package (2026-10-29)
`sessionDidLoad` (Session/SessionReconnect.swift): lần đầu vào `main.do` sau khi mở app hoặc sau đăng nhập lại (`pendingHomeTab`), gọi `openHomeTab` → `__desmOpenMenu('196', ...)` (tab Kiện hàng), thử lại tối đa ~12 giây vì menu trái nạp chậm. Công tắc: Cài đặt > "Mở màn Package khi vào app" (`desmOpenPackage`, mặc định bật). Nút "Về DESM" vẫn về trang chủ, không tự mở Package.

## Bộ lọc mặc định thu gọn (2026-10-29)
`addFilterBar` gọi `setCollapsed(true)` ngay khi dựng thanh lọc: mọi màn có bộ lọc mở ra ở dạng gọn (hàng tìm nhanh + nút Bộ lọc + Search). Bấm "Bộ lọc" để xổ ra; bấm Search thì thu lại như cũ.

## Khung bảng xanh lộ ra sau khi tìm (2026-10-29)
Giả thuyết (chưa tái hiện trên máy): sau Search trang dựng lại lưới TreeGrid, `cardView` vẫn bám lưới cũ trong `TGGrids` nên lưới mới không được ẩn. Sửa: `cardView` duyệt `TGGrids` từ cuối và chỉ nhận lưới còn gắn trong DOM; sau khi bấm Search gọi lại `cardView` ở 0,7s / 1,6s / 3,5s.
- Nguyên nhân khả dĩ hơn của khung bảng xanh lúc mới vào (người dùng: bấm qua lại nút Bộ lọc thì mất): `scan` bỏ qua lần quét nếu cách lần trước <400ms và không có lần quét bù, nên lưới nạp muộn không được chuyển sang thẻ cho tới khi có thay đổi DOM khác. Đã thêm quét bù (trailing) 450ms và quét lại ở 1s/2,5s/5s sau DOMContentLoaded.

## Dodo đọc dữ liệu màn hình (2026-10-29)
Dodo trả lời "không có dữ liệu bảng" dù màn Package đang có 17 kiện (`ScreenContext.snapshot()` của web không lấy được lưới trong app; nguyên nhân CHƯA xác minh — nghi: khung ẩn `desmDetailFrame` được xếp ưu tiên, hoặc lưới bị dời ra ngoài màn hình). Cách vòng: `cardView` lưu `window.__desmItems` (danh sách kiện đang hiển thị); `DodoBubble.swift` (`screenText`) nối bảng văn bản tối đa 300 kiện vào `user_prompt` gửi `/dodo/chat/stream`. Công tắc: Cài đặt > "Gửi dữ liệu kiện đang hiển thị cho Dodo" (`desmDodoData`, mặc định bật). Mới chỉ cho màn Package dạng thẻ; RSI/MRR/MRF... chưa có.


## AI riêng — thêm lựa chọn AI cho bong bóng Dodo (2026-10-29) — thư mục `AI/`
- Dodo là widget server của web DESM nên không đổi model được. Cách làm: Cài đặt > Trợ lý Dodo > "Chạm bong bóng mở" = Dodo (mặc định) hoặc AI riêng (`desmAIEngine`). Khi chọn AI riêng, JS trong `DodoBubble.swift` (`w.__desmDodoEngine === 'ai'`) gửi message `desmAI` → `WebView.swift` đặt `model.showAIChat = true` → `BrowserView` mở `AIChatView`.
- Nhà hỗ trợ: Gemini, Groq, Claude, OpenAI, DeepSeek, Mistral, OpenRouter, Tùy chỉnh (OpenAI-compatible, ví dụ Ollama/LM Studio). Dò danh sách model qua `/models` của từng nhà, lọc bỏ model không phải chat; "Tự chọn model dùng được" thử tối đa 8 model (ưu tiên model nhanh) và lấy cái chạy được đầu tiên.
- Đọc cả trang: `desmAIData` (mặc định TẮT) + `desmAILimit` (12000/40000/120000 ký tự). Bật thì `BrowserModel.fetchScreenTextForAI()` gọi `window.__desmDodo.pageText(limit)` (trong `DodoBubble.swift`): duyệt khung chính + iframe đang hiện (bỏ `desmDetailFrame` ẩn), mỗi lưới TreeGrid gắn trong DOM → tiêu đề cột + mọi dòng `Kind === 'Data'` đã tải (kể cả cột đang bị `compactGrid` ẩn, trừ `Panel`/`Select`), ô nhập/chọn đang có giá trị, rồi văn bản trang (ít nếu đã có lưới). Cắt theo giới hạn và ghi chú đã cắt. Gắn vào system prompt mỗi lượt gửi (không lưu lịch sử). Lưới phân trang chỉ có các trang đã tải. CHƯA kiểm chứng `G.Rows` lặp được như dự kiến trên web thật.
- Hội thoại giữ trong bộ nhớ (`AIChatSession.shared`), mất khi tắt app. Chưa có streaming (trả lời hiện một lần).
- CHƯA biên dịch/kiểm chứng trên máy thật (viết trên môi trường không có Xcode). Cần build thử: các API dùng đều ≥ iOS 16 (`onChange` bản 1 tham số, `TextField(axis:)`).

## AI tự tra dữ liệu DESM — function calling chỉ đọc (2026-10-29) — `AI/AIAgent.swift`, `AI/DesmAITools.swift`
- Công tắc: Cài đặt > Trợ lý Dodo > "Cho AI tự tra dữ liệu DESM (chỉ đọc)" (`desmAITools`, mặc định TẮT; chỉ hiện khi trợ lý = AI riêng). Độc lập với "Gửi kèm dữ liệu trang đang mở" (`desmAIData`).
- `AIClient.runAgent` chạy vòng tối đa 6 lượt: AI gọi công cụ → `DesmAITools.run` (@MainActor) → trả kết quả. Có bản cho 3 kiểu: OpenAI-compatible (`tool_calls`/`role:tool`), Claude (`tool_use`/`tool_result`), Gemini (`functionCall`/`functionResponse`, giữ nguyên `parts` để không mất thoughtSignature). Lượt cuối bỏ `tools` để buộc trả lời. Nhà/model báo 400/404/422 (không hỗ trợ công cụ) → lùi về hỏi đáp thường + ghi chú.
- Công cụ: `desm_list_endpoints`, `desm_query(endpoint, params_json, max_rows)`, `desm_recorded_endpoints` (đọc `NetLogStore`, cần bật Ghi API ở Nâng cao), `desm_read_open_page` (dùng `pageText`). `params_json` là CHUỖI JSON (Gemini không nhận object tự do).
- Danh mục `DesmAITools.catalog` lấy khoá tham số từ các màn native (Activity/DocSheet/EditLog/Outgoing/MrfReturn/WipCompletion/Vessel/PackingHistory/Notices): package `/getIdsmOsSummaryList.do`, hạng mục chi tiết `/getIdsmOsDetailList.do`, RSI view/outgoing, MRF summary/return, edit log, creation lists, WIP, tàu, shipping status, home summary, notice. `desm_query` cũng nhận API ngoài danh mục nếu tên khớp `^/.../(get|select|search|list|find|view|query)*.do` và không chứa từ ghi (save/delete/update/...). KHÔNG có công cụ ghi.
- Kết quả mỗi lần gọi cắt ~24.000 ký tự / tối đa 500 dòng, bỏ trường rỗng, giá trị ≤100 ký tự, và báo "ĐÃ CẮT" để AI lọc hẹp hơn.
- Chưa làm: `/getDesmMrrInfoList.do` (kết quả dạng object headerList/lineList, `desmQueryAsync` chỉ đọc mảng), file đính kèm, trang không qua API (chỉ có trong lưới trên trang → dùng `desm_read_open_page`).
- CHƯA biên dịch/kiểm chứng trên máy thật: định dạng tham số một số API (khoá để trống có được không), model free của Groq/OpenRouter có hỗ trợ công cụ không.

## Dodo đọc cả trang + vá nhỏ (2026-10-29, lượt tiếp theo)
- `DodoBubble.swift`: khi bật "Gửi dữ liệu kiện đang hiển thị cho Dodo" (`desmDodoData`) mà màn không phải Package dạng thẻ (`screenText()` rỗng) thì dùng `pageText(20000)` (mọi lưới TreeGrid đã tải + ô lọc + văn bản trang) nối vào `user_prompt` gửi `/dodo/chat/stream` — dữ liệu chỉ tới server DESM. JS đã `node --check`; CHƯA thử trên web thật (đặc biệt `G.Rows` lặp được hay không).
- `AIChatView.send()`: `Task { @MainActor in ... }` để cập nhật @State/`session.messages` đúng luồng chính.
- Vẫn CHƯA build Xcode (môi trường không có). Việc kế tiếp: build bằng GitHub Actions, gửi log lỗi để sửa.

## Dodo luôn Slow (2026-10-29)
- `Dodo.js` bản này đặt `.dodo-model{display:none}` nên người dùng không chọn được Fast/Slow. Thêm công tắc Cài đặt > "Dodo luôn dùng chế độ Slow (chính xác)" (`desmDodoSlow`, mặc định bật): wrapper `fetch` trong `DodoBubble.swift` ghi đè `mode=slow` trong form gửi `/dodo/chat/stream`. CHƯA kiểm chứng máy chủ có trả lời khác đi ở Slow hay không.
