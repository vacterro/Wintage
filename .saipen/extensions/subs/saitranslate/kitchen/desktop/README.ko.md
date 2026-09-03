# 데스크톱 애플리케이션용 Wintage

유저스크립트는 웹을 테마 처리한다. 이것은 같은 팔레트에서 그 주변의 프로그램을 테마 처리한다. 그래서 브라우저와 앱이 '다크 골든'이 무엇을 의미하는지에 대해 더 이상 다투지 않게 된다.

여기 모든 결정 뒤에는 규칙이 하나 있다: **애플리케이션은 스스로 업데이트되며, 업데이트는 어떤 것도 조용히 망가뜨려서는 안 된다.** 대상이 자신의 프로필에 자리가 있다면 테마는 거기에 가고 업데이트를 견딘다. 자리가 없으면 설치기는 재실행되도록 작성되어 있다 — 그리고 지속된 척하는 대신 그렇게 말한다.

## GUI

리포지토리 루트의 **`Wintage Installer.vbs`** 를 더블클릭하면 콘솔 창 없이 열린다. 또는 진단용으로 직접 실행:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

컬러 칩이 있는 테마 목록, 이 머신에서 찾은 대상, 라이브 Win95 미리보기, 편집 가능한 견본으로서의 21개 컬러 토큰 전부. 견본을 편집하면 출시된 테마를 몰래 바꾸는 대신 팔레트를 **Custom** 으로 분기시킨다. 오른쪽 패널은 텍스트를 담당하는 세 토큰의 라이브 WCAG 대비를 보여준다 — 거기서 FAIL하는 팔레트는 어차피 빌드 게이트가 거부하므로, Apply 후에 보는 것보다 Apply 전에 보는 편이 낫다.

대상은 키보드로 도달 가능한 두 목록으로 나뉜다: **MY APPS** 는 휴대용/소스 트리인 CodeNomad, SAIPENVIEW, SmartVac, WildRift 도구를 담고, **POPULAR APPS** 는 Windows, OBS, 터미널, 편집기 및 기타 설치된 소프트웨어를 담는다. ALL/NONE과 Apply/Revert는 그룹 구분을 바꾸지 않고 두 목록 모두에 걸쳐 동작한다.

창은 설치하려는 팔레트를 입는다. 그것이 가능한 가장 빠른 미리보기이며 도구를 정직하게 유지한다: 이 창을 읽을 수 없게 만드는 팔레트는 눈에 띄게 읽을 수 없다.

Apply는 `install.ps1` 을 셸 아웃한다. 테마를 설치하는 코드 경로는 정확히 하나뿐이므로 GUI가 명령줄에서 벗어날 수 없다.

## 명령줄

```powershell
.\desktop\install.ps1                                  # 무엇이 있는지, 무엇이 테마 처리되었는지, 어떤 팔레트로
.\desktop\install.ps1 -Target freebuff -Palette klite  # 앱 하나, 팔레트 하나
.\desktop\install.ps1 -Target all -Palette goldendefault # 전부
.\desktop\install.ps1 -Target all -WhatIf              # 무엇이 바뀔지 말할 뿐, 아무것도 건드리지 않음
.\desktop\install.ps1 -Target freebuff -Revert         # 하나 되돌리기
```

`-Palette` 기본값은 `goldendefault` (**Golden Default**). GUI도 같은 팔레트로 열리고 사용 가능한 모든 대상을 확인한다. 이미 테마 처리된 앱의 다시 그리기는 실행 중에도 동작한다. 처음 설치는 아카이브가 사용 중이라 동작하지 않는다.

## 각 대상이 실제로 테마 처리될 수 있는 것

