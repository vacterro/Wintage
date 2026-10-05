# 面向桌面应用程序的 Wintage

用户脚本为整个网络提供主题。这为网络周围的程序提供主题，来自同一组调色板，因此浏览器和应用不再对"深色金色"的含义争执不休。

这里每个决定背后只有一条规则：**应用程序会自我更新，而更新绝不能悄悄弄坏任何东西。** 如果某个目标在你的配置文件中有一席之地，主题就放在那里并扛住更新。如果没有，安装器的设计就是可重新运行 — 并且明说这一点，而不是假装它已经持久化。

## GUI

双击仓库根目录的 **`Wintage Installer.vbs`** 可在没有控制台窗口的情况下打开它，或直接运行以下命令用于诊断：

```powershell
powershell -File desktop\WintageInstaller.ps1
```

带颜色色块的主题列表、这台机器上找到的目标、实时 Win95 预览，以及全部 21 个可编辑色板形式的颜色令牌。编辑任何色板都会把调色板分叉为 **Custom**，而不是在你背后改动已发布主题。右侧面板实时显示三个承载文本令牌的 WCAG 对比度 — 在那里 FAIL 的调色板反正也会被构建门禁拒绝，所以在 Apply 之前而不是之后看到它更好。

目标被分成两个键盘可到达的列表：**MY APPS** 包含便携式/源码树的 CodeNomad, WorkBuddy 工具；**POPULAR APPS** 包含 Windows、OBS、终端、编辑器和其他已安装软件。ALL/NONE 和 Apply/Revert 在保持分组不变的前提下跨两个列表操作。

窗口穿着它即将安装的调色板。那是最快的预览，也让工具保持诚实：一个让此窗口不可读的调色板，会肉眼可见地不可读。

Apply 会向外调用 `install.ps1`。安装主题的代码路径只有一条，因此 GUI 不可能偏离命令行。

## 命令行

```powershell
.\desktop\install.ps1                                  # 这里有什么、哪些已主题化、用的是哪个调色板
.\desktop\install.ps1 -Target freebuff -Palette klite  # 一个应用、一个调色板
.\desktop\install.ps1 -Target all -Palette goldendefault # 全部
.\desktop\install.ps1 -Target all -WhatIf              # 只说出会改什么，不碰任何东西
.\desktop\install.ps1 -Target freebuff -Revert         # 撤销一个
```

`-Palette` 默认为 `goldendefault`（**Golden Default**）。GUI 以相同的调色板打开并检查每个可用目标。对已主题化的应用重新绘制在其运行时就有效；首次安装则不行，因为归档正在被占用。

## 每个目标实际能被主题化的内容

