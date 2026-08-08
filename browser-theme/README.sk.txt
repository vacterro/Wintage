Vintage Win 95 tmavozlatý — motív prehliadača (Cent Browser / Chrome / Edge)
===========================================================================

Doplnkový motív pre userscript Wintage (https://github.com/vacterro/Wintage).
Tento motív je pevná staršia tmavozlatá paleta, ručne zabalená a nezávislá od
prepínateľných paliet userscriptu: canvas #1A0F05, toolbar #2A1C0A, zlatý text
#D4B87A, zlatý bevel #C0A060, zapustený omnibox #0F0A04, zvýraznenie odkazov
#9DD9F9. Nesleduje predvolenú paletu skriptu (Golden Default) ani balíky
themes/*.json — zostáva pri klasickom tmavozlatom vzhľade, s ktorým bol tento
motív prehliadača vytvorený.

INŠTALÁCIA:
  1. Otvorte chrome://extensions
  2. Zapnite "Developer mode" (vpravo hore)
  3. Kliknite na "Load unpacked" a vyberte tento priečinok (vintage_theme)
  4. Motív sa použije okamžite. Po úpravách ho znova načítajte rovnakým spôsobom.

VRÁTENIE:
  Prejdite na Settings -> Appearance -> "Reset to default", alebo motív odstráňte
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
