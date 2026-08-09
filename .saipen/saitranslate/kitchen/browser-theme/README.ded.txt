Vintage Win 95 Dark Golden — тема браузера (Cent Browser / Chrome / Edge)
==========================================================================

Тема-компаньон юзерскрипта Wintage (https://github.com/vacterro/Wintage).
Это фиксированная устаревшая палитра Dark Golden, собрана вручную и не зависит
от переключаемых палитр юзерскрипта: canvas #1A0F05, toolbar #2A1C0A, золотой
текст #D4B87A, золотые фаски #C0A060, утопленный omnibox #0F0A04, акцент ссылок
#9DD9F9. За дефолтом скрипта (Golden Default) и пакетами themes/*.json она не
следит — сидит на классическом Dark Golden, с которым и родилась.

УСТАНОВКА:
  1. Открой chrome://extensions
  2. Включи "Developer mode" (справа сверху)
  3. Жми "Load unpacked" и тыкай в эту папку (vintage_theme)
  4. Тема применится сразу. Поковырял — перезагрузи так же.

ОТКАТ:
  Settings -> Appearance -> "Reset to default", либо снеси тему
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
