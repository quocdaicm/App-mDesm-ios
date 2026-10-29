// AISettingsView.swift — màn chọn nhà cung cấp AI, nhập key, dò model, tự chọn model dùng được.
// Chuyển từ SettingsView/QuickModelSheet của LiveTranslate (đã đổi sang iOS 16, giao diện sáng theo DESM).

import SwiftUI

/// Danh sách nhà cung cấp: chạm vào để nhập key / chọn model; kéo để đổi thứ tự ưu tiên.
struct AIProviderListView: View {
    @State private var order = AIStore.order()
    @State private var tick = 0

    var body: some View {
        List {
            Section {
                ForEach(order) { p in
                    NavigationLink { AIProviderDetail(p).onDisappear { tick += 1 } } label: {
                        AIProviderRow(provider: p, tick: tick)
                    }
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    AIStore.saveOrder(order)
                }
            } header: {
                Text("Nhà cung cấp AI")
            } footer: {
                Text("Nhà ở trên được dùng trước; nếu lỗi, app tự chuyển sang nhà kế tiếp đã có key. Bấm Sửa để kéo đổi thứ tự.")
            }
        }
        .id(tick)
        .navigationTitle("AI riêng (API key)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}

struct AIProviderRow: View {
    let provider: AIProvider
    let tick: Int

    var body: some View {
        let active = AIStore.config(provider) != nil
        let hasKey = !AIStore.key(provider).isEmpty || provider == .custom
        HStack(spacing: 12) {
            Image(systemName: provider.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(provider.color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name).font(.system(.body, design: .rounded).weight(.medium))
                Text(active ? "Đang dùng • \(AIStore.model(provider))"
                     : (hasKey ? "Đã tắt" : "Chưa nhập key"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Circle().fill(active ? Color.green : Color.secondary.opacity(0.3)).frame(width: 9, height: 9)
        }
        .padding(.vertical, 2)
    }
}

struct AIProviderDetail: View {
    let p: AIProvider
    @State private var key: String
    @State private var enabled: Bool
    @State private var model: String
    @State private var base: String
    @State private var testResult = ""
    @State private var testing = false
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var probing = false
    @State private var showPicker = false
    @State private var modelMsg = ""

    init(_ p: AIProvider) {
        self.p = p
        _key = State(initialValue: AIStore.key(p))
        _enabled = State(initialValue: AIStore.enabled(p))
        _model = State(initialValue: AIStore.model(p))
        _base = State(initialValue: AIStore.base(p))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Bật nhà này", isOn: $enabled)
            } footer: {
                Text(p.note)
            }

            Section("API key") {
                SecureField(p == .custom ? "API key (có thể để trống)" : "Dán API key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button { if let s = UIPasteboard.general.string { key = s } } label: {
                    Label("Dán từ clipboard", systemImage: "doc.on.clipboard")
                }
                if let url = p.keyURL {
                    Link(destination: url) { Label("Lấy API key", systemImage: "arrow.up.right.square") }
                }
            }

            Section {
                if p == .custom {
                    TextField("Base URL (vd. https://…/v1)", text: $base)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                TextField("Model", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button { fetchModels() } label: {
                    Label(loadingModels ? "Đang dò…" : "Dò danh sách model", systemImage: "list.bullet.rectangle")
                }
                .disabled(loadingModels || probing || (key.isEmpty && p != .custom))
                Button { autoPick() } label: {
                    Label(probing ? "Đang thử từng model…" : "Tự chọn model dùng được", systemImage: "wand.and.stars")
                }
                .disabled(loadingModels || probing || (key.isEmpty && p != .custom))
                if !modelMsg.isEmpty { Text(modelMsg).font(.footnote) }
            } header: {
                Text("Model")
            } footer: {
                Text("Bấm \"Dò danh sách model\" để xem các model key này dùng được rồi chọn, hoặc để app tự thử và chọn một model chạy được.")
            }

            Section {
                Button { test() } label: {
                    Label(testing ? "Đang thử…" : "Thử kết nối", systemImage: "bolt.horizontal.circle")
                }
                .disabled(testing || (key.isEmpty && p != .custom))
                if !testResult.isEmpty { Text(testResult).font(.footnote) }
            }
        }
        .navigationTitle(p.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: key) { v in AIStore.setKey(p, v) }
        .onChange(of: enabled) { v in AIStore.setEnabled(p, v) }
        .onChange(of: model) { v in AIStore.setModel(p, v) }
        .onChange(of: base) { v in AIStore.setBase(p, v) }
        .sheet(isPresented: $showPicker) {
            AIModelPicker(models: models, current: model) { model = $0 }
        }
    }

    private func config(model m: String) -> AIConfig {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIConfig(id: p,
                        key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                        model: m,
                        base: p == .custom ? b : p.defaultBase)
    }

    private func fetchModels() {
        loadingModels = true
        modelMsg = ""
        Task {
            do {
                models = try await AIClient.listModels(config(model: model))
                showPicker = true
            } catch {
                modelMsg = "❌ Không dò được: \(error.localizedDescription)"
            }
            loadingModels = false
        }
    }

    private func autoPick() {
        probing = true
        modelMsg = ""
        Task {
            do {
                let r = try await AIClient.pickWorkingModel(config(model: model)) { m in
                    Task { @MainActor in modelMsg = "Đang thử: \(m)" }
                }
                models = r.all
                if let picked = r.picked {
                    model = picked
                    modelMsg = "✅ Đã chọn: \(picked)"
                } else {
                    modelMsg = "❌ Thử 8 model đều lỗi. Bấm \"Dò danh sách model\" để chọn thủ công."
                }
            } catch {
                modelMsg = "❌ Không dò được: \(error.localizedDescription)"
            }
            probing = false
        }
    }

    private func test() {
        testing = true
        testResult = ""
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfg = config(model: m.isEmpty ? p.defaultModel : m)
        Task {
            do {
                let r = try await AIClient.complete(
                    cfg, system: "Reply in one short sentence.",
                    messages: [(role: "user", text: "Say hello in Vietnamese.")],
                    temperature: nil, timeout: 20)
                testResult = "✅ OK: \(r)"
            } catch {
                testResult = "❌ \(error.localizedDescription)"
            }
            testing = false
        }
    }
}

struct AIModelPicker: View {
    let models: [String]
    let current: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var shown: [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? models : models.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(shown, id: \.self) { m in
                Button {
                    onPick(m)
                    dismiss()
                } label: {
                    HStack {
                        Text(m).font(.system(.callout, design: .monospaced)).foregroundStyle(.primary)
                        Spacer()
                        if m == current { Image(systemName: "checkmark").foregroundStyle(.green) }
                    }
                }
            }
            .searchable(text: $search, prompt: "Tìm model")
            .navigationTitle("Chọn model (\(models.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
}
