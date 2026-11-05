<p align="center">
  <img src="../doni-icon.png" width="128" alt="Doni 应用图标：红色渐变背景上，白色纸飞机覆在淡化的音符上">
</p>

# Doni

[English](../../README.md) · [Tiếng Việt](README.vi.md) · **中文** · [Español](README.es.md) ·
[Français](README.fr.md) · [Русский](README.ru.md) · [العربية](README.ar.md)


iPhone 音乐播放器，播放你已经存在 Telegram 里的歌：你订阅的频道，以及当作私人曲库的 Saved Messages。
背后没有服务器，不用注册账号，也不上传任何数据。

<table>
  <tr>
    <td><img src="../screenshots/home.jpg" width="220"></td>
    <td><img src="../screenshots/now-playing.jpg" width="220"></td>
    <td><img src="../screenshots/lock-screen.jpg" width="220"></td>
    <td><img src="../screenshots/playlist.jpg" width="220"></td>
  </tr>
</table>

## 功能

- **立刻出声，边播边取。** 按播放位置附近的字节区间取文件，拖到 3:40 只要 3:40 附近那段，不下整个文件。
- **记住取过的部分。** 分块留在本机，被划掉应用也不丢；听完整首的歌离线还能放。
- **Cloud Music 就是 Saved Messages。** 上传即发到你自己的会话，随后删掉本机副本；在 Telegram 删除，这里也消失。
- **带时间的歌词**，来自 lrclib、NetEase、AMLL、QQ Music。正在唱的那句会替换锁屏和灵动岛上的歌名。
- **封面**取自文件内嵌标签或 Telegram 缩略图；服务端还没生成时会自动再问几次。
- **缓存有上限。** 额度由你定（默认 2 GiB），最少听的先清掉，正在放的永不删。
- 界面六种语言；代码里的源文案是越南语。

## 为什么用 Telegram

曲库本来就在那儿。每首歌是一条带文件的消息，每个文件都有 `file_unique_id`，在不同数据库里指同一串字节。
于是"这首歌是不是重复""听到哪了"由协议回答，不需要我再架一台服务器、付钱、还读你的隐私。
TDLib 负责网络：登录、重试、下载、文件缓存、CDN 跳转。Doni 只负责没人能替它决定的那部分。

## 流媒体是怎么做的

- `downloadFile` 有 offset 和 limit，但 limit 拦不住下载——TDLib 会一直取到被取消，所以窗口由应用自己关。
- `getFileDownloadedPrefixSize` 能回答*任意*偏移上已就绪多少字节，这是就绪位图，不是"下完没有"的开关，
  也是半截文件仍然可用的原因。
- 分块 64 KiB。窗口停在播放点前几 MB，用掉一半才往前挪。
- AVFoundation 通过 `AVAssetResourceLoaderDelegate` 要字节，它先用 2 字节探测，答得比要的多就会被拒，
  所以每次响应都按请求长度收窄。
- 就绪窗口之外的字节是垃圾。TDLib 没确认的内容不会进解码器，所以断网时音乐停下，而不是放噪声。

## 构建

需要 iOS 26、Xcode 26、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、CMake、Python 3，以及
[my.telegram.org](https://my.telegram.org) 的 `api_id`/`api_hash`。

```sh
make vendor       # 从源码编 TDLib 与 OpenSSL（首次约 20 分钟）
make project      # 由 project.yml 生成工程
cp Config/Tdlib.example.xcconfig Config/Tdlib.xcconfig   # 填入自己的 id/hash/team，此文件不入库
make build        # 编译门槛：警告即错误
make device && make install
```

## 发布

一个版本两个数字，都在 `project.yml`，必须同时改。`MARKETING_VERSION` 是 About 显示、tag 必须一致的那串；
`CURRENT_PROJECT_VERSION` 是构建号，把版本编进数字里：`90 | major | minor | patch`，所以 `9010000` 就是 1.0.0。
更新日志只写在 `RELEASE_NOTES.md`，中英两栏行数相等，`make notes` 生成应用内 JSON 与 release 正文。

## 限制

- 免费个人团队签名：最多 3 台设备，证书 7 天过期。
- 发布出来的 IPA 未签名，别人要用得用自己的团队重签。发布用 `make release`（本机编译、打 tag、推送并挂上 release），Actions 里的工作流保留给手动触发，用来验证干净检出能否构建。
- 暂不支持 CarPlay：需要 `carplay-audio` 权限，也就需要付费开发者账号。
- 歌词来自公开来源；没人写过的歌就是没有，应用会直说，不给空白页。
- 检查更新只提示新版本并打开发布页，不能自装。

## 许可与致谢

GPL-3.0（[LICENSE](../../LICENSE)）——歌词界面与若干页面取自 GPLv3 的
[MeloX](https://github.com/youshen2/MeloX)。**TDLib** BSL 1.0，**OpenSSL** Apache-2.0，
**SQLite** 存放曲库与歌单，**Telegram-iOS** GPL-2.0 仅用于量取间距与配色，未取其一行的代码。

Doni 与 Telegram 或任何音乐平台无关联、亦未获授权，只打开你账号里已有的文件。

联系：Telegram [@w1lliamcachamwri](https://t.me/w1lliamcachamwri) ·
[github.com/williamcachamwri/Doni](https://github.com/williamcachamwri/Doni)

