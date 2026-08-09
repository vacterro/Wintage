Vintage Win 95 Dark Golden — тема браузера (Cent Browser / Chrome / Edge)
==========================================================================

Тема-компаньон для юзерскрипта Wintage (https://github.com/vacterro/Wintage).
Это фиксированная устаревшая палитра Dark Golden, вручную собранная и независимая
от переключаемых палитр юзерскрипта: canvas #1A0F05, toolbar #2A1C0A, золотой текст
#D4B87A, золотые фаски #C0A060, утопленный omnibox #0F0A04, акцент ссылок #9DD9F9.
Она не следит за дефолтом скрипта (Golden Default) и не за пакетами themes/*.json —
остаётся на классическом виде Dark Golden, с которым эта тема и была собрана.

УСТАНОВКА:
  1. Откройте chrome://extensions
  2. Включите "Developer mode" (справа сверху)
  3. Нажмите "Load unpacked" и выберите эту папку (vintage_theme)
  4. Тема применяется сразу. Перезагрузите её так же после правок.

ОТКАТ:
  Settings -> Appearance -> "Reset to default", или удалите тему
  из chrome://extensions.

Соответствие токенов:
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
