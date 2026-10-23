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
- Thu gọn thanh trên để có thêm chỗ hiển thị trang.
- Vào được trang DESM (đã qua đăng nhập) thì thanh địa chỉ phía trên và thanh nút phía dưới tự ẩn; còn một nút tròn nổi ở góc dưới bên phải để ẩn/hiện lại cả hai (kéo nút để dời vị trí). Rời DESM thì thanh tự hiện lại.
- Cài đặt > "Sao chép cấu trúc trang đang mở": sao chép sơ đồ DOM (không gồm dữ liệu nhập) để tinh chỉnh CSS chính xác.
- Cài đặt CSS bổ sung, được lưu cục bộ trên thiết bị bằng `@AppStorage`.
- Quay lại/tiến/tải lại/về DESM/mở URL hiện tại bằng Safari.
- Tiếng Việt: ô Language của DESM có thêm mục "Tiếng Việt" (máy chủ chỉ có English/한국어/Russian nên app tự dịch phía máy khách). Chọn mục này hoặc bật Cài đặt > Ngôn ngữ > "Giao diện DESM bằng tiếng Việt" thì menu, nút, nhãn bộ lọc, tiêu đề cột, hộp thoại và alert/confirm của trang được dịch theo từ điển `Translations.swift` (khớp nguyên chuỗi; dữ liệu như mã kiện, mô tả hàng, vị trí giữ nguyên). Thiếu từ nào: Cài đặt > Ngôn ngữ > "Sao chép chuỗi chưa dịch", điền bản dịch sau dấu `=` rồi dán vào ô "Từ điển bổ sung" (mỗi dòng `English = Tiếng Việt`). Nên để ngôn ngữ gốc của trang là English.
- Header kiểu SVG (chế độ Mobile): nền gradient xanh có sóng/chấm/đường nhấn vàng, nút ≡ kính mờ, ô Language dạng viên thuốc có icon quả địa cầu + mũi tên, thẻ tab có icon kiện hàng và nút đóng tròn. Toàn bộ icon/nền là SVG nhúng trong CSS (cuối `MobileStyles.swift`); bản gốc nền ở `Branding/header-bg.svg`.
- Cuối trang: cuối danh sách thẻ Package có dải sóng SVG mỏng (cao 40px, đường nhấn vàng), bản gốc `Branding/footer-bg.svg`; nút nổi ẩn/hiện thanh và thanh dưới cùng của app đổi sang gradient xanh cùng tông header.
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
