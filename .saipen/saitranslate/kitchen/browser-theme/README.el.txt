Vintage Win 95 Dark Golden — θέμα browser (Cent Browser / Chrome / Edge)
========================================================================

Συνοδευτικό θέμα για το userscript Wintage (https://github.com/vacterro/Wintage).
Αυτό το θέμα είναι μια σταθερή παλέτα Dark Golden κληρονομιάς, συσκευασμένη με το χέρι
και ανεξάρτητη από τις εναλλάξιμες παλέτες του userscript: canvas #1A0F05, toolbar
#2A1C0A, χρυσό κείμενο #D4B87A, χρυσή φασέτα #C0A060, βυθισμένο omnibox #0F0A04,
link accent #9DD9F9. Δεν ακολουθεί το προεπιλεγμένο του script (Golden Default) ούτε
τα πακέτα themes/*.json — παραμένει στην κλασική εμφάνιση Dark Golden με την οποία
χτίστηκε αυτό το θέμα browser.

INSTALL:
  1. Ανοίξτε το chrome://extensions
  2. Ενεργοποιήστε το "Developer mode" (πάνω δεξιά)
  3. Κάντε κλικ στο "Load unpacked" και επιλέξτε αυτόν τον φάκελο (vintage_theme)
  4. Το θέμα εφαρμόζεται αμέσως. Φορτώστε το ξανά με τον ίδιο τρόπο μετά από αλλαγές.

REVERT:
  Settings -> Appearance -> "Reset to default", ή αφαιρέστε το θέμα
  από το chrome://extensions.

Αντιστοίχιση tokens:
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
