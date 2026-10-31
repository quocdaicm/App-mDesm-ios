// BrowserView.swift — màn hình chính: WebView + thanh địa chỉ/nút điều hướng, nút camera quét, toast.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

/// Màn hình chính: WebView + thanh địa chỉ/nút điều hướng (tự ẩn khi đã vào DESM), nút camera quét, toast và Cài đặt.
struct BrowserView: View {
    @StateObject private var model = BrowserModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showScanner = false
    @State private var showScanChoice = false
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem? = nil
    @State private var photoChoice: ScanChoice? = nil
    @State private var selectedTab: DesmTab = .package
    @State private var showMore = false
    @State private var showPackingHistory = false
    @State private var showActivity = false
    @State private var showEditLog = false
    @State private var showVessel = false
    @State private var showNotice = false
    @State private var showFetcher = false
    @State private var showAudit = false
    @State private var showSource = false
    @State private var docKind: DesmDocKind? = nil
    @State private var showOutgoing = false
    @State private var showWip = false
    @State private var showMrfReturn = false

    var body: some View {
        VStack(spacing: 0) {
            if !model.barsHidden {
                header
                if model.isLoading {
                    ProgressView(value: model.progress).tint(.blue).frame(height: 3)
                } else {
                    Rectangle().fill(Color(.separator).opacity(0.5)).frame(height: 0.5)
                }
            }
            WebView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if let text = model.toast {
                        Text(text)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.top, 8)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: model.toast)
            // Trong DESM: footer 5 tab mới (luôn hiện). Ngoài DESM (trang đăng nhập...): thanh điều hướng cũ, ẩn thì chỉ còn dải an toàn.
            if model.inDesm {
                DesmTabBar(selected: $selectedTab,
                           onScan: { showScanChoice = true },
                           moreBadge: model.unreadNotices,
                           onSelect: { tab in
                               if tab == .more { showMore = true }
                               else if tab == .outbound { showOutgoing = true }
                               else if tab == .inbound { showMrfReturn = true }
                               else { selectedTab = tab; model.openDesmTab(tab) }
                           })
            } else if !model.barsHidden {
                bottomBar
            } else {
                Color.clear.frame(height: 0)
                    .background(FooterBackground().ignoresSafeArea(edges: .bottom))
            }
        }
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)   // bàn phím phủ lên footer, không ép WebView (tránh lưới báo "Too small space" làm mất focus ô nhập)
        .tint(.blue)
        .onChange(of: scenePhase) { phase in
            if phase != .active { model.saveSession(); model.backgroundedAt = model.backgroundedAt ?? Date(); if phase == .background { BackgroundRefresh.schedule() } }
            else { model.appBecameActive(); model.refreshNoticeBadge() }
        }
        .onChange(of: model.inDesm) { inside in if inside { model.refreshNoticeBadge() } }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in model.refreshNoticeBadge() }
        .desmDialog(model.dialogQueue.first, finish: { model.finishDialog() })
        .desmAlert(isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        ), icon: "exclamationmark.triangle.fill", title: "Không mở được địa chỉ", message: model.errorMessage,
                   actions: [DesmDialogAction(title: "Đóng", kind: .cancel) { model.errorMessage = nil }])
        .fullScreenCover(isPresented: $showScanner) {
            PackageScannerView(onPick: { c in model.runScan(c) }, onQR: { d in model.runQRScan(d) }, onRsi: { r in model.runQRRsi(r) })
        }
        .desmAlert(isPresented: $showScanChoice, icon: "viewfinder", title: "Quét mã", actions: [
            DesmDialogAction(title: "Quét bằng camera", kind: .primary) { showScanner = true },
            DesmDialogAction(title: "Chọn ảnh có sẵn", kind: .normal) { showPhotoPicker = true },
            DesmDialogAction(title: "Hủy", kind: .cancel),
        ])
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .sheet(item: $photoChoice) { ch in
            ScanChoiceSheet(choice: ch, onPick: { c in
                photoChoice = nil
                PkgParser.learn(c)
                model.runScan(c)
            }, onCancel: { photoChoice = nil })
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: pickedPhoto) { item in
            guard let item = item else { return }
            Task {
                var img: UIImage? = nil
                if let data = try? await item.loadTransferable(type: Data.self) { img = UIImage(data: data) }
                pickedPhoto = nil
                guard let img = img else { model.showToast("Không mở được ảnh đã chọn"); return }
                model.showToast("Đang đọc ảnh…")
                ImageScanner.scan(img) { r in
                    switch r {
                    case .detail(let d): model.runQRScan(d)
                    case .rsi(let r): model.runQRRsi(r)
                    case .package(let c): PkgParser.learn(c); model.runScan(c)
                    case .choose(let ch): photoChoice = ch
                    case .otherQR(let q):
                        UIPasteboard.general.string = q
                        model.showToast("QR chưa hỗ trợ, đã sao chép: \(q.prefix(60))")
                    case .none: model.showToast("Không thấy QR, Package No hay Packing List No trong ảnh")
                    }
                }
            }
        }
        .sheet(isPresented: $showMore) {
            MoreSheet(model: model, onClose: { showMore = false }, onHistory: { showPackingHistory = true }, onDoc: { docKind = $0 }, onWip: { showWip = true }, onActivity: { showActivity = true }, onEditLog: { showEditLog = true }, onVessel: { showVessel = true }, onNotice: { showNotice = true }, onFetch: { showFetcher = true }, onSource: { showSource = true }, onAudit: { showAudit = true })
                .presentationDetents([.fraction(0.7), .large])
                .presentationDragIndicator(.visible)
                .tint(Color.tabBlue)
        }
        .sheet(isPresented: $showMrfReturn) {
            DesmMrfReturnSheet(model: model, onClose: { showMrfReturn = false })
                .desmSheet()
        }
        .sheet(isPresented: $showWip) {
            DesmWipSheet(model: model, onClose: { showWip = false })
                .desmSheet()
        }
        .onChange(of: model.pendingRsiScan) { r in
            guard let r = r else { return }
            if r.kind == .mrf { showMrfReturn = true } else { showOutgoing = true }
        }
        .sheet(isPresented: $showOutgoing) {
            DesmOutgoingSheet(model: model, onClose: { showOutgoing = false })
                .desmSheet()
        }
        .sheet(item: $docKind) { kind in
            DesmDocSheet(model: model, kind: kind, onClose: { docKind = nil })
                .desmSheet()
        }
        .sheet(isPresented: $showEditLog) {
            DesmEditLogSheet(model: model, onClose: { showEditLog = false })
                .desmSheet()
        }
        .sheet(isPresented: $showActivity) {
            DesmActivitySheet(model: model, onClose: { showActivity = false })
                .desmSheet()
        }
        .sheet(isPresented: $showNotice) {
            DesmNoticeSheet(model: model, onClose: { showNotice = false })
        }
        .sheet(isPresented: $showVessel) {
            DesmVesselSheet(model: model, onClose: { showVessel = false })
                .desmSheet()
        }
        .sheet(isPresented: $showAudit) {
            DesmAuditView(onClose: { showAudit = false })
                .desmSheet()
        }
        .sheet(isPresented: $showFetcher) {
            DesmFetchSheet(model: model, onClose: { showFetcher = false })
                .desmSheet()
        }
        .sheet(isPresented: $showSource) {
            DesmSourceSheet(model: model, onClose: { showSource = false })
                .desmSheet()
        }
        .sheet(isPresented: $showPackingHistory) {
            PackingHistorySheet(model: model, onClose: { showPackingHistory = false }, onOpen: { pl in
                showPackingHistory = false
                selectedTab = .package
                model.openPackingList(pl)
            })
                .desmSheet()
        }
        .sheet(isPresented: $model.showAIChat) {
            AIChatView(model: model, onClose: { model.showAIChat = false })
                .desmSheet()
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
                .desmSheet()
        }
        .sheet(item: $model.shotItem) { item in
            ShareSheet(url: item.url)
        }
    }

    func modeButton(size: CGFloat) -> some View {
        Button { model.cycleMode() } label: {
            Image(systemName: model.layoutMode.symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: size, height: size)
                .background(model.layoutMode == .off ? Color(.secondarySystemBackground) : Color.blue.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 11))
        }
        .accessibilityLabel("Đổi chế độ hiển thị: \(model.layoutMode.title)")
    }

    func settingsButton(size: CGFloat) -> some View {
        Button { model.showSettings = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: size, height: size)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11))
        }
        .accessibilityLabel("Cài đặt giao diện")
    }

    var addressField: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
            TextField("Nhập địa chỉ website…", text: $model.address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { model.loadAddress() }
                .font(.system(size: 14))
            Button { model.loadAddress() } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
            }
            .accessibilityLabel("Mở địa chỉ")
        }
        .padding(.horizontal, 12).padding(.vertical, model.compactHeader ? 7 : 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    var header: some View {
        VStack(spacing: 8) {
            if !model.compactHeader {
                HStack(spacing: 9) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DESM Mobile").font(.system(size: 16, weight: .bold))
                        Text(model.pageTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 3)
                    modeButton(size: 38)
                    settingsButton(size: 38)
                }
            }
            HStack(spacing: 8) {
                if model.compactHeader {
                    modeButton(size: 34)
                    settingsButton(size: 34)
                }
                addressField
            }
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 8)
        .background(LinearGradient(colors: [Color(red: 0.81, green: 0.90, blue: 0.99), Color(red: 0.89, green: 0.94, blue: 1.0)],
                                   startPoint: .top, endPoint: .bottom))
    }

    var bottomBar: some View {
        HStack(spacing: 0) {
            navButton("chevron.left", title: "Quay lại", enabled: model.canGoBack || model.inDesm) { model.goBack() }
            navButton("chevron.right", title: "Tiến", enabled: model.canGoForward) { model.goForward() }
            navButton("house.fill", title: "DESM", enabled: true) { model.home() }
            navButton("arrow.clockwise", title: "Tải lại", enabled: true) { model.reload() }
            navButton("camera.viewfinder", title: "Chụp", enabled: true) { model.captureFullPage() }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white)
                .shadow(color: Color(red: 0.09, green: 0.25, blue: 0.55).opacity(0.16), radius: 12, y: -2)
        )
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
        .background(FooterBackground().ignoresSafeArea(edges: .bottom))
    }

    func navButton(_ symbol: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(enabled ? Color.tabBlue : Color.tabInk.opacity(0.4))
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .disabled(!enabled)
    }
}
