// DESM Mobile — điểm vào của app iOS bọc website DESM (Doosan Enerbility) thành giao diện di động.
// Xem DEV_NOTES.md (thư mục gốc project) để hiểu kiến trúc, bản đồ file và những điều đã biết về web DESM.
import SwiftUI

@main
struct DESMMobileApp: App {
    init() { BackgroundRefresh.register(); LegacyAICleanup.runOnce() }

    var body: some Scene {
        WindowGroup { BrowserView() }
    }
}
