// SettingsView.swift — màn Cài đặt.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

struct SettingsView: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var shareItem: ShareItem?
    @AppStorage("desmExportStripValues2") private var stripValues = false
    @AppStorage("desmRememberLogin") private var rememberLogin = true
    @AppStorage("desmAutofill") private var autofill = true
    @AppStorage("desmAutoReconnect") private var autoReconnect = true
    @AppStorage("desmBgNotify") private var bgNotify = true
    @AppStorage("desmExportStripScripts2") private var stripScripts = false
    @AppStorage("desmScanOpenDetail") private var scanOpenDetail = true
    @AppStorage("desmNetLogOn") private var netLogOn = false
    @AppStorage("desmSnapOn") private var snapOn = false
    @AppStorage("desmEdgeSwipe") private var edgeSwipe = true
    @State private var fetchPath = ""

    func shareText(_ text: String, prefix: String, ext: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(formatter.string(from: Date())).\(ext)")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            shareItem = ShareItem(url: url)
        } catch {
            message = "Không lưu được file: \(error.localizedDescription)"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                languageSection
                startSection
                dodoSection
                scanSection
                loginSection
                Section {
                    NavigationLink("Nâng cao & công cụ phát triển") { advancedForm }
                } footer: {
                    Text("CSS và từ điển bổ sung, ghi API, lưu mã HTML/script của trang. Chỉ cần khi tinh chỉnh app.")
                }
            }
            .onAppear { model.setNetLog(netLogOn); model.setSnap(snapOn) }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Xong") { model.applyStyles(); dismiss() } } }
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
            }
        }
        .desmAlert(isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        ), icon: "info.circle.fill", title: "Kết quả", message: message,
                   actions: [DesmDialogAction(title: "OK", kind: .primary) { message = nil }])
    }

    // MARK: Cài đặt chính

    var displaySection: some View {
        Section {
            Picker("Chế độ", selection: Binding(
                get: { model.layoutMode },
                set: { model.setMode($0) }
            )) {
                ForEach(LayoutMode.allCases) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)

            if model.layoutMode == .fit {
                Stepper("Độ rộng khi thu nhỏ: \(model.fitWidth)px", value: Binding(
                    get: { model.fitWidth },
                    set: { model.fitWidth = $0; model.applyStyles() }
                ), in: 700...1800, step: 100)
            }
            Toggle("Chỉ áp dụng cho DESM", isOn: Binding(
                get: { model.scopeOnly },
                set: { model.scopeOnly = $0; model.applyStyles() }
            ))
            Toggle("Thu gọn thanh trên", isOn: $model.compactHeader)
            Toggle("Vuốt mép màn hình để quay lại / tiến", isOn: $edgeSwipe)
        } header: {
            Text("Hiển thị")
        } footer: {
            Text("Mobile: sắp xếp lại bố cục cho màn hình nhỏ. Vừa màn hình: bản desktop thu nhỏ, phóng to bằng hai ngón. Gốc: không can thiệp. Vuốt từ mép trái để quay lại trang trước, từ mép phải để tiến.")
        }
    }

    var languageSection: some View {
        Section {
            Toggle("Giao diện DESM bằng tiếng Việt", isOn: Binding(
                get: { model.viLang },
                set: { model.setVietnamese($0) }
            ))
        } header: {
            Text("Ngôn ngữ")
        } footer: {
            Text("Dịch nhãn, nút, menu, tiêu đề cột và hộp thoại; dữ liệu (mã kiện, mô tả hàng, vị trí) giữ nguyên. Nên để ngôn ngữ gốc của trang là English.")
        }
    }

    var startSection: some View {
        Section {
            Toggle("Mở màn Package khi vào app", isOn: Binding(
                get: { model.openPackageOnStart },
                set: { model.openPackageOnStart = $0 }
            ))
        } header: {
            Text("Màn hình chính")
        } footer: {
            Text("Mỗi lần mở app hoặc đăng nhập lại, app tự vào màn Package (Kiện hàng). Tắt thì ở trang chủ DESM.")
        }
    }

    var dodoSection: some View {
        Section {
            Toggle("Nút chat Dodo (trợ lý AI)", isOn: Binding(
                get: { model.dodoBubble },
                set: { model.dodoBubble = $0; model.applyStyles() }
            ))
            Toggle("Dodo trả lời bằng tiếng Việt", isOn: Binding(
                get: { model.dodoVi },
                set: { model.dodoVi = $0; model.applyStyles() }
            ))
        } header: {
            Text("Trợ lý Dodo")
        } footer: {
            Text("Hiện nút bong bóng trên trang DESM; chạm để mở khung chat với Dodo — trợ lý AI của web DESM, dùng chung tài khoản và lịch sử hội thoại với bản web. Kéo bong bóng để đổi vị trí.")
        }
    }

    var scanSection: some View {
        Section {
            Toggle("Quét xong mở luôn chi tiết kiện", isOn: $scanOpenDetail)
        } header: {
            Text("Quét Package No")
        } footer: {
            Text("Bấm nút camera ở giữa thanh dưới khi đang ở màn hình Package. App đọc Package No trên tem, điền ô Số kiện hàng rồi Search. Không có dòng khớp chính xác thì báo không tìm thấy, không mở nhầm kiện.")
        }
    }

    var loginSection: some View {
        Section {
            Toggle("Ghi nhớ phiên đăng nhập", isOn: $rememberLogin)
            Toggle("Tự điền tài khoản ở trang đăng nhập", isOn: $autofill)
            Toggle("Tự đăng nhập lại khi hết phiên", isOn: $autoReconnect)
            Toggle("Thông báo khi app đóng (thông báo mới, tàu sắp đến)", isOn: $bgNotify)
                .onChange(of: bgNotify) { on in if on { BackgroundRefresh.requestAuthorization(); BackgroundRefresh.schedule() } else { BackgroundRefresh.schedule() } }
            Button("Xóa tài khoản và phiên đã lưu", role: .destructive) {
                CredStore.clear()
                SessionStore.clear()
                model.showToast("Đã xóa tài khoản và phiên đã lưu")
            }
        } header: {
            Text("Đăng nhập")
        } footer: {
            Text("Tài khoản (chỉ khi bạn đồng ý lưu) và phiên được giữ trong Keychain của máy này. Khi phiên DESM hết hạn, app quay về trang đăng nhập, điền tài khoản đã lưu và tự bấm Login; cần bật \"Tự điền tài khoản\" và đã lưu tài khoản.")
        }
    }

    // MARK: Nâng cao

    var advancedForm: some View {
        Form {
            Section {
                TextEditor(text: $model.customCSS)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 110)
                Button("Xóa CSS bổ sung", role: .destructive) { model.customCSS = ""; model.applyStyles() }
            } header: {
                Text("CSS bổ sung")
            } footer: {
                Text("Áp dụng khi bấm Xong.")
            }

            Section {
                TextEditor(text: $model.customDict)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 110)
                Button("Sao chép chuỗi chưa dịch") { model.copyMissingStrings { message = $0 } }
            } header: {
                Text("Từ điển bổ sung")
            } footer: {
                Text("Mỗi dòng: English = Tiếng Việt. Áp dụng khi bấm Xong.")
            }

            Section {
                Toggle("Tự lưu cấu trúc & CSS từng màn hình", isOn: $snapOn)
                    .onChange(of: snapOn) { model.setSnap($0) }
                Button("Lưu tất cả màn hình đã ghi (1 file)…") {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let text = SnapStore.export()
                        DispatchQueue.main.async {
                            guard let text = text else { message = "Chưa ghi màn hình nào. Bật công tắc rồi mở lần lượt các màn hình DESM."; return }
                            shareText(text, prefix: "desm-screens", ext: "txt")
                        }
                    }
                }
                Button("Xóa các màn hình đã ghi", role: .destructive) {
                    SnapStore.clear(); message = "Đã xóa các màn hình đã ghi."
                }
            } header: {
                Text("Ghi từng màn hình")
            } footer: {
                Text("Bật công tắc rồi vào lần lượt từng màn hình (menu) của DESM, chờ vài giây cho trang tải xong. App tự lưu cây cấu trúc, HTML và toàn bộ file CSS của từng màn, kể cả màn nằm trong khung con. Xong thì lưu một file duy nhất và gửi cho tác giả. Nhớ tắt công tắc và xóa khi xong.")
            }

            Section {
                Toggle("Ghi lại các request API của trang", isOn: $netLogOn)
                    .onChange(of: netLogOn) { model.setNetLog($0) }
                Button("Lưu nhật ký API (JSON đầy đủ)…") {
                    model.fetchNetLog(format: .json) { text, error in
                        guard let text = text else { message = error; return }
                        shareText(text, prefix: "desm-api-full", ext: "json")
                    }
                }
                Button("Lưu tóm tắt các endpoint…") {
                    model.fetchNetLog(format: .summary) { text, error in
                        guard let text = text else { message = error; return }
                        shareText(text, prefix: "desm-api-summary", ext: "txt")
                    }
                }
                Button("Lưu nhật ký API (văn bản)…") {
                    model.fetchNetLog { text, error in
                        guard let text = text else { message = error; return }
                        shareText(text, prefix: "desm-api", ext: "txt")
                    }
                }
                Button("Xóa nhật ký API", role: .destructive) {
                    model.clearNetLog(); message = "Đã xóa nhật ký API."
                }
            } header: {
                Text("Nhật ký API")
            } footer: {
                Text("Bật công tắc, thao tác trên trang DESM (Search, quét, mở chi tiết…) rồi quay lại lưu file. Nhật ký nằm trong máy, có địa chỉ API, tham số và phản hồi đầy đủ của API dữ liệu; mật khẩu/token được che. Nhớ tắt và xóa khi xong.")
            }

            Section {
                Button("Lưu HTML trang đang mở…") {
                    model.fetchHTML(stripValues: stripValues, stripScripts: stripScripts) { html, error in
                        guard let html = html else { message = error; return }
                        shareText(html, prefix: "desm-page", ext: "html")
                    }
                }
                Button("Lưu script của trang…") {
                    model.fetchScriptFiles { text, info in
                        guard let text = text else { message = info; return }
                        message = "Đã tải \(info) file script."
                        shareText(text, prefix: "desm-scripts", ext: "txt")
                    }
                }
                Button("Sao chép cấu trúc trang đang mở") { model.copyDiagnostics { message = $0 } }
                Toggle("Ẩn giá trị trong ô nhập", isOn: $stripValues)
                Toggle("Bỏ mã script nội tuyến", isOn: $stripScripts)
            } header: {
                Text("Mã nguồn trang")
            } footer: {
                Text("Mở màn hình cần xem (Package, Hạng mục chi tiết…) trước. HTML có thể chứa thông tin nội bộ, hãy kiểm tra trước khi chia sẻ.")
            }

            Section {
                Button("Thu thập mẫu API (loginStatus + chuỗi giao diện)…") {
                    let specs = ["GET /loginStatus.do",
                                 "POST /getMessageProperties.do",
                                 "GET /getMessageProperties.do"]
                    var out = "DESM — mẫu API (loginStatus, getMessageProperties)\n"
                    func next(_ i: Int) {
                        if i >= specs.count { shareText(out, prefix: "desm-api-sample", ext: "txt"); return }
                        model.fetchResource(specs[i]) { r, err in
                            out += "\n===== \(specs[i]) =====\n"
                            if let r = r {
                                let body = r.text.count > 200_000 ? String(r.text.prefix(200_000)) + "\n…(cắt bớt)" : r.text
                                out += "HTTP \(r.status) · \(r.contentType) · \(r.text.count) ký tự\n\(body)\n"
                            } else { out += "LỖI: \(err)\n" }
                            next(i + 1)
                        }
                    }
                    next(0)
                }
            } header: {
                Text("Thu thập mẫu API")
            } footer: {
                Text("Cần đang ở DESM và đã đăng nhập. Gọi /loginStatus.do và /getMessageProperties.do rồi lưu một file để gửi lại cho tác giả. Nội dung phản hồi có thể chứa thông tin nội bộ, hãy xem trước khi chia sẻ.")
            }

            Section {
                TextField("Địa chỉ, vd /resources/scripts/…js", text: $fetchPath)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Tải nội dung địa chỉ và lưu file…") {
                    let path = fetchPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !path.isEmpty else { message = "Hãy nhập địa chỉ cần tải."; return }
                    model.fetchURLText(path) { text, error in
                        guard let text = text else { message = error; return }
                        shareText(text, prefix: "desm-fetch", ext: "txt")
                    }
                }
            } header: {
                Text("Tải địa chỉ")
            } footer: {
                Text("Tải script, trang hoặc API dạng GET cùng domain bằng phiên đăng nhập hiện có.")
            }
        }
        .navigationTitle("Nâng cao")
        .navigationBarTitleDisplayMode(.inline)
    }
}
