# DESM Mobile V2 — iOS

## Tính năng
- Thanh địa chỉ nhập URL bất kỳ có giao thức HTTP/HTTPS (tự thêm HTTPS nếu thiếu).
- Mở trang trong WKWebView; dùng kho cookie mặc định của WKWebView để duy trì phiên trong app.
- CSS mobile được tiêm bằng WKUserScript ở document start (cả iframe), tự áp lại nếu trang xóa style/class; mặc định chỉ áp cho domain doosanenerbility.com (có công tắc).
- 3 chế độ hiển thị (nút trên thanh đầu): Mobile (CSS sắp xếp lại bố cục, bảng biểu mẫu xếp dọc), Vừa màn hình (bản desktop thu nhỏ, chỉnh độ rộng trong Cài đặt), Gốc (không can thiệp).
- Cài đặt > "Mã HTML của trang": sao chép HTML trang đang mở hoặc lưu thành file .html (chia sẻ/Lưu vào Tệp), gồm iframe cùng domain; có tùy chọn ẩn giá trị ô nhập và bỏ script nội tuyến.
- Chế độ Mobile có xử lý riêng cho DESM (SB Admin 2): menu trái thành ngăn kéo mở bằng nút ≡ (tự đóng khi chọn mục), thanh tab cuộn ngang, form tìm kiếm dựng lại thành lưới 2 cột (nhãn trên - ô nhập dưới), nút Search/Reset xếp ngang, thanh nút chức năng tự xuống dòng, ẩn footer. Rời chế độ Mobile thì khung form được tải lại để về bố cục gốc.
- Màn hình có form tìm kiếm: thanh "Bộ lọc" (đếm số điều kiện đang dùng) + Search/Reset luôn hiện ở đầu; bấm Search thì bộ lọc tự thu gọn để thấy bảng kết quả, bấm lại để mở. Thanh nút chức năng (Save, Material Confirm...) thành một hàng cuộn ngang.
- Thu gọn thanh trên để có thêm chỗ hiển thị trang.
- Cài đặt > "Sao chép cấu trúc trang đang mở": sao chép sơ đồ DOM (không gồm dữ liệu nhập) để tinh chỉnh CSS chính xác.
- Cài đặt CSS bổ sung, được lưu cục bộ trên thiết bị bằng `@AppStorage`.
- Quay lại/tiến/tải lại/về DESM/mở URL hiện tại bằng Safari.
- Không lưu mật khẩu, không gửi dữ liệu đến dịch vụ ngoài.

## Tạo project và build bằng Xcode
1. Cần máy Mac và Xcode. Tạo **iOS > App**, Product Name `DESMMobile`, Interface `SwiftUI`, Language `Swift`, Deployment Target iOS 16+.
2. Xóa `ContentView.swift` mẫu khỏi target.
3. Thêm toàn bộ file `.swift` trong thư mục `DESMMobile` vào project và bật target membership.
4. Đảm bảo chỉ có một file chứa `@main` (`DESMMobileApp.swift`).
5. Trong Signing & Capabilities chọn Team của bạn; đổi Bundle Identifier nếu cần.
6. Chọn iPhone làm Run Destination rồi nhấn Run.

## Lưu ý
- Mã nguồn được tạo nhưng chưa được build bằng Xcode hoặc thử với tài khoản/SSO thật của DESM.
- CSS tổng quát có thể không sửa hoàn hảo mọi biểu mẫu hoặc thành phần dựng bằng iframe/canvas; cần tinh chỉnh theo DOM thực tế.
- Đăng nhập phụ thuộc chính sách website, SSO, VPN, chứng chỉ hoặc quản trị thiết bị của doanh nghiệp. Không dùng ứng dụng để vượt qua kiểm soát truy cập.
- Kiểm thử thao tác nghiệp vụ ở môi trường an toàn trước khi sử dụng thực tế.