| 대상 | 메커니즘 | 앱 업데이트를 견딤 |
|---|---|---|
| `windows` | 사용자 `.theme`: 다크 시스템/앱 모드, 액센트와 클래식 색상 역할 | yes — 로컬 Windows Themes 폴더에 설치됨 |
| `browsers` | 설치된 + 휴대용 Chromium 프로필을 감지하고, 선택한 chrome 테마를 준비하고, 브라우저 소유의 Tampermonkey/테마 확인 페이지를 엶 | yes — 프로필마다 **Load unpacked** 한 번 후 |
| `terminal` | Windows Terminal 스킴 + 모든 프로필 기본값, Consolas 12 앨리어스 | yes — 설정이 프로필에 있음 |
| `conhost` | `HKCU\Console` 기본값 + 기존의 모든 cmd/PowerShell 프로필 | yes — 정확한 터치 값 스냅샷 |
| `obs` | OBS 30.2+ `.ovt` 변형 + 활성 `user.ini` 테마 ID | yes — 프로필에 있음 |
| `antigravity`, `vscode` | `~/.antigravity/extensions` / `~/.vscode/extensions` 의 컬러 테마 확장 | **yes** — 프로필에 있음 |
| `freebuff`, `antigravity-app`, `codenomad` | Electron 셰임, 아래 참조 | no — 설치기 재실행 |
| `claude` | Electron 셰임, 그 자리에서 패치 — 아래 참조 | no — 업데이트가 새 `app-<version>` 폴더를 만듦 |
| `mpchc` | 레지스트리, 다크 테마 + OSD 타이포그래피만 | no — MPC-HC가 종료 시 설정을 다시 씀 |
| `obsidian` | 볼트별 커뮤니티 테마, 모든 팔레트를 한 번에 설치 | **yes** — 볼트에 있음 |
| `saipenview` | `style.css` 에서 자신의 `:root` 토큰 값을 다시 씀 | no — 소스 파일; pull 후 재실행 |
| `discord` | CSS를 BetterDiscord 자체 테마 폴더에 드롭 | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini` 의 `[Colors]` 키. 기존 최근 파일 필터는 팔레트 링크 색상을 사용 | yes — 당신의 ini |
| `smartvac`, `wildrift` | 앱 자체 소스에서 토큰 표를 다시 씀 | no — 소스 파일; pull 후 재실행 |

### FreeBuff 광고 제거

FreeBuff (AI 어시스턴트 데스크톱 앱) 는 자체 광고 네트워크를 동봉한다: 렌더러 번들 (`resources/orchestrator/ui/assets/index-*.js`) 이 `sponsored-ad` 카드와 스레드 배너를 그리고, 오케스트레이터 (`resources/orchestrator/orchestrator.js`) 는 원격 광고 경매를 부르는 `/api/ad/slot|impression|click` 라우트를 노출한다. 셰임은 앱을 테마 처리할 뿐이며 그 파일들에는 손대지 않는다.

`desktop/patch-freebuff-ads.js` 는 광고를 바이트 수준에서 잘라낸다:

- 렌더러: 광고 카드/배너 호출 지점은 `null` 이 되고, `adSlot` / `adImpression` / `adClick` API 클라이언트 메서드는 no-op이 된다 — 아무것도 렌더링되지 않으며 `/api/ad/*` 요청이 렌더러를 떠나지 않는다;
- 오케스트레이터: 세 `/api/ad/*` 라우트 모두 광고 네트워크 호출을 멈추고, 라이브 턴 인라인 광고 요청 (`maybeRequestAd`) 은 단락된다.

번들 파일명에는 빌드 해시가 박혀 있으므로, 패치는 버전 고정 페이로드를 동봉하는 대신 `index.html` 에서 현재 번들을 찾는다 — 그것이 업데이트를 견디는 이유다. 원본은 설치 디렉터리의 `_orig-backup-<timestamp>/` 에 백업된다. `--revert` 는 가장 최근 것을 복원한다.

**향후 버전은 서로 독립된 두 계층에서 처리된다:**

1. **정규식 폴백이 있는 바이트 패치.** 모든 대상에는 현재 빌드의 정확한 문자열과, minifier가 이름을 바꿀 수 없는 것에 고정된 정규식 폴백이 모두 있다 — `/api/ad/*` 경로 리터럴, `case"ad":` 프로토콜 판별자, `sponsored-ad` 클래스, `variant:"banner"` / `variant:"card"` 배치. 오케스트레이터는 minify되지 않았으므로 (`maybeRequestAd`, `app.ads.slotAd` 같은 읽을 수 있는 이름) 그 정확한 문자열은 오래 유지된다. 렌더러 번들은 minify되어 있으므로 다음 빌드가 식별자를 바꾸는 순간 정규식 폴백이 인계받는다.
2. **셰임 레벨 차단 (`targets/electron/shim.cjs`).** 번들과 완전히 독립적이다: 페이지 안에서 `/api/ad/` URL로 가는 모든 fetch/XHR이 거부되고, 클래스에 `sponsored-ad` 가 포함된 모든 요소는 나타나는 순간 숨겨진다. 이 스크립트가 아직 배우지 못한 완전히 새로운 번들조차 광고를 표면화할 수 없다.

```powershell
node .\desktop\patch-freebuff-ads.js           # 패치 (먼저 백업)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # 패치 + 사용자 지정 완료 사운드 (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # 이 빌드는 어떤 광고 마커를 담고 있나?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

이것은 `install.ps1 -Target freebuff` 의 일부로 자동 실행되며, FreeBuff 업데이트 후에는 반드시 다시 실행해야 한다 (업데이트는 스톡 파일을 복원한다). 빌드 모양이 바뀌면 스크립트는 더 이상 일치하지 않는 대상을 이름으로 말한다 — `--scan` 을 실행해 새 빌드가 여전히 가진 것을 확인하고 거기서 문자열을 갱신하라.

**FreeBuff 완료 사운드.** 렌더러는 턴이 끝나면 `chime-<hash>.mp3` 를 재생한다. 패치는 번들을 찾는 것과 같은 방식으로 그것을 찾는다 (이름에 빌드 해시가 박혀 있다) — 그래서 `--sound <file>` 은 당신의 오디오 (wav/mp3/ogg/flac/m4a/aac) 를 그 위에 설치하고 스톡 파일을 `chime-*.mp3.bak` 으로 보존한다. `--revert` 는 그것을 복원한다. `--verify` 는 어떤 것이 활성인지 보고한다.

### FreeBuff 사운드 버튼 (GUI)

`WintageInstaller.ps1` 에는 APPLY / REVERT 스택 아래에 작은 **FB SOUND** 버튼이 있다. 그것은 *설정값*만 저장한다. `install.ps1 -Target freebuff` 는 같은 파일을 읽고 그것을 `--sound` 로 패치에 넘긴다. 그래서 광고와 사운드가 한 번의 실행에서 적용된다:

- **왼쪽 클릭** — 오디오 파일을 고르고 (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) 즉시 재생을 들어 본다: PCM WAV는 System.Media.SoundPlayer로, 그 외 형식은 WPF MediaPlayer로 (Media Foundation, 비동기이므로 창이 얼지 않는다). 선택은 `%APPDATA%\Wintage\freebuff-sound.txt` 에 기억된다 (머신 단위, git 체크아웃 밖, 기억된 소스 트리 폴더와 똑같이).
- **오른쪽 클릭** — FreeBuff의 스톡 차임으로 설정을 되돌린다 (재생 중인 미리보기도 멈춘다).
- **COPY** — 고른 오디오를 리포지토리 자체에 복사하고 (`sounds\freebuff.<ext>`, 소스 확장자를 유지) 설정을 그 복사본으로 다시 가리킨다. 원본 파일이 삭제되거나 옮겨져도 사운드가 살아남는다. 사용자 지정 사운드가 설정되어 있는 동안에만 활성화된다. 다시 복사하면 리포지토리 복사본을 덮어쓸 뿐이다. `sounds/` 폴더는 평범한 git 추적 가능 콘텐츠이므로, 커밋하면 사운드는 재클론에도 견딘다.

인식된 오디오 컨테이너만 미리 보여진다 — 먼저 헤더를 스니핑하므로, 오디오가 아닌 선택은 조용히 아무것도 재생하지 않는 대신 알림이 나온다.

사용자 지정 사운드가 설정되어 있는 동안 버튼은 `ON` 을 표시하고, 호버하면 경로를 보여준다. 그 후 `freebuff` 대상을 적용하면 (FreeBuff에 체크하고 APPLY, 또는 터미널에서 `install.ps1 -Target freebuff` 실행) 효과가 나타난다.

### 터미널

`terminal` 은 감지된 모든 안정 버전, Preview, 미패키지 Windows Terminal 설정 파일에 `Wintage` 색상 스킴을 쓰고 `profiles.defaults` 를 통해 그것을 선택한다. 콘솔에 안전한 Consolas 12와 앨리어스 텍스트와 함께. 원본 파일은 그 옆에 바이트 단위로 보존되고 `-Revert` 가 그것을 복원한다.

`conhost` 는 클래식 `cmd.exe`, Windows PowerShell, Git CMD/Bash 콘솔 프로필 및 기타 기존 `HKCU\Console` 자식을 다룬다. 팔레트의 16색 표 전체를 루트 기본값과 기존의 모든 오버라이드 양쪽에 쓰고, 손댄 값만 복원한다. 거기서도 Consolas를 적용한다. 왜냐하면 비례 글꼴 Verdana는 두 터미널 호스트가 모두 쓰는 고정폭 셀 그리드 안에서 충돌하기 때문이다.

### 브라우저와 Tampermonkey

`browsers` 는 Chrome, Edge, Brave, Cent, Vivaldi, Opera 프로필을 설치된 위치와 당신이 가리키는 휴대용 루트 (`-PortableRoot`, 또는 `paths.json` 의 기억된 `portable` 항목) 양쪽에서 찾는다. 그 상태는 프로필 수와 Tampermonkey를 포함하는 수를 모두 보여준다. Apply는 선택한 browser-chrome 테마를 안정적인 `%LOCALAPPDATA%\Wintage\browser-theme` 폴더에 복사하고, 그 경로를 클립보드에 두고, 각 프로필을 정확히 `chrome://extensions` 와 Wintage 유저스크립트의 Install/Update 페이지로 연다. Tampermonkey가 없는 프로필에는 Chrome Web Store 페이지도 연다.

Chromium은 관리되지 않는 Windows 머신에서 오프스토어 확장의 조용한 설치를 의도적으로 금지한다. 따라서 첫 브라우저 테마 설치는 프로필마다 **Developer mode → Load unpacked** 확인이 한 번 필요하다. 복사된 경로를 고르라. 그 후 Wintage는 팔레트가 바뀌면 같은 안정 폴더를 계속 교체한다. Tampermonkey에서도 **Install/Update** 를 확인하라. 브라우저의 `Preferences`, Secure Preferences, Tampermonkey의 LevelDB 파일은 브라우저 등 뒤에서 편집되지 않는다. Tampermonkey가 없었다면 열린 스토어 탭에서 설치하고, 이미 열려 있는 `wintage.user.js` 탭을 새로고침해 Install 화면을 얻으라.

### Windows

`windows` 는 콘텐츠 주소가 있는 `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme` 를 설치하고 즉시 활성화한다. 활성 테마에서 시작해 문서화된 색상, 커서, 비주얼 스타일 섹션만 교체한다. 배경화면, 사운드, 바탕 화면 아이콘은 그대로다. 커서는 의도적으로 설치된 `___CURRENT___` 스킴으로 전환된다. 첫 활성 테마는 `Wintage.original.theme` 로 바이트 단위 저장된다. 팔레트 변경은 그 기준선을 유지하고 `-Revert` 는 그것을 다시 활성화한다. 모던 Windows 컨트롤은 서명된 Aero 비주얼 스타일에서 온다 — Wintage는 보호된 `.msstyles` 파일을 교체하는 대신 그 지원하는 다크 모드, 액센트, 클래식 시스템 색상 입력을 바꾼다. 활성과 비활성 캡션은 팔레트의 뮤트된 돌출 표면 색상을 공유한다. 밝은 하이라이트는 텍스트/선택 가장자리용으로 남겨진다. 이전의 비활성 캡션 액센트는 별도로 스냅샷되고 `-Revert` 가 정확히 복원한다. 콘텐츠 해시는 같은 팔레트가 다시 빌드될 때 Windows에 새 파일 연결 대상을 준다. 갱신된 팔레트의 재적용이 no-op으로 오인되지 않도록. 대체된 Wintage 파일은 Windows가 새 것을 활성으로 확인한 뒤 제거된다.

### OBS Studio

`obs` 는 유지 관리되는 Yami Classic 베이스 위에 OBS 30.2+ 변형을 생성하고, `%APPDATA%\obs-studio\themes` 에 설치하며, 안정 테마 ID를 `user.ini` 에 쓴다. 그래서 고른 Wintage 팔레트가 다음 실행에서 이미 선택되어 있다. Apply 또는 Revert 전에 OBS를 닫아라: OBS는 종료 시 `user.ini` 를 다시 쓴다. 첫 적용은 이전 선택과 같은 이름의 테마 양쪽을 바이트 단위로 백업한다.

### Electron 앱

`resources/app.asar` 는 `resources/app/app.asar` 로 옮겨진다 (그 `app.asar.unpacked` 형제도 함께 옮긴다 — 그 짝은 파일명으로 맺어진 것이고, 분리하면 모든 네이티브 모듈이 깨진다). 작은 `shim.cjs` 가 비워진 `resources/app` 슬롯을 차지한다. 셰임은 스타일시트를 주입한 다음 원래 아카이브를 불러온다. **어떤 애플리케이션 바이트도 다시 쓰이지 않는다**, 옮겨질 뿐이다. `-Revert` 는 그것을 그대로 되돌린다.

스타일시트는 이 앱들을 위해 작성되지 않는다 — `wintage.user.js` 에서 추출된다. 그래서 브라우저를 위해 만들어진 모든 베벨, 스크롤바, 타입 사다리 수정이, 썩을 두 번째 사본 없이 여기에도 도달한다.

미리 알아둘 가치가 있는 두 가지:

- 명백한 방법 — `resources/app` 를 아카이브 옆에 두고 Electron이 그것을 우선하기를 기대하는 것 — **동작하지 않으며 조용히 실패한다**. Electron은 `app.asar` 를 먼저 찾는다. 앱은 완벽하게 시작되고 테마는 결코 실행되지 않는다.
- 셰임은 의도적으로 `.cjs` 이며 `.js` 가 아니다. 그 `package.json` 은 앱 자신의 것에서 복사되므로 앱은 이름과 버전을 유지한다 (이름이 userData의 위치를 정한다 — 이름을 바꾸는 셰임은 앱을 빈 프로필로 옮긴다). 그 매니페스트가 `"type": "module"` 이라고 말한다면, `.js` 셰임은 첫 `require` 에서 죽는다.

### Claude 데스크톱 앱: 그 자리에서, 그리고 그것이 실제로 그리는 프레임

Claude는 위의 재배치를 쓸 수 없다. `OnlyLoadAppFromAsar` 가 퓨즈로 융합되어 켜져 있기 때문이다 — Electron은 `resources/app.asar` 만 로드하고 다른 것은 아무것도 로드하지 않으므로, `resources/app` 의 셰임은 결코 실행될 수 없다. 대신 **그 자리에서** 패치된다: 아카이브는 백업되고, 그 `package.json` 의 `main` 은 `"../wintage-shim.cjs"` 로 다시 쓰인다 (같은 바이트 길이로 패딩되어 아카이브의 모든 오프셋이 유효하게 남는다). 파일별 무결성 해시도 일치하도록 갱신된다. `-Revert` 는 백업을 복원한다.

설치기는 **무엇이든 옮기기 전에** 퓨즈를 읽고, 퓨즈가 막을 때 이유를 달아 거부한다 — `EnableEmbeddedAsarIntegrityValidation` 은 위의 재작성을 설치 시가 아니라 실행 시 실패하게 만들 것이다. 앱을 직접 확인하라:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

이 후반부는 훨씬 조용한 문제였다. Claude의 `BrowserWindow` 는 얇은 셸을 그리고, **보이는 애플리케이션 전체는 `WebContentsView`** 가 그것에 붙어 있다. 셰임은 `browser-window-created` 를 훅했기 때문에 셸에 스타일시트를 주입하고, `wintage-status.txt` 에 성공을 보고하고, 볼 수 있는 것을 아무것도 바꾸지 않았다. 이제는 `web-contents-created` 를 훅한다. 이는 창 콘텐츠, `WebContentsView`, `BrowserView`, `<webview>` 게스트, 팝업을 모두 덮는다.

### Obsidian

커뮤니티 테마가 모든 볼트의 `.obsidian/themes/` 에 쓰인다 — VS Code 대상과 똑같이 16개 팔레트 전부를 한 번에. 그래서 **Settings → Appearance** 에서 아무것도 다시 실행하지 않고 전환한다. 템플릿은 볼트에 이미 있는 손수 만든 `VintageWin95` 테마에서 도출되었고, 각 색상이 그것과 같은 토큰으로 교체되었다. `-Palette <slug>` 는 설치 시 어느 것이 활성인지 설정한다. `appearance.json` 은 먼저 백업되고, `-Revert` 는 `Wintage *` 테마만 제거하고 이전 선택을 복원한다 — 같은 볼트의 손수 만든 테마는 절대 건드리지 않는다.

### SAIPENVIEW

그 프런트엔드는 자신의 `:root` 에 이미 Wintage 토큰 이름을 선언한다. 그래서 이 패치는 **토큰 값만** 다시 쓴다 — 선택자, 글꼴, 테두리 두께, 패딩은 결코. 박스 모델에 영향을 주는 것은 아무것도 변하지 않으므로 텍스트는 움직일 수 없다. 이것은 의도적이다: 이전 접근은 브라우저 스타일시트 전체를 위에 덧붙였다. 그리고 `wintage.css` 는 임의의 웹 페이지를 위해 쓰였다 — 글꼴, 크기 사다리, 2px 테두리, 컨트롤 높이를 강제하는 범용 선택자. 이미 자기 레이아웃이 있는 앱에서는 그것이 모든 것을 움직인다.

모든 hex를 마스킹하고 백업과 diff하여 검증된다: 구조적으로 동일하고, 색상 리터럴만 다르다. `--link` 는 거기에 선언되지 않은 것으로 보고된다 (그 markdown 링크는 이것이 설정하는 `--accentTeal` 을 읽는다) — 그래서 주입되는 대신. 앱이 결코 읽지 않는 변수를 추가하는 것은 죽은 무게일 뿐이다.

### MPC-HC (K-Lite)

네이티브 Win32, 스타일시트도 주입 지점도 없고, 다크 테마의 색상은 프로그램에 컴파일되어 있다 — 레지스트리 값은 그것들을 노출하지 않는다. 그래서 이 대상은 **팔레트를 담을 수 없다**. 그것이 하는 일: 다크 테마를 켜고 UI.md 타이포그래피 규칙을 OSD에 적용한다. OSD는 MPC-HC가 사용자가 제어하게 두는 유일한 표면이다. 이전 설정은 먼저 `desktop/backup/mpc-hc-settings.reg` 로 내보내진다.

적용 전에 MPC-HC를 닫아라: 종료 시 설정을 다시 쓴다.

## 다시 빌드

`desktop/out/` 아래의 모든 것은 `themes/*.json` 에서 생성된다. git에 추적되지 않으므로 (T-160) 새 클론은 설치 전에 한 번 빌드해야 한다:

```powershell
node ..\tools\build-desktop.js          # 모든 대상 다시 빌드
node ..\tools\build-desktop.js --check  # 무엇이든 낡았으면 exit 1
```

`release.ps1` 은 빌드와 모든 게이트를 실행하므로, 릴리스가 팔레트에서 벗어난 출력을 출시할 수 없다.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
