// LaunchSplash.swift — màn hình mở app (chỉ khi mở app lần đầu, không hiện khi quay lại từ nền).
// Che toàn bộ chuỗi tải lộn xộn của DESM (trang trắng, Notice, popup Log "Last Login", "Loading style...")
// và mờ dần khi màn Package đã dựng xong (trang gửi tín hiệu `desmReady`), hoặc khi vào trang đăng nhập, hoặc quá thời gian chờ.

import SwiftUI
import UIKit

struct LaunchSplashView: View {
    @ObservedObject var model: BrowserModel
    var onFinish: () -> Void

    @State private var appear = false
    @State private var progress: CGFloat = 0.04
    @State private var phrase = 0
    @State private var leaving = false
    private let t0 = Date()

    private let c1 = Color(red: 23 / 255, green: 37 / 255, blue: 84 / 255)
    private let c2 = Color(red: 29 / 255, green: 78 / 255, blue: 216 / 255)
    private let c3 = Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255)
    private let phrases = ["Đang kết nối DESM…", "Đang tải dữ liệu kiện hàng…", "Sắp xong rồi…"]

    /// Bóng mờ trôi chậm ở nền: (x, y, đường kính, tốc độ, pha) theo tỉ lệ màn hình
    private let bokeh: [(CGFloat, CGFloat, CGFloat, Double, Double)] = [
        (0.15, 0.18, 150, 0.30, 0.0), (0.85, 0.12, 110, 0.42, 1.3), (0.70, 0.45, 210, 0.22, 2.1),
        (0.10, 0.62, 130, 0.36, 3.4), (0.88, 0.80, 160, 0.28, 4.2), (0.40, 0.88, 100, 0.46, 5.0),
        (0.30, 0.38, 70, 0.52, 0.7),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [c1, c2, c3], startPoint: .topLeading, endPoint: .bottomTrailing)
                bokehLayer(geo.size)
                RadialGradient(colors: [Color.white.opacity(0.16), .clear], center: .center, startRadius: 10, endRadius: geo.size.width * 0.8)
                    .blendMode(.plusLighter)
                content
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .scaleEffect(leaving ? 1.08 : 1)
        .opacity(leaving ? 0 : 1)
        .task { await run() }
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.72)) { appear = true } }
        .accessibilityHidden(true)
    }

    // MARK: Nền

    func bokehLayer(_ size: CGSize) -> some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<bokeh.count, id: \.self) { i in
                    let b = bokeh[i]
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .frame(width: b.2, height: b.2)
                        .position(x: size.width * b.0 + CGFloat(sin(t * b.3 + b.4)) * 22,
                                  y: size.height * b.1 + CGFloat(cos(t * b.3 * 0.8 + b.4)) * 26)
                        .blur(radius: 0.5)
                }
            }
        }
    }

    // MARK: Nội dung giữa màn hình

    var content: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                pulseRings
                spinningArc
                Image("AppLogo")
                    .resizable().scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                    .shadow(color: Color.black.opacity(0.35), radius: 18, y: 10)
                    .shadow(color: c3.opacity(0.6), radius: 30)
                    .scaleEffect(appear ? 1 : 0.4)
                    .opacity(appear ? 1 : 0)
            }
            .frame(width: 220, height: 220)

            Text("DESM Mobile")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .tracking(1)
                .padding(.top, 18)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 14)
                .animation(.easeOut(duration: 0.7).delay(0.25), value: appear)
            Text("Doosan Enerbility")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .tracking(2)
                .padding(.top, 4)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.7).delay(0.4), value: appear)
            Spacer()
            VStack(spacing: 12) {
                progressBar
                Text(phrases[min(phrase, phrases.count - 1)])
                    .id(phrase)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .transition(.opacity)
            }
            .padding(.bottom, 64)
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.5), value: appear)
        }
    }

    /// Hai vòng sóng toả ra từ logo, lệch pha nhau
    var pulseRings: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let p = (t / 2.4 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Color.white.opacity(0.5 * (1 - p)), lineWidth: 2)
                        .frame(width: 112 + CGFloat(p) * 100, height: 112 + CGFloat(p) * 100)
                }
            }
        }
    }

    /// Cung sáng xoay quanh logo
    var spinningArc: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(AngularGradient(colors: [.white.opacity(0), .white.opacity(0.9)], center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 148, height: 148)
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1.4) / 1.4 * 360))
        }
        .opacity(appear ? 1 : 0)
    }

    var progressBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.22)).frame(width: 190, height: 5)
            Capsule().fill(LinearGradient(colors: [.white.opacity(0.7), .white], startPoint: .leading, endPoint: .trailing))
                .frame(width: 190 * progress, height: 5)
                .overlay(alignment: .trailing) {
                    Circle().fill(Color.white).frame(width: 9, height: 9).shadow(color: .white.opacity(0.8), radius: 5)
                        .offset(x: 2)
                }
        }
    }

    // MARK: Điều khiển thời gian hiện / ẩn

    /// Trang đã sẵn sàng để lộ ra?
    @MainActor
    private func isReady(_ t: TimeInterval) -> Bool {
        if model.splashReady { return true }
        // Vào trang đăng nhập (hoặc lỗi mạng): lộ ra ngay để người dùng thao tác; đang tự đăng nhập lại thì giữ màn này
        if model.firstLoadDone && !model.inDesm && !model.reconnecting { return true }
        // Vào DESM nhưng trang không gửi tín hiệu (mở ở màn khác Package): chờ thêm một lúc rồi lộ ra
        if model.firstLoadDone && model.inDesm && t > 7 { return true }
        return false
    }

    @MainActor
    private func run() async {
        while !Task.isCancelled {
            let t = Date().timeIntervalSince(t0)
            withAnimation(.linear(duration: 0.12)) { progress = min(0.92, 1 - CGFloat(exp(-t / 3.2))) }
            let np = min(2, Int(t / 2.4))
            if np != phrase { withAnimation(.easeInOut(duration: 0.35)) { phrase = np } }
            if (isReady(t) && t > 1.9) || t > 14 { break }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { progress = 1 }
        try? await Task.sleep(nanoseconds: 280_000_000)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeIn(duration: 0.5)) { leaving = true }
        try? await Task.sleep(nanoseconds: 520_000_000)
        onFinish()
    }
}
