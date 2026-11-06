# Doni Release Notes / Doni 更新日志

The body of a GitHub release and the "Release notes" screen inside the app are generated from this
file by `Scripts/release-notes.py`. One platform section, two language sections per platform, and the
bullet counts have to match — `make notes` fails when they do not.

History lives in git tags and in GitHub Releases. This file holds the current release only.

## iOS

### Tiếng Việt

- Thư viện nhạc index trở lại. Ở 1.0.2 hai câu upsert chứa comment `//` ngay trong text SQL, mà SQLite chỉ nhận `--` và `/* */`, nên câu truy vấn không compile được và Trang chủ hiện nguyên văn nó.
- Mọi lượt ghi bài hát đều bị từ chối âm thầm vì lỗi đó: một channel đăng bao nhiêu bài thì thư viện vẫn trống bấy nhiêu. Từ bản này các lượt ghi chạy bình thường.
- Không mất gì và không phải làm gì. Lượt ghi thất bại bị từ chối trước khi chạy, không ghi dở — database vẫn nguyên. Mở app lên, lượt đọc channel tự bù phần bài còn thiếu.
- Quy tắc mà hai comment đó ghi (một bài đã ở Saved Messages giữ `message_id` của post đó) nay nằm trong doc comment phía trên câu truy vấn, nơi nó không chạm tới parser nữa.

### English

- The library indexes again. In 1.0.2 two upsert statements carried `//` comments inside the SQL text itself, and SQLite accepts only `--` and `/* */`, so the statement never prepared and the home screen printed it verbatim.
- Every song write was refused silently because of it: however many songs a channel posted, the library stayed empty. Writes run normally from this build.
- Nothing was lost and there is nothing to do. A refused write never runs, so it never half-wrote — the database is intact. Open the app and the channel walk back-fills the missing songs.
- The rule those comments recorded (a song already in Saved Messages keeps that post's `message_id`) now lives in the doc comment above the statement, where it cannot reach the parser.
