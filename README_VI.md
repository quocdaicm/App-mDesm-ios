# DESM Mobile V2 — iOS

## Tính năng
- Thanh địa chỉ nhập URL bất kỳ có giao thức HTTP/HTTPS (tự thêm HTTPS nếu thiếu).
- Mở trang trong WKWebView; dùng kho cookie mặc định của WKWebView để duy trì phiên trong app.
- CSS mobile được tiêm bằng WKUserScript ở document start (cả iframe), tự áp lại nếu trang xóa style/class; mặc định chỉ áp cho domain doosanenerbility.com (có công tắc).
- 3 chế độ hiển thị (nút trên thanh đầu): Mobile (CSS sắp xếp lại bố cục, bảng biểu mẫu xếp dọc), Vừa màn hình (bản desktop thu nhỏ, chỉnh độ rộng trong Cài đặt), Gốc (không can thiệp).
- Cài đặt > "Mã HTML của trang": sao chép HTML trang đang mở hoặc lưu thành file .html (chia sẻ/Lưu vào Tệp), gồm iframe cùng domain; có tùy chọn ẩn giá trị ô nhập và bỏ script nội tuyến.
- Chế độ Mobile có xử lý riêng cho DESM (SB Admin 2): menu trái thành ngăn kéo mở bằng nút ≡ (tự đóng khi chọn mục), thanh tab cuộn ngang, form tìm kiếm dựng lại thành lưới 2 cột (nhãn trên - ô nhập dưới), nút Search/Reset xếp ngang, thanh nút chức năng tự xuống dòng, ẩn footer. Rời chế độ Mobile thì khung form được tải lại để về bố cục gốc.
- Màn hình có form tìm kiếm: thanh "Bộ lọc" (đếm số điều kiện đang dùng) + Search/Reset luôn hiện ở đầu; bấm Search thì bộ lọc tự thu gọn để thấy bảng kết quả, bấm lại để mở. Thanh nút chức năng (Save, Material Confirm...) thành một hàng cuộn ngang.
- Lưới Package hiển thị dạng thẻ (Package No, mô tả, loại kiện, A/O, Location); chạm thẻ để chọn dòng, nút "Dạng: Thẻ/Bảng" trên thanh nút để đổi qua lại.
- Nút "Chạm: Chọn / Chạm: Chi tiết" trên thanh nút (cạnh "Dạng: Thẻ"): ở chế độ Chi tiết, chạm thẻ mở màn hình "Package" (thông tin kiện, kích thước/trọng lượng, Short/Over/DMG/Missing, nút Location Update); chạm vùng ô tích bên trái thẻ vẫn là chọn dòng. Lựa chọn được nhớ trên thiết bị. Danh sách Detail Item tự nạp theo mã kiện: app mở ngầm trang "Hạng mục chi tiết" (MENU_SEQ=197) trong một khung ẩn, điền Số kiện hàng, bấm Search rồi đọc lưới (kết quả được nhớ trong phiên); lần đầu mất vài giây. Chạm thẻ hạng mục để tích chọn một hoặc nhiều hạng mục (có "Chọn tất cả"); khi có hạng mục được tích, nút ở đáy thành "Location Update (n hạng mục)" để đổi vị trí hàng loạt, không tích thì vẫn cập nhật vị trí cả kiện. Chạm vào biểu tượng ghim của một hạng mục để cập nhật riêng hạng mục đó: app chọn đúng hạng mục, bấm Location Update của trang "Hạng mục chi tiết" và đưa khung trang lên toàn màn hình để thao tác hộp thoại; bấm "‹ Xong" để quay lại, danh sách tự nạp lại.
- Quét Package No bằng camera (file `PackageScanner.swift`): khi đang ở DESM có nút camera tròn ở góc dưới bên trái. Camera đọc chữ (Vision, chữ in và chữ viết tay), nhận dạng `OM4-xx-xx-0000-000`, tự sửa nhầm O/0, I/1, S/5, hiểu cả dạng viết tắt như `DE-LS-01-07` (tự bù `OM4-` và số 0). Chữ in đủ đoạn tự nhận sau 2 lần đọc trùng; chữ viết tay hiện thành thanh để chạm chọn. Sau đó app điền ô Số kiện hàng, Search, đợi lưới có đúng dòng khớp rồi mở chi tiết kiện (công tắc ở Cài đặt > Quét Package No; tắt thì chỉ tìm và chọn dòng). Không có dòng khớp chính xác thì báo không tìm thấy; nhiều dòng khớp thì báo để tự chọn. Cần mở màn hình Package trước. Camera cần quyền (Info.plist đã có mô tả).
- Quét QR nhãn hạng mục: camera cũng đọc mã QR dạng `DETAIL!!!<mã>!!!<tên Packing List>!!!<Material Code>`. Quét được thì app tra Material Code ở trang "Hạng mục chi tiết" (khung ẩn), lấy Package No rồi mở kiện chứa hạng mục (đang ở màn hình khác thì app tự mở tab Kiện hàng). Nhiều dòng trùng mã thì lọc thêm theo tên Packing List. Bấm nút camera tròn sẽ hiện 2 lựa chọn: "Quét bằng camera" hoặc "Chọn ảnh có sẵn" (ví dụ ảnh chụp màn hình nhãn QR; ảnh không có QR thì đọc chữ Package No). QR loại khác hiện nguyên chuỗi, chạm để sao chép (để gửi lại cho tác giả bổ sung).
- Danh sách dạng thẻ cho các màn hình RSI / MRR / MRF / MPR (tự nhận khi lưới có cột hoặc tiêu đề chứa các từ này): mỗi dòng một thẻ gồm số phiếu, nhãn trạng thái màu (xanh = hoàn tất/duyệt, vàng = đang chờ, đỏ = từ chối/huỷ), vài trường chính và các ngày; chạm thẻ để mở rộng xem đủ mọi cột, chạm vùng ô tích bên trái để chọn dòng (các nút gốc của trang như Confirm/Delete vẫn dùng dòng đã chọn). Có ô lọc nhanh, ô chọn tất cả và nút "Dạng: Thẻ/Bảng" để đổi qua lại (nhớ trên thiết bị). Phần này chưa thử trên trang thật; nếu có màn hình hiển thị chưa đúng, dùng Cài đặt > "Sao chép cấu trúc trang đang mở" để gửi lại và tinh chỉnh.
- Thu gọn thanh trên để có thêm chỗ hiển thị trang.
- Vào được trang DESM (đã qua đăng nhập) thì thanh địa chỉ phía trên và thanh nút phía dưới tự ẩn; còn một nút tròn nổi ở góc dưới bên phải để ẩn/hiện lại cả hai (kéo nút để dời vị trí). Rời DESM thì thanh tự hiện lại.
- Cài đặt > "Sao chép cấu trúc trang đang mở": sao chép sơ đồ DOM (không gồm dữ liệu nhập) để tinh chỉnh CSS chính xác.
- Cài đặt CSS bổ sung, được lưu cục bộ trên thiết bị bằng `@AppStorage`.
- Quay lại/tiến/tải lại/về DESM/mở URL hiện tại bằng Safari.
- Tiếng Việt: ô Language của DESM có thêm mục "Tiếng Việt" (máy chủ chỉ có English/한국어/Russian nên app tự dịch phía máy khách). Chọn mục này hoặc bật Cài đặt > Ngôn ngữ > "Giao diện DESM bằng tiếng Việt" thì menu, nút, nhãn bộ lọc, tiêu đề cột, hộp thoại và alert/confirm của trang được dịch theo từ điển `Translations.swift` (khớp nguyên chuỗi; dữ liệu như mã kiện, mô tả hàng, vị trí giữ nguyên). Thiếu từ nào: Cài đặt > Ngôn ngữ > "Sao chép chuỗi chưa dịch", điền bản dịch sau dấu `=` rồi dán vào ô "Từ điển bổ sung" (mỗi dòng `English = Tiếng Việt`). Nên để ngôn ngữ gốc của trang là English.
- Header kiểu SVG (chế độ Mobile): nền gradient xanh có sóng/chấm/đường nhấn vàng, nút ≡ kính mờ, ô Language dạng viên thuốc có icon quả địa cầu + mũi tên, thẻ tab có icon kiện hàng và nút đóng tròn. Toàn bộ icon/nền là SVG nhúng trong CSS (cuối `MobileStyles.swift`); bản gốc nền ở `Branding/header-bg.svg`.
- Footer: thanh dưới cùng của app (và dải vùng an toàn dưới cùng khi thanh nút ẩn) được vẽ bằng Canvas theo `Branding/footer-bg.svg` (`FooterBackground` trong `BrowserView.swift`): gradient xanh, chấm mờ, hai lớp sóng, đường nhấn vàng ở mép trên; icon và chữ nút điều hướng màu trắng.
- Không lưu mật khẩu, không gửi dữ liệu đến dịch vụ ngoài.

