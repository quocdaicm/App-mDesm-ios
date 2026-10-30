// AILog.swift — nhật ký + đồng hồ canh luồng chính + hàm giới hạn thời gian cho "AI riêng".
// Khi app treo: Cài đặt > AI riêng > "Nhật ký AI" (hoặc nút con bọ ở đầu khung chat) → xem dòng cuối cùng trước khi treo, rồi Chia sẻ file gửi lại.
// Nhật ký chỉ ghi tên bước, thời gian, kích thước (KB), tên tham số. KHÔNG ghi khoá API, nội dung câu hỏi hay dữ liệu DESM.
// File nhật ký nằm ở Caches/desm-ai.log, ghi bằng luồng nền nên vẫn còn nguyên kể cả khi iOS giết app lúc treo. Chưa build/chưa thử trên máy thật.

import SwiftUI
import UIKit

enum AILog {
    private static let lock = NSLock()
    private static var currentStep = "—"
    private static var renders: [String: Int] = [:]
    private static let fileQueue = DispatchQueue(label: "desm.ai.log.file", qos: .utility)
    private static let fileLimit = 300_000

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("desm-ai.log")
    }

    /// Chạy đúng một lần mỗi lần mở app: đánh dấu phiên mới để phân biệt các lần chạy trong file.
    private static let boot: Bool = {
        write("──── phiên mới (app vừa mở) ────")
        return true
    }()

    /// Ghi một dòng. [M] = luồng chính, [B] = luồng nền.
    static func add(_ msg: String) {
        _ = boot
        write(msg)
    }

    /// Ghi một bước và nhớ nó là "bước gần nhất" (watchdog in ra khi luồng chính đứng).
    static func step(_ s: String) {
        lock.lock(); currentStep = s; lock.unlock()
        add("▶ " + s)
    }

    static var lastStep: String {
        lock.lock(); defer { lock.unlock() }
        return currentStep
    }

    /// Đếm số lần một View được vẽ lại (watchdog báo nếu ≥ 20 lần/giây).
    static func render(_ name: String) {
        lock.lock(); renders[name, default: 0] += 1; lock.unlock()
    }

    fileprivate static func takeRenders() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        let r = renders
        renders = [:]
        return r
    }

    private static func write(_ msg: String) {
        let line = stamp.string(from: Date()) + (Thread.isMainThread ? " [M] " : " [B] ") + msg + "\n"
        let data = Data(line.utf8)
        fileQueue.async {
            let url = fileURL
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(data)
                let size = h.offsetInFile
                try? h.close()
                if size > UInt64(fileLimit) { trimFile() }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Chỉ gọi trên fileQueue: giữ nửa cuối file.
    private static func trimFile() {
        guard let d = try? Data(contentsOf: fileURL), d.count > fileLimit else { return }
        var s = String(decoding: d.suffix(fileLimit / 2), as: UTF8.self)
        if let i = s.firstIndex(of: "\n") { s = String(s[s.index(after: i)...]) }
        try? s.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Các dòng cuối của nhật ký (để hiện trên màn hình).
    static func tail(maxLines: Int = 300) -> [String] {
        let s: String = fileQueue.sync { () -> String in
            guard let d = try? Data(contentsOf: fileURL) else { return "" }
            return String(decoding: d.suffix(120_000), as: UTF8.self)
        }
        var ls = s.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
        if ls.count > maxLines { ls = Array(ls.suffix(maxLines)) }
        return ls
    }

    static func clear() {
        fileQueue.async { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// Gộp tiêu đề (bản app, iOS, nhà AI/model) + toàn bộ file thành một file tạm để chia sẻ. Gọi từ luồng chính.
    static func exportURL() -> URL? {
        let body: String = fileQueue.sync { () -> String in
            guard let d = try? Data(contentsOf: fileURL) else { return "" }
            return String(decoding: d, as: UTF8.self)
        }
        let dev = UIDevice.current
        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let p = AIStore.active
        var head = "DESM Mobile — nhật ký AI\n"
        head += "App " + ver + " · iOS " + dev.systemVersion + " · " + dev.model + "\n"
        head += "Nhà AI: " + p.name + " · model " + AIStore.model(p) + " · tra DESM " + (AIStore.toolsOn ? "bật" : "tắt") + "\n"
        head += "(Không chứa khoá API, câu hỏi hay dữ liệu DESM.)\n\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("desm-ai-log.txt")
        do {
            try (head + body).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Giới hạn thời gian

/// Cổng một lần: chỉ bên đến trước được `claim()` (dùng để "đua" giữa việc thật và đồng hồ hẹn giờ).
final class AIGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Chạy `op`; quá `seconds` giây thì trả `fallback` NGAY (việc thật có thể còn chạy nền nhưng không giữ người dùng chờ nữa).
/// Khác `withTaskGroup`: không đợi việc thật kết thúc, nên vẫn cắt được cả những việc không biết huỷ (evaluateJavaScript...).
func aiRace<T>(_ seconds: Double, fallback: T, _ op: @escaping () async -> T) async -> T {
    return await withCheckedContinuation { (c: CheckedContinuation<T, Never>) in
        let gate = AIGate()
        let work = Task {
            let r = await op()
            if gate.claim() { c.resume(returning: r) }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if gate.claim() {
                work.cancel()
                c.resume(returning: fallback)
            }
        }
    }
}

/// Như `aiRace` nhưng cho việc có thể ném lỗi; quá giờ thì ném `timeoutError`.
func aiRaceThrowing<T>(_ seconds: Double, timeoutError: Error, _ op: @escaping () async throws -> T) async throws -> T {
    return try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
        let gate = AIGate()
        let work = Task {
            do {
                let r = try await op()
                if gate.claim() { c.resume(returning: r) }
            } catch {
                if gate.claim() { c.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if gate.claim() {
                work.cancel()
                c.resume(throwing: timeoutError)
            }
        }
    }
}

// MARK: - Canh luồng chính

/// Mỗi giây gửi một "tiếng gõ" lên luồng chính; quá 2 giây không được trả lời thì ghi vào nhật ký (từ luồng nền, nên ghi được ngay LÚC đang treo)
/// kèm bước gần nhất. Chỉ chạy khi khung chat đang mở hoặc đang có lượt hỏi (hold/release).
final class AIWatchdog {
    static let shared = AIWatchdog()
    private let q = DispatchQueue(label: "desm.ai.watchdog", qos: .utility)
    private var holders = Set<String>()
    private var timer: DispatchSourceTimer? = nil
    private var pending = false
    private var pingedAt = Date()
    private var reported = false
    private var warnedLong = false

    func hold(_ tag: String) {
        q.async {
            self.holders.insert(tag)
            self.startIfNeeded()
        }
    }

    func release(_ tag: String) {
        q.async {
            self.holders.remove(tag)
            if self.holders.isEmpty { self.stopTimer() }
        }
    }

    private func startIfNeeded() {
        if timer != nil { return }
        AILog.add("Bắt đầu canh luồng chính")
        pending = false; reported = false; warnedLong = false
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        AILog.add("Dừng canh luồng chính")
    }

    private func tick() {
        let rc = AILog.takeRenders()
        for (k, v) in rc where v >= 20 {
            AILog.add("⚠️ Vẽ lại quá nhiều: " + k + " " + String(v) + " lần/giây")
        }
        if pending {
            let gap = Date().timeIntervalSince(pingedAt)
            if gap >= 2 && !reported {
                reported = true
                AILog.add("🧊 LUỒNG CHÍNH KHÔNG PHẢN HỒI " + String(format: "%.1f", gap) + "s — bước gần nhất: " + AILog.lastStep)
            } else if gap >= 8 && !warnedLong {
                warnedLong = true
                AILog.add("🧊 Vẫn chưa phản hồi sau " + String(format: "%.1f", gap) + "s (iOS giết app nếu treo khoảng 10s) — bước: " + AILog.lastStep)
            }
            return
        }
        pending = true
        pingedAt = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.q.async {
                let gap = Date().timeIntervalSince(self.pingedAt)
                if self.reported { AILog.add("✅ Luồng chính phản hồi lại sau " + String(format: "%.1f", gap) + "s") }
                self.reported = false
                self.warnedLong = false
                self.pending = false
            }
        }
    }
}

// MARK: - Màn xem nhật ký

struct AILogView: View {
    @State private var lines: [String] = []
    @State private var shareItem: ShareItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text("Nhật ký AI")
                .font(.headline)
                .padding(.top, 14).padding(.bottom, 6)
            Text("[M] = luồng chính, [B] = luồng nền. Dòng 🧊 = luồng chính bị đứng (kèm bước gần nhất). Nhật ký không chứa khoá API, câu hỏi hay dữ liệu DESM.")
                .font(.caption).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if lines.isEmpty {
                        Text("(Chưa có nhật ký. Hãy hỏi AI một câu rồi quay lại.)")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { item in
                        Text(verbatim: item.element)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AILogView.isAlert(item.element) ? .red : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            HStack(spacing: 10) {
                Button("Làm mới") { reload() }
                Spacer()
                Button("Chia sẻ file") {
                    if let u = AILog.exportURL() { shareItem = ShareItem(url: u) }
                }
                Spacer()
                Button("Xóa", role: .destructive) {
                    AILog.clear()
                    lines = []
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
        }
        .onAppear { reload() }
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
    }

    private func reload() {
        lines = AILog.tail(maxLines: 300)
    }

    static func isAlert(_ l: String) -> Bool {
        return l.contains("🧊") || l.contains("✗") || l.contains("⚠️")
    }
}
