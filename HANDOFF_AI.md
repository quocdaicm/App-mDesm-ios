## ⚠️ QUY ƯỚC BẮT BUỘC khi thêm mục/màn hình mới vào "Thêm" (More) — AI nào làm tiếp cũng phải theo
1. **Mục mới = một màn native mở dạng sheet từ `UI/MoreSheet.swift`** (thêm `Item` vào `webItems` hoặc `toolItems`, thêm callback `onXxx` rồi nối trong `UI/BrowserView.swift`). Sheet đăng ký trong `BrowserView.swift` bằng `.sheet { MànMới(model:, onClose:) .desmSheet() }`.
2. **Luôn gắn `.desmSheet()`** cho sheet mới: modifier này đã tự thêm (a) nút camera nổi góc dưới phải để chụp CẢ danh sách thành một ảnh dài (`DesmShotModifier` trong `UI/ShareSheet.swift`), (b) sheet toàn chiều cao, thanh kéo, màu nhấn `Color.tabBlue`. Không tự viết lại nút chụp riêng cho từng màn. Nếu bắt buộc không dùng `desmSheet()` thì gọi `.desmShotButton()`. Chỉ truyền `.desmSheet(shot: false)` cho màn có ô nhập/thanh gửi ở đáy (như AI chat, Cài đặt) và phải ghi lý do.
3. **Nội dung cuộn phải là `ScrollView`/`List` thật** (LazyVStack trong ScrollView đều được) để bộ chụp cuộn-ghép tìm thấy được. Đừng tự dựng cuộn bằng gesture/offset, đừng lồng nhiều ScrollView dọc.
4. **Đồng bộ giao diện app**: dùng `Color.tabBlue`/`tabBlueLight`, hộp thoại dùng `.desmAlert`/`.desmDialog` (KHÔNG dùng `.alert`/`confirmationDialog` hệ thống), chữ tiếng Việt, tiêu đề + nút "Đóng" ở thanh trên theo mẫu các sheet trong `Sheets/`. Thẻ dữ liệu, bộ lọc, trạng thái rỗng/lỗi làm giống các màn có sẵn (xem `Sheets/Outgoing.swift`, `Sheets/DocSheet.swift`).
5. File Swift mới phải được thêm vào `DESMMobile.xcodeproj/project.pbxproj` (PBXBuildFile, PBXFileReference, nhóm, Sources) — hoặc đặt code vào file có sẵn cho khỏi sửa pbxproj.
6. Sau khi thêm mục mới: cập nhật `DEV_NOTES.md`, và nhớ nói rõ với người dùng "chưa build/chưa thử máy thật" nếu chưa build.

> **LƯU Ý (2026-10-30, cập nhật): "AI riêng" đã được ĐƯA LẠI bằng bản viết lại gọn trong `DESMMobile/AI/` — xem mục cuối DEV_NOTES.md. Các mô tả bên dưới là bản cũ, chỉ để tham khảo.**

# BÀN GIAO CHO AI KHÁC — DESM Mobile: thêm "AI riêng" cho bong bóng Dodo

Người dùng nói tiếng Việt, làm app iOS (SwiftUI, iOS 16+), build bằng GitHub Actions (IPA không ký), KHÔNG có Xcode nên mọi code dưới đây **CHƯA được biên dịch**. Đọc thêm `DEV_NOTES.md` (cuối file có 3 mục AI mới).

## 1. Yêu cầu của người dùng (theo thứ tự)
1. Lấy toàn bộ phần AI trong app dịch **LiveTranslate** (nhiều nhà AI, dò model, tự chọn model dùng được) ghép vào **Dodo AI** của DESM để có nhiều lựa chọn AI.
2. AI phải đọc được dữ liệu DESM để trả lời; rồi: "đọc được cả trang", rồi "đọc tất cả web DESM kể cả hạng mục chi tiết và các mục sâu, đang mở hoặc chưa mở".
3. Hỏi Dodo gốc có làm được như vậy không → đã tải `Dodo.js` để phân tích.

