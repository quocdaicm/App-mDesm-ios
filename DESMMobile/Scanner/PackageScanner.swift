// PackageScanner.swift — quét bằng camera/ảnh trong app:
//  - Nhận diện 2 loại số trên tem: Package No (OM4-P2-LS-0006-051, OM4-MG-GEN1-KOB-0009...) và
//    Packing List No = Shipment No / Shipping Invoice No (OM4-DE-IS-0016, OM4-P2-LS-0006).
//    Đọc được chữ in lẫn chữ viết tay/viết tắt (P2-LS-06-51 → OM4-P2-LS-0006-051), tự sửa nhầm O/0, I/1, S/5...
//  - Thấy cả 2 số → hiện khung chọn 1 trong 2; chỉ thấy 1 số (chữ in rõ) → tự mở.
//  - Mã QR nhãn hạng mục: DETAIL!!!<mã>!!!<tên Packing List>!!!<Material Code> (QRDetail.parse).
//  - Mã QR phiếu xuất kho RSI: RSI!!!<số> (QRParser.parseDoc, cả MRF!!!<số> → tab Trả hàng) → mở tab Xuất kho đúng phiếu đó. Không có QR thì đọc chữ "RSI No : RSI2026006488" (RsiNoOCR).
//  - Kết quả được BrowserModel chuyển thành lệnh JS (__desmFindPkg / __desmFindPackingList / __desmFindDetail) chạy trong trang DESM.
// Xem DEV_NOTES.md (mục "Quét thông minh").
import SwiftUI
import AVFoundation
import Vision
import PhotosUI

// MARK: - Kiểu dữ liệu nhận diện

enum ScanKind: String {
    case package
    case packingList

    /// Tên hiển thị trong app (khớp tên cột trên trang DESM)
    var title: String { self == .package ? "Package No" : "Packing List No" }
}

struct PkgCandidate: Identifiable, Equatable {
    let id = UUID()
    let kind: ScanKind
    /// Chuỗi hiển thị cho người dùng
    let display: String
    /// Chuỗi điền vào ô Package No / Packing List No rồi bấm Search
    let term: String
    /// Phần đuôi (bỏ ký tự phân cách) để khớp với cột PACKAGE_NO của lưới
    let key: String
    /// true = đọc rõ, không phải sửa/đoán chữ nào → đủ tin cậy để tự nhận không cần chạm
    var printed: Bool
    /// Càng nhỏ càng đầy đủ/đáng tin
    var rank: Int
    /// true = số suy ra từ số kia (vd Packing List suy từ Package viết tay), không thấy trực tiếp trên tem
    var derived: Bool = false

    var uid: String { kind.rawValue + ":" + key }

    static func == (a: PkgCandidate, b: PkgCandidate) -> Bool {
        a.uid == b.uid && a.term == b.term && a.printed == b.printed && a.derived == b.derived
    }
}

/// Một dòng chữ Vision đọc được: tới 3 cách đọc + vị trí (toạ độ chuẩn hoá) để ghép nhãn với giá trị cùng hàng.
struct OCRObs {
    let texts: [String]
    let box: CGRect
}

/// Hai lựa chọn cùng lúc (Package No và Packing List No) để người dùng chạm chọn.
struct ScanChoice: Identifiable, Equatable {
    let package: PkgCandidate?
    let packingList: PkgCandidate?
    var id: String { (package?.uid ?? "-") + "|" + (packingList?.uid ?? "-") }
}

// MARK: - Nhận diện mã kiện / Packing List từ chữ in hoặc chữ viết tay
//
// Cách làm (xem DEV_NOTES.md):
//  1. Ghép các dòng chữ cùng hàng (nhãn "PACKAGE NO.:" + giá trị) để biết giá trị thuộc loại nào.
//  2. Tách thành token chữ-số, quét theo mẫu: OM4-<mã>-<mã>[-<mã>]-NNNN[-NNN] (in), hoặc viết tắt bỏ OM4 (P2-LS-06-51).
//  3. Tự sửa nhầm chữ/số, tự điền số 0 cho đủ 4 và 3 chữ số, "hít" mã giữa (GT1, TGO, GEN1...) về từ vựng đã biết.
//  4. Loại số nhiễu: số hợp đồng 06/2025/HĐ-PVN/OM4-06, gói thầu OM4-EPC-HHO-06, SĐT...
//  5. Có đuôi -NNN → Package. Không đuôi: có nhãn Shipment/Invoice/Packing List → Packing List; nhãn Package → Package;
//     không nhãn → 2 đoạn mã (DE-IS) là Packing List, từ 3 đoạn (MG-GEN1-KOB) là Package.

