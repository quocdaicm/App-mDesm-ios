// AIChatView.swift — khung chat với AI riêng (dùng khi Cài đặt > Trợ lý AI chọn "AI riêng").
// Mở từ bong bóng Dodo. Có thể gửi kèm dữ liệu kiện đang hiển thị (nếu bật) và đổi nhà/model ngay trong khung.

import SwiftUI

struct AIChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String      // "user" | "model"
    var text: String
    var by: String = ""
    var isError = false
}

/// Giữ hội thoại khi đóng/mở lại khung chat (chỉ trong lúc app còn chạy).
final class AIChatSession: ObservableObject {
    static let shared = AIChatSession()
    @Published var messages: [AIChatMessage] = []
}

struct AIChatView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var session = AIChatSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var sending = false
    @State private var showProviders = false
    @State private var showQuick = false
    @State private var tick = 0
    @State private var status = ""
    @FocusState private var focused: Bool

    private var primary: AIConfig? { AIStore.active().first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if AIStore.active().isEmpty {
                    emptyState
                } else {
                    messagesView
                    inputBar
                }
            }
            .navigationTitle("Trợ lý AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showQuick = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: primary?.id.icon ?? "sparkles")
                            Text(primary.map { "\($0.id.shortName) · \($0.model)" } ?? "Chọn AI")
                                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }
                    }
                    .id(tick)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button { session.messages.removeAll() } label: { Image(systemName: "trash") }
                            .disabled(session.messages.isEmpty)
                        Button("Xong") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showQuick, onDismiss: { tick += 1 }) {
                AIQuickSheet(openSettings: { showQuick = false; showProviders = true })
            }
            .sheet(isPresented: $showProviders, onDismiss: { tick += 1 }) {
                NavigationStack { AIProviderListView() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 38)).foregroundStyle(Color.tabBlue)
            Text("Chưa có nhà cung cấp AI nào").font(.headline)
            Text("Nhập API key của một nhà (Gemini, Groq, Claude, OpenAI, DeepSeek, Mistral, OpenRouter…) để chat.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Nhập API key") { showProviders = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(maxHeight: .infinity)
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if session.messages.isEmpty {
                        Text("Hỏi bất cứ điều gì" + (model.aiData ? (model.aiTools ? ". AI sẽ tự tra dữ liệu DESM khi cần." : ".") + (model.aiData ? " Dữ liệu trang đang mở sẽ được gửi kèm." : "") : "."))
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(.top, 40).padding(.horizontal, 30).multilineTextAlignment(.center)
                    }
                    ForEach(session.messages) { m in bubble(m).id(m.id) }
                    if sending {
                        HStack { ProgressView(); Text(status.isEmpty ? "Đang trả lời…" : status).font(.footnote).foregroundStyle(.secondary); Spacer() }
                            .padding(.horizontal, 16).id("typing")
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: session.messages) { _ in
                if let last = session.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: sending) { s in if s { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
        }
    }

    private func bubble(_ m: AIChatMessage) -> some View {
        let mine = m.role == "user"
        return HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 3) {
                Text(m.text)
                    .font(.system(size: 15))
                    .foregroundStyle(mine ? Color.white : (m.isError ? Color.red : Color.primary))
                    .textSelection(.enabled)
                if !mine && !m.by.isEmpty {
                    Text(m.by).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(mine ? Color.tabBlue : Color.secondary.opacity(0.14)))
            if !mine { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Hỏi AI…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.secondary.opacity(0.12)))
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.tabBlue : Color.secondary.opacity(0.4))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool { !sending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !sending else { return }
        input = ""
        session.messages.append(AIChatMessage(role: "user", text: q))
        sending = true
        let history = session.messages.filter { !$0.isError }.suffix(20).map { (role: $0.role, text: $0.text) }
        let providers = AIStore.active()
        Task { @MainActor in
            var system = """
            You are an AI assistant inside DESM Mobile, an iOS app for the DESM web system of Doosan Enerbility \
            (material, package, packing list, RSI/MRR/MRF documents, vessel tracking). Be concise and practical. \
            Answer in Vietnamese unless the user writes in another language. Do not invent data; if the page data \
            below does not contain the answer, say so (the user may need to open the right screen or load more rows).
            """
            if model.aiData {
                let screen = await model.fetchScreenTextForAI()
                if !screen.isEmpty { system += "\n\n" + screen }
            }
            if model.aiTools {
                system += """


                You can look up DESM data with tools (read-only; you cannot change anything). Use desm_query with the \
                right endpoint: packages /getIdsmOsSummaryList.do, detail items of a package /getIdsmOsDetailList.do, \
                RSI/MRF/WIP lists, vessels, notices. If unsure which endpoint, call desm_list_endpoints first; \
                desm_recorded_endpoints shows other APIs the user has used; desm_read_open_page reads the screen that is \
                open now. PROJECT_NO is filled automatically. Filter narrowly and call tools several times if needed. \
                Answer from tool results only and quote package/material numbers; if a result says it was truncated, \
                narrow the filter and ask again.
                """
            }
            status = ""
            do {
                let r: (text: String, by: AIConfig)
                if model.aiTools {
                    r = try await AIClient.runAgent(providers, system: system, messages: history,
                                                    tools: DesmAITools.defs(),
                                                    exec: { n, a in await DesmAITools.run(n, a, model: model) },
                                                    status: { s in Task { @MainActor in status = s } })
                } else {
                    r = try await AIClient.run(providers, system: system, messages: history)
                }
                session.messages.append(AIChatMessage(role: "model", text: r.text,
                                                      by: "\(r.by.id.shortName) · \(r.by.model)"))
            } catch {
                session.messages.append(AIChatMessage(role: "model", text: "Lỗi: \(error.localizedDescription)", isError: true))
            }
            sending = false
        }
    }
}