## 2. Đã làm (trong DESM_Mobile_iOS.zip)
Thư mục mới `DESMMobile/AI/` (đã thêm vào `project.pbxproj`, nhóm "AI"):
- `AIProviders.swift` — 8 nhà: Gemini, Groq, Claude, OpenAI, DeepSeek, Mistral, OpenRouter, Tùy chỉnh (OpenAI-compatible). Key trong Keychain (`DESMMobile.AI`), model/thứ tự ưu tiên trong UserDefaults.
- `AIClient.swift` — gọi 3 kiểu API, `listModels`, `pickWorkingModel` (thử tối đa 8 model), `run` (lỗi thì chuyển nhà kế tiếp).
- `AIAgent.swift` — function calling (tối đa 6 vòng) cho OpenAI/Claude/Gemini; model không hỗ trợ công cụ (HTTP 400/404/422) thì lùi về hỏi đáp thường.
- `DesmAITools.swift` — công cụ CHỈ ĐỌC: `desm_list_endpoints`, `desm_query(endpoint, params_json, max_rows)`, `desm_recorded_endpoints` (đọc `NetLogStore`), `desm_read_open_page`. Danh mục API lấy từ các màn native (package `/getIdsmOsSummaryList.do`, hạng mục chi tiết `/getIdsmOsDetailList.do`, RSI, MRF, WIP, edit log, tàu, notice, home summary). Chặn API có từ ghi (save/delete/update…). Cắt kết quả ~24.000 ký tự/500 dòng.
- `AISettingsView.swift` — danh sách nhà, nhập key, dò model, tự chọn model, kéo đổi thứ tự.
- `AIChatView.swift` — khung chat native, đổi nhanh nhà/model, hội thoại giữ trong bộ nhớ (`AIChatSession.shared`), chưa streaming.

Sửa file có sẵn (nhỏ):
- `Core/BrowserModel.swift`: `aiEngine` ("dodo"|"ai"), `aiData`, `aiLimit` (12000/40000/120000), `aiTools`, `showAIChat`, `fetchScreenTextForAI(limit:)`.
- `Scripts/DodoBubble.swift`: `w.__desmDodoEngine`; khi = 'ai' chạm bong bóng gửi message `desmAI`; thêm `pageText(limit)` (đọc mọi khung/iframe đang hiện, toàn bộ dòng TreeGrid đã tải kể cả cột ẩn, ô nhập, văn bản) và export `screenText`, `pageText` trong `w.__desmDodo`.
- `Web/WebView.swift`: đăng ký/gỡ/nhận handler `desmAI` → `model.showAIChat = true`.
- `UI/BrowserView.swift`: sheet `AIChatView`.
- `Settings/SettingsView.swift` (mục Trợ lý Dodo): Picker "Chạm bong bóng mở" (Dodo/AI riêng), link tới `AIProviderListView`, 2 toggle "Cho AI tự tra dữ liệu DESM (chỉ đọc)" (`desmAITools`) và "Gửi kèm dữ liệu trang đang mở" (`desmAIData`), Picker lượng dữ liệu. Cả hai toggle **mặc định TẮT** (dữ liệu công ty đi tới nhà AI ngoài).

## 3. Phát hiện từ `Dodo.js` (người dùng đã tải)
- Dodo là widget server: `POST /dodo/chat/stream.do` (form): `user_prompt`, `menu_context` (JSON mảng: thông tin menu + `module:'ps'` + `screen_context` từ `ScreenContext.snapshot()`), `session_id`, `mode` = `fast|slow`, `ui_selection`. Phản hồi SSE: `token`, `section`, `status`, `final_state`, `choices`, `error`, `done`. Còn `sessions.do`, `history.do`, `delete.do`, `reset.do`.
- Server có bước **`call_api`** ("đang truy vấn dữ liệu") → Dodo tự gọi API ở server, có thể trả lời cả mục chưa mở. Phạm vi thật chưa biết.
- Chọn **Slow** (chính xác) thay vì Fast cho câu hỏi dữ liệu. App không đổi được model của Dodo.
- Lỗi cũ trong DEV_NOTES: Dodo trả lời "không có dữ liệu bảng" dù màn có 17 kiện (`ScreenContext.snapshot()` không lấy được lưới trong app). App đang vòng bằng cách nối bảng kiện (màn Package dạng thẻ, ≤300 kiện) vào `user_prompt` qua bọc `fetch`.