enum PkgParser {
    /// Loại kiện đã thấy trên tem (LS, IS...). Học thêm từ tem in rõ.
    private static let baseTypes: Set<String> = ["LS", "IS"]
    /// Loại mà số viết tay dạng "DE-IS-05-01" nghĩa là Shipment (Packing List) + số thứ tự, không phải Package.
    static let shipTypes: Set<String> = ["IS"]
    /// Các mã giữa đã biết trên tem O Mon 4. Mã mới đọc rõ trên tem in sẽ được học thêm và nhớ lại.
    private static let baseVocab: Set<String> = ["DE", "P2", "MG", "MPW", "GEN1", "GEN2", "KOB", "MAR", "GT1", "TGO", "LS", "IS"]
    private static let stopTokens: Set<String> = ["GOI", "THAU", "NMND", "CONSIGNEE", "NOTIFY", "HD", "PVN", "HOP", "DONG", "CONTRACT"]
    private static let stopMids: Set<String> = ["EPC", "HHO", "HD", "PVN", "PECC2", "CTY", "MON", "NMND"]
    private static let digitFix: [Character: Character] = ["O": "0", "Q": "0", "D": "0", "I": "1", "L": "1", "S": "5", "B": "8", "Z": "2", "G": "6"]
    private static let letterFix: [Character: Character] = ["0": "O", "1": "I", "5": "S", "8": "B", "2": "Z", "6": "G"]
    /// Các ký tự dễ nhầm quy về cùng một dạng để so khớp với từ vựng (GTI ≈ GT1, TG0 ≈ TGO, 6EN1 ≈ GEN1)
    private static let canonMap: [Character: Character] = ["O": "0", "Q": "0", "D": "0", "I": "1", "L": "1", "S": "5", "B": "8", "Z": "2", "G": "6"]

    private static let lock = NSLock()
    private static var vocabSet: Set<String> = initialVocab()
    private static var typeSet: Set<String> = initialTypes()
    private static var canonIndex: [String: Set<String>] = buildIndex(initialVocab())

    private static let vocabKey = "desmScanVocab"
    private static let typesKey = "desmScanTypes"

    private static func initialVocab() -> Set<String> {
        baseVocab.union(UserDefaults.standard.stringArray(forKey: vocabKey) ?? [])
    }
    private static func initialTypes() -> Set<String> {
        baseTypes.union(UserDefaults.standard.stringArray(forKey: typesKey) ?? [])
    }
    private static func buildIndex(_ v: Set<String>) -> [String: Set<String>] {
        var d: [String: Set<String>] = [:]
        for w in v { d[canon(w), default: []].insert(w) }
        return d
    }

    // MARK: Học từ tem in rõ

    /// Nhớ các mã giữa / loại kiện của một số đã đọc rõ (không phải sửa), để lần sau "hít" chữ viết tay về đúng mã.
    static func learn(_ c: PkgCandidate) {
        guard c.printed else { return }
        let segs = c.term.split(separator: "-").map(String.init)
        guard segs.count >= 4, segs[0] == "OM4" else { return }
        lock.lock()
        defer { lock.unlock() }
        var changed = false
        for s in segs.dropFirst() where (2...4).contains(s.count) && s.contains(where: { $0.isLetter }) && !vocabSet.contains(s) {
            if vocabSet.count >= baseVocab.count + 300 { break }
            vocabSet.insert(s)
            canonIndex[canon(s), default: []].insert(s)
            changed = true
        }
        if c.kind == .package, segs.count == 5, segs[2].count == 2, segs[2].allSatisfy({ $0.isLetter }), !typeSet.contains(segs[2]) {
            typeSet.insert(segs[2])
            UserDefaults.standard.set(Array(typeSet.subtracting(baseTypes)).sorted(), forKey: typesKey)
        }
        if changed { UserDefaults.standard.set(Array(vocabSet.subtracting(baseVocab)).sorted(), forKey: vocabKey) }
    }

    // MARK: Chuẩn hoá chuỗi

    /// Chuỗi số, tự sửa nhầm chữ-số (O→0, I→1, S→5...). Phải có ít nhất 1 chữ số thật. Trả (chuỗi số, có sửa?).
    private static func digits(_ t: String) -> (String, Bool)? {
        var out = "", real = false, fixed = false
        for c in t {
            if c.isASCII && c.isNumber { out.append(c); real = true }
            else if let m = digitFix[c] { out.append(m); fixed = true }
            else { return nil }
        }
        return real ? (out, fixed) : nil
    }

    /// Chuỗi chữ, tự sửa nhầm số-chữ (0→O, 1→I, 5→S...). Phải có ít nhất 1 chữ cái thật.
    private static func letters(_ t: String) -> (String, Bool)? {
        var out = "", real = false, fixed = false
        for c in t {
            if c.isASCII && c.isLetter { out.append(c); real = true }
            else if let m = letterFix[c] { out.append(m); fixed = true }
            else { return nil }
        }
        return real ? (out, fixed) : nil
    }

    private static func pad(_ s: String, _ n: Int) -> String {
        String(repeating: "0", count: max(0, n - s.count)) + s
    }

    private static func canon(_ t: String) -> String {
        String(t.map { canonMap[$0] ?? $0 })
    }

