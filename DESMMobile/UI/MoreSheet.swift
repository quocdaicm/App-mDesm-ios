// MoreSheet.swift — trang "Thêm" và nền footer.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

struct MoreSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void
    var onHistory: () -> Void = {}
    var onDoc: (DesmDocKind) -> Void = { _ in }
    var onWip: () -> Void = {}
    var onActivity: () -> Void = {}
    var onEditLog: () -> Void = {}
    var onVessel: () -> Void = {}
    var onNotice: () -> Void = {}
    var onFetch: () -> Void = {}
    var onSource: () -> Void = {}
    var onAudit: () -> Void = {}

    struct Item: Identifiable {
        let id = UUID(); let symbol: String; let title: String; var enabled = true; let action: () -> Void
    }
    /// Nhóm 1: các mục của web DESM (mở màn hình / dữ liệu DESM)
    var webItems: [Item] {
        [
            Item(symbol: "line.3.horizontal", title: "Menu đầy đủ") {
                model.webView?.evaluateJavaScript("window.__desmToggleDrawer && window.__desmToggleDrawer();", completionHandler: nil)
            },
            Item(symbol: "house.fill", title: "Về DESM") { model.home() },
            Item(symbol: "clock.arrow.circlepath", title: "Lịch sử Packing List", enabled: model.inDesm) { onHistory() },
            Item(symbol: "doc.text.magnifyingglass", title: "RSI chưa đóng / vừa đóng", enabled: model.inDesm) { onDoc(.rsi) },
            Item(symbol: "chart.bar.xaxis", title: "RSI Summary", enabled: model.inDesm) { model.openDesmTab(.report) },
            Item(symbol: "chart.bar.doc.horizontal", title: "MRF Summary", enabled: model.inDesm) {
                model.openDesmMenu(id: "1696", title: "MRF Summary", pattern: "^(MRF ?Summary|Tổng hợp ?MRF)$")
            },
            Item(symbol: "arrow.uturn.backward.circle", title: "MRF trả hàng", enabled: model.inDesm) { onDoc(.mrf) },
            Item(symbol: "hammer", title: "WIP Completion", enabled: model.inDesm) { onWip() },
            Item(symbol: "bell.badge", title: "Hoạt động", enabled: model.inDesm) { onActivity() },
            Item(symbol: "clock.arrow.2.circlepath", title: "Tra Edit Log", enabled: model.inDesm) { onEditLog() },
            Item(symbol: "megaphone.fill", title: "Thông báo", enabled: model.inDesm) { onNotice() },
            Item(symbol: "ferry.fill", title: "Bản đồ tàu", enabled: model.inDesm) { onVessel() },
        ]
    }

    /// Nhóm 2: công cụ của app (giao diện, nhật ký, xuất dữ liệu, cài đặt)
    var toolItems: [Item] {
        [
            Item(symbol: "camera.viewfinder", title: "Chụp trang") { model.captureFullPage() },
            Item(symbol: model.layoutMode.symbol, title: model.layoutMode.shortTitle) { model.cycleMode() },
            Item(symbol: "rectangle.topthird.inset.filled", title: model.barsHidden ? "Hiện thanh địa chỉ" : "Ẩn thanh địa chỉ") {
                withAnimation(.easeInOut(duration: 0.2)) { model.barsHidden.toggle() }
            },
            Item(symbol: "list.clipboard", title: "Nhật ký thao tác ghi") { onAudit() },
            Item(symbol: "chevron.left.forwardslash.chevron.right", title: "Mã nguồn trang này", enabled: model.inDesm) { onSource() },
            Item(symbol: "square.and.arrow.down.on.square", title: "Tải file / API cho AI", enabled: model.inDesm) { onFetch() },
            Item(symbol: "slider.horizontal.3", title: "Cài đặt") { model.showSettings = true },
        ]
    }

    func group(_ title: String, _ list: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(list) { it in
                    Button {
                        onClose()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { it.action() }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: it.symbol).font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.tabBlue)
                            Text(it.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, minHeight: 82)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.tabBlue.opacity(0.08)))
                        .opacity(it.enabled ? 1 : 0.4)
                    }
                    .buttonStyle(.plain).disabled(!it.enabled)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 38, height: 5).padding(.top, 8)
            Text("Thêm").font(.system(size: 18, weight: .bold))
            ScrollView {
                VStack(spacing: 18) {
                    group("MENU WEB DESM", webItems)
                    group("CÔNG CỤ APP", toolItems)
                }
                .padding(.bottom, 24)
            }
        }
    }
}

/// Footer vẽ bằng Canvas theo Branding/footer-bg.svg: gradient xanh, chấm mờ, hai lớp sóng, đường nhấn vàng-xanh ở mép trên.
struct FooterBackground: View {
    let c1 = Color(red: 23 / 255, green: 37 / 255, blue: 84 / 255)
    let c2 = Color(red: 29 / 255, green: 78 / 255, blue: 216 / 255)
    let c3 = Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255)

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.97, blue: 1.0)
            TabWave().fill(LinearGradient(colors: [Color.tabBlueLight.opacity(0.45), Color.tabBlueLight.opacity(0.12)],
                                          startPoint: .top, endPoint: .bottom))
        }
    }
}
