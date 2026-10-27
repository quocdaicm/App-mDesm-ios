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
