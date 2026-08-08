# Wintage

**面向整个网络的 Win95 深色金色复古主题。** 一个 Tampermonkey 用户脚本，将每个网站重新样式化为深金棕色的 Windows 95 应用程序：像素级锐利的 3D 斜面、零圆角、零动画、无悬停闪屏，处处 Verdana。

[🤍 支持开发者](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_现代网络以牺牲可用性为代价来优化美感。圆角取代了视觉层级，动画取代了反馈，阴影取代了结构，而极简主义往往删除了我们大脑赖以理解界面的线索。_

_用户不应该去猜某个东西是按钮、标签、卡片还是普通文本。Wintage 重新带来了明确的视觉语言：凸起的按钮、凹陷的输入框、锐利的边界、一致的排版、零干扰、即时状态变化。_

_每个元素都能一眼传达其用途，降低认知负担，让网络再次像一台精密仪器，而不是一堆装饰性的气泡。_

[更新日志](CHANGELOG.md)

## 安装

1. 安装 [Tampermonkey](https://www.tampermonkey.net/)（Chrome, Edge, Firefox, Opera, Safari）。
2. 点击 **[安装 Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey 会自动打开安装页面。
3. 完成。你访问的每个网站现在都运行着深色金色版的 Windows 95。

## 更新

- **自动：** 脚本携带指向此仓库的 `@updateURL`/`@downloadURL`，因此 Tampermonkey 会在定期更新检查中获取新版本。
- **手动刷新：** Tampermonkey → **Utilities → Check for userscript updates**，或直接再次点击安装链接 — 它会就地替换旧版本，无需卸载。
- **主题行缺失意味着旧脚本：** 菜单由内嵌的主题注册表生成，发布测试要求每个内置调色板恰好有一行菜单。如果菜单短于下面的调色板列表，请再次点击 **Install Wintage** 并在 Tampermonkey 中确认 **Update**。

## 十六个调色板与一个开关

Wintage 不再只有一个调色板。六个是 UI.md 自身的结构旋转到另一个色相系（Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad），Custom 可以从桌面安装器中编辑和保存，九个是从 [FastPrompter](https://github.com/vacterro) 导入的（Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark）。它们每一个都在三个承载文本的令牌上通过 WCAG AA — 构建门禁会拒绝未通过的调色板。

在任意页面的 **Tampermonkey 菜单** 中选择一个；选择按用户而非按网站存储，因此跨所有域都有效。

调色板位于脚本之外的 `themes/*.json`，原因只有一个：Tampermonkey 每次更新都会重新下载 `wintage.user.js`，手工编辑进去的调色板会消失。重新应用到新构建：

```powershell
.\install-themes.ps1 -Latest
```

## 超越浏览器

同样的调色板也安装到桌面应用程序中 — VS Code 和 Antigravity 作为颜色主题，Electron 应用（Freebuff、Antigravity 代理应用）通过一个注入此用户脚本所用样式表的 shim。为此还有一个小的 GUI：

双击仓库根目录的 **`Wintage Installer.vbs`**。它会在没有控制台窗口的情况下打开 GUI。旧的 `.cmd` 启动器转发到同一个隐藏宿主；`desktop\WintageInstaller.ps1` 仍可直接运行用于诊断。

每个目标能触及什么、不能触及什么 — 包括两个被熔接关闭或其颜色被编译进程序的应用 — 都写在 **[desktop/README.md](desktop/README.md)** 中。

## 特性

- **Golden Default 调色板** — 深棕黑色画布 `#1A1810`、金色文本 `#D4C89A`、金色斜面高光 `#F0D060`。仅纯色平面：无渐变、无模糊、无透明效果。
- **经典 3D 斜面** — 按钮凸起、输入框凹陷、按下的按钮向内压（带有真实的 1px 标签位移）。滚动条是完整的 16px Win95 风格，包括带斜面的滑块和按钮。
- **圆角杀手** — 强制处处 `border-radius: 0`，包括框架 CSS 变量（Bootstrap, Material, YouTube, Reddit）。
- **禁止动效** — 所有过渡和动画都被归零。状态变化是即时的，如同真正的 1995 年界面。
- **悬停高亮完全禁用** — 没有白色闪屏行，没有灰色色调块：
  - 从每条可读的 `:hover` CSS 规则中外科手术式地剥离绘制属性（`display`/`visibility`/`opacity` 等功能属性保留，因此悬停打开的菜单仍然有效）；
  - 不可读的跨域样式表通过过渡冻结回退被中和。
  只有真正的控件（按钮、链接、输入框）保留即时的、主题化的斜面响应。
- **处处强制 Verdana 100%** — 包括输入框和 textarea，并禁用字体平滑。图标字体被排除，以免字形变成字母。如果你安装了名为 `Verdana_m1` 的自定义字体（例如去抗锯齿的 Verdana 补丁），会自动使用它；否则使用常规 Verdana。
- **自适应重绘器** — 一个轻量级 JS 清扫器将明亮的"闪屏"表面和未主题化的深色模式灰色转换为复古棕色系，并在 WCAG 感知阈值下将低对比度（深上加深）文本修复为金色。图像、视频、canvas 和播放器永远不会被触碰。
- **Shadow DOM 穿透** — 也为主题化 web 组件（YouTube、Reddit 等）提供支持，通过 `attachShadow` 钩子。
- **弹窗表现正常** — 菜单、对话框、工具提示和悬停卡片仅被重新着色；脚本从不强制 `opacity`/`z-index`/`visibility`，因此隐藏的网站 UI 保持隐藏。
- **安全保护** — 脚本会在 OAuth、验证码、银行和支付页面上自动禁用，因此关键流程绝不会被重新样式化。

## 调色板

下表展示了 Golden Default 调色板 21 个令牌中的 10 个。每个发布的调色板都定义了全部 21 个；其余 11 个涵盖斜面结构、次要文本、语义颜色（成功/警告/危险）、选中状态以及各目标的细节。

| Token | Hex | 用途 |
|---|---|---|
| background | `#1A1810` | 最外层背景 |
| backgroundSoft | `#232018` | body / 内容背景 |
| surface | `#332E22` | 标题栏、导航、面板 |
| surfaceRaised | `#3D372A` | 按钮、弹窗、滚动条滑块 |
| surfaceAlt | `#453D30` | 按钮悬停 |
| borderHighlight | `#F0D060` | 左上 3D 边缘 |
| borderDark | `#100E08` | 右下 3D 边缘 |
| textPrimary | `#D4C89A` | 主要金色文本 |
| textMuted | `#6E674E` | 占位符、禁用 |
| link | `#F0D060` | 链接、焦点 |

## 匹配的浏览器主题

桌面安装器的 `browsers` 目标会检测已安装和便携式 Chromium 配置文件，报告 Tampermonkey 覆盖情况，暂存所选浏览器主题，并为每个配置文件打开正确的安装/更新页面。Chromium 每个配置文件需要一次 **Developer mode → Load unpacked** 确认；安装器将稳定主题路径复制到剪贴板。之后的调色板更改复用该路径。

## 已知行为

- 使用 JavaScript（类切换）而非 CSS `:hover` 构建悬停效果的网站可能仍显示自己的高亮。
- 在 CSS 属于跨域的少数网站上，点击不可聚焦的元素可能会将其视觉状态变化延迟到鼠标离开之后（悬停冻结回退在起作用）。真正的按钮和链接不受影响。
- 脚本设计上是静态的：没有选项面板，没有按网站的开关。想要不同风味就 fork 并编辑顶部的令牌。

## 发布新版本（维护者）

编辑 `wintage.user.js`，然后运行：

```powershell
.\release.ps1 -Message "改了什么"
```

它会提升 `@version` 补丁号、提交并推送 — Tampermonkey 客户端会自动获取更新。较大的版本传递 `-Bump minor` 或 `-Bump major`。

## 许可证

[MIT](LICENSE)

<!-- source-digest: README.md sha256:ee7c6a2a1626faed -->
