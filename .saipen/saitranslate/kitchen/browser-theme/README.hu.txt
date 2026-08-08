Vintage Win 95 Dark Golden — böngészőtéma (Cent Browser / Chrome / Edge)
========================================================================

Kísérőtéma a Wintage felhasználóskripthez (https://github.com/vacterro/Wintage).
Ez a téma egy rögzített legacy Dark Golden paletta, kézzel csomagolva, és független a
felhasználóskript váltható palettáitól: canvas #1A0F05, toolbar #2A1C0A, arany szöveg
#D4B87A, ferde arany #C0A060, besüllyedt omnibox #0F0A04, link accent #9DD9F9. Nem
követi a szkript alapértelmezését (Golden Default), sem a themes/*.json csomagokat —
a klasszikus Dark Golden kinézetnél marad, amellyel ezt a böngészőtémát készítették.

INSTALL:
  1. Nyisd meg a chrome://extensions oldalt
  2. Kapcsold be a "Developer mode"-ot (jobbra fent)
  3. Kattints a "Load unpacked" gombra, és válaszd ki ezt a mappát (vintage_theme)
  4. A téma azonnal érvénybe lép. Szerkesztés után ugyanígy töltsd újra.

REVERT:
  Settings -> Appearance -> "Reset to default", vagy távolítsd el a témát
  a chrome://extensions oldalról.

Token-hozzárendelés:
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
