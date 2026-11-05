# Doni Release Notes / Doni 更新日志

The body of a GitHub release and the "Release notes" screen inside the app are generated from this
file by `Scripts/release-notes.py`. One platform section, two language sections per platform, and the
bullet counts have to match — `make notes` fails when they do not.

History lives in git tags and in GitHub Releases. This file holds the current release only.

## iOS

### Tiếng Việt

- Phát trực tiếp từng phần: bài hát bắt đầu gần như ngay, tua tới bất kỳ đoạn nào mà không phải tải cả file.
- Bộ nhớ đệm chia theo mẩu sống qua cả lần bị tắt cưỡng chế, có hạn mức tự chọn và dọn theo bài nghe ít nhất.
- Cloud Music chính là Saved Messages: tải file lên, gửi bài đang nghe vào cloud, đọc hết lịch sử chat.
- Lời khớp thời gian từ lrclib, NetEase, AMLL và QQ Music; dòng đang hát hiện trên Dynamic Island và màn hình khoá.
- Ảnh bìa lấy từ tag trong file hoặc thumbnail của Telegram, và hỏi lại khi Telegram chưa tạo xong ảnh.
- Trang chủ có "Gần đây phát", các shelf Mới nhất / Yêu thích / Trên máy và lưới "Nhạc" chia theo nhóm.
- Màn hình Bộ nhớ nói từng loại byte đang nằm ở đâu và cái gì xoá được.
- Kiểm tra phiên bản mới qua GitHub Releases, kèm release notes đọc ngay trong app.

### English

- Progressive streaming: a song starts almost at once and seeks anywhere without the whole file arriving first.
- A chunk cache that survives a force quit, with a quota you can set and a sweep that frees the least-heard songs.
- Cloud Music is Saved Messages: upload files, send the song you are hearing there, and read the whole chat.
- Timed lyrics from lrclib, NetEase, AMLL and QQ Music, with the line being sung on the Dynamic Island and the lock screen.
- Covers read out of the file's own tags or Telegram's thumbnail, asked again when Telegram has not made one yet.
- A Home feed with Recently played, the Newest / Liked / On-device shelves and a Nhạc grid split by group.
- A storage screen that says where each kind of byte lives and what can be reclaimed.
- Update checks against GitHub Releases, with the release notes readable inside the app.