/// Đổi nhanh nhà cung cấp (đứng đầu thứ tự ưu tiên) và model ngay trong khung chat.
struct AIQuickSheet: View {
    var openSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var order = AIStore.order()
    @State private var tick = 0
    @State private var loading: AIProvider?
    @State private var pickerFor: AIProvider?
    @State private var models: [String] = []
    @State private var message = ""

    private var ready: [AIProvider] { order.filter { AIStore.config($0) != nil } }

    var body: some View {
        NavigationStack {
            List {
                if ready.isEmpty {
                    Section {
                        Text("Chưa có nhà cung cấp AI nào. Vào Cài đặt AI để nhập API key.").font(.footnote)
                    }
                } else {
                    Section {
                        ForEach(Array(ready.enumerated()), id: \.element) { idx, p in row(p, primary: idx == 0) }
                    } header: {
                        Text("Bấm vào nhà cung cấp để dùng trước")
                    } footer: {
                        Text("Nhà đứng đầu được dùng trước; nếu lỗi, app tự chuyển sang nhà kế tiếp.")
                    }
                    if !message.isEmpty { Section { Text(message).font(.footnote).foregroundStyle(.orange) } }
                }
                Section {
                    Button { openSettings() } label: { Label("Cài đặt AI (key, model)", systemImage: "gearshape") }
                }
            }
            .id(tick)
            .navigationTitle("Mô hình AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Xong") { dismiss() } } }
        }
        .sheet(item: $pickerFor) { p in
            AIModelPicker(models: models, current: AIStore.model(p)) { m in
                AIStore.setModel(p, m)
                makePrimary(p)
            }
        }
    }

    private func row(_ p: AIProvider, primary: Bool) -> some View {
        HStack(spacing: 12) {
            Button { makePrimary(p) } label: {
                HStack(spacing: 12) {
                    Image(systemName: p.icon).foregroundStyle(p.color).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.shortName).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.primary)
                        Text(AIStore.model(p)).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if primary { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { loadModels(p) } label: {
                if loading == p { ProgressView() } else {
                    Text("Đổi model").font(.system(.caption, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(loading != nil)
        }
    }

    private func makePrimary(_ p: AIProvider) {
        var o = AIStore.order()
        o.removeAll { $0 == p }
        o.insert(p, at: 0)
        AIStore.saveOrder(o)
        order = o
        tick += 1
    }

    private func loadModels(_ p: AIProvider) {
        guard let cfg = AIStore.config(p) else { return }
        loading = p
        message = ""
        Task {
            do {
                models = try await AIClient.listModels(cfg)
                pickerFor = p
            } catch {
                message = "Không dò được danh sách model của \(p.shortName): \(error.localizedDescription). Có thể nhập tên model trong Cài đặt AI."
            }
            loading = nil
        }
    }
}
