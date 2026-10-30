// AIChatView.swift — khung chat native của "AI riêng" (mở khi chạm bong bóng nếu chọn AI riêng).
// Hội thoại giữ trong bộ nhớ (AIChatSession.shared); lịch sử gửi lại cho AI chỉ gồm câu hỏi + câu trả lời chữ (không kèm dữ liệu tra cứu cũ).
// Cố ý KHÔNG dùng textSelection / AsyncImage / animation cuộn / LazyVStack để tránh treo layout khi tin nhắn dài. Chưa build/chưa thử trên máy thật.

import SwiftUI

struct AIPlainTurn {
    let isUser: Bool
    let text: String
}

struct AIChatLine: Identifiable, Equatable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

enum AITheme {
    static let blue1 = Color(red: 0x4e / 255, green: 0x73 / 255, blue: 0xdf / 255)
    static let blue2 = Color(red: 0x22 / 255, green: 0x4a / 255, blue: 0xbe / 255)
}

/// Một bong bóng tin nhắn. Equatable + `.equatable()` để SwiftUI KHÔNG tính lại bố cục các tin cũ mỗi lần khung chat vẽ lại.
struct AIBubbleView: View, Equatable {
    let line: AIChatLine

    var body: some View {
        HStack {
            if line.isUser { Spacer(minLength: 40) }
            Text(verbatim: line.text)
                .font(.body)
                .foregroundColor(line.isUser ? .white : .primary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(line.isUser ? AnyView(LinearGradient(colors: [AITheme.blue1, AITheme.blue2], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyView(Color.white))
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(line.isUser ? Color.clear : Color(red: 0.91, green: 0.92, blue: 0.96), lineWidth: 1))
                .contextMenu { Button("Sao chép") { UIPasteboard.general.string = line.text } }
            if !line.isUser { Spacer(minLength: 40) }
        }
    }
}

/// Dòng "đang xử lý": tự đếm giây (chỉ riêng view này được vẽ lại mỗi giây) để biết app chưa treo mà đang chờ.
struct AIBusyRow: View {
    let status: String
    let since: Date

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            TimelineView(.periodic(from: since, by: 1)) { ctx in
                Text((status.isEmpty ? "Đang xử lý…" : status) + " · " + String(max(0, Int(ctx.date.timeIntervalSince(since)))) + "s")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }
}

@MainActor
final class AIChatSession: ObservableObject {
    static let shared = AIChatSession()

    @Published var lines: [AIChatLine] = []
    @Published var busy = false
    @Published var status = ""
    @Published var busySince = Date()
    private var turns: [AIPlainTurn] = []     // lịch sử chỉ chữ: dùng được cho mọi nhà AI (mỗi nhà định dạng khác nhau)
    private var task: Task<Void, Never>? = nil
    private var runTag = ""

    private func endRunWatch() {
        if !runTag.isEmpty { AIWatchdog.shared.release(runTag); runTag = "" }
    }

    func clear() {
        endRunWatch()
        task?.cancel()
        task = nil
        lines = []
        turns = []
        busy = false
        status = ""
        AILog.add("Người dùng xoá hội thoại")
    }

    func stop() {
        endRunWatch()
        task?.cancel()
        task = nil
        busy = false
        status = ""
        lines.append(AIChatLine(isUser: false, text: "(Đã dừng.)"))
        AILog.add("✋ Người dùng bấm dừng")
    }

    private func append(_ l: AIChatLine) {
        lines.append(l)
        if lines.count > 150 { lines.removeFirst(lines.count - 150) }    // tin quá cũ không cần giữ trên màn hình
    }

    static func systemPrompt(tools: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy/MM/dd"
        var s = "Bạn là trợ lý trong app DESM Mobile (hệ thống quản lý vật tư, kiện hàng DESM của Doosan Enerbility). Hôm nay là " + f.string(from: Date()) + ". "
        s += "Trả lời bằng tiếng Việt, ngắn gọn, đúng số liệu. Không bịa: nếu không có dữ liệu thì nói rõ.\n"
        if tools {
            s += "Bạn có công cụ CHỈ ĐỌC để tra dữ liệu thật của DESM. Với câu hỏi về dữ liệu, hãy tra trước rồi mới trả lời; được gọi nhiều lần.\n"
            s += "Nếu chưa biết endpoint hay tham số, gọi desm_list_endpoints. Tra dữ liệu bằng desm_query(endpoint, params_json, max_rows); params_json là CHUỖI JSON, ví dụ {\"PACKAGE_NO\":\"0009-001\"}.\n"
            s += "Số kiện (Package No) có dạng 0009-001. Vị trí kho của kiện là trường STORAGE_LOCATION trong /getIdsmOsSummaryList.do; vị trí từng hạng mục là LOCATION trong /getIdsmOsDetailList.do. Ngày dạng yyyy/MM/dd.\n"
            s += "desm_read_open_page đọc nội dung màn đang mở trên app, dùng khi người dùng hỏi về 'màn này', 'trang này', 'đang hiển thị'.\n"
            s += "Nếu kết quả bị cắt thì thu hẹp bộ lọc hoặc tăng max_rows, và nói rõ khi số liệu chưa đầy đủ."
        } else {
            s += "Bạn không có quyền truy cập dữ liệu DESM; chỉ trả lời kiến thức chung và hướng dẫn thao tác."
        }
        return s
    }

    private func plainMsgs(kind: AIKind) -> [AIMsg] {
        var out: [AIMsg] = []
        for t in turns {
            if t.isUser { out.append(.user(t.text)) } else { out.append(.assistant(AITurn.plain(t.text, kind: kind))) }
        }
        return out
    }

    func send(_ text: String, model: BrowserModel) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty || busy { return }
        append(AIChatLine(isUser: true, text: q))
        let cands = AIStore.candidates()
        if cands.isEmpty {
            let p = AIStore.active
            append(AIChatLine(isUser: false, text: "Chưa dùng được " + p.name + " (thiếu khoá API hoặc model). Vào Cài đặt > Trợ lý Dodo > AI riêng để nhập khoá, hoặc đổi nhà AI ở đầu khung này."))
            return
        }
        let useTools = AIStore.toolsOn
        busy = true
        busySince = Date()
        status = "Đang suy nghĩ…"
        AILog.step("Gửi câu hỏi (" + String(q.count) + " ký tự) · thứ tự thử: " + cands.map { $0.name }.joined(separator: " → ") + " · tra DESM " + (useTools ? "bật" : "tắt"))
        let tag = "run-" + UUID().uuidString
        runTag = tag
        AIWatchdog.shared.hold(tag)
        task = Task { [weak self] in
            defer { AIWatchdog.shared.release(tag) }
            guard let me = self else { return }
            var failures: [String] = []
            for (i, p) in cands.enumerated() {
                if Task.isCancelled { return }
                let key = AIStore.key(p.id)
                let modelName = AIStore.model(p)
                if i > 0 {
                    me.status = "Chuyển sang " + p.name + "…"
                    AILog.step("↪︎ Chuyển sang " + p.name + " · " + modelName + " (nhà trước lỗi)")
                }
                var msgs = me.plainMsgs(kind: p.kind)
                msgs.append(.user(q))
                // Thử model đã chọn; nếu model sai/không có thì thử model mặc định của nhà; đứt mạng/5xx thì thử lại 1 lần; sau đó mới sang nhà khác
                var tryModels = [modelName]
                if !p.defaultModel.isEmpty && p.defaultModel != modelName { tryModels.append(p.defaultModel) }
                var mi = 0
                var retried = false
                var lastErr: Error? = nil
                var answer: String? = nil
                while mi < tryModels.count && answer == nil {
                    do {
                        answer = try await AIAgent.run(
                            provider: p, key: key, model: tryModels[mi],
                            system: AIChatSession.systemPrompt(tools: useTools),
                            history: msgs, tools: useTools ? DesmAITools.toolDefs : [],
                            exec: { (name: String, args: [String: Any]) async -> String in
                                return await model.runDesmTool(name, args)
                            },
                            status: { (s: String) in
                                Task { @MainActor in me.status = s }
                            },
                            budget: i == 0 ? 180 : 90)
                    } catch {
                        if error is CancellationError || Task.isCancelled { return }
                        lastErr = error
                        if AIStore.isTransient(error) && !retried {
                            retried = true
                            AILog.add("↻ " + p.name + " mất kết nối tạm thời → thử lại sau 1,5 giây")
                            me.status = "Mất kết nối " + p.name + ", đang thử lại…"
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            continue
                        }
                        if AIStore.isBadModel(error) && mi + 1 < tryModels.count {
                            AILog.add("↪︎ Model " + tryModels[mi] + " lỗi → thử model mặc định " + tryModels[mi + 1])
                            me.status = "Model " + tryModels[mi] + " không dùng được, thử " + tryModels[mi + 1] + "…"
                            mi += 1
                            continue
                        }
                        break
                    }
                }
                if Task.isCancelled { return }
                if let ans = answer {
                    AIStore.clearFailed(p.id)
                    var shown = ans
                    var notes = failures
                    if mi > 0 { notes.append("model " + tryModels[0] + " không dùng được, đã dùng " + tryModels[mi]) }
                    if !notes.isEmpty {
                        let head: String = failures.isEmpty ? "Đã tự đổi model" : "Đã tự chuyển sang " + p.name
                        let detail: String = notes.joined(separator: "; ")
                        shown = "↪︎ " + head + " (" + detail + ").\n\n" + ans
                    }
                    me.append(AIChatLine(isUser: false, text: shown))
                    me.turns.append(AIPlainTurn(isUser: true, text: q))
                    me.turns.append(AIPlainTurn(isUser: false, text: ans))
                    if me.turns.count > 12 { me.turns.removeFirst(me.turns.count - 12) }
                    me.busy = false
                    me.status = ""
                    return
                }
                AIStore.markFailed(p.id)
                let why = String((lastErr?.localizedDescription ?? "không rõ").prefix(110))
                failures.append(p.name + " lỗi: " + why)
                AILog.add("✗ " + p.name + " thất bại: " + why + (i + 1 < cands.count ? " → thử nhà kế tiếp" : ""))
            }
            me.append(AIChatLine(isUser: false, text: "⚠️ " + (failures.count > 1 ? "Tất cả nhà AI đều lỗi:\n" : "") + failures.joined(separator: "\n")))
            me.busy = false
            me.status = ""
        }
    }
}

struct AIChatView: View {
    // CỐ Ý không dùng @ObservedObject cho model: BrowserModel phát thay đổi liên tục (progress, tiêu đề, trạng thái tải trang…),
    // mỗi lần như vậy cả khung chat bị vẽ lại → giật/treo. Khung chat chỉ cần gọi model.runDesmTool nên giữ tham chiếu thường.
    let model: BrowserModel
    @ObservedObject private var session = AIChatSession.shared
    var onClose: () -> Void

