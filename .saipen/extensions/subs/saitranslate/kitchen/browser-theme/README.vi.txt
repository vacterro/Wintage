Vintage Win 95 Dark Golden — theme trình duyệt (Cent Browser / Chrome / Edge)
==========================================================================

Theme đồng hành cho userscript Wintage (https://github.com/vacterro/Wintage).
Theme này là một palette Dark Golden cố định kiểu legacy, đóng gói thủ công và độc lập
với các palette chuyển đổi của userscript: canvas #1A0F05, toolbar #2A1C0A, chữ vàng #D4B87A,
viền vàng #C0A060, omnibox lõm #0F0A04, link nhấn #9DD9F9. Nó không theo palette mặc định
(Golden Default) của script hay các gói themes/*.json — nó giữ phong cách Dark Golden cổ điển
mà theme trình duyệt này được xây dựng.

INSTALL:
  1. Mở chrome://extensions
  2. Bật "Developer mode" (góc trên phải)
  3. Nhấp "Load unpacked" và chọn thư mục này (vintage_theme)
  4. Theme áp dụng ngay. Tải lại nó theo cách tương tự sau khi chỉnh sửa.

REVERT:
  Settings -> Appearance -> "Reset to default", hoặc gỡ theme
  khỏi chrome://extensions.

Ánh xạ token:
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
