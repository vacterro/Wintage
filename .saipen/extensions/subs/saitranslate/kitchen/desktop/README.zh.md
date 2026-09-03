# 面向桌面应用程序的 Wintage

用户脚本为整个网络提供主题。这为网络周围的程序提供主题，来自同一组调色板，因此浏览器和应用不再对"深色金色"的含义争执不休。

这里每个决定背后只有一条规则：**应用程序会自我更新，而更新绝不能悄悄弄坏任何东西。** 如果某个目标在你的配置文件中有一席之地，主题就放在那里并扛住更新。如果没有，安装器的设计就是可重新运行 — 并且明说这一点，而不是假装它已经持久化。

## GUI

双击仓库根目录的 **`Wintage Installer.vbs`** 可在没有控制台窗口的情况下打开它，或直接运行以下命令用于诊断：

```powershell
powershell -File desktop\WintageInstaller.ps1
```

带颜色色块的主题列表、这台机器上找到的目标、实时 Win95 预览，以及全部 21 个可编辑色板形式的颜色令牌。编辑任何色板都会把调色板分叉为 **Custom**，而不是在你背后改动已发布主题。右侧面板实时显示三个承载文本令牌的 WCAG 对比度 — 在那里 FAIL 的调色板反正也会被构建门禁拒绝，所以在 Apply 之前而不是之后看到它更好。

目标被分成两个键盘可到达的列表：**MY APPS** 包含便携式/源码树的 CodeNomad、SAIPENVIEW、SmartVac 和 WildRift 工具；**POPULAR APPS** 包含 Windows、OBS、终端、编辑器和其他已安装软件。ALL/NONE 和 Apply/Revert 在保持分组不变的前提下跨两个列表操作。

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
| `antigravity`, `vscode` | `~/.antigravity/extensions` / `~/.vscode/extensions` 中的颜色主题扩展 | **yes** — 它存在于你的配置文件中 |
| `freebuff`, `antigravity-app`, `codenomad` | Electron shim，见下文 | no — 重新运行安装器 |
| `claude` | Electron shim，就地修补 — 见下文 | no — 更新会生成新的 `app-<version>` 文件夹 |
| `mpchc` | 注册表，仅深色主题 + OSD 排版 | no — MPC-HC 退出时会重写其设置 |
| `obsidian` | 每个 vault 的社区主题，一次安装所有调色板 | **yes** — 它存在于你的 vault 中 |
| `saipenview` | 在 `style.css` 中重写自己的 `:root` 令牌值 | no — 源码文件；pull 后重新运行 |
| `discord` | 将 CSS 放入 BetterDiscord 自己的主题文件夹 | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini` 的 `[Colors]` 键；现有的最近文件过滤器使用调色板链接色 | yes — 那是你的 ini |
| `smartvac`, `wildrift` | 在应用自己的源码中重写令牌表 | no — 源码文件；pull 后重新运行 |

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

### SAIPENVIEW

它的前端已经在自己的 `:root` 中声明了 Wintage 令牌名，所以此补丁只重写**令牌值** — 绝不动选择器、字体、边框宽度或内边距。任何影响盒模型的东西都不会改变，因此文本不会移位。这是有意的：早期做法把整个浏览器样式表叠加上去，而 `wintage.css` 是为任意网页编写的 — 通用选择器强制字体、字号阶梯、2px 边框和控制高度。在一个已经有自己布局的应用上，那会移动一切。

通过屏蔽每个十六进制值并与备份做 diff 来验证：结构上相同，只有颜色字面量不同。`--link` 被报告为在那里未声明（它的 markdown 链接读取 `--accentTeal`，而这确实会设置它），因此不注入 — 添加一个应用从不读取的变量只会是死重。

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

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
