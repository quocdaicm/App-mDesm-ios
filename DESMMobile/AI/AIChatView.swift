// AIChatView.swift — khung chat native của "AI riêng" (mở khi chạm bong bóng nếu chọn AI riêng).
// Hội thoại giữ trong bộ nhớ (AIChatSession.shared); lịch sử gửi lại cho AI chỉ gồm câu hỏi + câu trả lời chữ (không kèm dữ liệu tra cứu cũ).
// Cố ý KHÔNG dùng textSelection / AsyncImage / animation cuộn / LazyVStack để tránh treo layout khi tin nhắn dài. Chưa build/chưa thử trên máy thật.

import SwiftUI
import Speech
import AVFoundation
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

struct AIPlainTurn: Codable {
    let isUser: Bool
    let text: String
}

struct AIChatLine: Identifiable, Equatable, Codable {
    var id = UUID()
    let isUser: Bool
    let text: String
}

/// Một cuộc trò chuyện đã lưu (giống danh sách chat của Dodo).
struct AIConversation: Codable, Identifiable {
    var id = UUID()
    var title = "Cuộc trò chuyện mới"
    var updated = Date()
    var lines: [AIChatLine] = []
    var turns: [AIPlainTurn] = []
}

/// Lưu lịch sử chat AI riêng vào tệp JSON trong thư mục Application Support của app (chỉ nằm trên máy này).
enum AIChatStore {
    static let maxChats = 40
    static var fileURL: URL {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        return dir.appendingPathComponent("DESMAIChats.json")
    }
    static func load() -> [AIConversation] {
        guard let d = try? Data(contentsOf: fileURL), let l = try? JSONDecoder().decode([AIConversation].self, from: d) else { return [] }
        return l
    }
    static func save(_ l: [AIConversation]) {
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            if let d = try? JSONEncoder().encode(l) { try? d.write(to: url, options: .atomic) }
        }
    }
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

    @Published var lines: [AIChatLine] = [] { didSet { persistSoon() } }
    @Published var chats: [AIConversation] = []          // đã lưu, mới nhất trước
    @Published private(set) var currentID = UUID()
    @Published var busy = false
    @Published var status = ""
    @Published var busySince = Date()
    private var turns: [AIPlainTurn] = [] { didSet { persistSoon() } }    // lịch sử chỉ chữ: dùng được cho mọi nhà AI (mỗi nhà định dạng khác nhau)
    private var loading = false
    private var saveQueued = false

    init() {
        chats = AIChatStore.load().sorted { $0.updated > $1.updated }
        if let c = chats.first { open(c.id) }     // mở lại cuộc trò chuyện gần nhất
    }

    private func persistSoon() {
        if loading || saveQueued { return }
        saveQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.saveQueued = false
            self?.persistNow()
        }
    }

    private func title() -> String {
        let t = lines.first(where: { $0.isUser })?.text ?? "Cuộc trò chuyện"
        let first = t.components(separatedBy: "\n").first ?? t
        return String(first.prefix(40))
    }

    private func persistNow() {
        if lines.isEmpty { return }
        let c = AIConversation(id: currentID, title: title(), updated: Date(), lines: lines,
                               turns: turns.map { AIPlainTurn(isUser: $0.isUser, text: String($0.text.prefix(20000))) })
        chats.removeAll { $0.id == currentID }
        chats.insert(c, at: 0)
        if chats.count > AIChatStore.maxChats { chats.removeLast(chats.count - AIChatStore.maxChats) }
        AIChatStore.save(chats)
    }

    private func cancelRun() {
        endRunWatch()
        task?.cancel()
        task = nil
        busy = false
        status = ""
    }

    /// Tạo cuộc trò chuyện mới (cuộc hiện tại đã được lưu).
    func newChat() {
        if lines.isEmpty { return }
        cancelRun()
        persistNow()
        loading = true
        currentID = UUID()
        lines = []
        turns = []
        loading = false
        AILog.add("Tạo cuộc trò chuyện mới")
    }

    /// Mở lại một cuộc trò chuyện đã lưu.
    func open(_ id: UUID) {
        guard id != currentID, let c = chats.first(where: { $0.id == id }) else { return }
        cancelRun()
        persistNow()
        loading = true
        currentID = c.id
        lines = c.lines
        turns = c.turns
        loading = false
        AILog.add("Mở lại cuộc trò chuyện: " + c.title)
    }

    func delete(_ id: UUID) {
        chats.removeAll { $0.id == id }
        AIChatStore.save(chats)
        if id == currentID {
            cancelRun()
            loading = true
            currentID = UUID()
            lines = []
            turns = []
            loading = false
        }
    }
    private var task: Task<Void, Never>? = nil
    private var runTag = ""

    private func endRunWatch() {
        if !runTag.isEmpty { AIWatchdog.shared.release(runTag); runTag = "" }
    }

    func clear() {
        delete(currentID)
        AILog.add("Người dùng xoá cuộc trò chuyện")
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

    func send(_ text: String, attachments: [AIAttachment] = [], model: BrowserModel) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.isEmpty && attachments.isEmpty) || busy { return }
        let q = trimmed.isEmpty ? "Hãy xem phần đính kèm và tóm tắt nội dung chính." : trimmed
        // Tệp chữ chèn thẳng vào câu hỏi; ảnh gửi riêng
        var q2v = q
        var imgsV: [Data] = []
        var names: [String] = []
        for a in attachments {
            names.append(a.name)
            if let d = a.image { imgsV.append(d) }
            if let t = a.text { q2v += "\n\n--- Tệp: " + a.name + " ---\n" + t + "\n--- hết tệp ---" }
        }
        let q2 = q2v
        let imgs = imgsV
        let histText = q2 + (imgs.isEmpty ? "" : "\n[Lượt này có " + String(imgs.count) + " ảnh đính kèm, không giữ lại ở lượt sau]")
        append(AIChatLine(isUser: true, text: names.isEmpty ? q : q + "\n📎 " + names.joined(separator: ", ")))
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
                msgs.append(imgs.isEmpty ? .user(q2) : .userImages(q2, imgs))
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
                    me.turns.append(AIPlainTurn(isUser: true, text: histText))
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

