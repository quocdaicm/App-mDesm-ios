import SwiftUI
import AVFoundation
import Vision

// MARK: - Nhận diện mã kiện (Package No) từ chữ in hoặc chữ viết tay

struct PkgCandidate: Identifiable, Equatable {
    let id = UUID()
    /// Chuỗi hiển thị cho người dùng
    let display: String
    /// Chuỗi điền vào ô Số kiện hàng rồi bấm Search
    let term: String
    /// Phần đuôi (bỏ ký tự phân cách) để khớp với cột PACKAGE_NO của lưới
    let key: String
    /// true = in rõ đủ 5 đoạn dạng OM4-xx-xx-0000-000, đủ tin cậy để tự nhận không cần chạm
    let printed: Bool
    /// Càng nhỏ càng đầy đủ/đáng tin
    let rank: Int

    static func == (a: PkgCandidate, b: PkgCandidate) -> Bool { a.key == b.key && a.term == b.term }
}

enum PkgParser {
    private static let digitFix: [Character: Character] = ["O": "0", "Q": "0", "D": "0", "I": "1", "L": "1", "S": "5", "B": "8", "Z": "2", "G": "6"]
    private static let letterFix: [Character: Character] = ["0": "O", "1": "I", "5": "S", "8": "B", "2": "Z", "6": "G"]
    /// Loại kiện đã thấy trên tem (LS, IS...). Dạng viết tắt 3 đoạn chỉ nhận khi loại nằm trong tập này để tránh nhận nhầm chữ khác.
    static let knownTypes: Set<String> = ["LS", "IS"]

    /// Chuỗi số, tự sửa nhầm chữ-số (O→0, I→1, S→5...). Phải có ít nhất 1 chữ số thật.
    private static func digits(_ t: String) -> String? {
        var out = "", real = false
        for c in t {
            if c.isASCII && c.isNumber { out.append(c); real = true }
            else if let m = digitFix[c] { out.append(m) }
            else { return nil }
        }
        return real ? out : nil
    }

    /// Chuỗi chữ, tự sửa nhầm số-chữ (0→O, 1→I, 5→S...). Phải có ít nhất 1 chữ cái thật.
    private static func letters(_ t: String) -> String? {
        var out = "", real = false
        for c in t {
            if c.isASCII && c.isLetter { out.append(c); real = true }
            else if let m = letterFix[c] { out.append(m) }
            else { return nil }
        }
        return real ? out : nil
    }

    private static func pad(_ s: String, _ n: Int) -> String {
        String(repeating: "0", count: max(0, n - s.count)) + s
    }

