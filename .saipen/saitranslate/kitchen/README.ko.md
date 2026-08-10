# Wintage

**웹 전체를 위한 Win95 다크 골든 빈티지 테마.** 모든 사이트를 어두운 금갈색 Windows 95 애플리케이션으로 다시 스타일링하는 Tampermonkey 유저스크립트: 픽셀처럼 날카로운 3D 베벨, 둥근 모서리 없음, 애니메이션 없음, 호버 플래시뱅 없음, 모든 곳에 Verdana.

[🤍 개발자 후원](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_모던 웹은 사용성을 희생하면서 미관을 최적화한다. 둥근 모서리는 시각적 위계를 대체하고, 애니메이션은 피드백을 대체하고, 그림자는 구조를 대체하며, 미니멀리즘은 인터페이스를 이해하기 위해 뇌가 의존하는 단서들 자체를 제거한다._

_사용자가 어떤 것이 버튼인지, 라벨인지, 카드인지, 아니면 그냥 텍스트인지 추측하게 해서는 안 된다. Wintage는 명시적인 시각 언어를 되살린다: 돌출된 버튼, 함몰된 입력란, 날카로운 경계, 일관된 타이포그래피, 주의를 흩뜨리는 것 없음, 즉각적인 상태 변화._

_모든 요소는 한눈에 자신의 용도를 전달한다. 이는 인지 부하를 줄이고 웹을 장식용 거품의 모임이 아니라 다시 정밀한 도구처럼 느끼게 한다._

[변경 이력](CHANGELOG.md)

## 설치

1. [Tampermonkey](https://www.tampermonkey.net/) 설치 (Chrome, Edge, Firefox, Opera, Safari).
2. **[Wintage 설치](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** 클릭 — Tampermonkey가 설치 페이지를 자동으로 연다.
3. 끝. 방문하는 모든 사이트가 이제 다크 골든 에디션의 Windows 95로 동작한다.

## 업데이트

- **자동:** 스크립트는 이 리포지토리를 가리키는 `@updateURL`/`@downloadURL` 을 담고 있어, Tampermonkey가 정기 업데이트 확인에서 새 버전을 가져온다.
- **수동 새로고침:** Tampermonkey → **Utilities → Check for userscript updates**, 또는 설치 링크를 다시 클릭 — 기존 버전을 그 자리에서 교체하므로 제거할 필요가 없다.
- **테마 행이 없으면 오래된 스크립트:** 메뉴는 내장 테마 레지스트리에서 생성되며 릴리스 테스트는 모든 내장 팔레트에 정확히 하나의 메뉴 행을 요구한다. 메뉴가 아래 팔레트 목록보다 짧으면 **Install Wintage** 를 다시 클릭하고 Tampermonkey에서 **Update** 를 확인한다.

## 열여섯 개의 팔레트와 스위치

Wintage는 더 이상 단일 팔레트가 아니다. 여섯 개는 UI.md 자체의 구조를 다른 색조 계열로 회전시킨 것 (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad) 이고, Custom은 데스크톱 설치기에서 편집·저장할 수 있으며, 아홉 개는 [FastPrompter](https://github.com/vacterro) 에서 가져온 것이다 (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). 그 모두가 텍스트를 담당하는 세 토큰에서 WCAG AA를 충족한다 — 빌드 게이트는 충족하지 못하는 팔레트를 거부한다.

어느 페이지에서나 **Tampermonkey 메뉴** 에서 하나를 고른다. 선택은 사이트별이 아니라 사용자별로 저장되므로 모든 도메인에서 유지된다.

팔레트는 스크립트 밖 `themes/*.json` 에 있다. 이유는 하나: Tampermonkey는 업데이트 때마다 `wintage.user.js` 를 다시 다운로드하므로, 손으로 편집해 넣은 팔레트는 사라진다. 새 빌드에 다시 적용하려면:

```powershell
.\install-themes.ps1 -Latest
```

## 브라우저 너머로

같은 팔레트가 데스크톱 애플리케이션에도 설치된다 — VS Code와 Antigravity에는 컬러 테마로, Electron 앱 (Freebuff, Antigravity 에이전트 앱) 에는 이 유저스크립트가 사용하는 바로 그 스타일시트를 주입하는 셰임을 통해. 이를 위한 작은 GUI도 있다:

리포지토리 루트의 **`Wintage Installer.vbs`** 를 더블클릭. 콘솔 창 없이 GUI가 열린다. 레거시 `.cmd` 런처는 같은 숨은 호스트로 전달한다. `desktop\WintageInstaller.ps1` 은 진단용으로 직접 실행할 수도 있다.

각 대상이 무엇에 도달할 수 있고 무엇에 도달할 수 없는지 — 용접되어 닫힌 앱과 색상이 컴파일되어 들어있는 앱 두 가지를 포함 — 는 **[desktop/README.md](desktop/README.md)** 에 적혀 있다.

## 기능

- **Golden Default 팔레트** — 깊은 갈색-검정 캔버스 `#1A1810`, 금색 텍스트 `#D4C89A`, 금색 베벨 하이라이트 `#F0D060`. 단색 평면뿐: 그라데이션 없음, 블러 없음, 투명 효과 없음.
- **클래식 3D 베벨** — 버튼은 돌출, 입력란은 함몰, 누른 버튼은 눌린다 (본래의 1px 라벨 이동 포함). 스크롤바는 완전한 16px Win95 스타일로, 베벨 처리된 엄지와 버튼 포함.
- **둥근 모서리 제거기** — `border-radius: 0` 이 프레임워크 CSS 변수 (Bootstrap, Material, YouTube, Reddit) 까지 포함해 모든 곳에 강제된다.
- **동작 금지** — 모든 트랜지션과 애니메이션은 0으로 처리된다. 상태 변화는 실제 1995년 UI처럼 즉시 일어난다.
- **호버 하이라이트 완전 비활성화** — 흰색 플래시뱅 행도, 회색 틴트 블록도 없음:
  - 읽을 수 있는 모든 `:hover` CSS 규칙에서 페인트 속성이 외과적으로 제거된다 (`display`/`visibility`/`opacity` 같은 기능 속성은 유지되므로 호버로 여는 메뉴는 작동한다);
  - 읽을 수 없는 크로스 오리진 스타일시트는 트랜지션 동결 폴백으로 무력화된다.
  실제 컨트롤 (버튼, 링크, 입력란) 만 즉각적인 테마 베벨 응답을 유지한다.
- **Verdana 100% 강제** — 입력란과 textarea를 포함하고 글꼴 스무딩은 비활성화. 아이콘 글꼴은 글리프가 글자로 변하지 않도록 제외된다. `Verdana_m1` 이라는 이름의 사용자 지정 글꼴 (예: 디앤티앨리어싱된 Verdana 패치) 이 설치되어 있으면 자동으로 사용되고, 없으면 일반 Verdana를 사용한다.
- **적응형 다시 그리기** — 가벼운 JS 스위퍼가 밝은 "플래시뱅" 표면과 테마 없는 다크 모드 회색을 빈티지 갈색 스케일로 바꾸고, 낮은 대비 (어두운 위에 어두운) 텍스트를 WCAG 인식 임계값에서 금색으로 수정한다. 이미지, 비디오, 캔버스, 플레이어는 절대 건드리지 않는다.
- **Shadow DOM 관통** — `attachShadow` 훅을 통해 웹 컴포넌트 (YouTube, Reddit 등) 도 테마 적용한다.
- **팝업이 제대로 행동한다** — 메뉴, 다이얼로그, 툴팁, 호버카드는 재색칠만 된다. 스크립트는 `opacity`/`z-index`/`visibility` 를 결코 강제하지 않으므로 숨겨진 사이트 UI는 숨은 채로 남는다.
- **안전 가드** — 스크립트는 OAuth, 캡차, 뱅킹, 결제 페이지에서 스스로 비활성화되어 중요한 흐름이 다시 스타일링되지 않는다.

## 팔레트

아래 표는 Golden Default 팔레트의 21개 토큰 중 10개를 보여준다. 출시되는 모든 팔레트는 21개 전부를 정의한다. 나머지 11개는 베벨 구조, 보조 텍스트, 의미 색상 (성공/경고/위험), 선택 상태, 대상별 세부 사항을 담당한다.

| Token | Hex | 용도 |
|---|---|---|
| background | `#1A1810` | 최외곽 배경 |
| backgroundSoft | `#232018` | body / 콘텐츠 배경 |
| surface | `#332E22` | 헤더, 내비게이션, 패널 |
| surfaceRaised | `#3D372A` | 버튼, 팝업, 스크롤바 엄지 |
| surfaceAlt | `#453D30` | 버튼 호버 |
| borderHighlight | `#F0D060` | 왼쪽-위 3D 가장자리 |
| borderDark | `#100E08` | 오른쪽-아래 3D 가장자리 |
| textPrimary | `#D4C89A` | 기본 금색 텍스트 |
| textMuted | `#6E674E` | 플레이스홀더, 비활성 |
| link | `#F0D060` | 링크, 포커스 |

## 일치하는 브라우저 테마

데스크톱 설치기의 `browsers` 대상은 설치된 프로필과 휴대용 Chromium 프로필을 모두 탐지하고, Tampermonkey 적용 범위를 보고하며, 선택한 브라우저 테마를 준비하고, 모든 프로필에 대해 올바른 설치/업데이트 페이지를 연다. Chromium은 프로필마다 **Developer mode → Load unpacked** 확인이 한 번 필요하다. 설치기는 안정 테마 경로를 클립보드에 복사한다. 이후 팔레트 변경은 그 경로를 재사용한다.

## 알려진 동작

- 호버 효과를 CSS `:hover` 대신 JavaScript (클래스 토글) 로 만드는 사이트는 자체 하이라이트를 계속 표시할 수 있다.
- CSS가 크로스 오리진인 드문 사이트에서는 포커스할 수 없는 요소를 클릭하면 마우스가 떠날 때까지 시각적 상태 변화가 지연될 수 있다 (호버 동결 폴백이 작동 중). 실제 버튼과 링크는 예외다.
- 스크립트는 설계상 정적이다: 옵션 패널도, 사이트별 토글도 없다. 다른 맛을 원하면 포크해서 맨 위의 토큰을 편집하라.

## 새 버전 릴리스 (메인테이너용)

먼저 `CHANGELOG.md` 맨 위에 `## [x.y.z] - date` 항목을 추가하세요 — 없으면 `release.ps1`이 실행을 거부합니다. 그런 다음:

```powershell
.\release.ps1 -Message "변경 내용"
```

`@version` 패치 번호를 올리고(Tampermonkey 헤더와 `W95_VERSION` 스탬프가 함께 움직임), 생성된 데스크톱 테마를 다시 빌드하며, 릴리스 게이트 전체를 실행하고, 커밋·태그·푸시한다 — Tampermonkey 클라이언트가 업데이트를 자동으로 가져간다. 더 큰 릴리스에는 `-Bump minor` 또는 `-Bump major` 를 전달한다.

## 라이선스

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