    /// "Hít" token về mã trong từ vựng nếu khớp duy nhất (sau khi quy các ký tự dễ nhầm). Trả (mã chuẩn, có sửa?).
    private static func snap(_ t: String) -> (String, Bool)? {
        lock.lock()
        defer { lock.unlock() }
        if vocabSet.contains(t) { return (t, false) }
        if let hits = canonIndex[canon(t)], hits.count == 1, let h = hits.first { return (h, true) }
        return nil
    }

    private static func knownTypes() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return typeSet
    }

    static func norm(_ s: String) -> String {
        String(s.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    private static func tokens(_ line: String) -> [String] {
        let up = line.uppercased().replacingOccurrences(of: "Đ", with: "D").folding(options: .diacriticInsensitive, locale: nil)
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

    private struct Mid {
        let s: String
        let fixed: Bool
        let known: Bool
    }

    /// Mã giữa (DE, P2, MG, GEN1, KOB, GT1...): trong từ vựng (kể cả đọc nhầm nhẹ) hoặc 2–4 ký tự có chữ cái và không giống số.
    private static func midTok(_ t: String) -> Mid? {
        if isOM4(t) || stopMids.contains(t) { return nil }
        if let s = snap(t) { return Mid(s: s.0, fixed: s.1, known: true) }
        guard (2...4).contains(t.count), t.contains(where: { $0.isLetter }), digits(t) == nil else { return nil }
        return Mid(s: t, fixed: false, known: false)
    }

    /// Nhãn đứng ngay trước vị trí i (trong 8 token, dừng khi gặp mã OM4 khác) cho biết giá trị là loại nào.
    private static func labelBefore(_ t: [String], _ i: Int) -> ScanKind? {
        var k = i - 1
        let lo = max(0, i - 8)
        while k >= lo {
            if isOM4(t[k]) { return nil }
            let w = t[k]
            let prev = k > 0 ? t[k - 1] : ""
            let nxt = k + 1 < t.count ? t[k + 1] : ""
            if w == "SHIPMENT" || w == "INVOICE" || (w == "SHIPPING" && nxt == "INVOICE") || (w == "PACKING" && nxt == "LIST") {
                return .packingList
            }
            if w == "PACKAGE" || w == "PKG" || (w == "KIEN" && prev == "SO") { return .package }
            k -= 1
        }
        return nil
    }

    private static func make(_ kind: ScanKind, _ mids: [String], _ a: String, _ b: String?,
                             printed: Bool, rank: Int, derived: Bool = false) -> PkgCandidate {
        let base = "OM4-" + mids.joined(separator: "-") + "-" + a
        var s = base
        if kind == .package, let b = b { s += "-" + b }
        return PkgCandidate(kind: kind, display: s, term: s, key: norm(s), printed: printed, rank: rank, derived: derived)
    }

    // MARK: Ghép dòng cùng hàng

    /// Các chuỗi để phân tích: từng cách đọc của từng dòng, cộng các dòng cùng hàng ghép lại (nhãn + giá trị).
    static func textLines(_ obs: [OCRObs]) -> [String] {
        var out: [String] = []
        for o in obs { out.append(contentsOf: o.texts) }
        let sorted = obs.sorted { $0.box.midY > $1.box.midY }
        var rows: [[OCRObs]] = []
        for o in sorted {
            var placed = false
            for idx in rows.indices.reversed() {
                let r = rows[idx]
                var sum: CGFloat = 0
                for x in r { sum += x.box.midY }
                let mean = sum / CGFloat(r.count)
                let h = min(max(r[0].box.height, o.box.height), 0.04)
                if abs(mean - o.box.midY) < h * 0.8 { rows[idx].append(o); placed = true; break }
            }
            if !placed { rows.append([o]) }
        }
        for r in rows where r.count >= 2 && r.count <= 6 {
            let row = r.sorted { $0.box.minX < $1.box.minX }
            out.append(row.map { $0.texts[0] }.joined(separator: " "))
            for (k, o) in row.enumerated() {
                for alt in o.texts.dropFirst() {
                    var parts = row.map { $0.texts[0] }
                    parts[k] = alt
                    out.append(parts.joined(separator: " "))
                }
            }
        }
        return out
    }

    // MARK: Phân tích

    static func candidates(in obs: [OCRObs]) -> [PkgCandidate] {
        candidates(inLines: textLines(obs))
    }

    /// Sắp xếp: số thấy trực tiếp trước số suy ra, rồi theo độ đầy đủ/đáng tin.
    static func ranked(_ c: [PkgCandidate]) -> [PkgCandidate] {
        c.sorted { a, b in
            if a.derived != b.derived { return !a.derived }
            if a.rank != b.rank { return a.rank < b.rank }
            return a.key < b.key
        }
    }

    /// Số Package tốt nhất và Packing List tốt nhất trong danh sách.
    static func pair(_ c: [PkgCandidate]) -> (package: PkgCandidate?, packingList: PkgCandidate?) {
        let r = ranked(c)
        return (r.first { $0.kind == .package }, r.first { $0.kind == .packingList })
    }

    static func candidates(inLines lines: [String]) -> [PkgCandidate] {
        var out: [PkgCandidate] = []
        let types = knownTypes()

        func add(_ c: PkgCandidate) {
            for idx in out.indices where out[idx].kind == c.kind {
                let o = out[idx]
                if o.key == c.key {
                    var best = (c.rank < o.rank || (c.rank == o.rank && !c.derived && o.derived)) ? c : o
                    best.derived = c.derived && o.derived
                    best.printed = c.printed || o.printed
                    out[idx] = best
                    return
                }
                if o.key.hasSuffix(c.key) { return }
            }
            out.removeAll { $0.kind == c.kind && c.key.hasSuffix($0.key) }
            out.append(c)
        }

        for line in lines {
            let t = tokens(line)
            if t.count < 3 || t.contains(where: { stopTokens.contains($0) }) { continue }
            var covered = Set<Int>()

            // A. Có OM4:  OM4 - mã - mã [- mã - mã] - NNNN [- NNN]
            for i in t.indices where isOM4(t[i]) {
                var j = i + 1
                var mids: [String] = []
                var fx = false
                while j < t.count, mids.count < 4, let m = midTok(t[j]) {
                    mids.append(m.s)
                    fx = fx || m.fixed
                    j += 1
                }
                guard mids.count >= 2, j < t.count, let da = digits(t[j]), (1...4).contains(da.0.count) else { continue }
                var fixed = fx || da.1 || da.0.count < 4
                let a = pad(da.0, 4)
                var b: String? = nil
                var end = j + 1
                let lab = labelBefore(t, i)
                // Đuôi -NNN: đủ 3 chữ số, hoặc cả hai đoạn đều viết tắt (06-51). Nhãn Packing List thì không có đuôi.
                if lab != .packingList, j + 1 < t.count, let db = digits(t[j + 1]),
                   db.0.count == 3 || (da.0.count < 4 && (1...2).contains(db.0.count)) {
                    b = pad(db.0, 3)
                    fixed = fixed || db.1 || db.0.count < 3
                    end = j + 2
                }
                for x in i..<end { covered.insert(x) }
                let last = mids[mids.count - 1]
                let twoLetter = last.count == 2 && last.allSatisfy { $0.isLetter }
                var kind: ScanKind
                if b != nil {
                    kind = .package
                    // Viết tay "OM4-DE-IS-05-01": loại IS là Shipment + số thứ tự → Packing List
                    if fixed && lab == nil && shipTypes.contains(last) { kind = .packingList }
                } else if let l = lab {
                    kind = l
                } else {
                    kind = (mids.count == 2 && twoLetter) ? .packingList : .package
                }
                let printed = !fixed
                if kind == .packingList {
                    add(make(.packingList, mids, a, nil, printed: printed, rank: printed ? 0 : 1))
                    if b != nil { add(make(.package, mids, a, b, printed: false, rank: 1, derived: true)) }
                } else {
                    add(make(.package, mids, a, b, printed: printed, rank: printed ? 0 : 1))
                    if b != nil && fixed { add(make(.packingList, mids, a, nil, printed: false, rank: 1, derived: true)) }
                }
            }

            // B1. Viết tay bỏ OM4:  mã - loại - NN [- NN]   (P2-LS-06-51, DE-IS-05-01, P2-LS-06)
            if t.count >= 3 {
                for i in 0...(t.count - 3) {
                    if covered.contains(i) || (i > 0 && isOM4(t[i - 1])) { continue }
                    guard let m = midTok(t[i]), let ty = letters(t[i + 1]), ty.0.count == 2,
                          !covered.contains(i + 1), !covered.contains(i + 2) else { continue }
                    if !(types.contains(ty.0) || m.known) { continue }
                    if !(m.known || m.s.count == 2) { continue }
                    guard let da = digits(t[i + 2]), (1...4).contains(da.0.count) else { continue }
                    let a = pad(da.0, 4)
                    let lab = labelBefore(t, i)
                    var b: String? = nil
                    var end = i + 3
                    if lab != .packingList, i + 3 < t.count, let db = digits(t[i + 3]), (1...3).contains(db.0.count) {
                        b = pad(db.0, 3)
                        end = i + 4
                    }
                    // 3 đoạn mà mã giữa lạ: bỏ để khỏi nhận nhầm chữ thường
                    if b == nil && !m.known { continue }
                    for x in i..<end { covered.insert(x) }
                    let mids = [m.s, ty.0]
                    var kind: ScanKind = lab ?? (b != nil ? .package : .packingList)
                    if b != nil && lab == nil && shipTypes.contains(ty.0) { kind = .packingList }
                    if kind == .packingList {
                        add(make(.packingList, mids, a, nil, printed: false, rank: 1))
                        if b != nil { add(make(.package, mids, a, b, printed: false, rank: 1, derived: true)) }
                    } else {
                        add(make(.package, mids, a, b, printed: false, rank: 1))
                        if b != nil { add(make(.packingList, mids, a, nil, printed: false, rank: 1, derived: true)) }
                    }
                }
            }

            // B2. Viết tắt hơn nữa:  loại - NNNN - NNN  (LS-0006-051), chưa biết mã giữa
            if t.count >= 3 {
                for i in 0...(t.count - 3) {
                    if covered.contains(i) || covered.contains(i + 1) || covered.contains(i + 2) { continue }
                    guard let ty = letters(t[i]), types.contains(ty.0),
                          let da = digits(t[i + 1]), da.0.count == 4,
                          let db = digits(t[i + 2]), db.0.count == 3 else { continue }
                    let s = "\(ty.0)-\(da.0)-\(db.0)"
                    add(PkgCandidate(kind: .package, display: s, term: s, key: norm(s), printed: false, rank: 2))
                    for x in i...(i + 2) { covered.insert(x) }
                }
            }

            // B3. Từ 2 mã quen thuộc liên tiếp + số:  MG-GEN1-KOB-0009 (đủ → Package), GEN2-KOB-0001 (đuôi → gợi ý)
            var i = 0
            while i < t.count {
                if covered.contains(i) { i += 1; continue }
                var run: [String] = []
                var j = i
                while j < t.count, !covered.contains(j), run.count < 4, let s = snap(t[j]) {
                    run.append(s.0)
                    j += 1
                }
                if run.count >= 2, j < t.count, !covered.contains(j), let da = digits(t[j]), (1...4).contains(da.0.count) {
                    let a = pad(da.0, 4)
                    var b: String? = nil
                    if j + 1 < t.count, let db = digits(t[j + 1]), db.0.count == 3 { b = pad(db.0, 3) }
                    if run.count >= 3 {
                        add(make(.package, run, a, b, printed: false, rank: 1))
                    } else {
                        let s = run.joined(separator: "-") + "-" + a + (b.map { "-" + $0 } ?? "")
                        add(PkgCandidate(kind: .package, display: s, term: s, key: norm(s), printed: false, rank: 3))
                    }
                    i = j + 1
                    continue
                }
                i += 1
            }
        }
        return Array(ranked(out).prefix(8))
    }
}

// MARK: - Mã QR trên nhãn DESM

/// Nhãn hạng mục chi tiết: `DETAIL!!!<mã>!!!<tên Packing List>!!!<Material Code>`
struct QRDetail: Equatable {
    let material: String
    let plName: String
    let raw: String
}

/// Phiếu xuất kho RSI in QR dạng `RSI!!!<giá trị>`. Giá trị có thể là số RSI đầy đủ (RSI2026006488)
/// hoặc mã nội bộ dạng số (vd 86167, nhiều khả năng là RSI_HEADER_ID) → isNo phân biệt hai trường hợp.
struct QRRsi: Equatable {
    let value: String
    let raw: String
    let isNo: Bool
    /// Loại phiếu: RSI (xuất kho) hoặc MRF (trả hàng)
    var kind: DesmDocKind = .rsi
}

/// Đọc số RSI in bằng chữ trên phiếu ("RSI No : RSI2026006488") khi không quét được QR.
enum RsiNoOCR {
    static func parse(_ s: String) -> String? {
        let up = s.uppercased().filter { !$0.isWhitespace }
        guard let r = up.range(of: "RSI20[0-9]{8}", options: .regularExpression) else { return nil }
        return String(up[r])
    }

    static func find(_ obs: [OCRObs]) -> String? {
        for line in PkgParser.textLines(obs) { if let n = parse(line) { return n } }
        return nil
    }

    /// Số MRF in trên phiếu trả hàng ("MRF No : MRF2026…"; dạng số đoán theo RSI, CHƯA kiểm chứng với phiếu thật).
    static func parseMrf(_ s: String) -> String? {
        let up = s.uppercased().filter { !$0.isWhitespace }
        guard let r = up.range(of: "MRF20[0-9]{8}", options: .regularExpression) else { return nil }
        return String(up[r])
    }

    /// Tìm số phiếu trong chữ đọc được. MRF xét trước vì phiếu MRF còn liệt kê cả số RSI ở từng dòng.
    static func findDoc(_ obs: [OCRObs]) -> QRRsi? {
        let lines = PkgParser.textLines(obs)
        for l in lines { if let n = parseMrf(l) { return QRRsi(value: n, raw: n, isNo: true, kind: .mrf) } }
        for l in lines { if let n = parse(l) { return QRRsi(value: n, raw: n, isNo: true, kind: .rsi) } }
        return nil
    }
}

enum QRParser {
    /// `RSI!!!<giá trị>` hoặc `MRF!!!<giá trị>` (MRF: định dạng đoán theo RSI, CHƯA kiểm chứng với tem thật).
    static func parseDoc(_ s: String) -> QRRsi? {
        let parts = s.components(separatedBy: "!!!").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2, !parts[1].isEmpty else { return nil }
        let tag = parts[0].uppercased()
        guard tag == "RSI" || tag == "MRF" else { return nil }
        let v = parts[1].uppercased()
        let isNo = v.hasPrefix(tag) && v.count >= 9 && v.dropFirst(3).allSatisfy { $0.isNumber }
        return QRRsi(value: v, raw: s, isNo: isNo, kind: tag == "MRF" ? .mrf : .rsi)
    }

    static func parse(_ s: String) -> QRDetail? {
        let parts = s.components(separatedBy: "!!!").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 4, parts[0].uppercased() == "DETAIL", let m = parts.last, !m.isEmpty else { return nil }
        return QRDetail(material: m, plName: parts[2], raw: s)
    }
}

// MARK: - Trạng thái quét

final class ScanState: ObservableObject {
    /// Gợi ý hiển thị khi chỉ có một loại số (đã sắp xếp)
    @Published var candidates: [PkgCandidate] = []
    /// Có đủ cả Package No và Packing List No → hiện khung chọn 1 trong 2
    @Published var choice: ScanChoice? = nil
    @Published var torch = false
    @Published var zoom2x = false
    @Published var denied = false
    @Published var unavailable = false

    @Published var otherQR: String? = nil

    var onAccept: ((PkgCandidate) -> Void)?
    var onQR: ((QRDetail) -> Void)?
    var onQRRsi: ((QRRsi) -> Void)?
    private var rsiStreak: [String: Int] = [:]

    private struct Seen {
        var cand: PkgCandidate
        var hits: Int
        var first: Date
        var last: Date
    }
    /// Trí nhớ ngắn: số thấy ở khung hình trước vẫn còn 2 giây, nên 2 số đọc ở 2 khung khác nhau vẫn ghép được thành khung chọn.
    private var seen: [String: Seen] = [:]
    private var qrStreak: [String: Int] = [:]
    private var lastSeen = Date.distantPast
    private var finished = false

    func ingest(_ obs: [OCRObs]) {
        guard !finished else { return }
        let now = Date()
        // Phiếu RSI có chữ "RSI No : RSI2026…" (và nhiều Package No bên trong): thấy số RSI thì ưu tiên mở phiếu, không đoán Package.
        if let doc = RsiNoOCR.findDoc(obs) {
            let n = doc.kind.rawValue + ":" + doc.value
            let c = (rsiStreak[n] ?? 0) + 1
            rsiStreak = [n: c]
            if c >= 2 {
                finished = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onQRRsi?(doc)
            }
            return
        }
        let found = PkgParser.candidates(in: obs)
        for c in found {
            if var s = seen[c.uid] {
                s.hits += 1
                s.last = now
                s.cand = c
                seen[c.uid] = s
            } else {
                seen[c.uid] = Seen(cand: c, hits: 1, first: now, last: now)
            }
        }
        if !found.isEmpty { lastSeen = now }
        seen = seen.filter { now.timeIntervalSince($0.value.last) < 2.0 }
        refresh(now)
    }

    private func refresh(_ now: Date) {
        let list = seen.values.sorted { a, b in
            if a.cand.derived != b.cand.derived { return !a.cand.derived }
            if a.cand.rank != b.cand.rank { return a.cand.rank < b.cand.rank }
            if a.hits != b.hits { return a.hits > b.hits }
            return a.cand.key < b.cand.key
        }
        let all = list.map { $0.cand }
        let pkg = all.first { $0.kind == .package }
        let pl = all.first { $0.kind == .packingList }
        let ch: ScanChoice? = (pkg != nil && pl != nil) ? ScanChoice(package: pkg, packingList: pl) : nil
        let shown = ch == nil ? Array(all.prefix(3)) : []
        if ch != choice { choice = ch }
        if shown != candidates { candidates = shown }

        // Tự mở: chỉ khi thấy trực tiếp đúng MỘT loại số, đọc rõ (không phải sửa), không có số cùng loại nào khác, giữ ổn định ≥ ~1 giây.
        let real = list.filter { !$0.cand.derived }
        guard Set(real.map { $0.cand.kind }).count == 1, let top = real.first, top.cand.printed else { return }
        // Số cùng loại khác (đọc nhầm) chỉ cản khi cũng được thấy khá nhiều lần so với số đang dẫn đầu.
        let rivals = real.filter { $0.cand.kind == top.cand.kind && $0.cand.key != top.cand.key && $0.hits >= max(2, top.hits / 2) }
        guard rivals.isEmpty, ch == nil else { return }
        if top.hits >= 3 && now.timeIntervalSince(top.first) >= 1.0 { accept(top.cand) }
    }

    /// Kết quả đọc mã QR của một khung hình. DETAIL!!! đọc trùng 2 lần thì nhận; QR loại khác chỉ hiện nguyên chuỗi để chạm sao chép.
    func ingestQR(_ payloads: [String]) {
        guard !finished else { return }
        var next: [String: Int] = [:]
        for p in payloads {
            next[p] = (qrStreak[p] ?? 0) + 1
            if let d = QRParser.parse(p) {
                if (next[p] ?? 0) >= 2 {
                    finished = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onQR?(d)
                    return
                }
            } else if let r = QRParser.parseDoc(p) {
                if (next[p] ?? 0) >= 2 {
                    finished = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onQRRsi?(r)
                    return
                }
            } else if otherQR != p { otherQR = p }
        }
        qrStreak = next
        if payloads.isEmpty, otherQR != nil, Date().timeIntervalSince(lastSeen) > 1.5 { otherQR = nil }
    }

    func accept(_ c: PkgCandidate) {
        guard !finished else { return }
        finished = true
        PkgParser.learn(c)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onAccept?(c)
    }
}

// MARK: - Camera + Vision

final class CameraVC: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onObs: (([OCRObs]) -> Void)?
    var onQR: (([String]) -> Void)?
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
            var obs: [OCRObs] = []
            for o in (r.results as? [VNRecognizedTextObservation]) ?? [] {
                // Lấy tới 3 cách đọc cho mỗi dòng: chữ viết tay hay bị đọc nhiều kiểu
                let texts = o.topCandidates(3).filter { $0.confidence > 0.25 }.map { $0.string }
                if !texts.isEmpty { obs.append(OCRObs(texts: texts, box: o.boundingBox)) }
            }
            DispatchQueue.main.async { self?.onObs?(obs) }
            self?.busy = false
        }
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US"]
        req.minimumTextHeight = 0.015
        let bar = VNDetectBarcodesRequest()
        bar.symbologies = [.qr]
        let handler = VNImageRequestHandler(cvPixelBuffer: px, orientation: .right, options: [:])
        do {
            try handler.perform([bar, req])
            let codes = ((bar.results as? [VNBarcodeObservation]) ?? []).compactMap { $0.payloadStringValue }
            DispatchQueue.main.async { [weak self] in self?.onQR?(codes) }
        } catch { busy = false }
    }
}

