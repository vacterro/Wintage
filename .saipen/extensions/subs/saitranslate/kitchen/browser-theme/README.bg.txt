Vintage Win 95 Dark Golden — браузърна тема (Cent Browser / Chrome / Edge)
=========================================================================

Компаньон тема за Wintage userscript-а (https://github.com/vacterro/Wintage).
Тази тема е фиксирана legacy Dark Golden палитра, ръчно вградена и независима от
превключваемите палитри на userscript-а: canvas #1A0F05, toolbar #2A1C0A, златист
текст #D4B87A, бевел злато #C0A060, вдлъбнат omnibox #0F0A04, линк accent #9DD9F9.
Тя не следи стандартната палитра на скрипта (Golden Default), нито themes/*.json
пакетите — остава на класическия Dark Golden вид, с който тази браузърна тема е
създадена.

INSTALL:
  1. Отворете chrome://extensions
  2. Включете "Developer mode" (горе вдясно)
  3. Кликнете "Load unpacked" и изберете тази папка (vintage_theme)
  4. Темата се прилага веднага. Презаредете я по същия начин след промени.

REVERT:
  Settings -> Appearance -> "Reset to default", или премахнете темата
  от chrome://extensions.

Картографиране на токените:
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
