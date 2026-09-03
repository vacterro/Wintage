Vintage Win 95 Dark Golden — тема браузера (Cent Browser / Chrome / Edge)
==========================================================================

Супутня тема для юзерскрипта Wintage (https://github.com/vacterro/Wintage).
Це фіксована застаріла палітра Dark Golden, вручну зібрана та незалежна від
палітр юзерскрипта, що перемикаються: canvas #1A0F05, toolbar #2A1C0A, golden text
#D4B87A, bevel gold #C0A060, sunken omnibox #0F0A04, link accent #9DD9F9. Вона не
стежить за типовою палітрою скрипта (Golden Default) і не залежить від пакетів
themes/*.json — тема лишається на класичному вигляді Dark Golden, з яким вона й була створена.

ВСТАНОВЛЕННЯ:
  1. Відкрийте chrome://extensions
  2. Увімкніть «Developer mode» (угорі праворуч)
  3. Натисніть «Load unpacked» і виберіть цю теку (vintage_theme)
  4. Тема застосовується одразу. Після редагувань перезавантажте її так само.

ВІДКАТ:
  Налаштування -> Зовнішній вигляд -> «Reset to default», або видаліть тему
  з chrome://extensions.

Token mapping:
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
