// LayoutMode.swift — chế độ hiển thị (mobile / vừa khung / tắt).

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

enum LayoutMode: String, CaseIterable, Identifiable {
    case mobile, fit, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mobile: return "Mobile (sắp xếp lại)"
        case .fit: return "Thu nhỏ vừa màn hình"
        case .off: return "Giao diện gốc"
        }
    }
    var shortTitle: String {
        switch self {
        case .mobile: return "Mobile"
        case .fit: return "Vừa màn hình"
        case .off: return "Gốc"
        }
    }
    var symbol: String {
        switch self {
        case .mobile: return "iphone.gen3"
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .off: return "desktopcomputer"
        }
    }
    var next: LayoutMode {
        switch self {
        case .mobile: return .fit
        case .fit: return .off
        case .off: return .mobile
        }
    }
}
