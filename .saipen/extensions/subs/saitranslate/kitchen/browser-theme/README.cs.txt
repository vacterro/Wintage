Vintage Win 95 tmavě zlatá — motiv prohlížeče (Cent Browser / Chrome / Edge)
==========================================================================

Doprovodný motiv pro userscript Wintage (https://github.com/vacterro/Wintage).
Tento motiv je pevná starší tmavě zlatá paleta, ručně svázaná a nezávislá na
přepínatelných paletách userscriptu: canvas #1A0F05, toolbar #2A1C0A, zlatý text
#D4B87A, zlatý bevel #C0A060, zapuštěný omnibox #0F0A04, akcent odkazů #9DD9F9.
Nesleduje výchozí paletu skriptu (Golden Default) ani balíčky themes/*.json —
zůstává u klasického tmavě zlatého vzhledu, se kterým byl tento motiv prohlížeče
vytvořen.

INSTALACE:
  1. Otevřete chrome://extensions
  2. Povolte "Developer mode" (vpravo nahoře)
  3. Klikněte na "Load unpacked" a vyberte tuto složku (vintage_theme)
  4. Motiv se použije okamžitě. Po úpravách jej stejným způsobem znovu načtěte.

NÁVRAT:
  Přejděte na Settings -> Appearance -> "Reset to default", nebo motiv odeberte
  z chrome://extensions.

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
