# Wintage cho ứng dụng desktop

Userscript theme cho web. Phần này theme cho các chương trình quanh nó, từ cùng một bộ palette, để trình duyệt và ứng dụng không còn bất đồng về việc vàng đậm là gì.

Có một quy tắc đằng sau mọi quyết định ở đây: **ứng dụng tự cập nhật, và một bản cập nhật không được âm thầm làm vỡ gì đó.** Nơi nào target có chỗ trong profile của bạn, theme nằm đó và sống sót qua các bản cập nhật. Nơi nào không có, trình cài được viết để chạy lại — và nói rõ điều đó, thay vì giả vờ rằng nó đã được duy trì.

## GUI

Nhấp đúp **`Wintage Installer.vbs`** ở gốc repo để mở nó không có cửa sổ console, hoặc chạy trực tiếp để chẩn đoán:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Danh sách theme kèm chip màu, các target tìm thấy trên máy này, một preview Win95 trực tiếp, và toàn bộ hai mươi mốt token màu dưới dạng swatch chỉnh sửa được. Sửa bất kỳ swatch nào sẽ fork palette thành **Custom** thay vì đổi theme phát hành ngầm dưới tay bạn. Panel bên phải hiển thị tương phản WCAG trực tiếp cho ba token mang chữ — một palette FAIL ở đó đã bị cổng build từ chối, nên thấy nó trước Apply còn hơn sau.

Target được chia thành hai danh sách truy cập được bằng bàn phím: **MY APPS** chứa các công cụ CodeNomad, SAIPENVIEW, SmartVac và WildRift dạng portable/source-tree; **POPULAR APPS** chứa Windows, OBS, terminal, editor và phần mềm đã cài khác. ALL/NONE và Apply/Revert hoạt động trên cả hai danh sách mà không đổi cách phân nhóm.

Cửa sổ mặc chính palette mà nó sắp cài. Đó là preview nhanh nhất có được, và giữ công cụ trung thực: một palette làm cửa sổ này khó đọc thì trông khó đọc một cách thấy rõ.

Apply gọi ra ngoài `install.ps1`. Chỉ có đúng một đường code cài theme, nên GUI không thể lệch khỏi dòng lệnh.

## Dòng lệnh

```powershell
.\desktop\install.ps1                                  # cái gì ở đây, cái gì được theme, với palette nào
.\desktop\install.ps1 -Target freebuff -Palette klite  # một app, một palette
.\desktop\install.ps1 -Target all -Palette goldendefault # tất cả
.\desktop\install.ps1 -Target all -WhatIf              # nói những gì sẽ đổi, không đụng gì
.\desktop\install.ps1 -Target freebuff -Revert         # hoàn tác một app
```

`-Palette` mặc định là `goldendefault` (**Golden Default**). GUI mở ở cùng palette và kiểm tra mọi target khả dụng. Sơn lại một app đã được theme hoạt động trong khi nó đang chạy; lần cài đầu tiên thì không, vì archive đang bị dùng.

## Từng target thực sự được theme đến đâu

| target | cơ chế | sống sót qua cập nhật app |
|---|---|---|
| `windows` | `.theme` người dùng: chế độ tối hệ thống/app, vai trò màu accent và cổ điển | có — cài trong thư mục Windows Themes cục bộ của bạn |
| `browsers` | phát hiện profile Chromium đã cài + portable, dàn dựng chrome theme đã chọn và mở các trang xác nhận Tampermonkey/theme do trình duyệt quản lý | có sau một lần **Load unpacked** mỗi profile |
| `terminal` | scheme Windows Terminal + mặc định mọi profile, Consolas 12 aliased | có — cài đặt nằm trong profile của bạn |
| `conhost` | mặc định `HKCU\Console` + mọi profile cmd/PowerShell hiện có | có — snapshot chính xác giá trị đã đụng |
| `obs` | variant OBS 30.2+ `.ovt` + id theme `user.ini` đang dùng | có — nó nằm trong profile của bạn |
| `antigravity`, `vscode` | extension theme màu trong `~/.antigravity/extensions` / `~/.vscode/extensions` | **có** — nó nằm trong profile của bạn |
| `freebuff`, `antigravity-app`, `codenomad` | shim Electron, xem bên dưới | không — chạy lại trình cài |
| `claude` | shim Electron, vá ngay tại chỗ — xem bên dưới | không — bản cập nhật tạo thư mục `app-<version>` mới |
| `mpchc` | registry, chỉ theme tối + kiểu chữ OSD | không — MPC-HC tự ghi lại cài đặt khi thoát |
| `obsidian` | theme cộng đồng mỗi vault, cài mọi palette cùng lúc | **có** — nó nằm trong vault của bạn |
| `saipenview` | ghi lại giá trị token `:root` của chính nó trong `style.css` | không — file nguồn; chạy lại sau pull |
| `discord` | CSS thả vào thư mục theme riêng của BetterDiscord | có |
| `totalcmd`, `totalcmd2` | khoá `[Colors]` trong `wincmd.ini`; bộ lọc file gần đây hiện có dùng màu link của palette | có — nó là ini của bạn |
| `smartvac`, `wildrift` | bảng token ghi lại trong nguồn của chính app | không — file nguồn; chạy lại sau pull |

