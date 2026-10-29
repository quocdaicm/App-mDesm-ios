// DesmTabBar.swift — thanh 5 tab ở chân màn hình.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Footer 5 tab (mẫu mới)

/// 5 tab của footer. Muốn đổi mục menu DESM mà tab mở: sửa `menuId` (id thẻ <a> trong menu trái) hoặc `pattern` (regex tên mục, Anh|Việt).
enum DesmTab: CaseIterable, Identifiable {
    case package, inbound, outbound, report, more
    var id: Self { self }
    var title: String {
        switch self {
        case .package: return "Kiện hàng"
        case .inbound: return "Trả hàng"
        case .outbound: return "Xuất kho"
        case .report: return "Báo cáo"
        case .more: return "Thêm"
        }
    }
    var symbol: String {
        switch self {
        case .package: return "shippingbox"
        case .inbound: return "arrow.uturn.backward.circle"
        case .outbound: return "square.and.arrow.up"
        case .report: return "chart.bar.xaxis"
        case .more: return "square.grid.2x2"
        }
    }
    /// id thẻ <a> trong menu (đã biết: 196 = Kiện hàng). nil = tìm theo tên.
    var menuId: String? {
        switch self {
        case .package: return "196"   // Package
        case .inbound: return "816"   // Material Receiving (dự phòng; tab này mở màn Trả hàng native)
        case .outbound: return "376"  // Outgoing Control (dự phòng; tab này mở màn xuất kho native)
        case .report: return "436"    // RSI Summary (xác nhận từ dump DESM 2026-10-29)
        case .more: return nil
        }
    }
    /// Tên mục menu (không phân biệt hoa thường, cả tiếng Anh và tiếng Việt).
    var pattern: String {
        switch self {
        case .package: return "^(Package|Kiện hàng)$"
        case .inbound: return "^(Material Receiving|Nhận vật tư)$"
        case .outbound: return "^(Outgoing Control|Kiểm soát xuất kho)$"
        case .report: return "^(RSI Summary|Tổng hợp RSI)$"
        case .more: return ""
        }
    }
}

extension Color {
    static let tabBlue = Color(red: 47 / 255, green: 125 / 255, blue: 224 / 255)
    static let tabBlueLight = Color(red: 150 / 255, green: 200 / 255, blue: 248 / 255)
    static let tabInk = Color(red: 112 / 255, green: 133 / 255, blue: 160 / 255)
}

/// Sóng xanh nhạt phía sau thanh tab (như mẫu).
struct TabWave: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.height * 0.42))
        p.addCurve(to: CGPoint(x: r.width * 0.55, y: r.height * 0.30),
                   control1: CGPoint(x: r.width * 0.18, y: r.height * 0.10),
                   control2: CGPoint(x: r.width * 0.35, y: r.height * 0.55))
        p.addCurve(to: CGPoint(x: r.width, y: r.height * 0.22),
                   control1: CGPoint(x: r.width * 0.75, y: r.height * 0.05),
                   control2: CGPoint(x: r.width * 0.90, y: r.height * 0.40))
        p.addLine(to: CGPoint(x: r.width, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height)); p.closeSubpath()
        return p
    }
}

struct DesmTabBar: View {
    @Binding var selected: DesmTab
    var onScan: () -> Void
    var moreBadge = 0
    var onSelect: (DesmTab) -> Void

    /// Nút camera cố định ở giữa thanh: Kiện hàng, Nhập kho, [camera], Xuất kho, Thêm
    var scanItem: some View {
        Button(action: onScan) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(LinearGradient(colors: [Color(red: 0.20, green: 0.58, blue: 0.95),
                                                                  Color(red: 0.30, green: 0.72, blue: 0.98)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 2))
                .shadow(color: Color(red: 0.15, green: 0.40, blue: 0.80).opacity(0.35), radius: 6, y: 3)
                .offset(y: -8)
        }
        .buttonStyle(.plain)
        .frame(width: 64)
        .accessibilityLabel("Quét số kiện hàng bằng camera")
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DesmTab.allCases.filter { $0 != .report }) { tab in
                if tab == .outbound { scanItem }
                let on = tab == selected
                Button { onSelect(tab) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: on ? .semibold : .regular))
                            .overlay(alignment: .topTrailing) {
                                if tab == .more && moreBadge > 0 {
                                    Text(moreBadge > 9 ? "9+" : "\(moreBadge)")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                                        .background(Color.red, in: Capsule())
                                        .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                                        .offset(x: 10, y: -7)
                                }
                            }
                        Text(tab.title)
                            .font(.system(size: 11, weight: on ? .bold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? Color.tabBlue : Color.tabInk)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(on ? Color.tabBlue.opacity(0.09) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white)
                .shadow(color: Color(red: 0.09, green: 0.25, blue: 0.55).opacity(0.16), radius: 12, y: -2)
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.9), lineWidth: 1))
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
        .background(
            ZStack {
                Color(red: 0.95, green: 0.97, blue: 1.0)
                TabWave().fill(LinearGradient(colors: [Color.tabBlueLight.opacity(0.45), Color.tabBlueLight.opacity(0.12)],
                                              startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }
}
