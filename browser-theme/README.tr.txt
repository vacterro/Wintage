Vintage Win 95 Koyu Altın — tarayıcı teması (Cent Browser / Chrome / Edge)
==========================================================================

Wintage kullanıcı betiği için tamamlayıcı tema (https://github.com/vacterro/Wintage).
Bu tema, el ile paketlenmiş, sabit bir eski Koyu Altın paletidir ve kullanıcı betiğinin
değiştirilebilir paletlerinden bağımsızdır: canvas #1A0F05, toolbar #2A1C0A, altın metin
#D4B87A, bevel altını #C0A060, batık omnibox #0F0A04, bağlantı vurgusu #9DD9F9. Betiğin
varsayılanını (Golden Default) ve themes/*.json paketlerini izlemez — bu tarayıcı temasının
kurulduğu klasik Koyu Altın görünümünde kalır.

KURULUM:
  1. chrome://extensions öğesini açın
  2. "Developer mode" öğesini etkinleştirin (sağ üstte)
  3. "Load unpacked" öğesine tıklayın ve bu klasörü seçin (vintage_theme)
  4. Tema hemen uygulanır. Düzenlemelerden sonra aynı şekilde yeniden yükleyin.

GERİ AL:
  Settings -> Appearance -> "Reset to default" bölümünden sıfırlayın veya temayı
  chrome://extensions üzerinden kaldırın.

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
