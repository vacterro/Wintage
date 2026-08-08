Vintage Win 95 tamno zlatna — tema preglednika (Cent Browser / Chrome / Edge)
============================================================================

Popratna tema za Wintage userscript (https://github.com/vacterro/Wintage).
Ova tema je fiksna starija tamno zlatna paleta, ručno pakirana i neovisna o
prebacivim paletama userscripta: canvas #1A0F05, toolbar #2A1C0A, zlatni tekst
#D4B87A, zlatni bevel #C0A060, udubljeni omnibox #0F0A04, akcent poveznica
#9DD9F9. Ne prati zadane palete skripte (Golden Default) ni pakete themes/*.json
— ostaje na klasičnom tamno zlatnom izgledu s kojim je ova tema preglednika
izgrađena.

INSTALACIJA:
  1. Otvori chrome://extensions
  2. Omogući "Developer mode" (gore desno)
  3. Klikni "Load unpacked" i odaberi ovu mapu (vintage_theme)
  4. Tema se odmah primjenjuje. Nakon izmjena je ponovno učitaj na isti način.

PONIŠTAVANJE:
  Idi na Settings -> Appearance -> "Reset to default", ili ukloni temu
  iz chrome://extensions.

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