// MARK: - Đính kèm ảnh / tệp để hỏi
/// Ảnh (JPEG đã thu nhỏ) gửi thẳng cho AI nhìn được; tệp chữ / PDF có chữ được đọc thành văn bản chèn vào câu hỏi.
struct AIAttachment: Identifiable {
    let id = UUID()
    let name: String
    var image: Data? = nil
    var text: String? = nil
    var preview: UIImage? = nil
}

enum AIAttach {
    static let maxItems = 6
    static let maxTextChars = 40000
    static let textExts: Set<String> = ["txt", "csv", "tsv", "json", "md", "log", "xml", "html", "htm", "yaml", "yml", "sql", "ini", "cfg", "js", "swift", "py"]
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"]

    /// Thu nhỏ cạnh dài về tối đa 1600px, JPEG 0.7 để gửi nhẹ.
    static func jpeg(_ img: UIImage, maxSide: CGFloat = 1600) -> Data? {
        let w = img.size.width, h = img.size.height
        guard w > 0, h > 0 else { return nil }
        let k = min(1, maxSide / max(w, h))
        let size = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = true
        let r = UIGraphicsImageRenderer(size: size, format: fmt)
        let out = r.image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        return out.jpegData(compressionQuality: 0.7)
    }

    static func image(_ img: UIImage, name: String) -> AIAttachment? {
        guard let d = jpeg(img) else { return nil }
        let thumb = jpeg(img, maxSide: 160).flatMap { UIImage(data: $0) }
        return AIAttachment(name: name, image: d, text: nil, preview: thumb)
    }

    static func image(data: Data, name: String) -> AIAttachment? {
        guard let u = UIImage(data: data) else { return nil }
        return image(u, name: name)
    }

    static func clip(_ s: String, _ name: String) -> String {
        if s.count <= maxTextChars { return s }
        return String(s.prefix(maxTextChars)) + "\n…(tệp " + name + " dài, chỉ gửi " + String(maxTextChars) + " ký tự đầu)"
    }

