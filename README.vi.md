# Wintage

**Theme Windows 95 vàng đậm cổ điển cho toàn bộ web.** Một userscript Tampermonkey định dạng lại mọi trang web thành ứng dụng Windows 95 nâu vàng đậm: viền 3D sắc nét từng pixel, không bo góc, không animation, không hiệu ứng chớp khi hover, Verdana ở mọi nơi.
[🤍 Ủng hộ nhà phát triển](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Web hiện đại tối ưu cho thẩm mỹ nhưng đánh đổi bằng khả năng sử dụng. Góc bo tròn thay thế phân cấp thị giác, animation thay thế phản hồi, bóng đổ thay thế cấu trúc, và chủ nghĩa tối giản thường gỡ bỏ chính những tín hiệu mà não ta dựa vào để hiểu một giao diện._

_Người dùng không nên phải đoán một thứ là nút, nhãn, thẻ hay văn bản thuần. Wintage mang lại ngôn ngữ thị giác tường minh: nút nổi, ô nhập lõm, ranh giới sắc nét, kiểu chữ nhất quán, không phiền nhiễu, và thay đổi trạng thái tức thì._

_Mọi thành phần truyền đạt mục đích của nó chỉ trong một cái nhìn, giảm tải nhận thức và khiến web trở lại như một công cụ chính xác thay vì một đống bong bóng trang trí._

[Nhật ký thay đổi](CHANGELOG.md)

## Cài đặt

1. Cài [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Nhấp **[Cài Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey tự mở trang cài đặt.
3. Xong. Mọi trang bạn ghé thăm giờ đang chạy Windows 95, bản vàng đậm.

## Cập nhật

- **Tự động:** script mang `@updateURL`/`@downloadURL` trỏ về repo này, nên Tampermonkey tự lấy phiên bản mới trong các lượt kiểm tra cập nhật định kỳ.
- **Làm mới thủ công:** Tampermonkey → **Utilities → Check for userscript updates**, hoặc chỉ cần nhấp lại link cài đặt — nó thay thế phiên bản cũ ngay tại chỗ, không cần gỡ cài đặt.
- **Thiếu dòng theme nghĩa là script cũ:** menu được sinh từ registry theme nhúng sẵn và bài kiểm tra phát hành yêu cầu đúng một dòng menu cho mọi palette nhúng. Nếu menu ngắn hơn danh sách palette bên dưới, hãy nhấp lại **Install Wintage** và xác nhận **Update** trong Tampermonkey.

## Mười sáu palette, và một công tắc

Wintage không còn là một palette. Sáu là cấu trúc của riêng UI.md xoay sang một họ màu khác (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad), Custom có thể chỉnh sửa và lưu từ trình cài desktop, và chín được nhập từ [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Mọi palette đều đạt WCAG AA trên ba token mang chữ — cổng build từ chối bất kỳ palette nào không đạt.

Chọn một từ **menu Tampermonkey** trên bất kỳ trang nào; lựa chọn được lưu theo người dùng, không theo trang, nên giữ nguyên trên mọi tên miền.

Palette nằm trong `themes/*.json`, bên ngoài script, vì một lý do: Tampermonkey tải lại `wintage.user.js` mỗi lần cập nhật, nên một palette sửa tay vào đó sẽ biến mất. Áp lại chúng lên một build mới bằng:

```powershell
.\install-themes.ps1 -Latest
```

## Ngoài trình duyệt

Cùng những palette đó cài được vào ứng dụng desktop — VS Code và Antigravity dưới dạng theme màu, ứng dụng Electron (Freebuff, ứng dụng agent Antigravity) qua một shim chèn chính stylesheet mà userscript này dùng. Có một GUI nhỏ cho việc đó:

Nhấp đúp **`Wintage Installer.vbs`** ở thư mục gốc repo. Nó mở GUI mà không có cửa sổ console. Bộ khởi chạy `.cmd` cũ chuyển tiếp đến cùng host ẩn đó; `desktop\WintageInstaller.ps1` vẫn có thể chạy trực tiếp để chẩn đoán.

Những gì mỗi target chạm tới và không chạm tới — kể cả hai ứng dụng bị hàn chết hoặc có màu biên dịch sẵn — được ghi trong **[desktop/README.md](desktop/README.md)**.

## Tính năng

- **Palette Golden Default** — nền nâu đen sâu `#1A1810`, chữ vàng `#D4C89A`, viền nổi vàng `#F0D060`. Chỉ bề mặt phẳng đặc: không gradient, không mờ, không hiệu ứng trong suốt.
- **Viền 3D cổ điển** — nút nổi, ô nhập lõm, nút bị nhấn thì lún vào (kèm dịch chuyển nhãn 1px chân thật). Thanh cuộn đủ 16px kiểu Win95, đủ núm và nút viền.
- **Kẻ diệt bo góc** — ép `border-radius: 0` ở mọi nơi, gồm cả biến CSS framework (Bootstrap, Material, YouTube, Reddit).
- **Cấm chuyển động** — mọi transition và animation bị đưa về không. Thay đổi trạng thái tức thì, như một UI 1995 thật sự.
- **Tắt hoàn toàn highlight khi hover** — không hàng chớp trắng, không khối tô xám:
  - thuộc tính vẽ bị cắt phẫu thuật khỏi mọi luật CSS `:hover` đọc được (thuộc tính chức năng như `display`/`visibility`/`opacity` được giữ, nên menu mở khi hover vẫn hoạt động);
  - stylesheet chéo nguồn không đọc được bị vô hiệu hoá bằng cơ chế dự phòng đóng băng transition.
  Chỉ các điều khiển thật (nút, link, ô nhập) giữ được phản hồi viền theo theme tức thì.
- **Ép Verdana 100% ở mọi nơi** — gồm cả ô nhập và textarea, với làm mịn font bị tắt. Font icon bị loại trừ để glyph không thành chữ. Nếu bạn có font tùy chỉnh cài dưới tên `Verdana_m1` (ví dụ bản Verdana khử răng cưa), nó được dùng tự động; còn không thì Verdana thường.
- **Bộ vẽ lại thích ứng** — một trình quét JS nhẹ chuyển các bề mặt sáng kiểu "flashbang" và mảng xám dark mode chưa theme thành thang nâu cổ điển, và sửa chữ kém tương phản (tối trên tối) thành vàng, ở ngưỡng nhận biết WCAG. Ảnh, video, canvas và trình phát không bao giờ bị đụng tới.
- **Xuyên Shadow DOM** — theme cả web component (YouTube, Reddit và đồng minh) qua hook `attachShadow`.
- **Popup ngoan ngoãn** — menu, hộp thoại, tooltip và hovercard chỉ được tô màu lại; script không bao giờ ép `opacity`/`z-index`/`visibility`, nên UI trang bị ẩn vẫn ẩn.
- **Lớp bảo vệ an toàn** — script tự vô hiệu trên các trang OAuth, captcha, ngân hàng và thanh toán để các luồng quan trọng không bao giờ bị định dạng lại.

## Palette

Bảng dưới đây hiển thị 10 trong 21 token của palette Golden Default. Mọi palette phát hành đều định nghĩa đủ 21; 11 token còn lại bao phủ cấu trúc viền, chữ phụ, màu ngữ nghĩa (thành công/cảnh báo/nguy hiểm), lựa chọn và chi tiết riêng từng target.

| Token | Hex | Dùng cho |
|---|---|---|
| background | `#1A1810` | nền ngoài cùng |
| backgroundSoft | `#232018` | nền thân trang / nội dung |
| surface | `#332E22` | header, nav, panel |
| surfaceRaised | `#3D372A` | nút, popup, núm thanh cuộn |
| surfaceAlt | `#453D30` | hover nút |
| borderHighlight | `#F0D060` | cạnh 3D trên-trái |
| borderDark | `#100E08` | cạnh 3D dưới-phải |
| textPrimary | `#D4C89A` | chữ vàng chính |
| textMuted | `#6E674E` | placeholder, vô hiệu |
| link | `#F0D060` | link, focus |

## Theme trình duyệt tương ứng

Target `browsers` của trình cài desktop phát hiện các profile Chromium đã cài và portable, báo cáo độ phủ Tampermonkey, dàn dựng theme trình duyệt đã chọn, và mở đúng trang cài/cập nhật cho mọi profile. Chromium yêu cầu một lần xác nhận **Developer mode → Load unpacked** mỗi profile; trình cài sao chép đường dẫn theme ổn định vào clipboard. Các thay đổi palette sau đó tái dùng đường dẫn đó.

## Hành vi đã biết

- Trang web dựng hiệu ứng hover bằng JavaScript (toggling class) thay vì CSS `:hover` có thể vẫn hiện highlight của riêng nó.
- Trên các trang hiếm có CSS chéo nguồn, nhấp một phần tử không nhận focus có thể trì hoãn thay đổi trạng thái hình ảnh cho đến khi chuột rời khỏi (cơ chế dự phòng đóng băng hover đang hoạt động). Nút và link thật được miễn trừ.
- Script tĩnh theo thiết kế: không bảng tùy chọn, không công tắc theo từng trang. Fork nó và sửa các token ở đầu nếu bạn muốn một hương vị khác.

## Phát hành phiên bản mới (cho maintainer)

Đầu tiên thêm mục `## [x.y.z] - date` vào đầu `CHANGELOG.md` — nếu không có thì `release.ps1` sẽ từ chối chạy. Sau đó:

```powershell
.\release.ps1 -Message "what changed"
```

Nó tăng số patch `@version` (tiêu đề Tampermonkey và dấu `W95_VERSION` di chuyển cùng nhau), dựng lại các theme desktop được tạo, chạy toàn bộ chuỗi cổng phát hành, rồi commit, tag và push — client Tampermonkey tự nhận cập nhật. Truyền `-Bump minor` hoặc `-Bump major` cho bản phát hành lớn hơn.

## Giấy phép

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