    @State private var input = ""
    @State private var tick = 0     // ép vẽ lại khi đổi nhà AI
    @State private var showLog = false
    @State private var showModels = false

    private let blue1 = AITheme.blue1
    private let blue2 = AITheme.blue2

    var body: some View {
        let _ = AILog.render("AIChatView")
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if session.lines.isEmpty { hint }
                        ForEach(session.lines) { l in
                            AIBubbleView(line: l).equatable().id(l.id)
                        }
                        if session.busy {
                            AIBusyRow(status: session.status, since: session.busySince)
                                .id("busy")
                        }
                    }
                    .padding(14)
                }
                .onChange(of: session.lines.last?.id) { _ in scrollEnd(proxy) }
                .onChange(of: session.busy) { _ in scrollEnd(proxy) }
            }
            inputBar
        }
        .background(Color(red: 0.97, green: 0.97, blue: 0.99))
        .onAppear {
            AILog.add("Mở khung chat AI (" + String(session.lines.count) + " tin)")
            AIWatchdog.shared.hold("view")
        }
        .onDisappear {
            AILog.add("Đóng khung chat AI")
            AIWatchdog.shared.release("view")
        }
        .sheet(isPresented: $showLog) {
            AILogView()
        }
        .sheet(isPresented: $showModels, onDismiss: { tick += 1 }) {
            AIModelPickerView(provider: AIStore.active)
        }
    }

    private func scrollEnd(_ proxy: ScrollViewProxy) {
        if session.busy { proxy.scrollTo("busy", anchor: .bottom) }
        else if let last = session.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private var header: some View {
        let p = AIStore.active
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Trợ lý AI").font(.title3.bold()).foregroundColor(.white)
                HStack(spacing: 6) {
                    Menu {
                        ForEach(AIProvider.all) { q in
                            Button((AIStore.key(q.id).isEmpty ? "○ " : "● ") + q.name) { AIStore.activeID = q.id; tick += 1 }
                        }
                    } label: {
                        Text(p.name + " ▾").font(.footnote.bold()).foregroundColor(Color.white.opacity(0.95)).lineLimit(1)
                    }
                    Button { showModels = true } label: {
                        Text(AIStore.model(p) + (AIStore.toolsOn ? " · tra DESM" : "") + " ▾")
                            .font(.footnote).foregroundColor(Color.white.opacity(0.9)).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.18)).cornerRadius(8)
                    }
                }
            }
            Spacer()
            Button { showLog = true } label: {
                Image(systemName: "ladybug").foregroundColor(.white)
                    .frame(width: 40, height: 40).background(Color.white.opacity(0.18)).cornerRadius(12)
            }
            Button { session.clear() } label: {
                Image(systemName: "trash").foregroundColor(.white)
                    .frame(width: 40, height: 40).background(Color.white.opacity(0.18)).cornerRadius(12)
            }
            Button { onClose() } label: {
                Image(systemName: "xmark").foregroundColor(blue2)
                    .frame(width: 40, height: 40).background(Color.white).cornerRadius(12)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(LinearGradient(colors: [blue1, blue2], startPoint: .topLeading, endPoint: .bottomTrailing))
        .id(tick)
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hỏi về dữ liệu DESM").font(.headline)
            Text("Ví dụ: \"kiện 0009-001 vị trí ở đâu\", \"hạng mục thiếu của kiện 0009-001\", \"RSI tuần này\", \"MRF đã trả hôm nay\".")
                .font(.footnote).foregroundColor(.secondary)
            Text("Câu hỏi và dữ liệu AI tra được sẽ được gửi tới nhà AI bạn chọn (không phải máy chủ DESM). Chỉ dùng khi công ty cho phép.")
                .font(.caption).foregroundColor(.orange)
        }
        .padding(12)
        .background(Color.white).cornerRadius(14)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Hỏi về dữ liệu DESM…", text: $input)
                .submitLabel(.send)
                .onSubmit { sendNow() }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color(red: 0.945, green: 0.949, blue: 0.976)).cornerRadius(22)
            Button {
                if session.busy { session.stop() } else { sendNow() }
            } label: {
                Image(systemName: session.busy ? "stop.fill" : "paperplane.fill").foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [blue1, blue2], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white)
    }

    private func sendNow() {
        let t = input
        input = ""
        session.send(t, model: model)
    }
}
