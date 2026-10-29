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
    var snapshot: (text: String, at: Date)?
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
    @State private var job: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var primary: AIConfig? { AIStore.active().first }

    var body: some View {
        VStack(spacing: 0) {
            header
            if AIStore.active().isEmpty {
                emptyState
            } else {
                messagesView
                inputBar
            }
        }
        .background(AIStyle.bg.ignoresSafeArea())
        .sheet(isPresented: $showQuick, onDismiss: { tick += 1 }) {
            AIQuickSheet(openSettings: { showQuick = false; showProviders = true })
        }
        .sheet(isPresented: $showProviders, onDismiss: { tick += 1 }) {
            NavigationStack { AIProviderListView() }
        }
    }

    // Đầu khung: nền xanh chuyển màu, vòng tròn mờ góc phải, avatar gấu, tiêu đề + dòng phụ, nút xoá hội thoại và nút đóng (giống Dodo AI)
    private var header: some View {
        HStack(spacing: 12) {
            DodoAvatar(size: 46)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 3))
            Button { showQuick = true } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trợ lý AI").font(.system(size: 17, weight: .bold)).foregroundStyle(Color.white)
                    Text(primary.map { "\($0.id.shortName) · \($0.model)" } ?? "Chạm để chọn AI")
                        .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .id(tick)
            Spacer(minLength: 4)
            Button { session.messages.removeAll() } label: {
                Image(systemName: "trash").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(session.messages.isEmpty)
            .opacity(session.messages.isEmpty ? 0.5 : 1)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(AIStyle.blue2)
                    .frame(width: 36, height: 36)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: Color(red: 28 / 255, green: 40 / 255, blue: 90 / 255).opacity(0.25), radius: 4, y: 2)
            }
        }
        .padding(.leading, 18).padding(.trailing, 16).padding(.vertical, 16)
        .background(
            ZStack(alignment: .topTrailing) {
                AIStyle.gradient
                Circle().fill(Color.white.opacity(0.1)).frame(width: 160, height: 160).offset(x: 40, y: -60)
            }
            .clipped()
            .ignoresSafeArea(edges: .top)
        )
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            DodoAvatar(size: 110)
                .shadow(color: AIStyle.blue1.opacity(0.25), radius: 10, y: 8)
            Text("Xin chào! Mình là trợ lý AI của DESM. Bạn cần hỏi gì?")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(red: 107 / 255, green: 112 / 255, blue: 144 / 255))
                .multilineTextAlignment(.center)
            if model.aiData || model.aiTools || model.aiAll {
                Text((model.aiAll ? "Dữ liệu DESM được tải sẵn. " : "") + (model.aiTools ? "AI sẽ tự tra dữ liệu DESM khi cần. " : "") + (model.aiData ? "Dữ liệu trang đang mở sẽ được gửi kèm." : ""))
                    .font(.system(size: 12)).foregroundStyle(Color(red: 138 / 255, green: 143 / 255, blue: 176 / 255))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 50).padding(.horizontal, 30)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            DodoAvatar(size: 90)
            Text("Chưa có nhà cung cấp AI nào").font(.system(size: 16, weight: .bold)).foregroundStyle(AIStyle.text)
            Text("Nhập API key của một nhà (Gemini, Groq, Claude, OpenAI, DeepSeek, Mistral, OpenRouter…) để chat.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { showProviders = true } label: {
                Text("Nhập API key").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.white)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(AIStyle.gradient, in: Capsule())
            }
        }
        .padding(30)
        .frame(maxHeight: .infinity)
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if session.messages.isEmpty { welcome }
                    ForEach(session.messages) { m in bubble(m).id(m.id) }
                    if sending {
                        HStack(alignment: .top, spacing: 10) {
                            DodoAvatar(size: 28)
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text(status.isEmpty ? "Đang trả lời…" : status)
                                    .font(.system(size: 13)).foregroundStyle(Color(red: 138 / 255, green: 143 / 255, blue: 176 / 255))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(AIStyle.aiBubble(CornerShape(tl: 4, tr: 18, br: 18, bl: 18)))
                            Spacer(minLength: 20)
                        }
                        .id("typing")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 18)
            }
            .onChange(of: session.messages) { _ in
                if let last = session.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: sending) { s in if s { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
        }
    }

    private func bubble(_ m: AIChatMessage) -> some View {
        let mine = m.role == "user"
        return HStack(alignment: .top, spacing: 10) {
            if mine {
                Spacer(minLength: 40)
                Text(m.text)
                    .font(.system(size: 15)).lineSpacing(3)
                    .foregroundStyle(Color.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(AIStyle.gradient.clipShape(CornerShape(tl: 18, tr: 18, br: 4, bl: 18)))
            } else {
                DodoAvatar(size: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.text)
                        .font(.system(size: 15)).lineSpacing(4)
                        .foregroundStyle(m.isError ? Color.red : AIStyle.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(AIStyle.aiBubble(CornerShape(tl: 4, tr: 18, br: 18, bl: 18)))
                    if !m.by.isEmpty {
                        Text(m.by).font(.system(size: 10)).foregroundStyle(Color(red: 138 / 255, green: 143 / 255, blue: 176 / 255))
                            .padding(.leading, 4)
                    }
                }
                Spacer(minLength: 24)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Hỏi AI bất cứ điều gì", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .font(.system(size: 16))
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(focused ? Color.white : Color(red: 241 / 255, green: 242 / 255, blue: 249 / 255))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(focused ? Color(red: 127 / 255, green: 155 / 255, blue: 240 / 255) : Color.clear, lineWidth: 1)
                )
            Button {
                if sending { job?.cancel(); job = nil; sending = false; status = "" } else { send() }
            } label: {
                Image(systemName: sending ? "stop.fill" : "paperplane")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AIStyle.gradient))
                    .shadow(color: AIStyle.blue1.opacity(0.4), radius: 6, y: 4)
                    .opacity((sending || canSend) ? 1 : 0.45)
            }
            .disabled(!sending && !canSend)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        .background(Color.white.ignoresSafeArea(edges: .bottom))
        .overlay(Rectangle().fill(Color(red: 235 / 255, green: 236 / 255, blue: 245 / 255)).frame(height: 1), alignment: .top)
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
        job = Task { @MainActor in
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
            if model.aiAll {
                if let s = session.snapshot, Date().timeIntervalSince(s.at) < 300 {
                    system += "\n\n" + s.text
                } else {
                    status = "Đang tải dữ liệu DESM…"
                    let snap = await DesmAITools.snapshotAll(model: model, budget: max(model.aiLimit, 40000),
                                                             status: { s in status = s })
                    if !snap.isEmpty {
                        session.snapshot = (snap, Date())
                        system += "\n\n" + snap
                    }
                }
            }
            if model.aiTools {
                system += """


                You can look up DESM data with tools (read-only; you cannot change anything). Use desm_query with the \
                right endpoint: packages /getIdsmOsSummaryList.do, detail items of a package /getIdsmOsDetailList.do, \
                RSI/MRF/WIP lists, vessels, notices. If unsure which endpoint, call desm_list_endpoints first; \
                desm_recorded_endpoints shows other APIs the user has used; desm_read_open_page reads the screen that is \
                open now. PROJECT_NO is filled automatically. Filter narrowly and call tools several times if needed. \
                Answer from tool results only and quote package/material numbers; if a result says it was truncated, \
                narrow the filter and ask again. \
                Notes from real traffic: a package list (\"lô hàng\" / packing list, e.g. 0009) is filtered with \
                PACKAGE_LIST_NO=0009 (partial match works) on /getIdsmOsSummaryList.do — one returned row = one package \
                (kiện, PACKAGE_NO like OM4-DE-IS-0009-001); count the rows to answer \"có bao nhiêu kiện\". Items inside \
                one package: /getIdsmOsDetailList.do with PACKAGE_NO=<full package no> and QTY_TYPE=rsi.
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
                let stopped = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                session.messages.append(AIChatMessage(role: "model",
                                                      text: stopped ? "Đã dừng hoặc quá thời gian chờ. Thử lại hoặc hỏi ngắn gọn hơn." : "Lỗi: \(error.localizedDescription)",
                                                      isError: true))
            }
            status = ""
            sending = false
            job = nil
        }
        // Chốt chặn: quá 150 giây thì tự huỷ để không treo khung chat
        let current = job
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000_000)
            current?.cancel()
        }
    }
}

// MARK: - Giao diện giống Dodo AI (màu và bo góc lấy từ Dodo.js của web DESM)

enum AIStyle {
    static let blue1 = Color(red: 78 / 255, green: 115 / 255, blue: 223 / 255)    // #4e73df
    static let blue2 = Color(red: 34 / 255, green: 74 / 255, blue: 190 / 255)     // #224abe
    static let bg = Color(red: 246 / 255, green: 248 / 255, blue: 251 / 255)      // #f6f8fb
    static let text = Color(red: 58 / 255, green: 63 / 255, blue: 92 / 255)       // #3a3f5c
    static let border = Color(red: 232 / 255, green: 234 / 255, blue: 245 / 255)  // #e8eaf5
    static var gradient: LinearGradient {
        LinearGradient(colors: [blue1, blue2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func aiBubble(_ shape: CornerShape) -> some View {
        shape.fill(Color.white)
            .overlay(shape.stroke(border, lineWidth: 1))
            .shadow(color: Color(red: 28 / 255, green: 40 / 255, blue: 90 / 255).opacity(0.05), radius: 4, y: 2)
    }
}

/// Hình chữ nhật bo từng góc riêng (trái-trên, phải-trên, phải-dưới, trái-dưới)
struct CornerShape: Shape {
    var tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let tl = min(self.tl, min(w, h) / 2), tr = min(self.tr, min(w, h) / 2)
        let br = min(self.br, min(w, h) / 2), bl = min(self.bl, min(w, h) / 2)
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Avatar gấu của Dodo (tải từ web DESM; nếu chưa tải được thì hiện biểu tượng).
struct DodoAvatar: View {
    var size: CGFloat
    var body: some View {
        AsyncImage(url: URL(string: BrowserModel.apiOrigin + "/resources/img/bear-assistant.png")) { phase in
            if let img = phase.image {
                img.resizable().scaledToFill()
            } else {
                Image(systemName: "sparkles").resizable().scaledToFit()
                    .padding(size * 0.25).foregroundStyle(AIStyle.blue1)
            }
        }
        .frame(width: size, height: size)
        .background(Color(red: 219 / 255, green: 229 / 255, blue: 251 / 255))
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: size > 40 ? 0 : 2))
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
