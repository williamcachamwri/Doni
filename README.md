# Doni

Máy nghe nhạc cá nhân chạy trên iOS, lấy nhạc trực tiếp từ Telegram: các kênh bạn tham gia và
Saved Messages của chính bạn. Không có máy chủ trung gian, không có tài khoản riêng, không có telemetry.

Mã nguồn: <https://github.com/williamcachamwri/Doni> · Liên hệ: <https://t.me/w1lliamcachamwri>

## Nó làm gì

- **Phát trực tiếp từng phần.** Bài hát bắt đầu gần như ngay và tua được tới bất kỳ đoạn nào mà không
  phải tải cả file — app hỏi TDLib theo từng dải byte và chỉ lấy phần đang nghe.
- **Bộ nhớ đệm sống qua lần tắt app.** Cache chia theo mẩu, có hạn mức tự chọn, dọn theo bài nghe ít
  nhất. Bài nào đủ byte thì nghe được khi mất mạng.
- **Cloud Music là Saved Messages.** Tải file lên, gửi bài đang nghe vào đó, danh sách đọc từ lịch sử
  chat — không có kho thứ hai.
- **Lời bài hát khớp thời gian** từ lrclib, NetEase, AMLL và QQ Music; dòng đang hát hiện trên Dynamic
  Island và màn hình khoá.
- **Giao diện** theo phong cách Apple Music / MeloX: Liquid Glass, tab bar nổi, Now Playing kéo lên.

Mọi thứ bạn nghe đều nằm trong tài khoản Telegram của bạn. App chỉ gọi tới Telegram (qua TDLib) và tới
các nguồn lời bài hát để tra tên bài.

## Yêu cầu

- iOS 26 trở lên (giao diện dùng Liquid Glass của hệ thống).
- Xcode 26 + [XcodeGen](https://github.com/yonaskolb/XcodeGen) + Python 3.
- Một tài khoản Telegram, và `api_id` / `api_hash` của riêng bạn lấy từ <https://my.telegram.org>.
- Máy dev iPhone để cài (app ký bằng free personal team, tối đa 3 app, hết hạn sau 7 ngày).

## Cài đặt

```sh
make vendor      # biên dịch TDLib + OpenSSL thành XCFramework (chạy lần đầu, ~20 phút)
make project     # sinh Doni.xcodeproj từ project.yml
```

Rồi tạo `Config/Tdlib.xcconfig` (đã được `.gitignore`, **đừng commit**):

```
TDLIB_API_ID=12345
TDLIB_API_HASH=0123456789abcdef0123456789abcdef
DONI_TEAM_ID=AAAAAAAAAA
```

```sh
make build       # compile cho iOS, không ký — đây là cổng "0 warning"
make device      # compile + ký bằng team của bạn
make check       # build + test package + cổng ngôn ngữ
make install     # cài lên máy đang cắm cáp (devicectl)
```

## Phát hành

Một phiên bản có hai số, cả hai nằm trong `project.yml` và phải đổi cùng nhau:

| | |
|---|---|
| `MARKETING_VERSION` | phiên bản hiển thị và tên tag, ví dụ `1.0.0` |
| `CURRENT_PROJECT_VERSION` | số build, mã hoá chính phiên bản đó: `90 \| major \| minor \| patch`, nên `9010000` là `1.0.0` |

Nhật ký cập nhật viết tay trong [`RELEASE_NOTES.md`](RELEASE_NOTES.md) — phần `## iOS` phải có đủ
`### Tiếng Việt` và `### English` với số dòng bằng nhau.

```sh
make notes               # sinh App/Generated/ReleaseNotes.json + build/ReleaseNotes.md
Scripts/build-unsigned-ipa.sh   # build Release không ký + gói thành build/Doni.unsigned.ipa
```

Rồi cắt tag và đẩy lên GitHub — workflow `build-unsigned.yml` sẽ dựng IPA, đính kèm vào release và
dùng `build/ReleaseNotes.md` làm nội dung:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

File IPA là **chưa ký**: nó để lưu trữ và cho người khác tự ký lại bằng team của chính họ. App không
tự cập nhật — bản ký bởi team này cài lên máy khác sẽ bị từ chối.

## Giấy phép & ghi công

- Doni phát hành theo **GPL-3.0** (xem [`LICENSE`](LICENSE)) vì màn lời bài hát và một số màn giao diện
  được bê từ MeloX, vốn là GPLv3.
- **MeloX** — app tham chiếu cho giao diện; một số file được chép nguyên trạng.
- **TDLib** — Boost Software License 1.0, thư viện Telegram chính thức.
- **OpenSSL** — Apache-2.0, chỉ để TDLib nói chuyện TLS.
- **Telegram-iOS** — GPL-2.0. Chỉ dùng để *đo* số đo giao diện; không một dòng code nào lấy từ đó.
- **lrclib / NetEase / AMLL / QQ Music** — dịch vụ web cho lời bài hát, gọi từ máy của bạn.

## Miễn trừ trách nhiệm

Doni là ứng dụng không chính thức, không liên kết và không được Telegram hay bất kỳ hãng nhạc nào uỷ
quyền. Nó chỉ mở những file đang nằm trong tài khoản Telegram của bạn; việc bạn dùng bot, kênh hay
file nào là trách nhiệm của bạn.