    private static func tokens(_ line: String) -> [String] {
        let up = line.uppercased().folding(options: .diacriticInsensitive, locale: nil)
        var out: [String] = [], cur = ""
        for ch in up {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { cur.append(ch) }
            else if !cur.isEmpty { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private static func isOM4(_ t: String) -> Bool {
        let a = Array(t)
        return a.count == 3 && (a[0] == "O" || a[0] == "0") && a[1] == "M" && (a[2] == "4" || a[2] == "A")
    }

    /// Mã giữa (DE, P2...): 2-3 ký tự chữ/số, có ít nhất 1 chữ cái, không phải "OM4".
    private static func mid(_ t: String) -> String? {
        guard (2...3).contains(t.count), !isOM4(t), t.contains(where: { $0.isLetter }) else { return nil }
        return t
    }

    static func norm(_ s: String) -> String {
        String(s.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    static func candidates(in lines: [String]) -> [PkgCandidate] {
        var out: [PkgCandidate] = []
        func add(_ c: PkgCandidate) {
            if out.contains(where: { $0.key == c.key || $0.key.hasSuffix(c.key) }) { return }
            out.removeAll { c.key.hasSuffix($0.key) }
            out.append(c)
        }
        for line in lines {
            let t = tokens(line)
            if t.count < 3 { continue }
            for i in 0..<t.count {
                // OM4 - mid - type - 0000 - 000 (in rõ hoặc viết tay đủ đoạn)
                if i + 5 <= t.count, isOM4(t[i]), let m = mid(t[i + 1]), let ty = letters(t[i + 2]), ty.count == 2,
                   let a = digits(t[i + 3]), (1...4).contains(a.count), let b = digits(t[i + 4]), (1...3).contains(b.count) {
                    let full = "OM4-\(m)-\(ty)-\(pad(a, 4))-\(pad(b, 3))"
                    add(PkgCandidate(display: full, term: full, key: norm(full), printed: a.count == 4 && b.count == 3, rank: 0))
                }
                // Viết tay bỏ OM4: mid - type - n1 - n2 (VD DE-LS-01-07)
                if i + 4 <= t.count, let m = mid(t[i]), let ty = letters(t[i + 1]), ty.count == 2,
                   let a = digits(t[i + 2]), (1...4).contains(a.count), let b = digits(t[i + 3]), (1...3).contains(b.count) {
                    let part = "\(m)-\(ty)-\(pad(a, 4))-\(pad(b, 3))"
                    add(PkgCandidate(display: "OM4-" + part, term: "OM4-" + part, key: norm(part), printed: false, rank: 1))
                }
                // Viết tắt hơn nữa: type - n1 - n2 (VD LS-01-07), chưa biết mã giữa
                if i + 3 <= t.count, let ty = letters(t[i]), knownTypes.contains(ty),
                   let a = digits(t[i + 1]), (2...4).contains(a.count), let b = digits(t[i + 2]), (1...3).contains(b.count) {
                    let part = "\(ty)-\(pad(a, 4))-\(pad(b, 3))"
                    add(PkgCandidate(display: part, term: part, key: norm(part), printed: false, rank: 2))
                }
            }
        }
        return Array(out.sorted { $0.rank < $1.rank }.prefix(4))
    }
}

// MARK: - Trạng thái quét

final class ScanState: ObservableObject {
    @Published var candidates: [PkgCandidate] = []
    @Published var torch = false
    @Published var zoom2x = false
    @Published var denied = false
    @Published var unavailable = false

    var onAccept: ((PkgCandidate) -> Void)?
    private var streak: [String: Int] = [:]
    private var lastSeen = Date.distantPast
    private var finished = false

    func ingest(_ lines: [String]) {
        guard !finished else { return }
        let found = PkgParser.candidates(in: lines)
        if found.isEmpty {
            streak = [:]
            if Date().timeIntervalSince(lastSeen) > 1.5 && !candidates.isEmpty { candidates = [] }
            return
        }
        lastSeen = Date()
        if found != candidates { candidates = found }
        var next: [String: Int] = [:]
        for c in found where c.printed { next[c.key] = (streak[c.key] ?? 0) + 1 }
        streak = next
        if let c = found.first(where: { $0.printed && (streak[$0.key] ?? 0) >= 2 }) { accept(c) }
    }

    func accept(_ c: PkgCandidate) {
        guard !finished else { return }
        finished = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onAccept?(c)
    }
}

// MARK: - Camera + Vision

final class CameraVC: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onLines: (([String]) -> Void)?
    var onDenied: (() -> Void)?
    var onUnavailable: (() -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "desm.scan.queue")
    private var preview: AVCaptureVideoPreviewLayer?
    private var device: AVCaptureDevice?
    private var configured = false
    private var busy = false
    private var last = Date.distantPast
    private(set) var torchOn = false
    private(set) var zoomX: CGFloat = 1

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: setup()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { if ok { self.setup() } else { self.onDenied?() } }
            }
        default: onDenied?()
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(focusTap(_:)))
        view.addGestureRecognizer(tap)
    }

    private func setup() {
        guard !configured else { return }
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: dev) else { onUnavailable?(); return }
        configured = true
        device = dev
        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        if session.canAddInput(input) { session.addInput(input) }
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) { session.addOutput(out) }
        session.commitConfiguration()
        let pl = AVCaptureVideoPreviewLayer(session: session)
        pl.videoGravity = .resizeAspectFill
        pl.frame = view.bounds
        view.layer.insertSublayer(pl, at: 0)
        preview = pl
        try? dev.lockForConfiguration()
        if dev.isFocusModeSupported(.continuousAutoFocus) { dev.focusMode = .continuousAutoFocus }
        dev.unlockForConfiguration()
        queue.async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        setTorch(false)
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func setTorch(_ on: Bool) {
        torchOn = on
        guard let d = device, d.hasTorch else { return }
        try? d.lockForConfiguration()
        d.torchMode = on ? .on : .off
        d.unlockForConfiguration()
    }