### Gỡ quảng cáo FreeBuff

FreeBuff (app desktop trợ lý AI) vận chuyển mạng quảng cáo của riêng nó: bundle renderer (`resources/orchestrator/ui/assets/index-*.js`) render một thẻ `sponsored-ad` và một banner thread, và orchestrator (`resources/orchestrator/orchestrator.js`) phơi bày các route `/api/ad/slot|impression|click` gọi đấu giá quảng cáo từ xa. Shim chỉ theme app; nó không đụng vào những file đó.

`desktop/patch-freebuff-ads.js` cắt quảng cáo ra ở mức byte:

- renderer: các điểm gọi thẻ/banner quảng cáo thành `null`, và các phương thức client API `adSlot` / `adImpression` / `adClick` thành no-op — không gì render, và không một request `/api/ad/*` nào rời khỏi renderer;
- orchestrator: cả ba route `/api/ad/*` ngừng gọi mạng quảng cáo, và request quảng cáo inline theo lượt (`maybeRequestAd`) bị short-circuit.

Tên file bundle nhúng hash build, nên patch khám phá bundle hiện tại từ `index.html` thay vì vận chuyển payload khoá theo phiên bản — đó là điều khiến nó sống sót qua các bản cập nhật. Bản gốc được sao lưu vào `_orig-backup-<timestamp>/` trong thư mục cài; `--revert` khôi phục bản mới nhất.

**Các phiên bản tương lai được xử lý ở hai tầng độc lập:**

1. **Byte patch kèm dự phòng regex.** Mỗi target có một chuỗi chính xác cho build hiện tại *và* một dự phòng biểu thức chính quy neo vào thứ mà minifier không thể đổi tên — các ký tự đường dẫn `/api/ad/*`, bộ phân biệt giao thức `case"ad":`, class `sponsored-ad`, và các vị trí `variant:"banner"` / `variant:"card"`. Orchestrator không bị minify (tên đọc được như `maybeRequestAd` và `app.ads.slotAd`), nên chuỗi chính xác của nó trụ lâu; bundle renderer bị minify, nên dự phòng regex của nó tiếp quản ngay khi build kế tiếp đổi tên định danh.
2. **Chặn ở tầng shim (`targets/electron/shim.cjs`).** Độc lập hoàn toàn với bundle: mọi fetch/XHR tới URL `/api/ad/` bị từ chối ngay trong trang, và mọi thành phần có class chứa `sponsored-ad` bị ẩn ngay khi nó xuất hiện. Kể cả một bundle hoàn toàn mới mà script này chưa học cũng không thể hiện quảng cáo.

