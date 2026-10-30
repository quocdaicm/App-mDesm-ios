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
    @State private var checks: [String: AIModelCheck] = [:]
    @State private var okSaved: [String] = []
    @State private var info = ""
    @State private var busy = false

    /// Model chạy được lên đầu, chưa thử ở giữa, lỗi ở cuối.
    private var sortedModels: [String] {
        func r(_ m: String) -> Int {
            if let c = checks[m] { return c.usable ? 0 : 2 }
            return okSaved.contains(m) ? 0 : 1
        }
        // thứ tự gốc = chat-model ưu tiên trước (rankChatModels), model không phải chat xếp cuối
        let ranked = AIClient.rankChatModels(provider, models)
        let order = ranked + models.filter { !ranked.contains($0) }
        let idx = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { (a: Int, _: Int) -> Int in a })
        return models.sorted { (a: String, b: String) -> Bool in
            let ra = r(a), rb = r(b)
            return ra != rb ? ra < rb : (idx[a] ?? 0) < (idx[b] ?? 0)
        }
    }

    @ViewBuilder private func badge(_ m: String) -> some View {
        if let c = checks[m] {
            switch c.state {
            case .ok: Text("✓ " + String(c.ms) + "ms").font(.caption).foregroundColor(.green)
            case .okNoTools: Text("✓ không công cụ").font(.caption).foregroundColor(.orange)
            case .limited: Text("hết hạn mức").font(.caption).foregroundColor(.orange)
            case .failed: Text("✗ " + c.note).font(.caption).foregroundColor(.red).lineLimit(1)
            }
        } else if okSaved.contains(m) {
            Text("✓").font(.caption).foregroundColor(.green)
        }
    }

    var body: some View {
        Form {
            Section {
                SecureField("Dán khoá API", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .onSubmit { if models.isEmpty { autoDetect() } }
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
                Button { autoDetect() } label: { Label("Tự dò model dùng được", systemImage: "wand.and.stars") }.disabled(busy)
                Button("Chỉ lấy danh sách (không kiểm tra)") { listModels() }.disabled(busy)
                if busy { ProgressView() }
                ForEach(Array(sortedModels.prefix(120)), id: \.self) { m in
                    Button {
                        model = m
                    } label: {
                        HStack {
                            Text(m).foregroundColor(.primary).lineLimit(1)
                            Spacer()
                            badge(m)
                            if m == model { Image(systemName: "checkmark").foregroundColor(.blue) }
                        }
                    }
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Nhập khoá rồi bấm \"Tự dò model dùng được\": app lấy danh sách rồi thử nhanh tối đa 10 model (ưu tiên model nhanh), đánh dấu ✓ cái chạy được và tự chọn cái tốt nhất. Để trống = dùng model mặc định của nhà. Model phải hỗ trợ gọi công cụ thì AI mới tự tra được dữ liệu DESM.")
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
            models = AIStore.cachedModels(provider.id)
            okSaved = AIStore.okModels(provider.id)
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
                    if !list.isEmpty { AIStore.setCachedModels(list, for: p.id) }
                    info = list.isEmpty ? "Không thấy model nào." : "Tìm thấy \(list.count) model — chạm để chọn."
                    busy = false
                }
            } catch {
                await MainActor.run { info = "Lỗi: " + error.localizedDescription; busy = false }
            }
        }
    }

    private func autoDetect() {
        save()
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { info = "Hãy nhập khoá API trước."; return }
        busy = true
        checks = [:]
        info = "Đang lấy danh sách model…"
        let p = provider
        let current = model.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let list = try await AIClient.listModels(p, key: k)
                await MainActor.run {
                    models = list
                    if !list.isEmpty { AIStore.setCachedModels(list, for: p.id) }
                    info = "Tìm thấy \(list.count) model, đang thử…"
                }
                let results = await AIClient.probe(p, key: k, models: list, first: current.isEmpty ? [] : [current]) { (r: AIModelCheck, done: Int, total: Int) in
                    checks[r.model] = r
                    info = "Đang thử model " + String(done) + "/" + String(total) + "…"
                }
                let okSet = Set(results.filter { $0.usable }.map { $0.model })
                let ranked = AIClient.rankChatModels(p, list).filter { okSet.contains($0) }
                let full = results.filter { $0.state == .ok }.map { $0.model }
                await MainActor.run {
                    okSaved = ranked
                    AIStore.setOkModels(ranked, for: p.id)
                    if ranked.isEmpty {
                        let why = results.first?.note ?? ""
                        info = "Không model nào chạy được" + (why.isEmpty ? "." : ": " + why) + " Kiểm tra lại khoá API."
                    } else {
                        // giữ model đang chọn nếu nó chạy được; không thì chọn model tốt nhất (ưu tiên cái gọi được công cụ)
                        if !okSet.contains(current) {
                            let best = AIClient.rankChatModels(p, list).first(where: { full.contains($0) }) ?? ranked[0]
                            model = best
                            AIStore.setModel(best, for: p.id)
                        }
                        info = "Dùng được " + String(ranked.count) + "/" + String(results.count) + " model đã thử. Đang chọn: " + model
                    }
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

/// Chọn model tự do cho một nhà AI (mở từ đầu khung chat): gõ tên bất kỳ, hoặc chạm vào danh sách dò từ nhà đó.
struct AIModelPickerView: View {
    let provider: AIProvider
    @Environment(\.dismiss) private var dismiss
    @State private var models: [String] = []
    @State private var current = ""
    @State private var custom = ""
    @State private var filter = ""
    @State private var busy = false
    @State private var info = ""
    @State private var okSaved: [String] = []

    private var shown: [String] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let ranked = AIClient.rankChatModels(provider, models)
        let base = ranked + models.filter { !ranked.contains($0) }
        let l = f.isEmpty ? base : base.filter { $0.lowercased().contains(f) }
        let ok = l.filter { okSaved.contains($0) }
        return Array((ok + l.filter { !okSaved.contains($0) }).prefix(200))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Gõ tên model bất kỳ", text: $custom)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .submitLabel(.done)
                            .onSubmit { pick(custom) }
                        Button("Dùng") { pick(custom) }
                            .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text(provider.name)
                } footer: {
                    Text("Đang dùng: " + (current.isEmpty ? "(chưa có)" : current) + ". Nhà AI này lỗi thì app tự thử model mặc định của nhà rồi mới sang nhà khác.")
                }
                if !provider.defaultModel.isEmpty {
                    Section {
                        row(provider.defaultModel, label: "Mặc định: " + provider.defaultModel)
                    }
                }
                Section {
                    TextField("Lọc danh sách…", text: $filter)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Button("Tự dò model dùng được") { detect() }.disabled(busy)
                    Button("Chỉ tải lại danh sách") { reload() }.disabled(busy)
                    if busy { ProgressView() }
                    if !info.isEmpty { Text(info).font(.footnote).foregroundColor(.secondary) }
                    ForEach(shown, id: \.self) { m in row(m, label: m) }
                } header: {
                    Text("Danh sách model")
                }
            }
            .navigationTitle("Chọn model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        }
        .onAppear {
            current = AIStore.model(provider)
            okSaved = AIStore.okModels(provider.id)
            models = AIStore.cachedModels(provider.id)
            if models.isEmpty && !AIStore.key(provider.id).isEmpty { reload() }
        }
    }

    private func row(_ m: String, label: String) -> some View {
        Button { pick(m) } label: {
            HStack {
                Text(label).foregroundColor(.primary).lineLimit(1)
                Spacer()
                if okSaved.contains(m) { Text("✓").font(.caption).foregroundColor(.green) }
                if m == current { Image(systemName: "checkmark").foregroundColor(.blue) }
            }
        }
    }

    private func pick(_ m: String) {
        let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        AIStore.setModel(t, for: provider.id)
        current = t
        dismiss()
    }

    private func detect() {
        let k = AIStore.key(provider.id)
        if k.isEmpty { info = "Chưa có khoá API cho nhà này (vào Cài đặt > AI riêng để nhập)."; return }
        busy = true
        info = "Đang lấy danh sách model…"
        let p = provider
        let cur = current
        Task {
            do {
                let list = try await AIClient.listModels(p, key: k)
                await MainActor.run {
                    models = list
                    if !list.isEmpty { AIStore.setCachedModels(list, for: p.id) }
                }
                let results = await AIClient.probe(p, key: k, models: list, first: cur.isEmpty ? [] : [cur]) { (_: AIModelCheck, done: Int, total: Int) in
                    info = "Đang thử model " + String(done) + "/" + String(total) + "…"
                }
                let okSet = Set(results.filter { $0.usable }.map { $0.model })
                let ranked = AIClient.rankChatModels(p, list).filter { okSet.contains($0) }
                await MainActor.run {
                    okSaved = ranked
                    AIStore.setOkModels(ranked, for: p.id)
                    info = ranked.isEmpty ? "Không model nào chạy được. Kiểm tra lại khoá API." : "Dùng được " + String(ranked.count) + "/" + String(results.count) + " model đã thử (có dấu ✓), chạm để chọn."
                    busy = false
                }
            } catch {
                await MainActor.run { info = "Lỗi: " + error.localizedDescription; busy = false }
            }
        }
    }

    private func reload() {
        let k = AIStore.key(provider.id)
        if k.isEmpty { info = "Chưa có khoá API cho nhà này (vào Cài đặt > AI riêng để nhập)."; return }
        busy = true
        info = "Đang dò model…"
        let p = provider
        Task {
            do {
                let list = try await AIClient.listModels(p, key: k)
                await MainActor.run {
                    models = list
                    if !list.isEmpty { AIStore.setCachedModels(list, for: p.id) }
                    info = list.isEmpty ? "Không thấy model nào." : "Tìm thấy \(list.count) model."
                    busy = false
                }
            } catch {
                await MainActor.run { info = "Lỗi: " + error.localizedDescription; busy = false }
            }
        }
    }
}
