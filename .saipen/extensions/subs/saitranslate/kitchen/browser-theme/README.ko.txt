Vintage Win 95 다크 골든 — 브라우저 테마 (Cent Browser / Chrome / Edge)
==========================================================================

Wintage 유저스크립트 (https://github.com/vacterro/Wintage) 의 동반 테마.
이 테마는 고정된 레거시 Dark Golden 팔레트로, 직접 번들되어 있으며 유저스크립트의
전환 가능한 팔레트와 무관하다: 캔버스 #1A0F05, 툴바 #2A1C0A, 금색 텍스트 #D4B87A,
베벨 골드 #C0A060, 함몰된 옴니박스 #0F0A04, 링크 액센트 #9DD9F9. 스크립트의
기본값 (Golden Default) 이나 themes/*.json 팩을 따르지 않는다 — 이 브라우저
테마가 만들어진 클래식 Dark Golden 모습을 유지한다.

설치:
  1. chrome://extensions 열기
  2. "Developer mode" 사용 설정 (오른쪽 위)
  3. "Load unpacked" 클릭 후 이 폴더 (vintage_theme) 선택
  4. 테마는 즉시 적용된다. 편집 후에도 같은 방식으로 다시 불러온다.

되돌리기:
  Settings -> Appearance -> "Reset to default", 또는 chrome://extensions 에서
  테마를 제거한다.

토큰 매핑:
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