## 4. CHƯA kiểm chứng / rủi ro biên dịch
- Chưa build lần nào. Chỗ dễ lỗi: `AIChatView.send()` (chuỗi nhiều dòng `"""` có `\` nối dòng, tuple `(text, by)`), closure `status`/`exec` của `runAgent`, `Task { @MainActor in }` trong View, `onChange` bản 1 tham số (iOS 16), `TextField(axis:)`.
- Chưa biết: API nào chấp nhận khoá tham số để trống; model free (Groq/OpenRouter) có hỗ trợ công cụ không; `G.Rows` của TreeGrid lặp được như dự kiến (`pageText`); chạm bong bóng khi chọn AI riêng có mở đúng khung.
- `/getDesmMrrInfoList.do` chưa hỗ trợ (kết quả dạng object, `desmQueryAsync` chỉ đọc mảng). File đính kèm chưa đọc.
- AI chỉ tra được API trong danh mục hoặc đã được ghi (cần bật "Ghi lại các request API" ở Nâng cao rồi duyệt các màn).

## 5. Việc nên làm tiếp (theo ưu tiên)
1. Build bằng GitHub Actions, sửa lỗi biên dịch.
2. Người dùng thử Dodo ở chế độ **Slow** với 3 câu (hạng mục của một kiện chưa mở; một RSI cụ thể; màn đang mở) để quyết định còn cần AI riêng cho câu hỏi dữ liệu không.
3. ✅ ĐÃ LÀM (chưa kiểm chứng) — Cho Dodo đọc cả trang: nối `pageText()` vào `user_prompt` ở `DodoBubble.swift` cho mọi màn (dữ liệu chỉ tới server DESM).
4. (Lớn, chỉ khi có nhật ký API thật của một lần hỏi Dodo) Đưa Dodo vào chung khung `AIChatView` bằng cách parse SSE ở trên.
5. Thêm streaming, lưu hội thoại, hỗ trợ `getDesmMrrInfoList` nếu cần.

## 6. Lưu ý với người dùng
- Trả lời bằng tiếng Việt, ngắn gọn. Luôn nói rõ chưa build/chưa kiểm chứng.
- Bật AI riêng = câu hỏi và dữ liệu DESM đi tới nhà cung cấp AI do người dùng chọn; chỉ bật khi công ty cho phép. Không thêm công cụ ghi/sửa/xoá.
- Cảnh báo khi tải thử Dodo: đừng gọi `reset.do`/`delete.do` (xoá lịch sử chat).

## 7. Cập nhật lượt sau (2026-10-29)
- Đã làm mục 5.3 (fallback `pageText(20000)` trong wrapper `fetch` của DodoBubble.swift) và vá `Task { @MainActor in }` trong `AIChatView.send()`. Mục 5.1 (build) vẫn chờ người dùng chạy GitHub Actions và gửi log lỗi.

## 8. Cập nhật (2026-10-30, chống treo)
- Xem mục "AI riêng: chống treo + nhật ký" cuối DEV_NOTES.md: thêm `AI/AILog.swift`, giới hạn thời gian mọi bước, parse JSON ngoài luồng chính, khung chat không còn theo dõi BrowserModel. Khi người dùng báo treo: nhờ họ gửi file từ Cài đặt > AI riêng > Nhật ký AI > Chia sẻ file.