struct CameraRepresentable: UIViewControllerRepresentable {
    @ObservedObject var state: ScanState

    func makeUIViewController(context: Context) -> CameraVC {
        let vc = CameraVC()
        vc.onObs = { [weak state] in state?.ingest($0) }
        vc.onQR = { [weak state] in state?.ingestQR($0) }
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

// MARK: - Khung chọn 1 trong 2 (Package No / Packing List No)

private enum ScanPalette {
    static let package = Color(red: 0.11, green: 0.31, blue: 0.85)
    static let packingList = Color(red: 0.04, green: 0.52, blue: 0.47)
}

/// Thẻ chọn khi thấy cả 2 số: hai ô lớn, mỗi ô là một lựa chọn. Dùng cả trên camera lẫn khi quét từ ảnh.
struct ScanChoiceCard: View {
    let choice: ScanChoice
    var onCamera: Bool = true
    let onPick: (PkgCandidate) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill").font(.system(size: 13, weight: .bold))
                Text("Thấy 2 số trên tem, chạm số cần mở").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(onCamera ? Color.white.opacity(0.9) : Color.secondary)
            if let p = choice.package { option(p, icon: "shippingbox.fill", color: ScanPalette.package) }
            if let l = choice.packingList { option(l, icon: "list.bullet.rectangle.fill", color: ScanPalette.packingList) }
        }
        .padding(14)
        .background(onCamera ? AnyShapeStyle(Color.black.opacity(0.62)) : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(onCamera ? 0.14 : 0), lineWidth: 1))
    }

    private func note(_ c: PkgCandidate) -> String {
        if c.derived { return "suy ra từ số kia" }
        return c.printed ? "đọc rõ" : "chữ viết tay, kiểm tra lại"
    }

    private func option(_ c: PkgCandidate, icon: String, color: Color) -> some View {
        Button { onPick(c) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.kind.title.uppercased()).font(.system(size: 11, weight: .bold)).opacity(0.85)
                    Text(c.display).font(.system(size: 17, weight: .bold, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(note(c)).font(.system(size: 11)).opacity(0.8)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right.circle.fill").font(.system(size: 22)).opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [color, color.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: color.opacity(0.35), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

/// Khung chọn dạng sheet cho trường hợp quét từ ảnh có sẵn.
struct ScanChoiceSheet: View {
    let choice: ScanChoice
    let onPick: (PkgCandidate) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Tìm thấy 2 số trong ảnh").font(.system(size: 19, weight: .bold)).padding(.top, 22)
            ScanChoiceCard(choice: choice, onCamera: false, onPick: onPick)
            Button("Hủy", action: onCancel)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 14).padding(.bottom, 8)
    }
}

// MARK: - Màn hình quét

struct PackageScannerView: View {
    let onPick: (PkgCandidate) -> Void
    let onQR: (QRDetail) -> Void
    let onRsi: (QRRsi) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var st = ScanState()

    init(onPick: @escaping (PkgCandidate) -> Void, onQR: @escaping (QRDetail) -> Void = { _ in }, onRsi: @escaping (QRRsi) -> Void = { _ in }) {
        self.onPick = onPick
        self.onQR = onQR
        self.onRsi = onRsi
    }

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
        .animation(.easeOut(duration: 0.18), value: st.choice?.id)
        .onAppear {
            st.onAccept = { c in
                dismiss()
                onPick(c)
            }
            st.onQR = { d in
                dismiss()
                onQR(d)
            }
            st.onQRRsi = { r in
                dismiss()
                onRsi(r)
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
            if let q = st.otherQR {
                Button { UIPasteboard.general.string = q } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("QR chưa hỗ trợ · chạm để sao chép").font(.system(size: 12, weight: .semibold))
                        Text(q).font(.system(size: 13, design: .monospaced)).lineLimit(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if let ch = st.choice {
                ScanChoiceCard(choice: ch) { st.accept($0) }
            } else if st.candidates.isEmpty && st.otherQR == nil {
                Text("Đưa camera vào tem: dòng Package No hoặc Shipment No (chữ in hoặc viết tay), mã QR, hay phiếu RSI xuất kho / MRF trả hàng (QR hoặc dòng RSI No / MRF No).\nChạm màn hình để lấy nét.")
                    .font(.system(size: 14, weight: .medium)).multilineTextAlignment(.center)
                    .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(st.candidates) { c in
                    Button { st.accept(c) } label: {
                        HStack {
                            Image(systemName: c.printed ? "checkmark.circle.fill" : "hand.draw")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.kind.title).font(.system(size: 11, weight: .bold)).opacity(0.85)
                                Text(c.display).font(.system(size: 17, weight: .bold, design: .monospaced))
                            }
                            Spacer()
                            Text(c.printed ? "tự nhận" : "chạm để chọn").font(.system(size: 12))
                        }
                        .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 12)
                        .background((c.kind == .package ? ScanPalette.package : ScanPalette.packingList).opacity(0.92),
                                    in: RoundedRectangle(cornerRadius: 12))
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


extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}


// MARK: - Quét từ ảnh có sẵn (chọn trong thư viện)

enum ImageScanResult {
    case detail(QRDetail)
    /// Phiếu RSI (xuất kho) hoặc MRF (trả hàng): QR `RSI!!!…` / `MRF!!!…` hoặc chữ số phiếu → mở tab Xuất kho / Trả hàng
    case rsi(QRRsi)
    /// Chỉ có một số (Package hoặc Packing List) → mở luôn
    case package(PkgCandidate)
    /// Có cả hai số → cho người dùng chọn
    case choose(ScanChoice)
    case otherQR(String)
    case none
}

enum ImageScanner {
    /// Ưu tiên QR (DETAIL!!!…); không có QR thì đọc chữ Package No / Packing List No.
    static func scan(_ img: UIImage, completion: @escaping (ImageScanResult) -> Void) {
        guard let cg = img.cgImage else { completion(.none); return }
        let ori = CGImagePropertyOrientation(img.imageOrientation)
        DispatchQueue.global(qos: .userInitiated).async {
            let bar = VNDetectBarcodesRequest()
            bar.symbologies = [.qr]
            let txt = VNRecognizeTextRequest()
            txt.recognitionLevel = .accurate
            txt.usesLanguageCorrection = false
            txt.recognitionLanguages = ["en-US"]
            txt.minimumTextHeight = 0.008
            let h = VNImageRequestHandler(cgImage: cg, orientation: ori, options: [:])
            try? h.perform([bar, txt])
            let codes = ((bar.results as? [VNBarcodeObservation]) ?? []).compactMap { $0.payloadStringValue }
            var obs: [OCRObs] = []
            for o in (txt.results ?? []) {
                let texts = o.topCandidates(3).filter { $0.confidence > 0.25 }.map { $0.string }
                if !texts.isEmpty { obs.append(OCRObs(texts: texts, box: o.boundingBox)) }
            }
            var out = ImageScanResult.none
            if let d = codes.compactMap({ QRParser.parse($0) }).first { out = .detail(d) }
            else if let r = codes.compactMap({ QRParser.parseDoc($0) }).first { out = .rsi(r) }
            else if let o = codes.first { out = .otherQR(o) }
            else if let doc = RsiNoOCR.findDoc(obs) { out = .rsi(doc) }
            else {
                let p = PkgParser.pair(PkgParser.candidates(in: obs))
                if let a = p.package, let b = p.packingList {
                    out = .choose(ScanChoice(package: a, packingList: b))
                } else if let one = p.package ?? p.packingList {
                    out = .package(one)
                }
            }
            DispatchQueue.main.async { completion(out) }
        }
    }
}