    /// Đọc một tệp người dùng chọn. Trả về các mục đính kèm + ghi chú (nếu có vấn đề).
    static func load(url: URL) -> (items: [AIAttachment], note: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if imageExts.contains(ext) {
            if let d = try? Data(contentsOf: url), let a = image(data: d, name: name) { return ([a], "") }
            return ([], "Không đọc được ảnh " + name + ".")
        }
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else { return ([], "Không mở được PDF " + name + ".") }
            let txt = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if txt.count > 30 {
                return ([AIAttachment(name: name + " (" + String(doc.pageCount) + " trang)", image: nil, text: clip(txt, name), preview: nil)], "")
            }
            // PDF dạng ảnh quét: không có chữ → chụp vài trang đầu thành ảnh cho AI đọc
            var items: [AIAttachment] = []
            for i in 0..<min(doc.pageCount, 3) {
                guard let page = doc.page(at: i) else { continue }
                let b = page.bounds(for: .mediaBox)
                let k = 1400 / max(b.width, b.height, 1)
                let img = page.thumbnail(of: CGSize(width: b.width * k, height: b.height * k), for: .mediaBox)
                if let a = image(img, name: name + " tr." + String(i + 1)) { items.append(a) }
            }
            return (items, items.isEmpty ? "PDF " + name + " không có chữ và không vẽ được trang." : (doc.pageCount > 3 ? "PDF quét ảnh: chỉ gửi 3 trang đầu của " + name + "." : ""))
        }
        guard let d = try? Data(contentsOf: url) else { return ([], "Không đọc được " + name + ".") }
        if d.count > 5_000_000 { return ([], name + " quá lớn (trên 5 MB).") }
        if textExts.contains(ext) || ext.isEmpty || d.prefix(2000).allSatisfy({ $0 != 0 }) {
            if let t = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) {
                return ([AIAttachment(name: name, image: nil, text: clip(t, name), preview: nil)], "")
            }
        }
        return ([], "Chưa đọc được định dạng ." + ext + " (" + name + "). Dùng ảnh, PDF hoặc tệp chữ (txt, csv, json…). Excel/Word: xuất ra CSV/PDF rồi gửi.")
    }
}