    func setZoom(_ x: CGFloat) {
        zoomX = x
        guard let d = device else { return }
        try? d.lockForConfiguration()
        d.videoZoomFactor = min(max(1, x), d.activeFormat.videoMaxZoomFactor)
        d.unlockForConfiguration()
    }

    @objc private func focusTap(_ g: UITapGestureRecognizer) {
        guard let d = device, let pl = preview, d.isFocusPointOfInterestSupported else { return }
        let p = pl.captureDevicePointConverted(fromLayerPoint: g.location(in: view))
        try? d.lockForConfiguration()
        d.focusPointOfInterest = p
        d.focusMode = .autoFocus
        d.unlockForConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !busy, Date().timeIntervalSince(last) > 0.4,
              let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy = true
        last = Date()
        let req = VNRecognizeTextRequest { [weak self] r, _ in
            var lines: [String] = []
            for o in (r.results as? [VNRecognizedTextObservation]) ?? [] {
                // Lấy tới 3 cách đọc cho mỗi dòng: chữ viết tay hay bị đọc nhiều kiểu
                for c in o.topCandidates(3) where c.confidence > 0.25 { lines.append(c.string) }
            }
            DispatchQueue.main.async { self?.onLines?(lines) }
            self?.busy = false
        }
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US"]
        req.minimumTextHeight = 0.02
        let handler = VNImageRequestHandler(cvPixelBuffer: px, orientation: .right, options: [:])
        do { try handler.perform([req]) } catch { busy = false }
    }
}

struct CameraRepresentable: UIViewControllerRepresentable {
    @ObservedObject var state: ScanState

    func makeUIViewController(context: Context) -> CameraVC {
        let vc = CameraVC()
        vc.onLines = { [weak state] in state?.ingest($0) }
        vc.onDenied = { [weak state] in state?.denied = true }
        vc.onUnavailable = { [weak state] in state?.unavailable = true }
        return vc
    }

    func updateUIViewController(_ vc: CameraVC, context: Context) {
        if vc.torchOn != state.torch { vc.setTorch(state.torch) }
        let z: CGFloat = state.zoom2x ? 2 : 1
        if vc.zoomX != z { vc.setZoom(z) }
    }
}

// MARK: - Màn hình quét

struct PackageScannerView: View {
    let onPick: (PkgCandidate) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var st = ScanState()

    init(onPick: @escaping (PkgCandidate) -> Void) { self.onPick = onPick }

    var body: some View {
        ZStack {
            CameraRepresentable(state: st).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
            if st.denied || st.unavailable { blocked }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .onAppear {
            st.onAccept = { c in
                dismiss()
                onPick(c)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            circleButton("xmark") { dismiss() }
            Spacer()
            circleButton(st.torch ? "flashlight.on.fill" : "flashlight.off.fill") { st.torch.toggle() }
            Button { st.zoom2x.toggle() } label: {
                Text(st.zoom2x ? "2×" : "1×").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
        }
        .padding(.horizontal, 14).padding(.top, 8)
    }

    private func circleButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white).frame(width: 44, height: 44)
                .background(.black.opacity(0.45), in: Circle())
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if st.candidates.isEmpty {
                Text("Đưa camera vào dòng Package No (chữ in hoặc viết tay).\nChạm màn hình để lấy nét.")
                    .font(.system(size: 14, weight: .medium)).multilineTextAlignment(.center)
                    .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(st.candidates) { c in
                    Button { st.accept(c) } label: {
                        HStack {
                            Image(systemName: c.printed ? "checkmark.circle.fill" : "hand.draw")
                            Text(c.display).font(.system(size: 17, weight: .bold, design: .monospaced))
                            Spacer()
                            Text(c.printed ? "tự nhận" : "chạm để chọn").font(.system(size: 12))
                        }
                        .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color(red: 0.11, green: 0.31, blue: 0.85).opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 24)
    }

    private var blocked: some View {
        VStack(spacing: 14) {
            Text(st.denied ? "Chưa cho phép dùng camera" : "Không mở được camera")
                .font(.headline).foregroundStyle(.white)
            if st.denied {
                Text("Vào Cài đặt > DESM Mobile > Camera để bật.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                Button("Mở Cài đặt") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }.buttonStyle(.borderedProminent)
            }
            Button("Đóng") { dismiss() }.foregroundStyle(.white)
        }
        .padding(24).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
    }
}