```powershell
node .\desktop\patch-freebuff-ads.js           # patch (sao lưu trước)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patch + âm thanh hoàn tất tùy chỉnh (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # build này mang những marker quảng cáo nào?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Nó chạy tự động như một phần của `install.ps1 -Target freebuff`, và phải chạy lại sau mỗi lần cập nhật FreeBuff (bản cập nhật khôi phục các file gốc). Nếu một build đổi hình dạng, script nêu tên target không còn khớp — chạy `--scan` để xem build mới còn mang gì và làm mới các chuỗi ở đó.

**Âm thanh hoàn tất FreeBuff.** Renderer phát `chime-<hash>.mp3` khi một lượt kết thúc. Patch tìm nó cùng cách nó tìm bundle (tên nhúng hash build), nên `--sound <file>` cài âm thanh của bạn (wav/mp3/ogg/flac/m4a/aac) đè lên và giữ file gốc làm `chime-*.mp3.bak`; `--revert` khôi phục nó. `--verify` báo cái nào đang hoạt động.

### Nút âm thanh FreeBuff (GUI)

`WintageInstaller.ps1` có một nút nhỏ **FB SOUND** dưới cột APPLY / REVERT. Nó chỉ lưu một *sở thích*; `install.ps1 -Target freebuff` đọc cùng file đó và đưa cho patch làm `--sound`, nên quảng cáo và âm thanh được áp trong một lần chạy:

- **Nhấp trái** — chọn một file âm thanh (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) và nghe phát lại ngay: PCM WAV qua System.Media.SoundPlayer, mọi định dạng khác qua WPF MediaPlayer (Media Foundation, async, nên cửa sổ không bao giờ treo). Lựa chọn được nhớ trong `%APPDATA%\Wintage\freebuff-sound.txt` (theo máy, ngoài git checkout, đúng như các thư mục source-tree đã nhớ).
- **Nhấp phải** — xoá sở thích về lại tiếng chime gốc của FreeBuff (cũng dừng mọi preview đang phát).
- **COPY** — sao chép âm thanh đã chọn vào chính repo (`sounds\freebuff.<ext>`, giữ nguyên phần mở rộng nguồn) và trỏ sở thích vào bản sao đó, nên âm thanh sống sót khi file gốc bị xoá hay di chuyển. Chỉ bật khi đang đặt âm thanh tùy chỉnh; sao chép lại chỉ đơn giản ghi đè bản sao trong repo. Thư mục `sounds/` là nội dung git-track thường, nên commit nó khiến âm thanh sống sót cả qua các lần clone lại.

Chỉ các container âm thanh được nhận diện mới được preview — header được dò trước, nên một lựa chọn không phải âm thanh sẽ được báo thay vì lặng lẽ phát chẳng gì.

Nút đọc `ON` trong khi đang đặt âm thanh tùy chỉnh; hover vào nó sẽ hiện đường dẫn. Áp target `freebuff` sau đó (tick FreeBuff + APPLY, hoặc chạy `install.ps1 -Target freebuff` từ terminal) để nó có hiệu lực.

### Terminal

`terminal` ghi một scheme màu `Wintage` vào mọi file cài đặt Windows Terminal đã phát hiện — stable, Preview hay chưa đóng gói — và chọn nó qua `profiles.defaults`, cùng Consolas 12 an toàn console và chữ aliased. File gốc được giữ nguyên byte bên cạnh và `-Revert` khôi phục nó.

`conhost` bao phủ `cmd.exe` cổ điển, Windows PowerShell, các profile console Git CMD/Bash, và các con `HKCU\Console` hiện có khác. Nó ghi toàn bộ bảng 16 màu của palette vào cả mặc định gốc lẫn mọi override hiện có, rồi chỉ khôi phục những giá trị nó đã đụng. Nó cũng áp Consolas ở đó, vì Verdana tỷ lệ va chạm trong lưới ô độ rộng cố định mà cả hai host terminal dùng.

### Trình duyệt và Tampermonkey

`browsers` tìm profile Chrome, Edge, Brave, Cent, Vivaldi và Opera từ các vị trí đã cài và từ root portable bạn trỏ tới (`-PortableRoot`, hoặc mục `portable` được nhớ trong `paths.json`). Trạng thái của nó hiện cả số profile lẫn số profile chứa Tampermonkey. Apply sao chép browser-chrome theme đã chọn vào thư mục ổn định `%LOCALAPPDATA%\Wintage\browser-theme`, đặt đường dẫn đó vào clipboard, và mở mỗi profile chính xác tại `chrome://extensions` cùng trang Install/Update của userscript Wintage. Profile không có Tampermonkey cũng nhận trang Chrome Web Store của nó.

