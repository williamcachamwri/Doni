# Doni Release Notes / Doni 更新日志

The body of a GitHub release and the "Release notes" screen inside the app are generated from this
file by `Scripts/release-notes.py`. One platform section, two language sections per platform, and the
bullet counts have to match — `make notes` fails when they do not.

History lives in git tags and in GitHub Releases. This file holds the current release only.

## macOS

### Tiếng Việt

- Lệnh Cmd+Q không còn làm app sụp (SIGABRT trong bộ lập lịch TDLib). Trước đây khi thoát, tiến trình huỷ các luồng trước khi TDLib kịp xác nhận đã đóng cơ sở dữ liệu, nên bộ kiểm tra luồng bị kích hoạt. Nay app đợi tín hiệu "đã đóng" từ TDLib trước khi thực sự thoát, với trần 10 giây.
- Lời bài hát trên desktop giờ vẽ từ renderer riêng của desktop (DoniLyricsDesktop), không còn dùng chung renderer của iOS. Khoảng cách giữa các dòng cũng được sửa cho khớp với tham chiếu.
- Có thể chọn nguồn lời bài hát mặc định (NetEase, QQ, LRCLIB) trong Cài đặt. Bộ chuyển đổi nguồn cho từng bài đã bị xoá vì thừa — một menu đã liệt kê đủ lựa chọn thì không cần thêm công tắc bật/tắt từng cái.

### English

- Cmd+Q no longer crashes the app (SIGABRT in the TDLib scheduler). Previously, the process destroyed its threads before TDLib could confirm the database was closed, triggering a thread assertion. The app now waits for TDLib's "closed" signal before exiting, with a 10-second ceiling.
- Desktop lyrics now draw from a dedicated desktop renderer (DoniLyricsDesktop) instead of reusing the iOS renderer. The vertical spacing between lines has also been fixed to match the reference.
- You can now choose the default lyrics source (NetEase, QQ, LRCLIB) in Settings. The per-source toggles have been removed — redundant, since a menu that already lists every choice does not need individual on/off switches for each one.

## iOS

### Tiếng Việt

- App không còn bị hệ thống giết khi nghe nhạc nền lâu (80% CPU sau 60 giây). Nguyên nhân là một TimelineView chạy mãi ngay cả khi màn hình tắt; giờ nó được cổng scenePhase chặn lại.
- Màn hình "Thêm" giờ giống hệt màn hình tràn của hệ thống iOS 26: danh sách dọc với icon đỏ, chữ trắng, và chevron. Trước đây nó vẽ tay với nền panel.
- Có thể chọn nguồn lời bài hát mặc định (NetEase, QQ, LRCLIB) trong Cài đặt. Bộ chuyển đổi nguồn cho từng bài đã bị xoá vì thừa — một menu đã liệt kê đủ lựa chọn thì không cần thêm công tắc bật/tắt từng cái.

### English

- The app is no longer killed by the system during long background listening (80% CPU after 60 seconds). A TimelineView kept running even when the screen was off; it is now gated by scenePhase.
- The "More" screen now matches the iOS 26 system overflow list: vertical rows with red icons, white text, and chevrons. Previously it was hand-drawn with a panel background.
- You can now choose the default lyrics source (NetEase, QQ, LRCLIB) in Settings. The per-source toggles have been removed — redundant, since a menu that already lists every choice does not need individual on/off switches for each one.
