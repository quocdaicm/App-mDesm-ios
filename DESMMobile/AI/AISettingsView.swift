// AISettingsView.swift — Cài đặt "AI riêng": chọn nhà AI, nhập khoá, dò/chọn model, kiểm tra kết nối, bật/tắt tra cứu dữ liệu DESM.
// Chưa build/chưa thử trên máy thật.

import SwiftUI

struct AIProviderListView: View {
    @State private var active = AIStore.activeID
    @State private var tools = AIStore.toolsOn
    @State private var autoSwitch = AIStore.autoSwitch

    var body: some View {
        Form {
            Section {
                ForEach(AIProvider.all) { p in
                    NavigationLink {
                        AIProviderDetailView(provider: p, active: $active)
                    } label: {
                        HStack {
                            Text(p.name)
                            Spacer()
                            if !AIStore.key(p.id).isEmpty { Text("có khoá").font(.caption).foregroundColor(.green) }
                            if active == p.id { Text("đang dùng").font(.caption.bold()).foregroundColor(.blue) }
                        }
                    }
                }
            } header: {
                Text("Nhà AI")
            } footer: {
                Text("Mỗi nhà cần khoá API của chính bạn (lưu trong Keychain của máy này). Chọn một nhà làm mặc định ở màn chi tiết.")
            }
            Section {
                Toggle("Tự chuyển sang AI khác khi lỗi", isOn: $autoSwitch)
            } footer: {
                Text("Nhà đang chọn lỗi, hết hạn mức hoặc quá 60 giây không trả lời thì app tự thử nhà kế tiếp đã có khoá (tối đa 4 nhà; nhà vừa lỗi được cho nghỉ 5 phút). Lưu ý: câu hỏi và dữ liệu DESM tra được sẽ đi tới nhà AI được thử.")
            }
            Section {
                NavigationLink("Nhật ký AI (tìm chỗ bị treo)") { AILogView() }
            } footer: {
                Text("Ghi từng bước (gửi AI, tra DESM, đọc trang) kèm thời gian và cảnh báo khi giao diện bị đứng. Không chứa khoá API hay dữ liệu. Khi app treo: mở lại app, vào đây, bấm Chia sẻ file rồi gửi lại.")
            }
            Section {
                Toggle("Cho AI tự tra dữ liệu DESM (chỉ đọc)", isOn: $tools)
            } footer: {
                Text("Bật: AI tự gọi các API DESM trong danh mục (kiện, hạng mục, RSI, MRF, tàu, thông báo) và đọc màn đang mở để trả lời; tuyệt đối không có công cụ ghi/sửa/xoá. Dữ liệu tra được SẼ ĐƯỢC GỬI tới nhà AI đã chọn — chỉ bật khi công ty cho phép. Tắt: AI chỉ trả lời kiến thức chung.")
            }
        }
        .navigationTitle("AI riêng")
        .onChange(of: tools) { v in AIStore.toolsOn = v }
        .onChange(of: autoSwitch) { v in AIStore.autoSwitch = v }
        .onAppear { active = AIStore.activeID; tools = AIStore.toolsOn; autoSwitch = AIStore.autoSwitch }
    }
}

struct AIProviderDetailView: View {
    let provider: AIProvider
    @Binding var active: String

    @State private var key = ""
    @State private var model = ""
    @State private var base = ""
    @State private var models: [String] = []
    @State private var info = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                SecureField("Dán khoá API", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            } header: {
                Text("Khoá API")
            } footer: {
                Text(provider.keyHelp)
            }
            if provider.id == "custom" {
                Section {
                    TextField("https://máy-chủ/v1", text: $base)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                } header: {
                    Text("Địa chỉ API (OpenAI-compatible)")
                }
            }
            Section {
                TextField("Tên model", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("Dò danh sách model") { listModels() }.disabled(busy)
                ForEach(Array(models.prefix(80)), id: \.self) { m in
                    Button {
                        model = m
                    } label: {
                        HStack {
                            Text(m).foregroundColor(.primary)
                            Spacer()
                            if m == model { Image(systemName: "checkmark").foregroundColor(.blue) }
                        }
                    }
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Để trống = dùng model mặc định của nhà. Model phải hỗ trợ gọi công cụ (function calling) thì AI mới tự tra được dữ liệu DESM.")
            }
            Section {
                Button("Kiểm tra kết nối") { testNow() }.disabled(busy)
                Button(active == provider.id ? "Đang dùng nhà này" : "Dùng nhà này") {
                    save()
                    active = provider.id
                    AIStore.activeID = provider.id
                }
                if busy { ProgressView() }
                if !info.isEmpty { Text(info).font(.footnote) }
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            key = AIStore.key(provider.id)
            model = AIStore.model(provider)
            base = AIStore.baseURL(provider)
        }
        .onDisappear { save() }
    }

    private func save() {
        AIStore.setKey(key, for: provider.id)
        AIStore.setModel(model, for: provider.id)
        if provider.id == "custom" { AIStore.setCustomBase(base) }
    }

    private func listModels() {
        save()
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { info = "Hãy nhập khoá API trước."; return }
        busy = true
        info = "Đang dò model…"
        let p = provider
        Task {
            do {
                let list = try await AIClient.listModels(p, key: k)
                await MainActor.run {
                    models = list
                    info = list.isEmpty ? "Không thấy model nào." : "Tìm thấy \(list.count) model — chạm để chọn."
                    busy = false
                }
            } catch {
                await MainActor.run { info = "Lỗi: " + error.localizedDescription; busy = false }
            }
        }
    }

    private func testNow() {
        save()
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { info = "Hãy nhập khoá API trước."; return }
        busy = true
        info = "Đang kiểm tra…"
        let p = provider
        let m = AIStore.model(p)
        Task {
            let r = await AIClient.test(p, key: k, model: m)
            await MainActor.run { info = r; busy = false }
        }
    }
}