Chromium cố ý cấm cài extension ngoài store âm thầm trên máy Windows không được quản lý. Lần cài browser theme đầu tiên vì vậy cần một lần xác nhận **Developer mode → Load unpacked** mỗi profile. Chọn đường dẫn đã sao; sau đó Wintage tiếp tục thay thế cùng thư mục ổn định khi palette đổi. Xác nhận **Install/Update** trong Tampermonkey nữa. Không file `Preferences`, Secure Preferences hay LevelDB Tampermonkey nào bị sửa sau lưng trình duyệt. Nếu Tampermonkey không có, cài nó từ tab store đã mở và refresh tab `wintage.user.js` đang mở để lấy màn hình Install.

### Windows

`windows` cài và kích hoạt ngay một `.theme` định địa chỉ nội dung `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`. Nó bắt đầu từ theme đang hoạt động và chỉ thay các phần màu, con trỏ và phong cách hình ảnh đã ghi chép. Hình nền, âm thanh và icon desktop vẫn nguyên; con trỏ chủ động chuyển sang scheme `___CURRENT___` đã cài. Theme hoạt động đầu tiên được lưu nguyên byte thành `Wintage.original.theme`; thay đổi palette giữ đường cơ sở đó, và `-Revert` kích hoạt lại nó. Điều khiển Windows hiện đại vẫn đến từ phong cách hình ảnh Aero đã ký — Wintage đổi chế độ tối, accent và các đầu vào màu hệ thống cổ điển mà nó hỗ trợ thay vì thay các file `.msstyles` được bảo vệ. Caption active và inactive dùng chung màu bề mặt nổi muted của palette; highlight sáng được giữ riêng cho cạnh chữ/lựa chọn. Accent caption inactive trước đó được snapshot riêng và khôi phục chính xác bởi `-Revert`. Hash nội dung cho Windows một mục tiêu liên kết file mới khi cùng palette được build lại, nên áp lại một palette đã cập nhật không bị nhầm thành no-op; file Wintage bị thay thế được gỡ sau khi Windows xác nhận file mới hoạt động.

### OBS Studio

`obs` sinh một variant OBS 30.2+ trên nền Yami Classic được duy trì, cài vào `%APPDATA%\obs-studio\themes`, và ghi id theme ổn định của nó vào `user.ini`, nên palette Wintage đã chọn được chọn sẵn ở lần khởi động sau. Đóng OBS trước Apply hoặc Revert: OBS tự ghi lại `user.ini` khi thoát. Lần apply đầu sao lưu cả lựa chọn trước đó lẫn mọi theme cùng tên nguyên byte.

### Ứng dụng Electron

`resources/app.asar` được di chuyển thành `resources/app/app.asar` (anh em `app.asar.unpacked` của nó đi cùng — cặp đó gắn theo tên file, tách nó ra làm hỏng mọi module native), và một `shim.cjs` nhỏ chiếm vị trí `resources/app` để trống. Shim chèn stylesheet rồi tải archive gốc. **Không byte nào của ứng dụng bị viết lại**, chỉ được di dời; `-Revert` chuyển nó thẳng về.

Stylesheet không được viết cho các app này — nó được trích từ `wintage.user.js`, nên mọi sửa viền, thanh cuộn và thang chữ làm cho trình duyệt đều hạ cánh ở đây, không có bản sao thứ hai để mục nát.

Hai ghi chú đáng biết trước:

- Cách hiển nhiên — thả `resources/app` cạnh archive và trông cậy Electron ưu tiên nó — **không hoạt động và lặng lẽ thất bại**. Electron tìm `app.asar` trước. App khởi động hoàn hảo và theme không bao giờ chạy.
- Shim là `.cjs`, không phải `.js`, có chủ đích. `package.json` của nó được sao từ chính app để app giữ tên và phiên bản (tên quyết định userData nằm ở đâu — một shim đổi tên sẽ chuyển app sang một profile rỗng). Nếu manifest đó ghi `"type": "module"`, shim `.js` chết ở `require` đầu tiên.

### App desktop của Claude: tại chỗ, và khung mà nó thực sự vẽ

