// ShareSheet.swift — chia sẻ file/văn bản qua share sheet.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Cài đặt: chế độ hiển thị, CSS/từ điển bổ sung, đăng nhập, quét, và nhóm công cụ tinh chỉnh
/// (cấu trúc trang, HTML/script, nhật ký API, tải nội dung địa chỉ). Xem DEV_NOTES.md §7.
