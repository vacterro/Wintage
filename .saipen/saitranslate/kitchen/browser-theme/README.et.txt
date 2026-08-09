Vintage Win 95 Dark Golden — brauseri teema (Cent Browser / Chrome / Edge)
==========================================================================

Wintage-juuskripti kaaslane (https://github.com/vacterro/Wintage).
See teema on fikseeritud pärand-Dark Golden palett, käsitsi kokku pandud ja
sõltumatu juuskripti vahetatavatest palettidest: canvas #1A0F05, toolbar #2A1C0A,
kuldne tekst #D4B87A, kuldne faasimine #C0A060, süvistatud omnibox #0F0A04,
lingiaktsent #9DD9F9. See ei järgi skripti vaikepaletti (Golden Default) ega
themes/*.json pakke — jääb klassikalise Dark Golden välimuse juurde, millega see
teema ehitati.

PAIGALDAMINE:
  1. Avage chrome://extensions
  2. Lülitage sisse "Developer mode" (paremal üleval)
  3. Vajutage "Load unpacked" ja valige see kaust (vintage_theme)
  4. Teema rakendub kohe. Laadige pärast muudatusi samamoodi uuesti.

TAGASIVÕTMINE:
  Settings -> Appearance -> "Reset to default", või eemaldage teema
  saidilt chrome://extensions.

Tokenite vastavus:
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