Claude không dùng được cách di dời trên, vì `OnlyLoadAppFromAsar` bị hàn bật — Electron tải `resources/app.asar` và không gì khác, nên shim trong `resources/app` không bao giờ chạy. Nó được vá **ngay tại chỗ** thay thế: archive được sao lưu, `main` trong `package.json` của nó được viết lại thành `"../wintage-shim.cjs"` (đệm đúng độ dài byte, nên mọi offset trong archive vẫn hợp lệ), và hash toàn vẹn từng file được cập nhật khớp. `-Revert` khôi phục bản sao lưu.

Trình cài vẫn đọc các fuse **trước khi nó di chuyển bất cứ gì** và từ chối kèm lý do khi chúng chặn — `EnableEmbeddedAsarIntegrityValidation` sẽ khiến việc viết lại trên thất bại lúc khởi động thay vì lúc cài. Tự kiểm tra bất kỳ app nào:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Nửa sau của vấn đề này êm hơn nhiều. `BrowserWindow` của Claude render một lớp vỏ mỏng và **toàn bộ ứng dụng nhìn thấy là một `WebContentsView`** gắn vào nó. Shim từng hook `browser-window-created`, nên nó chèn stylesheet vào lớp vỏ, báo thành công vào `wintage-status.txt`, và chẳng đổi gì bạn thấy được. Giờ nó hook `web-contents-created`, bao phủ cả nội dung cửa sổ, `WebContentsView`, `BrowserView`, khách `<webview>` và popup.

### Obsidian

Một theme cộng đồng được ghi vào `.obsidian/themes/` của mọi vault — toàn bộ mười sáu palette cùng lúc, giống hệt target VS Code, nên bạn chuyển giữa chúng trong **Settings → Appearance** mà không cần chạy lại gì. Template được suy ra từ theme `VintageWin95` làm tay đã có trong vault, mỗi màu được thay bằng token mà nó tương đương. `-Palette <slug>` đặt cái nào hoạt động khi cài; `appearance.json` được sao lưu trước, và `-Revert` chỉ gỡ các theme `Wintage *` và khôi phục lựa chọn trước của bạn — một theme làm tay trong cùng vault không bao giờ bị đụng.

### SAIPENVIEW

Frontend của nó đã khai báo tên token Wintage trong `:root` của chính nó, nên patch này chỉ ghi lại **giá trị token** — không bao giờ selector, font, độ rộng viền hay padding. Không gì ảnh hưởng box model thay đổi, nên chữ không thể xê dịch. Đó là chủ đích: cách tiếp cận trước đây chồng toàn bộ stylesheet trình duyệt lên trên, và `wintage.css` được viết cho trang web bất kỳ — selector phổ quát ép font, thang kích thước, viền 2px và chiều cao điều khiển. Trên một app đã có layout riêng, điều đó làm xê dịch mọi thứ.

Được kiểm chứng bằng cách che mọi hex và diff với bản sao lưu: giống hệt về cấu trúc, chỉ khác các literal màu. `--link` được báo là không khai báo ở đó (link markdown của nó đọc `--accentTeal`, cái mà file này có đặt) thay vì bị chèn — thêm một biến app không bao giờ đọc là trọng lượng chết.

### MPC-HC (K-Lite)

Win32 native, không stylesheet và không điểm chèn, và màu theme tối của nó được biên dịch trong chương trình — không giá trị registry nào phơi bày chúng. Target này vì vậy **không thể mang palette**. Cái nó làm: bật theme tối và áp quy tắc kiểu chữ của UI.md lên OSD, bề mặt duy nhất MPC-HC để người dùng điều khiển. Cài đặt trước đó được xuất ra `desktop/backup/mpc-hc-settings.reg` trước.

Đóng MPC-HC trước khi áp: nó tự ghi lại cài đặt khi thoát.

## Xây dựng lại

Mọi thứ dưới `desktop/out/` được sinh từ `themes/*.json`. Nó không được git track (T-160), nên một bản clone mới phải build nó một lần trước khi cài:

```powershell
node ..\tools\build-desktop.js          # build lại mọi target
node ..\tools\build-desktop.js --check  # exit 1 nếu có gì lỗi thời
```

`release.ps1` chạy build và mọi cổng, nên một bản phát hành không thể vận chuyển output đã lệch khỏi các palette.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