/// Mở camera chụp ảnh.
struct AICameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }

    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: AICameraPicker
        init(_ p: AICameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Hỏi bằng giọng nói (nhận dạng giọng nói của iOS, tiếng Việt)
/// Bấm mic để nói, câu nói hiện dần vào ô nhập; im lặng ~2,5 giây hoặc bấm mic lần nữa thì dừng. Không tự gửi: kiểm tra chữ rồi bấm gửi.
final class AIVoiceInput: NSObject, ObservableObject {
    @Published var listening = false
    @Published var error = ""
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var silence: Timer?
    private var onText: ((String) -> Void)?

    func toggle(onText: @escaping (String) -> Void) {
        if listening { stop(); return }
        self.onText = onText
        error = ""
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async {
                guard st == .authorized else { self.error = "Chưa cho phép nhận dạng giọng nói (Cài đặt > DESM Mobile)."; return }
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    DispatchQueue.main.async {
                        guard ok else { self.error = "Chưa cho phép micro (Cài đặt > DESM Mobile)."; return }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        let rec = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN")) ?? SFSpeechRecognizer()
        guard let r = rec, r.isAvailable else { error = "Máy chưa hỗ trợ nhận dạng giọng nói tiếng Việt lúc này."; return }
        recognizer = r
        do {
            let a = AVAudioSession.sharedInstance()
            try a.setCategory(.record, mode: .measurement, options: .duckOthers)
            try a.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            let fmt = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in req.append(buf) }
            engine.prepare()
            try engine.start()
            listening = true
            armSilence()
            task = r.recognitionTask(with: req) { [weak self] res, err in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let res = res {
                        self.onText?(res.bestTranscription.formattedString)
                        self.armSilence()
                        if res.isFinal { self.stop() }
                    }
                    if err != nil { self.stop() }
                }
            }
        } catch {
            self.error = "Không mở được micro: " + error.localizedDescription
            stop()
        }
    }

    private func armSilence() {
        silence?.invalidate()
        silence = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in self?.stop() }
    }

    func stop() {
        silence?.invalidate(); silence = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Danh sách các cuộc trò chuyện đã lưu: chạm để mở lại, vuốt trái để xoá, nút trên cùng tạo cuộc mới.
struct AIHistoryView: View {
    @ObservedObject var session: AIChatSession
    @Environment(\.dismiss) private var dismiss

    private static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        NavigationView {
            List {
                Button { session.newChat(); dismiss() } label: {
                    Label("Cuộc trò chuyện mới", systemImage: "square.and.pencil")
                }
                Section {
                    ForEach(session.chats) { c in
                        Button { session.open(c.id); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(c.title).font(.body).lineLimit(1)
                                    if c.id == session.currentID { Spacer(); Image(systemName: "checkmark").foregroundColor(.blue) }
                                }
                                Text(AIHistoryView.fmt(c.updated) + " · " + String(c.lines.count) + " tin")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .onDelete { idx in
                        let ids = idx.map { session.chats[$0].id }
                        for id in ids { session.delete(id) }
                    }
                } header: {
                    Text("Lịch sử (" + String(session.chats.count) + ")")
                } footer: {
                    Text("Lưu trên máy này, tối đa " + String(AIChatStore.maxChats) + " cuộc gần nhất. Vuốt trái để xoá.")
                }
            }
            .navigationTitle("Lịch sử chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Xong") { dismiss() } } }
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
    @State private var showHistory = false
    @FocusState private var inputFocused: Bool
    @StateObject private var voice = AIVoiceInput()
    @State private var attachments: [AIAttachment] = []
    @State private var attachNote = ""
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var photoItems: [PhotosPickerItem] = []

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
                .scrollDismissesKeyboard(.interactively)   // vuốt danh sách là tự hạ bàn phím
                .simultaneousGesture(TapGesture().onEnded { inputFocused = false })   // chạm vào tin chat là ẩn bàn phím
                .onChange(of: session.lines.last?.id) { _ in scrollEnd(proxy) }
                .onChange(of: session.busy) { _ in scrollEnd(proxy) }
                .onChange(of: session.currentID) { _ in DispatchQueue.main.async { scrollEnd(proxy, animated: false) } }
                .onChange(of: inputFocused) { f in
                    // bàn phím mở/đóng làm khung co giãn: giữ tin cuối trong tầm nhìn
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { scrollEnd(proxy) }
                }
                .onAppear {
                    // mở lại chat: tự trượt xuống tin cuối (thử lại sau khi bố cục xong)
                    DispatchQueue.main.async { scrollEnd(proxy, animated: false) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scrollEnd(proxy, animated: false) }
                }
            }
            if voice.listening || !voice.error.isEmpty {
                Text(voice.listening ? "🎙 Đang nghe… nói xong bấm mic để dừng" : voice.error)
                    .font(.caption).foregroundColor(voice.listening ? .red : .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .background(Color.white)
            }
            if !attachNote.isEmpty {
                Text(attachNote).font(.caption).foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 4).background(Color.white)
            }
            if !attachments.isEmpty { attachChips }
            inputBar
        }
        .fullScreenCover(isPresented: $showCamera) {
            AICameraPicker { img in addImage(img) }.ignoresSafeArea()
        }
        .background(Color(red: 0.97, green: 0.97, blue: 0.99))
        .onAppear {
            AILog.add("Mở khung chat AI (" + String(session.lines.count) + " tin)")
            AIWatchdog.shared.hold("view")
        }
        .onDisappear {
            voice.stop()
            AILog.add("Đóng khung chat AI")
            AIWatchdog.shared.release("view")
        }
        .sheet(isPresented: $showLog) {
            AILogView()
        }
        .sheet(isPresented: $showHistory) {
            AIHistoryView(session: session)
        }
        .sheet(isPresented: $showModels, onDismiss: { tick += 1 }) {
            AIModelPickerView(provider: AIStore.active)
        }
    }

    private func scrollEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let go: () -> Void = {
            if session.busy { proxy.scrollTo("busy", anchor: .bottom) }
            else if let last = session.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
        if animated { go() } else { var t = Transaction(); t.disablesAnimations = true; withTransaction(t, go) }
    }

    private var header: some View {
        let p = AIStore.active
        return HStack(spacing: 8) {
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
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath").foregroundColor(.white)
                    .frame(width: 36, height: 40).background(Color.white.opacity(0.18)).cornerRadius(12)
            }
            Button { session.newChat() } label: {
                Image(systemName: "square.and.pencil").foregroundColor(.white)
                    .frame(width: 36, height: 40).background(Color.white.opacity(0.18)).cornerRadius(12)
            }
            Menu {
                Button { showLog = true } label: { Label("Nhật ký lỗi", systemImage: "ladybug") }
                Button(role: .destructive) { session.clear() } label: { Label("Xoá cuộc trò chuyện này", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").foregroundColor(.white)
                    .frame(width: 36, height: 40).background(Color.white.opacity(0.18)).cornerRadius(12)
            }
            Button { onClose() } label: {
                Image(systemName: "xmark").foregroundColor(blue2)
                    .frame(width: 36, height: 40).background(Color.white).cornerRadius(12)
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
                .focused($inputFocused)
                .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in loadFiles(r) }
                .submitLabel(.send)
                .onSubmit { sendNow() }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color(red: 0.945, green: 0.949, blue: 0.976)).cornerRadius(22)
            Menu {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { Label("Chụp ảnh", systemImage: "camera") }
                }
                Button { showPhotos = true } label: { Label("Chọn ảnh từ thư viện", systemImage: "photo") }
                Button { showFiles = true } label: { Label("Chọn tệp (PDF, txt, csv…)", systemImage: "doc") }
            } label: {
                Image(systemName: "paperclip").foregroundColor(blue1)
                    .frame(width: 40, height: 44)
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 4, matching: .images)
            .onChange(of: photoItems) { items in loadPhotos(items) }
            Button {
                inputFocused = false
                voice.toggle { t in input = t }
            } label: {
                Image(systemName: voice.listening ? "mic.fill" : "mic")
                    .foregroundColor(voice.listening ? .white : blue1)
                    .frame(width: 44, height: 44)
                    .background(voice.listening ? Color.red : Color(red: 0.91, green: 0.94, blue: 1.0))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Hỏi bằng giọng nói")
            Button {
                if voice.listening { voice.stop() }
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

    private var attachChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { a in
                    HStack(spacing: 6) {
                        if let pv = a.preview {
                            Image(uiImage: pv).resizable().scaledToFill().frame(width: 36, height: 36).clipped().cornerRadius(6)
                        } else {
                            Image(systemName: "doc.text").foregroundColor(blue1).frame(width: 36, height: 36)
                        }
                        Text(a.name).font(.caption).lineLimit(1).frame(maxWidth: 120, alignment: .leading)
                        Button { attachments.removeAll { $0.id == a.id } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                        }
                    }
                    .padding(6)
                    .background(Color(red: 0.945, green: 0.949, blue: 0.976)).cornerRadius(10)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(Color.white)
    }

    private func addItems(_ items: [AIAttachment], note: String = "") {
        var room = AIAttach.maxItems - attachments.count
        var added: [AIAttachment] = []
        for a in items { if room > 0 { added.append(a); room -= 1 } }
        attachments.append(contentsOf: added)
        var n = note
        if added.count < items.count { n += (n.isEmpty ? "" : " ") + "Tối đa " + String(AIAttach.maxItems) + " mục đính kèm mỗi lần." }
        attachNote = n
    }

    private func addImage(_ img: UIImage) {
        if let a = AIAttach.image(img, name: "Ảnh chụp " + String(attachments.count + 1)) { addItems([a]) }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        if items.isEmpty { return }
        Task {
            var got: [AIAttachment] = []
            for (i, it) in items.enumerated() {
                if let d = try? await it.loadTransferable(type: Data.self),
                   let a = AIAttach.image(data: d, name: "Ảnh " + String(attachments.count + i + 1)) { got.append(a) }
            }
            await MainActor.run {
                addItems(got, note: got.count < items.count ? "Có ảnh không đọc được." : "")
                photoItems = []
            }
        }
    }

    private func loadFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var all: [AIAttachment] = []
        var notes: [String] = []
        for u in urls {
            let r = AIAttach.load(url: u)
            all.append(contentsOf: r.items)
            if !r.note.isEmpty { notes.append(r.note) }
        }
        addItems(all, note: notes.joined(separator: " "))
    }

    private func sendNow() {
        let t = input
        if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty { return }
        let a = attachments
        input = ""
        attachments = []
        attachNote = ""
        session.send(t, attachments: a, model: model)
    }
}
