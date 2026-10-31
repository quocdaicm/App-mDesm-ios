// BackgroundRefresh.swift — kiểm tra DESM ở nền (BGAppRefreshTask) và báo bằng thông báo cục bộ khi app đã đóng.
//
// Báo 3 loại: (1) thông báo DESM mới; (2) tàu sắp đến (ETA trong 7 ngày, `DesmVessel.arrivingSoon`); (3) RSI mới, MRF mới/đã trả (công tắc desmBgRsi / desmBgMrf).
// Dùng desmQueryAsync không cần WebView: cookie lấy từ Keychain (SessionStore.storedCookies).
// iOS KHÔNG đảm bảo giờ chạy (thường vài lần/ngày, ít khi nếu ít mở app, tắt "Làm mới ứng dụng nền" thì không chạy).
// Cần thông báo đúng lúc thì phải có backend đẩy tin (APNs). Hết phiên DESM thì lượt kiểm tra đó bỏ qua, không báo lỗi.
// Cấu hình: Info.plist có BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes=fetch. Công tắc: Cài đặt > "Thông báo khi app đóng" (desmBgNotify).
// CHƯA kiểm chứng trên máy thật. Cách thử: chạy bằng Xcode, tạm dừng app rồi trong lldb gõ
//   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.desm.mobile.refresh"]

import Foundation
import BackgroundTasks
import UserNotifications

enum BackgroundRefresh {
    static let taskId = "com.desm.mobile.refresh"
    static let notifiedNoticesKey = "desmNotifiedNotices"
    static let notifiedVesselsKey = "desmNotifiedVessels"
    static let notifiedDocsKey = "desmNotifiedDocs"
    static var rsiEnabled: Bool { UserDefaults.standard.object(forKey: "desmBgRsi") as? Bool ?? true }
    static var mrfEnabled: Bool { UserDefaults.standard.object(forKey: "desmBgMrf") as? Bool ?? true }

    static var enabled: Bool { UserDefaults.standard.object(forKey: "desmBgNotify") as? Bool ?? true }

    /// Gọi một lần khi app khởi động (trước khi app chạy xong launch).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            guard let t = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(t)
        }
    }

    /// Xin lịch chạy lần sau (sớm nhất sau 30 phút). Gọi khi app xuống nền và sau mỗi lần chạy nền.
    static func schedule() {
        guard enabled else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId); return }
        let req = BGAppRefreshTaskRequest(identifier: taskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        guard enabled else { task.setTaskCompleted(success: true); return }
        let work = Task { @MainActor in
            let ok = await check()
            task.setTaskCompleted(success: ok && !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Một lượt kiểm tra. Trả false nếu lỗi mạng (để iOS biết lượt này không thành công); hết phiên thì coi như xong.
    @MainActor
    static func check() async -> Bool {
        let model = BrowserModel()          // không có WebView -> desmQueryAsync dùng cookie Keychain
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let canAlert = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        var ok = true
        let ud = UserDefaults.standard

        // 1) Thông báo DESM mới
        do {
            let (list, _) = try await model.fetchNoticesAsync()
            let ids = list.map { $0.id }
            let seen = DesmNoticeSeen.load() ?? Set(ids)
            let unread = list.filter { !seen.contains($0.id) }
            if canAlert { try? await center.setBadgeCount(unread.count) }
            if let old = ud.array(forKey: notifiedNoticesKey) as? [String] {
                let known = Set(old)
                let fresh = unread.filter { !known.contains($0.id) }
                if canAlert {
                    for n in fresh.prefix(3) {
                        await post(id: "notice-\(n.id)", title: "Thông báo DESM mới", body: n.title.isEmpty ? "Có thông báo mới." : n.title)
                    }
                    if fresh.count > 3 { await post(id: "notice-more", title: "Thông báo DESM mới", body: "Và \(fresh.count - 3) thông báo khác.") }
                }
                ud.set(Array(known.union(ids)).suffix(500).map { $0 }, forKey: notifiedNoticesKey)
            } else {
                ud.set(ids, forKey: notifiedNoticesKey)   // lần đầu: chỉ ghi mốc, không báo dồn
            }
        } catch DesmAPIError.expired, DesmAPIError.noSession {
            return true                                    // hết phiên: bỏ qua, người dùng sẽ đăng nhập lại khi mở app
        } catch { ok = false }

        // 2) Tàu sắp đến (ETA < 7 ngày)
        do {
            let vessels = try await model.fetchVesselsAsync()
            var known = Set((ud.array(forKey: notifiedVesselsKey) as? [String]) ?? [])
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd"
            for v in vessels where v.arrivingSoon {
                guard let eta = v.tEnd else { continue }
                let key = "\(v.invoice)|\(f.string(from: eta))"
                if known.contains(key) { continue }
                known.insert(key)
                if canAlert {
                    let days = max(0, Int((eta.timeIntervalSinceNow / 86400).rounded(.up)))
                    let when = days == 0 ? "hôm nay" : "trong \(days) ngày"
                    let name = v.vessel.isEmpty ? v.invoice : "\(v.vessel) (\(v.invoice))"
                    await post(id: "vessel-\(key)", title: "Tàu sắp đến", body: "\(name) dự kiến đến \(v.pod.isEmpty ? "cảng" : v.pod) \(when).")
                }
            }
            ud.set(Array(known).suffix(300).map { $0 }, forKey: notifiedVesselsKey)
        } catch DesmAPIError.expired, DesmAPIError.noSession {
            return true
        } catch { ok = false }

        // 3) RSI mới tạo, MRF mới / MRF đã trả hàng (cùng truy vấn với màn "Hoạt động", 3 ngày gần nhất)
        var kinds = Set<DesmActivityKind>()
        if rsiEnabled { kinds.insert(.rsiNew) }
        if mrfEnabled { kinds.insert(.mrfNew); kinds.insert(.mrfReturn) }
        if !kinds.isEmpty {
            let r = await model.fetchActivityAsync(days: 3, only: kinds)
            // Có lỗi (mạng/hết phiên) thì bỏ qua cả bước, KHÔNG đổi mốc — nếu không lần sau sẽ báo dồn phiếu cũ
            if r.errors.isEmpty {
                let ids = r.items.map { $0.id }
                if let old = ud.array(forKey: notifiedDocsKey) as? [String] {
                    let known = Set(old)
                    let fresh = r.items.filter { !known.contains($0.id) }
                    if canAlert {
                        for a in fresh.prefix(4) {
                            let head: String
                            switch a.kind {
                            case .rsiNew: head = "RSI mới"
                            case .mrfNew: head = "MRF mới (yêu cầu trả hàng)"
                            default: head = "MRF đã trả hàng"
                            }
                            await post(id: "doc-\(a.id)", title: head, body: [a.title, a.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                        }
                        if fresh.count > 4 { await post(id: "doc-more", title: "DESM có phiếu mới", body: "Và \(fresh.count - 4) phiếu khác — mở mục Hoạt động để xem.") }
                    }
                    ud.set(Array(known.union(ids)).suffix(800).map { $0 }, forKey: notifiedDocsKey)
                } else {
                    ud.set(ids, forKey: notifiedDocsKey)      // lần đầu: chỉ ghi mốc, không báo dồn
                }
            }
        }
        return ok
    }

    private static func post(id: String, title: String, body: String) async {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }
}