## Tạo project và build bằng Xcode
1. Cần máy Mac và Xcode. Tạo **iOS > App**, Product Name `DESMMobile`, Interface `SwiftUI`, Language `Swift`, Deployment Target iOS 16+.
2. Xóa `ContentView.swift` mẫu khỏi target.
3. Thêm toàn bộ file `.swift` (gồm `Translations.swift`) trong thư mục `DESMMobile` vào project và bật target membership.
4. Đảm bảo chỉ có một file chứa `@main` (`DESMMobileApp.swift`).
5. Trong Signing & Capabilities chọn Team của bạn; đổi Bundle Identifier nếu cần.
6. Chọn iPhone làm Run Destination rồi nhấn Run.

## Logo
Icon đã được gắn sẵn vào project (DESMMobile/Assets.xcassets, AppIcon + AppLogo dùng ở thanh đầu app). Thư mục `Branding/` còn lưu bản gốc: `logo.svg` (vector) và `AppIcon-1024.png` (1024x1024, không trong suốt). Trong Xcode: tạo Assets.xcassets (nếu chưa có) > AppIcon > kéo `AppIcon-1024.png` vào ô 1024pt, Xcode tự cắt các cỡ còn lại.

## Lưu ý
- Mã nguồn được tạo nhưng chưa được build bằng Xcode hoặc thử với tài khoản/SSO thật của DESM.
- CSS tổng quát có thể không sửa hoàn hảo mọi biểu mẫu hoặc thành phần dựng bằng iframe/canvas; cần tinh chỉnh theo DOM thực tế.
- Đăng nhập phụ thuộc chính sách website, SSO, VPN, chứng chỉ hoặc quản trị thiết bị của doanh nghiệp. Không dùng ứng dụng để vượt qua kiểm soát truy cập.
- Kiểm thử thao tác nghiệp vụ ở môi trường an toàn trước khi sử dụng thực tế.
