Vintage Win 95 深色金色 — 浏览器主题 (Cent Browser / Chrome / Edge)
==========================================================================

Wintage 用户脚本 (https://github.com/vacterro/Wintage) 的配套主题。
此主题采用固定的传统深色金色调色板，手动打包，独立于用户脚本的可切换调色板:
画布 #1A0F05、工具栏 #2A1C0A、金色文本 #D4B87A、斜面金 #C0A060、
凹陷的地址栏 #0F0A04、链接强调色 #9DD9F9。它不跟随脚本的默认调色板
(Golden Default)，也不跟随 themes/*.json 主题包 —— 它保持此浏览器主题
构建时采用的经典深色金色外观。

安装:
  1. 打开 chrome://extensions
  2. 启用 "Developer mode" (右上角)
  3. 点击 "Load unpacked" 并选择此文件夹 (vintage_theme)
  4. 主题立即生效。编辑后以相同方式重新加载。

还原:
  Settings -> Appearance -> "Reset to default"，或从 chrome://extensions 中
  移除主题。

令牌映射:
  frame / ntp_background   #1A0F05  (canvas)
  frame_inactive / toolbar #2A1C0A  (surface)
  frame_incognito          #0F0A04  (compare-back)
  omnibox_background       #0F0A04  (sunken field)
  tab_text / ntp_text      #D4B87A  (golden primary)
  tab_background_text      #B09558  (golden secondary)
  ntp_header               #C0A060  (bevel highlight)
  button_background        #362812  (raised)
  ntp_link                 #9DD9F9  (accent)

<!-- source-digest: browser-theme/README.txt sha256:056bdd1c330ee8c2 -->
