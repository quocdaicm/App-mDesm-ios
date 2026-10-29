// DesmDialog.swift — hộp thoại tự vẽ thay alert/confirmationDialog hệ thống.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Hộp thoại tự vẽ (thay alert/confirmationDialog hệ thống)
//
// Thẻ bo tròn lớn nằm sát ĐÁY màn hình (tầm ngón cái tay phải), nút cao 52pt chiếm hết chiều ngang, màu theo app.
// `DesmDialogAction.kind`: primary = nút xanh đặc, normal = xanh nhạt, destructive = đỏ nhạt, cancel = xám.
// Chạm nền mờ: chạy nút cancel nếu có; chỉ có một nút thì chạy nút đó; còn lại thì không làm gì.

struct DesmDialogAction: Identifiable {
    enum Kind { case primary, normal, destructive, cancel }
    let id = UUID()
    let title: String
    var kind: Kind = .normal
    var handler: () -> Void = {}
}

struct DesmDialogState: Identifiable {
    let id: String
    var icon: String? = nil
    var title: String
    var message: String? = nil
    var actions: [DesmDialogAction]
    init(id: String = UUID().uuidString, icon: String? = nil, title: String, message: String? = nil, actions: [DesmDialogAction]) {
        self.id = id; self.icon = icon; self.title = title; self.message = message; self.actions = actions
    }
}

struct DesmDialogCard: View {
    let state: DesmDialogState
    let finish: () -> Void

    func fg(_ k: DesmDialogAction.Kind) -> Color {
        switch k { case .primary: return .white; case .normal: return Color.tabBlue; case .destructive: return .red; case .cancel: return .primary }
    }
    func bg(_ k: DesmDialogAction.Kind) -> Color {
        switch k {
        case .primary: return Color.tabBlue
        case .normal: return Color.tabBlue.opacity(0.12)
        case .destructive: return Color.red.opacity(0.12)
        case .cancel: return Color(.secondarySystemFill)
        }
    }
    func run(_ a: DesmDialogAction) { finish(); a.handler() }
    func backdropTap() {
        if let c = state.actions.first(where: { $0.kind == .cancel }) { run(c) }
        else if state.actions.count == 1, let a = state.actions.first { run(a) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.38).ignoresSafeArea().onTapGesture { backdropTap() }
            VStack(spacing: 12) {
                if let icon = state.icon {
                    Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.tabBlue)
                        .frame(width: 52, height: 52).background(Color.tabBlue.opacity(0.12), in: Circle())
                }
                Text(state.title).font(.system(size: 19, weight: .bold)).multilineTextAlignment(.center)
                if let m = state.message, !m.isEmpty {
                    Text(m).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .lineLimit(12).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    ForEach(state.actions) { a in
                        Button { run(a) } label: {
                            Text(a.title).font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(fg(a.kind))
                                .background(bg(a.kind), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 22, y: 6)
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

extension View {
    /// Hiện hộp thoại đang có trong `state` (nil = ẩn); `finish` gọi khi đóng.
    func desmDialog(_ state: DesmDialogState?, finish: @escaping () -> Void) -> some View {
        overlay { if let s = state { DesmDialogCard(state: s, finish: finish) } }
            .animation(.easeOut(duration: 0.22), value: state?.id)
    }
    /// Thay `.alert(...)`: hiện khi `isPresented` = true, đóng thì đặt lại false rồi chạy hành động đã chọn.
    func desmAlert(isPresented: Binding<Bool>, icon: String? = nil, title: String, message: String? = nil, actions: [DesmDialogAction]) -> some View {
        desmDialog(isPresented.wrappedValue ? DesmDialogState(id: title, icon: icon, title: title, message: message, actions: actions) : nil,
                   finish: { isPresented.wrappedValue = false })
    }
}

/// Kiểu chung cho mọi màn hình native mở từ "Thêm": sheet toàn chiều cao, thanh kéo, màu nhấn xanh của app.
struct DesmSheetStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Color.tabBlue)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}
extension View {
    func desmSheet() -> some View { modifier(DesmSheetStyle()) }
}

/// Mục "Thêm": các nút điều hướng/công cụ cũ của thanh dưới + mở menu đầy đủ, Cài đặt.
