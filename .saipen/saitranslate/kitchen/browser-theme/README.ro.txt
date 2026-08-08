Vintage Win 95 Dark Golden — tema de browser (Cent Browser / Chrome / Edge)
===========================================================================

Temă companion pentru userscript-ul Wintage (https://github.com/vacterro/Wintage).
Această temă este o paletă Dark Golden moștenită, fixă, împachetată manual și
independentă de paletele comutabile ale userscript-ului: canvas #1A0F05, toolbar
#2A1C0A, text auriu #D4B87A, teșire aurie #C0A060, omnibox adâncit #0F0A04, accent
de link #9DD9F9. Nu urmărește implicitul scriptului (Golden Default) nici pachetele
themes/*.json — rămâne la aspectul Dark Golden clasic cu care a fost construită
această temă de browser.

INSTALL:
  1. Deschide chrome://extensions
  2. Activează "Developer mode" (sus dreapta)
  3. Dă clic pe "Load unpacked" și selectează acest dosar (vintage_theme)
  4. Tema se aplică imediat. Reîncarc-o la fel după editări.

REVERT:
  Settings -> Appearance -> "Reset to default", sau elimină tema
  din chrome://extensions.

Maparea tokenurilor:
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