| 目标 | 机制 | 是否扛住应用更新 |
|---|---|---|
| `windows` | 用户 `.theme`：深色系统/应用模式、强调色与经典颜色角色 | yes — 安装到你的本地 Windows Themes 文件夹 |
| `browsers` | 检测已安装 + 便携式 Chromium 配置文件，暂存所选 chrome 主题并打开浏览器自有的 Tampermonkey/主题确认页面 | yes — 每个配置文件一次 **Load unpacked** 之后 |
| `terminal` | Windows Terminal 方案 + 所有配置文件默认值，Consolas 12 别名 | yes — 设置就在你的配置文件中 |
| `conhost` | `HKCU\Console` 默认值 + 每个现有的 cmd/PowerShell 配置文件 | yes — 精确的已触碰值快照 |
| `obs` | OBS 30.2+ `.ovt` 变体 + 活动的 `user.ini` 主题 ID | yes — 它存在于你的配置文件中 |
| `qbittorrent` | 未打包的 Qt 界面主题（`config.json` + `stylesheet.qss`）+ `qBittorrent.ini` 中的两个主题键 | yes — 它存在于你的配置文件中 |
| `antigravity`, `vscode` | `~/.antigravity/extensions` / `~/.vscode/extensions` 中的颜色主题扩展 | **yes** — 它存在于你的配置文件中 |
| `freebuff`, `antigravity-app`, `codenomad` | Electron shim，见下文 | no — 重新运行安装器 |
| `claude` | Electron shim，就地修补 — 见下文 | no — 更新会生成新的 `app-<version>` 文件夹 |
| `mpchc` | 注册表，仅深色主题 + OSD 排版 | no — MPC-HC 退出时会重写其设置 |
| `obsidian` | 每个 vault 的社区主题，一次安装所有调色板 | **yes** — 它存在于你的 vault 中 |
| `discord` | 将 CSS 放入 BetterDiscord 自己的主题文件夹 | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini` 的 `[Colors]` 键；现有的最近文件过滤器使用调色板链接色 | yes — 那是你的 ini |

### FreeBuff 广告移除

FreeBuff（AI 助手桌面应用）自带自己的广告网络：渲染器 bundle（`resources/orchestrator/ui/assets/index-*.js`）会渲染一个 `sponsored-ad` 卡片和一个线程横幅，而 orchestrator（`resources/orchestrator/orchestrator.js`）暴露调用远程广告拍卖的 `/api/ad/slot|impression|click` 路由。shim 只为应用提供主题，不会碰那些文件。

`desktop/patch-freebuff-ads.js` 在字节层面把广告切掉：

- 渲染器：广告卡片/横幅的调用点变为 `null`，`adSlot` / `adImpression` / `adClick` API 客户端方法变为 no-op — 不渲染任何东西，也没有任何 `/api/ad/*` 请求离开渲染器；
- orchestrator：全部三个 `/api/ad/*` 路由停止调用广告网络，实时回合的内联广告请求（`maybeRequestAd`）被短路。

bundle 文件名内嵌了构建哈希，因此该补丁从 `index.html` 发现当前 bundle，而不是随附一个版本锁定的载荷 — 这就是它能扛住更新的原因。原文件备份到安装目录中的 `_orig-backup-<timestamp>/`；`--revert` 恢复最新的那份。

**未来版本在两个相互独立的层面处理：**

1. **带正则回退的字节补丁。** 每个目标都有当前构建的精确字符串，以及一个锚定在 minifier 无法改名的事物上的正则回退 — `/api/ad/*` 路径字面量、`case"ad":` 协议判别符、`sponsored-ad` 类，以及 `variant:"banner"` / `variant:"card"` 投放位。orchestrator 未被 minify（像 `maybeRequestAd` 和 `app.ads.slotAd` 这样可读的名称），所以它的精确字符串能长期成立；渲染器 bundle 已被 minify，所以下一次构建重命名其标识符的那一刻，正则回退就会接管。
2. **shim 级拦截（`targets/electron/shim.cjs`）。** 与 bundle 完全无关：页面内任何对 `/api/ad/` URL 的 fetch/XHR 都会被拒绝，任何类名包含 `sponsored-ad` 的元素一出现就被隐藏。即使是一个此脚本尚未学会的全新 bundle，也无法浮现广告。

```powershell
node .\desktop\patch-freebuff-ads.js           # 修补（先备份）
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # 修补 + 自定义完成音（wav/mp3/ogg/flac/m4a/aac）
node .\desktop\patch-freebuff-ads.js --scan    # 此构建带有哪些广告标记？
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

它作为 `install.ps1 -Target freebuff` 的一部分自动运行，并且必须在每次 FreeBuff 更新后重新运行（更新会恢复库存文件）。如果构建形态变化，脚本会点名不再匹配的目标 — 运行 `--scan` 看看新构建还带有什么，并在那里刷新字符串。

**FreeBuff 完成音。** 渲染器在回合结束时播放 `chime-<hash>.mp3`。补丁用与发现 bundle 相同的方式找到它（名称内嵌构建哈希），所以 `--sound <file>` 会把你的音频（wav/mp3/ogg/flac/m4a/aac）安装到它之上，并把库存文件保留为 `chime-*.mp3.bak`；`--revert` 恢复它。`--verify` 报告哪个正在生效。

### FreeBuff 声音按钮（GUI）

`WintageInstaller.ps1` 在 APPLY / REVERT 按钮组下方有一个小的 **FB SOUND** 按钮。它只存储一个*偏好*；`install.ps1 -Target freebuff` 读取同一文件并将其作为 `--sound` 交给补丁，因此广告和声音在同一次运行中一起应用：

- **左键单击** — 挑选一个音频文件（OpenFileDialog，wav/mp3/ogg/flac/m4a/aac）并立即听到它回放：PCM WAV 通过 System.Media.SoundPlayer，其他所有格式通过 WPF MediaPlayer（Media Foundation，异步，因此窗口永不冻结）。选择被记在 `%APPDATA%\Wintage\freebuff-sound.txt`（按机器存放，位于 git 检出之外，与记下的源码树文件夹完全一样）。
- **右键单击** — 把偏好清回 FreeBuff 的库存提示音（也会停止仍在播放的任何预览）。
- **COPY** — 把所选音频复制进仓库本身（`sounds\freebuff.<ext>`，保留源扩展名）并将偏好改指向该副本，因此即使原文件被删除或移动，声音依然存活。仅在设置了自定义声音时启用；重新复制只是覆盖仓库副本。`sounds/` 文件夹是普通的可 git 追踪内容，所以提交它也能让声音在重新克隆后存活。

只有被识别的音频容器才会被预览 — 会先嗅探头部，因此非音频的选择会被告知，而不是悄悄什么都不播放。

设置了自定义声音期间，按钮显示 `ON`；悬停它会显示路径。之后应用 `freebuff` 目标（勾选 FreeBuff 并按 APPLY，或从终端运行 `install.ps1 -Target freebuff`）即可生效。

### 终端

`terminal` 会向每个检测到的稳定版、Preview 或未打包的 Windows Terminal 设置文件写入 `Wintage` 颜色方案，并通过 `profiles.defaults` 选择它，同时使用控制台安全的 Consolas 12 和别名文本。原文件逐字节保留在它旁边，`-Revert` 会恢复它。

`conhost` 覆盖经典的 `cmd.exe`、Windows PowerShell、Git CMD/Bash 控制台配置文件，以及其他现有的 `HKCU\Console` 子项。它把调色板的完整 16 色表同时写入根默认值和每个现有覆盖项，然后只恢复它触碰过的值。它在那里也应用 Consolas，因为比例字体 Verdana 会在两个终端宿主共用的定宽单元格网格内冲突。

### 浏览器与 Tampermonkey

`browsers` 从已安装位置以及你指向的便携式根目录（`-PortableRoot`，或 `paths.json` 中记下的 `portable` 条目）查找 Chrome、Edge、Brave、Cent、Vivaldi 和 Opera 配置文件。它的状态同时显示配置文件数量和其中包含 Tampermonkey 的数量。Apply 将所选 browser-chrome 主题复制到稳定的 `%LOCALAPPDATA%\Wintage\browser-theme` 文件夹，把该路径放到剪贴板上，并打开每个确切的配置文件到 `chrome://extensions` 以及 Wintage 用户脚本的 Install/Update 页面。没有 Tampermonkey 的配置文件还会获得其 Chrome Web Store 页面。

Chromium 故意禁止在不受管理的 Windows 机器上静默安装商店外扩展。因此首次浏览器主题安装每个配置文件需要一次 **Developer mode → Load unpacked** 确认。挑选复制好的路径；之后调色板变化时，Wintage 会不断替换同一个稳定文件夹。同时也要在 Tampermonkey 中确认 **Install/Update**。不会有浏览器 `Preferences`、Secure Preferences 或 Tampermonkey LevelDB 文件在浏览器背后被编辑。如果 Tampermonkey 不存在，就从打开的商店标签页安装它，并刷新已打开的 `wintage.user.js` 标签页以得到 Install 界面。

### Windows

`windows` 安装并立即激活一个内容寻址的 `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`。它从当前活动主题开始，只替换有文档说明的颜色、光标和视觉样式部分。壁纸、声音和桌面图标保持不变；光标则有意切换到已安装的 `___CURRENT___` 方案。第一个活动主题逐字节保存为 `Wintage.original.theme`；调色板更改保留该基线，`-Revert` 会再次激活它。现代 Windows 控件仍来自签名的 Aero 视觉样式 — Wintage 修改其受支持的深色模式、强调色和经典系统颜色输入，而不是替换受保护的 `.msstyles` 文件。活动与非活动标题栏共享调色板中静音凸起表面的颜色；明亮高光仍保留给文本/选择边缘。之前的非活动标题栏强调色被单独快照，并由 `-Revert` 精确恢复。内容哈希为 Windows 提供了一个新的文件关联目标，因此当同一调色板被重新构建时，重新应用更新的调色板不会被误认为 no-op；被取代的 Wintage 文件会在 Windows 确认新文件生效后被移除。

### OBS Studio

`obs` 在维护的 Yami Classic 基础上生成 OBS 30.2+ 变体，安装到 `%APPDATA%\obs-studio\themes`，并把其稳定主题 ID 写入 `user.ini`，这样所选的 Wintage 调色板在下次启动时已被选中。在 Apply 或 Revert 之前关闭 OBS：OBS 退出时会重写 `user.ini`。首次应用会把之前的选项和任何同名主题都逐字节备份。

### qBittorrent

`qbittorrent` 会把一份**未打包**的 Qt 界面主题写入 `%APPDATA%\qBittorrent\themes\wintage`：一个 `config.json`（`Palette.*` 各项角色，加上 qBittorrent 自身的上下文颜色：传输列表状态、日志级别），以及旁边一个 `stylesheet.qss`（2px 斜面、直角边角，以及调色板无法表达的 Verdana）；随后把 `General\CustomUIThemePath` 指向该 `config.json` 并设置 `General\UseCustomUITheme=true`。
刻意采用未打包形式而非 `.qbtheme` 包：`.qbtheme` 是 Qt Resource Collection 文件，生成它需要机器上有一个主版本号匹配的 `rcc` 可执行文件，为了两个文本文件而引入编译器依赖并不划算。qBittorrent 原生支持读取文件夹形式（`FolderThemeSource`）。
在 Apply 或 Revert 之前请关闭 qBittorrent：它在退出时会重写整个 `qBittorrent.ini`，因此运行期间所做的修改会在关闭时被丢弃——该目标在此状态下会拒绝执行，而不是报告一个会被下次退出抹掉的“成功”。`-Revert` 会把两个 INI 键恢复为 Wintage 之前的精确值（若原本不存在则删除），并把任何同名主题文件夹按字节原样放回；Apply 之后对 `qBittorrent.ini` 所做的无关修改仍会保留。
无法覆盖：工具栏与托盘图标来自 qBittorrent 自身已编译的资源包，因此会保持原有配色。

### 字体：只命名，从不安装

UI.md 第一条法则要求 Verdana **关闭抗锯齿**。Qt 样式表没有对应属性，MPC-HC 的 `OSDFont` 也只是一个普通的 GDI 字体名——所以唯一的杠杆就是字体本身。仓库根目录下的 `Verdana_m1.ttf` 是 Verdana 的副本，携带 3 到 30 ppem 预先渲染的 1bpp 点阵字形，渲染器会优先使用它们，而不是对轮廓做平滑处理。
`qbittorrent` 与 `obs` 的样式表都写明 `Verdana_m1, Verdana`，而 `mpchc` 写的是这两者中机器实际解析出的那一个。**安装程序从不安装或卸载字体**，这是有意为之，而非未竟之事：
字体族按（字体族，样式）解析。注册 Regular + Bold + Italic 后，每个使用者都能正确解析；而只要注销**其中任意一个**成员，所有请求该字体族的使用者就会转向仍然存在的成员。在通过 `HKLM\...\FontSubstitutes` 把 `MS Shell Dlg 2`（Windows 对话框字体）映射到该字体族的机器上，移除 Regular 会让**整个桌面变成斜体**，连 DWM 早已缓存的窗口标题也一并波及，并且需要注销才能恢复。再怎么引用计数也修不好这一点：影响范围是整台机器，主题安装程序不该伸手到那里。
因此字体是一次性的、由用户明确执行的操作：右键点击 `Verdana_m1.ttf` → **安装**（按用户安装，无需管理员权限），然后重新应用目标。如果字体缺失，各目标只会提示一次，说明修复办法，并回退到系统自带的 Verdana——带抗锯齿，但没有在你的机器背后动任何手脚。

### Electron 应用

`resources/app.asar` 被移动到 `resources/app/app.asar`（它的 `app.asar.unpacked` 兄弟随之移动 — 该配对基于文件名，拆开它会弄坏每个原生模块），一个小 `shim.cjs` 占据空出的 `resources/app` 插槽。shim 注入样式表，然后加载原始归档。**没有任何应用程序字节被重写**，只是被搬迁；`-Revert` 直接把它移回去。

样式表不是为这些应用编写的 — 它从 `wintage.user.js` 中提取，因此为浏览器制作的每一个斜面、滚动条和字号阶梯修复也会落在这里，没有第二份会腐烂的副本。

有两点值得提前知道：

- 显而易见的做法 — 把 `resources/app` 放在归档旁边并指望 Electron 优先使用它 — **行不通，而且会静默失败**。Electron 会先搜索 `app.asar`。应用完美启动，主题却从未运行。
- shim 故意是 `.cjs` 而不是 `.js`。它的 `package.json` 从应用自己的那里复制，因此应用保留其名称和版本（名称决定了 userData 的位置 — 重命名它的 shim 会把应用移到空的配置文件中）。如果该清单写着 `"type": "module"`，`.js` shim 会在第一个 `require` 处死掉。

### Claude 桌面应用：就地修补，以及它真正绘制于其上的框架

Claude 无法使用上面的搬迁方案，因为 `OnlyLoadAppFromAsar` 被熔接开启 — Electron 只加载 `resources/app.asar`，其他一概不加载，所以 `resources/app` 中的 shim 永远无法运行。它改为**就地**修补：归档被备份，其 `package.json` 的 `main` 被重写为 `"../wintage-shim.cjs"`（填充到相同字节长度，使归档中的每个偏移量都保持有效），逐文件完整性哈希也被更新以匹配。`-Revert` 恢复备份。

安装器在**移动任何东西之前**读取保险丝，并在它们阻止时附上理由拒绝 — `EnableEmbeddedAsarIntegrityValidation` 会让上述重写在启动时而不是安装时失败。你自己检查任何应用：

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

这后一半是一个安静得多的问题。Claude 的 `BrowserWindow` 渲染一个薄壳，而**整个可见应用是一个 `WebContentsView`** 附着在它上面。shim 曾经挂钩 `browser-window-created`，所以它把样式表注入壳中，向 `wintage-status.txt` 报告成功，却没有改变任何你能看到的东西。现在它挂钩 `web-contents-created`，同样覆盖窗口内容、`WebContentsView`、`BrowserView`、`<webview>` guest 和弹窗。

### Obsidian

社区主题被写入每个 vault 的 `.obsidian/themes/` — 全部十六个调色板一次写入，与 VS Code 目标完全一样，因此你可以在 **Settings → Appearance** 中切换而无需重新运行任何东西。模板源自 vault 中已有的手工 `VintageWin95` 主题，每个颜色都被替换为它等于的令牌。`-Palette <slug>` 设置安装时哪个处于活动状态；`appearance.json` 首先被备份，`-Revert` 只移除 `Wintage *` 主题并恢复你之前的选择 — 同一 vault 中的手工主题永远不会被触碰。


### MPC-HC (K-Lite)

原生 Win32，没有样式表也没有注入点，其深色主题的颜色编译在程序内部 — 没有任何注册表值暴露它们。所以这个目标**无法承载调色板**。它做的是：打开深色主题并把 UI.md 排版规则应用到 OSD — OSD 是 MPC-HC 让用户控制的唯一表面。之前的设置首先导出到 `desktop/backup/mpc-hc-settings.reg`。

应用前关闭 MPC-HC：它退出时会重写设置。

## 重新构建

`desktop/out/` 下的所有内容都由 `themes/*.json` 生成。它不被 git 追踪（T-160），所以新克隆必须在安装前构建一次：

```powershell
node ..\tools\build-desktop.js          # 重新构建所有目标
node ..\tools\build-desktop.js --check  # 有任何过期内容则 exit 1
```

`release.ps1` 会运行构建和每一道门禁，因此发布不可能交付偏离调色板的输出。

<!-- T-311 target/section coverage supplement -->
## 目标与章节覆盖

本节对照当前英文 README 中 Process Explorer、Notepad++、Cinema 4D 和终端字体的覆盖范围，使本语言版本不会在无声中过时。代码字面量（目标 ID、注册表路径、文件名）按设计就是语言无关的；其周围的文字在此已作翻译。

### 每个目标实际能被主题化的内容（新增目标）

| 目标 | 机制 | 是否扛住应用更新 |
|---|---|---|
| `notepadplusplus` | 主题 XML + 别名写入你本人的 Notepad++ `themes` 文件夹 | 是 — 它就在你的配置文件中 |
| `cinema4d` | 颜色方案放入你本人的 Cinema 4D `schemes` 文件夹 | 是 — 它就在你的配置文件中 |
| `processexplorer` | `HKCU\Software\Sysinternals\Process Explorer`：行高亮颜色与图表背景，见下文 | 否 — Process Explorer 退出时会重写其设置；关掉它再重新运行 |

### Process Explorer (Sysinternals)

Process Explorer 把颜色保存在 `HKCU\Software\Sysinternals\Process Explorer`，并在退出时重写该键，所以只要 `procexp`、`procexp64` 或 `procexp64a` 还在运行，该目标就**拒绝执行** — 关掉它再运行一次。它主题化那些可配置的颜色类别：

- **够得着**：进程行高亮颜色（`ColorOwn`、`ColorServices`、`ColorRelocatedDlls`、`ColorImmersive`、`ColorPacked`、`ColorJobs`、`ColorNet`、`ColorProtected`、`ColorNewProc`、`ColorDelProc`、`ColorSuspend`）的浅色模式与 `*Dark` 两种变体，外加图表背景（`ColorGraphBk`、`ColorGraphBkDark`）— 一共 24 个值。每个变体都朝当前调色板的对应一极混合（浅色模式填充用更浅的色调，`*Dark` 用更深的色调），因此行填充保持调色板自身的调子，而不是褪成近白的粉彩；
- **够不着**：标题栏、菜单栏、工具栏、列表视图背景与文字颜色，以及图表线条颜色 — 这些编译在 `procexp.exe` 里，没有任何设置值会暴露它们。该目标主题化行高亮和它真正拥有的图表背景，不多声称任何东西。

Apply 能够改动的每一个值都会在改动前先做快照（位于 `%APPDATA%\Wintage\recovery\processexplorer\` 的首次触碰恢复），并由 `-Revert` 精确还原，包括每个值原本是否缺失，以及该标记是否存在但为空。标准 Sysinternals 目录之外的便携文件夹通过规范的 `paths.json` 键 `processexplorer` 记住（命令行参数 `-ProcessExplorerPath`；GUI 也可以选取）。

### 终端字体（`fonts/terminal/`）

两个终端目标都从 `%APPDATA%\Wintage\terminal-font.json` 读取**同一份**规范排版偏好（`schema`、`fontSlug`、`family`、`size`、`renderingMode`）。文件缺失时，目标保持随附的默认值（Windows 下为 Terminus (TTF)、12 pt、别名渲染），因此现有机器不受影响。格式错误的偏好会封闭失败：不覆盖任何东西，目标直接拒绝。

`fonts/terminal/catalog.json` 是唯一的字体目录：20 个内置开源等宽字族，加上 Wintage 只点名、从不随附的两个系统字面（Windows 下为 Terminus (TTF)、Consolas）。每个内置条目都带有其上游来源、固定版本、许可证 ID、许可证文件和 SHA-256。确切的字体文件以 vendored 形式放在 `fonts/terminal/files/`，许可证文本放在 `licenses/`；运行时的 Wintage 完全离线工作，从不下载字体。

`tools/sync-terminal-fonts.ps1` 是仅限维护者使用的下载器。它读取 `fonts/terminal/sources.json`（每个字族一个不可变构件），校验每个 SHA-256，遇到不匹配就拒绝。`-VerifyOnly`（默认）在无网络的情况下检查磁盘上的目录树；`-Fetch -Write` 重新 vendor。下载的字体字节按不可信二进制资产处理 — 只做哈希和写入，绝不执行。已记录一处替换：**Fantasque Sans Mono** 取代 Liberation Mono，后者不发布任何固定的二进制版本（只有 `.sfd` 源文件）。

安装器**只浏览字体，并不安装它们。** TERMINAL FONTS 标签页把一个内置字面载入进程本地的 `PrivateFontCollection` 以做实时预览，这一步进行**零**次系统字体注册。选择字体、字号（7–24 pt）或渲染模式（aliased/grayscale/cleartype）只更新预览和偏好。安装字体是一个明确的 **INSTALL SELECTED** 动作，它会打开 Windows 自带的字体安装器；在 Windows 确认之后，用户用 Refresh 重新探测。终端的实际变更只发生在明确的 **APPLY TERMINAL / APPLY CONHOST / APPLY BOTH** 动作时。

Windows Terminal 会以选定的字号应用到所选已安装的字族上，渲染模式则映射到 `profiles.defaults.antialiasingMode`。经典 conhost 更严格：它在固定的单元格网格上渲染，因此选中的字面会在任何注册表改动之前被拒绝，除非 Windows 能解析它（默认字面和 Consolas 回退属于既有豁免）。Health 和 Reapply 会拿已配置的字面/字号/抗锯齿与那份偏好对照校验，因此在一次 Apply 之后改动偏好会被报告为漂移，而不是仍算"健康"。终端颜色的生命周期未受影响：Revert 精确还原 Wintage 之前所拥有的值，且绝不从机器上移除任何字体。
<!-- source-digest: desktop/README.md sha256:15c96dac8494ab84 -->
