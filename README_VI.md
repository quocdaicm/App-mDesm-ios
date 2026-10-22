# DESM Mobile V2 — iOS

## Tính năng
- Thanh địa chỉ nhập URL bất kỳ có giao thức HTTP/HTTPS (tự thêm HTTPS nếu thiếu).
- Mở trang trong WKWebView; dùng kho cookie mặc định của WKWebView để duy trì phiên trong app.
- CSS mobile được tiêm bằng WKUserScript ở document start (cả iframe), tự áp lại nếu trang xóa style/class; mặc định chỉ áp cho domain doosanenerbility.com (có công tắc).
- Bật/tắt chế độ CSS mobile.
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
