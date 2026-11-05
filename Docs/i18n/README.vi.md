# Doni

[English](../../README.md) · **Tiếng Việt** · [中文](README.zh.md) · [Español](README.es.md) ·
[Français](README.fr.md) · [Русский](README.ru.md) · [العربية](README.ar.md)


Máy nghe nhạc cho iPhone, phát những bài đã có sẵn trong Telegram của bạn: kênh bạn theo dõi, và
Saved Messages như thư viện riêng. Không có máy chủ đứng sau, không đăng ký tài khoản, không gửi số
liệu đi đâu.

<table>
  <tr>
    <td><img src="../screenshots/home.jpg" width="220"></td>
    <td><img src="../screenshots/now-playing.jpg" width="220"></td>
    <td><img src="../screenshots/lock-screen.jpg" width="220"></td>
    <td><img src="../screenshots/playlist.jpg" width="220"></td>
  </tr>
</table>

## Nó làm gì

- **Bắt đầu ngay, vừa phát vừa tải.** Bài hát được lấy theo dải byte quanh vị trí đang nghe, nên tua
  tới 3:40 chỉ xin phần quanh 3:40 chứ không tải cả file.
- **Nhớ những gì đã tải.** Các mẩu ở lại trên máy kể cả khi app bị tắt khỏi switcher. Bài đã nghe hết
  thì nghe lại được khi mất mạng.
- **Cloud Music chính là Saved Messages.** Tải file lên là gửi vào chat của chính bạn rồi xoá bản trên
  máy; xoá trong Telegram thì bài đó cũng rời khỏi app.
- **Lời khớp thời gian** từ lrclib, NetEase, AMLL và QQ Music. Dòng đang hát thay tên bài trên màn hình
  khoá và Dynamic Island.
- **Ảnh bìa** lấy từ tag trong file hoặc thumbnail của Telegram; Telegram chưa tạo xong thì hỏi lại vài lần.
- **Cache có trần.** Bạn chọn hạn mức (mặc định 2 GiB), bài nghe ít nhất bị dọn trước, bài đang nghe
  không bao giờ bị xoá.
- Giao diện có sáu ngôn ngữ; chuỗi trong code là tiếng Việt.

## Vì sao là Telegram

Vì thư viện đã nằm ở đó. Mỗi bài là một message mang theo một file, và mỗi file có `file_unique_id`
nghĩa là cùng một dòng byte ở mọi database — nên "bài này đã có chưa" và "dừng ở đâu" do giao thức trả
lời, không cần một máy chủ mà tôi phải nuôi và phải đọc tin của bạn.

TDLib lo phần mạng: đăng nhập, thử lại, tải file, cache, chuyển hướng CDN. Doni lo phần mà không ai
quyết hộ được.

## Streaming thật diễn ra thế nào

- `downloadFile` nhận offset và limit, nhưng limit không chặn nổi việc tải — TDLib vẫn tải tiếp cho tới
  khi bị cancel, nên app tự đóng từng cửa sổ.
- `getFileDownloadedPrefixSize` trả số byte đã sẵn sàng ở *mọi* offset: đó là ready bitmask, không phải
  cờ "xong chưa", và nó là lý do một file tải dở vẫn dùng được.
- Mẩu có kích thước 64 KiB. Cửa sổ nằm trước đầu phát vài MB và dịch khi khoảng nửa cửa sổ đã nghe xong.
- AVFoundation hỏi byte qua `AVAssetResourceLoaderDelegate`. Nó mở file bằng một probe 2 byte và từ chối
  trả lời dài hơn chỗ nó xin, nên mọi phản hồi đều bị buộc theo yêu cầu.
- Byte nằm ngoài cửa sổ đã sẵn sàng là rác. Không có gì được đưa vào decoder mà TDLib chưa xác nhận — vì
  thế mất mạng thì nhạc dừng lại, không phát nhiễu.

## Build

Cần iOS 26, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), CMake, Python 3 và
`api_id`/`api_hash` từ [my.telegram.org](https://my.telegram.org).

```sh
make vendor       # biên dịch TDLib + OpenSSL thành XCFramework (~20 phút lần đầu)
make project      # sinh Doni.xcodeproj từ project.yml
cp Config/Tdlib.example.xcconfig Config/Tdlib.xcconfig
# điền api_id, api_hash, team id — file này đã gitignore, chỉ nằm ở máy bạn
make build        # cổng compile: warning là lỗi
make device       # compile và ký cho iPhone của bạn
make install      # cài qua cáp
```

## Phát hành

Một phiên bản, hai số, cả hai trong `project.yml` và phải đổi cùng nhau: `MARKETING_VERSION` là thứ
About hiển thị và tag phải khớp; `CURRENT_PROJECT_VERSION` là số build mang đúng phiên bản trong các
chữ số — `90 | major | minor | patch`, nên `9010000` là 1.0.0.

Nhật ký cập nhật viết một lần trong `RELEASE_NOTES.md`, hai ngôn ngữ cùng số dòng; `make notes` sinh
JSON cho app và markdown cho release.

```sh
make notes      # RELEASE_NOTES.md → JSON cho app + nội dung release
make release    # build ở máy, tag đúng phiên bản, push, tạo release kèm IPA
```

`make release` chạy `Scripts/build-unsigned-ipa.sh`, chuyển tag về commit vừa build, push cả hai rồi
đính IPA vào release. Workflow vẫn còn đó nhưng bật bằng tay từ tab Actions: nó dựng lại từ checkout
sạch để trả lời câu hỏi CI giỏi thật — *project này build được ở máy khác không?*

## Giới hạn

- Ký bằng free personal team: tối đa 3 máy, chứng chỉ hết hạn sau 7 ngày.
- IPA phát hành là bản chưa ký; muốn cài phải tự ký lại bằng team của bạn.
- Chưa có CarPlay: cần entitlement `carplay-audio`, tức tài khoản Apple developer trả phí.
- Lời bài hát lấy từ nguồn công khai; bài chưa ai gõ lời thì app nói là không có, không để trang trắng.
- Kiểm tra cập nhật chỉ báo có bản mới và mở trang phát hành, không tự cài.

## Giấy phép & ghi công

GPL-3.0 ([LICENSE](../../LICENSE)) — màn lời bài hát và một số màn giao diện bê từ
[MeloX](https://github.com/youshen2/MeloX), vốn là GPLv3.

- **TDLib** — Boost Software License 1.0.
- **OpenSSL** — Apache-2.0.
- **SQLite** — thư viện, danh sách và tim nằm trong một file.
- **Telegram-iOS** — GPL-2.0, chỉ dùng để đo khoảng cách và màu; không một dòng code lấy từ đó.

Doni không liên kết và không được Telegram hay bất kỳ hãng nhạc nào uỷ quyền. App chỉ mở file đã nằm
trong tài khoản của bạn.

## Liên hệ

Telegram: [@w1lliamcachamwri](https://t.me/w1lliamcachamwri) · Repo:
[github.com/williamcachamwri/Doni](https://github.com/williamcachamwri/Doni)

