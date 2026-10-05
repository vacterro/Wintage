# デスクトップアプリ向け Wintage

ユーザースクリプトはウェブをテーマ化する。これは、同じパレットからその周りのプログラムをテーマ化する。ブラウザとアプリが「ダークゴールデン」の意味で食い違わなくなるように。

ここでのすべての決定の背後には1つのルールがある: **アプリケーションは自分で更新される。そして更新は何かを静かに壊してはならない。** 対象が自分のプロファイルの中に置き場所を持つなら、テーマはそこに置かれ、更新を乗り越える。置き場所がなければ、インストーラーは再実行されるように書かれている — 永続したかのように装う代わりに、そう明言する。

## GUI

リポジトリルートの **`Wintage Installer.vbs`** をダブルクリックすると、コンソールウィンドウなしで開く。診断用に直接実行するなら:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

カラーチップ付きのテーマ一覧、このマシンで見つかった対象、ライブのWin95プレビュー、そして編集可能なスウォッチとしての21個すべてのカラートークン。任意のスウォッチを編集すると、出荷済みテーマをあなたの裏で変えるのではなく、パレットを **Custom** にフォークする。右のパネルはテキストを担う3トークンのライブWCAGコントラストを表示する — そこでFAILするパレットはどうせビルドゲートが拒否するので、Applyの後よりも前で見る方が良い。

対象はキーボードで到達可能な2つのリストに分かれている: **MY APPS** にはポータブル/ソースツリーのCodeNomad, WorkBuddyツールが入り、**POPULAR APPS** にはWindows、OBS、ターミナル、エディタ、その他のインストール済みソフトウェアが入る。ALL/NONEとApply/Revertは、グループ分けを変えずに両方のリストにまたがって動作する。

ウィンドウは、これからインストールしようとするパレットをまとう。それが可能な限り最速のプレビューであり、ツールを正直に保つ: このウィンドウを読めなくするパレットは、目に見えて読めない。

Applyは `install.ps1` にシェルアウトする。テーマをインストールするコードパスはちょうど1つしかないので、GUIがコマンドラインから逸脱することはない。

## コマンドライン

```powershell
.\desktop\install.ps1                                  # 何があるか、何がテーマ化されているか、どのパレットか
.\desktop\install.ps1 -Target freebuff -Palette klite  # 1つのアプリ、1つのパレット
.\desktop\install.ps1 -Target all -Palette goldendefault # すべて
.\desktop\install.ps1 -Target all -WhatIf              # 何が変わるかを言うだけ、何も触らない
.\desktop\install.ps1 -Target freebuff -Revert         # 1つを元に戻す
```

`-Palette` の既定値は `goldendefault` (**Golden Default**)。GUIも同じパレットで開き、利用可能なすべての対象をチェックする。すでにテーマ化されているアプリの再描画は実行中でも動作する。初回インストールはアーカイブが使用中のため動作しない。

## 各対象が実際にテーマ化できるもの

| 対象 | 仕組み | アプリの更新を乗り越える |
|---|---|---|
| `windows` | ユーザー `.theme`: ダークシステム/アプリモード、アクセントとクラシックカラーロール | yes — ローカルWindows Themesフォルダにインストールされる |
| `browsers` | インストール済み+ポータブルのChromiumプロファイルを検出し、選択したchromeテーマをステージングし、ブラウザ所有のTampermonkey/テーマ確認ページを開く | yes — プロファイルごとに1回の **Load unpacked** の後 |
| `terminal` | Windows Terminalスキーム+全プロファイル既定値、Consolas 12エイリアス | yes — 設定はプロファイルにある |
| `conhost` | `HKCU\Console` 既定値+既存のすべてのcmd/PowerShellプロファイル | yes — 触れた値の正確なスナップショット |
| `obs` | OBS 30.2+ `.ovt` バリアント+アクティブな `user.ini` テーマID | yes — プロファイルにある |
| `qbittorrent` | 未パッケージの Qt UI テーマ（`config.json` + `stylesheet.qss`）+ `qBittorrent.ini` の 2 つのテーマキー | yes — プロファイルにある |
| `antigravity`, `vscode` | `~/.antigravity/extensions` / `~/.vscode/extensions` のカラーテーマ拡張 | **yes** — プロファイルにある |
| `freebuff`, `antigravity-app`, `codenomad` | Electronシム、下記参照 | no — インストーラーを再実行 |
| `claude` | Electronシム、その場でパッチ — 下記参照 | no — 更新が新しい `app-<version>` フォルダを作る |
| `mpchc` | レジストリ、ダークテーマ+OSDタイポグラフィのみ | no — MPC-HCは終了時に設定を書き直す |
| `obsidian` | ボールトごとのコミュニティテーマ、全パレットを一度にインストール | **yes** — ボールトにある |
| `discord` | CSSをBetterDiscord自身のテーマフォルダにドロップ | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini` の `[Colors]` キー。既存の最近使ったファイルフィルタはパレットのリンク色を使う | yes — あなたのini |

### FreeBuff 広告の除去

FreeBuff (AIアシスタントのデスクトップアプリ) は独自の広告ネットワークを同梱している: レンダラーバンドル (`resources/orchestrator/ui/assets/index-*.js`) は `sponsored-ad` カードとスレッドバナーを描画し、オーケストレーター (`resources/orchestrator/orchestrator.js`) はリモートの広告オークションを呼ぶ `/api/ad/slot|impression|click` ルートを公開している。シムはアプリをテーマ化するだけで、それらのファイルには触れない。

`desktop/patch-freebuff-ads.js` は広告をバイトレベルで切り取る:

- レンダラー: 広告カード/バナーの呼び出し箇所は `null` になり、`adSlot` / `adImpression` / `adClick` APIクライアントメソッドはno-opになる — 何も描画されず、`/api/ad/*` リクエストがレンダラーから出ることはない;
- オーケストレーター: 3つの `/api/ad/*` ルートすべてが広告ネットワークを呼ぶのをやめ、ライブターンのインライン広告リクエスト (`maybeRequestAd`) は短絡される。

バンドルのファイル名にはビルドハッシュが埋め込まれているため、パッチはバージョンロックされたペイロードを同梱する代わりに `index.html` から現在のバンドルを発見する — それが更新を乗り越える理由だ。オリジナルはインストールディレクトリ内の `_orig-backup-<timestamp>/` にバックアップされる。`--revert` は最新のものを復元する。

**将来のバージョンは、互いに独立した2つの層で処理される:**

1. **正規表現フォールバック付きのバイトパッチ。** すべての対象には、現在のビルドの正確な文字列と、ミニファイアが改名できないものにアンカーされた正規表現フォールバックの両方がある — `/api/ad/*` パスリテラル、`case"ad":` プロトコル判別子、`sponsored-ad` クラス、`variant:"banner"` / `variant:"card"` 配置。オーケストレーターはミニファイされていない (`maybeRequestAd` や `app.ads.slotAd` のような読みやすい名前) ため、正確な文字列は長く保たれる。レンダラーバンドルはミニファイされているため、次のビルドが識別子を改名した瞬間に正規表現フォールバックが引き継ぐ。
2. **シムレベルのブロック (`targets/electron/shim.cjs`)。** バンドルから完全に独立している: ページ内で `/api/ad/` URLへの任意のfetch/XHRは拒否され、`sponsored-ad` を含むクラスの任意の要素は現れた瞬間に隠される。このスクリプトがまだ学習していない真新しいバンドルでさえ、広告を表面化させることはできない。

```powershell
node .\desktop\patch-freebuff-ads.js           # パッチ (最初にバックアップ)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # パッチ+カスタム完了サウンド (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # このビルドはどの広告マーカーを持つ?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

これは `install.ps1 -Target freebuff` の一部として自動的に実行され、FreeBuffを更新するたびに再実行する必要がある (更新はストックファイルを復元する)。ビルドの形が変わった場合、スクリプトはもはや一致しなくなった対象の名前を挙げる — `--scan` を実行して新しいビルドがまだ何を持っているかを確認し、そこにある文字列を更新する。

**FreeBuff 完了サウンド。** レンダラーはターンが終わると `chime-<hash>.mp3` を再生する。パッチはバンドルと同じ方法でそれを見つける (名前にはビルドハッシュが埋め込まれている) ので、`--sound <file>` は独自のオーディオ (wav/mp3/ogg/flac/m4a/aac) をその上にインストールし、ストックファイルを `chime-*.mp3.bak` として保持する。`--revert` はそれを復元する。`--verify` はどちらが稼働中かを報告する。

### FreeBuff サウンドボタン (GUI)

`WintageInstaller.ps1` には、APPLY / REVERTスタックの下に小さな **FB SOUND** ボタンがある。それは*設定値*を保存するだけ。`install.ps1 -Target freebuff` は同じファイルを読み、それを `--sound` としてパッチに渡す。広告とサウンドが一度の実行で適用される:

- **左クリック** — オーディオファイルを選び (OpenFileDialog、wav/mp3/ogg/flac/m4a/aac)、即座に再生を聞く: PCM WAVはSystem.Media.SoundPlayer、その他の形式はWPF MediaPlayer (Media Foundation、非同期なのでウィンドウがフリーズすることはない)。選択は `%APPDATA%\Wintage\freebuff-sound.txt` に記憶される (マシン単位、gitチェックアウトの外、記憶されたソースツリーフォルダとまったく同じ)。
- **右クリック** — FreeBuffのストックチャイムに設定を戻す (再生中のプレビューも停止する)。
- **COPY** — 選んだオーディオをリポジトリ自身にコピーし (`sounds\freebuff.<ext>`、ソースの拡張子を保持)、設定をそのコピーに向け直す。元ファイルが削除・移動されてもサウンドは生き残る。カスタムサウンドが設定されている間だけ有効。コピーし直すとリポジトリのコピーを上書きするだけ。`sounds/` フォルダは普通のgit追跡可能なコンテンツなので、コミットすればサウンドは再クローンにも耐える。

認識されたオーディオコンテナだけがプレビューされる — まずヘッダーがスニッフィングされるので、オーディオでない選択は何も再生しない代わりに告知される。

カスタムサウンドが設定されている間、ボタンは `ON` と表示し、ホバーするとパスを示す。その後 `freebuff` 対象を適用する (FreeBuffにチェックしてAPPLY、またはターミナルから `install.ps1 -Target freebuff` を実行) と効果が出る。

### ターミナル

`terminal` は、検出されたすべての安定版・Preview・未パッケージのWindows Terminal設定ファイルに `Wintage` カラースキームを書き込み、`profiles.defaults` を通じてそれを選択する。コンソール対応のConsolas 12とエイリアステキスト付き。元のファイルはその隣にバイト単位で保持され、`-Revert` がそれを復元する。

`conhost` はクラシックな `cmd.exe`、Windows PowerShell、Git CMD/Bashコンソールプロファイル、その他の既存の `HKCU\Console` 子をカバーする。パレットの16色テーブル全体をルート既定値と既存のすべてのオーバーライドの両方に書き込み、触れた値だけを復元する。そこでもConsolasを適用する。なぜなら、プロポーショナルなVerdanaは両方のターミナルホストが使う固定幅セルグリッドの中で衝突するからだ。

### ブラウザと Tampermonkey

`browsers` はChrome、Edge、Brave、Cent、Vivaldi、Operaプロファイルを、インストール済みの場所と、あなたが指すポータブルルート (`-PortableRoot`、または `paths.json` の記憶された `portable` エントリ) の両方から見つける。そのステータスはプロファイル数とTampermonkeyを含む数の両方を表示する。Applyは選択したbrowser-chromeテーマを安定版の `%LOCALAPPDATA%\Wintage\browser-theme` フォルダにコピーし、そのパスをクリップボードに置き、各プロファイルを正確に `chrome://extensions` とWintageユーザースクリプトのInstall/Updateページで開く。TampermonkeyのないプロファイルにはChrome Web Storeのページも開く。

Chromiumは、管理されていないWindowsマシンでのオフストア拡張のサイレントインストールを意図的に禁止している。したがって初回のブラウザテーマインストールには、プロファイルごとに1回の **Developer mode → Load unpacked** 確認が必要。コピーしたパスを選ぶ。その後Wintageは、パレットが変わると同じ安定フォルダを置き換え続ける。Tampermonkeyでも **Install/Update** を確認する。ブラウザの `Preferences`、Secure Preferences、TampermonkeyのLevelDBファイルは、ブラウザの裏で編集されることはない。Tampermonkeyが存在しなかった場合は、開かれたストアタブからインストールし、すでに開いている `wintage.user.js` タブをリフレッシュしてInstall画面を得る。

### Windows

`windows` は、コンテンツアドレス付きの `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme` をインストールし、すぐにアクティブ化する。アクティブなテーマから始めて、文書化された色・カーソル・ビジュアルスタイルのセクションだけを置き換える。壁紙、サウンド、デスクトップアイコンは変更されない。カーソルは意図的に、インストールされた `___CURRENT___` スキームに切り替わる。最初のアクティブテーマは `Wintage.original.theme` としてバイト単位で保存される。パレット変更はそのベースラインを保ち、`-Revert` はそれを再びアクティブ化する。モダンなWindowsコントロールは、署名済みのAeroビジュアルスタイルから来る — Wintageは、保護された `.msstyles` ファイルを置き換える代わりに、そのサポートされたダークモード、アクセント、クラシックシステムカラー入力だけを変更する。アクティブと非アクティブのキャプションは、パレットのミュートされた浮き上げサーフェスの色を共有する。明るいハイライトはテキスト/選択エッジのために予約されたまま。以前の非アクティブキャプションアクセントは別途スナップショットされ、`-Revert` が正確に復元する。コンテンツハッシュにより、同じパレットが再構築されたときWindowsは新しいファイル関連付けターゲットを得る。更新されたパレットの再適用がno-opと誤解されないように。置き換えられたWintageファイルは、Windowsが新しいものをアクティブと確認した後に削除される。

### OBS Studio

`obs` は、維持されているYami Classicベースの上にOBS 30.2+バリアントを生成し、`%APPDATA%\obs-studio\themes` にインストールし、安定テーマIDを `user.ini` に書き込む。選択したWintageパレットが次回起動時にすでに選択されているように。ApplyまたはRevertの前にOBSを閉じること: OBSは終了時に `user.ini` を書き直す。初回の適用は、以前の選択と同名のテーマの両方をバイト単位でバックアップする。

### qBittorrent

`qbittorrent` は**展開済み**の Qt UI テーマを `%APPDATA%\qBittorrent\themes\wintage` に書き込みます — `config.json`（`Palette.*` の役割に加え、qBittorrent 自身の文脈色：転送リストの状態、ログの重要度）と、その隣の `stylesheet.qss`（2px の面取り、直角の角、そしてパレットでは表現できない Verdana）です — その後 `General\CustomUIThemePath` をその `config.json` に向け、`General\UseCustomUITheme=true` を設定します。
あえて `.qbtheme` バンドルではなく展開形式にしています。`.qbtheme` は Qt Resource Collection ファイルで、生成するには同じメジャーバージョンの `rcc` バイナリがマシンに必要となり、テキストファイル 2 つのためにコンパイラ依存を持ち込むことになります。qBittorrent はフォルダ形式をネイティブに読み込みます（`FolderThemeSource`）。
Apply や Revert の前に qBittorrent を終了してください。終了時に `qBittorrent.ini` 全体を書き直すため、起動中に行った編集は終了時に破棄されます — このターゲットはその状態での実行を拒否し、次回の終了で消える「成功」を報告したりはしません。`-Revert` は 2 つの INI キーを Wintage 以前の正確な値に戻し（存在しなかった場合は削除し）、同名のテーマフォルダをバイト単位で復元します。Apply 後に加えた無関係な `qBittorrent.ini` の編集は残ります。
到達不可：ツールバーとトレイのアイコンは qBittorrent 自身のコンパイル済みリソースバンドル由来なので、標準の色のままです。

### フォント: 名前を持つだけで、インストールはしない

UI.md の第一法則は Verdana を**アンチエイリアシング無し**で要求する。Qt のスタイルシートにそのプロパティは無く、MPC-HC の `OSDFont` は単なる GDI のフォント名だ——つまり唯一のレバーはフォントそのものにある。リポジトリルートにある `Verdana_m1.ttf` は Verdana の複製で、3〜30 ppem の 1bpp ビットマップ打面がレンダリング済みで、レンダラーは輪郭を滑らかにするよりこちらを選ぶ。
`qbittorrent` と `obs` のスタイルシートは `Verdana_m1, Verdana` と名指しし、`mpchc` はそのうち機械が実際に解決した方を名指しする。**インストーラはフォントをインストールも削除もしない**。これは未完成ではなく、意図的な設計だ:
フォントファミリーは（ファミリー, スタイル）で解決される。Regular + Bold + Italic を登録すればあらゆる利用者が正しく解決するが、**一つ**のメンバーを解除すると、そのファミリーを要求するすべての利用者は残るメンバーへ向け直される。`HKLM\...\FontSubstitutes` を通じて `MS Shell Dlg 2`（Windows のダイアログフォント）をそのファミリーにエイリアスしている機械では、Regular を外すと**デスクトップ全体がイタリック**になり、すでに DWM がキャッシュしたウィンドウタイトルまで巻き込んで、戻すにはログオフが必要だ。参照カウントのいかなる工夫も直らない。被害範囲は機械全体で、テーマのインストーラが踏み込むところではない。
したがってフォントは一度きりの明示的なユーザー操作である。`Verdana_m1.ttf` を右クリック → **インストール**（ユーザーごと、管理者権限は不要）、その後ターゲットを再適用する。フォントが無い場合、ターゲットは一度だけその旨を述べ、修正名を挙げ、標準の Verdana へフォールバックする——アンチエイリアシングは付くが、あなたの背後で機械に何もしない。

### Electron アプリ

`resources/app.asar` は `resources/app/app.asar` に移動される (その `app.asar.unpacked` の兄弟も一緒に移動する — そのペアリングはファイル名によるもので、分離するとすべてのネイティブモジュールが壊れる)。小さな `shim.cjs` が空いた `resources/app` スロットを占める。シムはスタイルシートを注入してから、元のアーカイブを読み込む。**アプリケーションのバイトは書き換えられない**。移動されるだけ。`-Revert` はそれをそのまま戻す。

スタイルシートはこれらのアプリ用に書かれるのではなく、`wintage.user.js` から抽出される。ブラウザのために作られたすべてのベベル、スクロールバー、タイプラダー修正が、腐るためのセカンドコピーなしに、ここにも届く。

前もって知っておく価値のある2つの注意:

- 明白な方法 — `resources/app` をアーカイブの隣に置き、Electronがそれを優先することに頼る — **機能せず、静かに失敗する**。Electronは最初に `app.asar` を検索する。アプリは完璧に起動し、テーマは決して実行されない。
- シムは意図的に `.cjs` であり `.js` ではない。その `package.json` はアプリ自身のものからコピーされるので、アプリは名前とバージョンを保つ (名前がuserDataの場所を決める — 改名するシムはアプリを空のプロファイルに移してしまう)。そのマニフェストが `"type": "module"` と言う場合、`.js` シムは最初の `require` で死ぬ。

### Claude のデスクトップアプリ: その場でのパッチと、実際に描画するフレーム

Claudeは上記の再配置を使えない。`OnlyLoadAppFromAsar` がフューズで溶接されオンになっているためだ — Electronは `resources/app.asar` だけを読み込み、他は何も読み込まない。`resources/app` のシムは決して実行できない。代わりに**その場で**パッチされる: アーカイブはバックアップされ、その `package.json` の `main` は `"../wintage-shim.cjs"` に書き換えられる (同じバイト長にパディングされるので、アーカイブ内のすべてのオフセットが有効なまま)。ファイルごとの整合性ハッシュも一致するよう更新される。`-Revert` はバックアップを復元する。

インストーラーは**何かを動かす前に**フューズを読み、それらがブロックするときは理由付きで拒否する — `EnableEmbeddedAsarIntegrityValidation` は、上記の書き換えをインストール時ではなく起動時に失敗させるだろう。アプリを自分で確認する:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

この後半は、ずっと静かな問題だった。Claudeの `BrowserWindow` は薄いシェルを描画し、**可視のアプリケーション全体は `WebContentsView`** がそれに取り付けられている。シムは `browser-window-created` をフックしていたので、スタイルシートをシェルに注入し、`wintage-status.txt` に成功を報告し、見えるものを何も変えなかった。今は `web-contents-created` をフックする。これはウィンドウコンテンツ、`WebContentsView`、`BrowserView`、`<webview>` ゲスト、ポップアップを同様にカバーする。

### Obsidian

コミュニティテーマがすべてのボールトの `.obsidian/themes/` に書かれる — VS Code対象とまったく同じように、16個のパレットすべてを一度に。**Settings → Appearance** で何も再実行せずに切り替えられる。テンプレートはボールトにすでにある手作りの `VintageWin95` テーマから導出され、各色がそれと等しいトークンに置き換えられた。`-Palette <slug>` はインストール時にどれをアクティブにするかを設定する。`appearance.json` は最初にバックアップされ、`-Revert` は `Wintage *` テーマだけを削除して以前の選択を復元する — 同じボールトの手作りテーマは決して触れられない。


### MPC-HC (K-Lite)

ネイティブWin32、スタイルシートも注入ポイントもなく、ダークテーマの色はプログラムにコンパイルされている — レジストリ値はそれらを公開しない。したがってこの対象は**パレットを運べない**。それが行うのは: ダークテーマをオンにし、UI.mdのタイポグラフィルールをOSDに適用すること。OSDはMPC-HCがユーザーに制御させる唯一の面だ。以前の設定は最初に `desktop/backup/mpc-hc-settings.reg` にエクスポートされる。

適用する前にMPC-HCを閉じること: 終了時に設定を書き直す。

## 再構築

`desktop/out/` の下のすべては `themes/*.json` から生成される。gitで追跡されない (T-160) ので、新しいクローンはインストール前に一度ビルドする必要がある:

```powershell
node ..\tools\build-desktop.js          # すべての対象を再ビルド
node ..\tools\build-desktop.js --check  # 何か古ければexit 1
```

`release.ps1` はビルドとすべてのゲートを実行するので、リリースがパレットから逸脱した出力を出荷することはない。

<!-- T-311 target/section coverage supplement -->
## 対象とセクションのカバレッジ

このセクションは現在の英語版READMEのProcess Explorer, Notepad++, Cinema 4D, ターミナルフォントのカバレッジを反映しており, このロケーションが黙って古びないようにしている。コードリテラル (対象ID, レジストリパス, ファイル名) は意図的に言語非依存である。周囲の散文は日本語に翻訳済み。

### 各対象が実際にテーマ化できるもの (追加された対象)

| 対象 | 仕組み | アプリの更新を乗り越える |
|---|---|---|
| `notepadplusplus` | テーマXML + ユーザーのNotepad++ `themes` フォルダへのエイリアス | はい — あなたのプロファイル内にあります |
| `cinema4d` | ユーザーのCinema 4D `schemes` フォルダに配置される配色スキーム | はい — あなたのプロファイル内にあります |
| `processexplorer` | `HKCU\Software\Sysinternals\Process Explorer`: 行ハイライトの色とグラフ背景, 下述参照 | いいえ — Process Explorerは終了時に設定を書き直すため, 閉じて再実行してください |

### Process Explorer (Sysinternals)

Process Explorerは色を `HKCU\Software\Sysinternals\Process Explorer` に保持し, 終了時にそのキーを書き直す。そのため対象は **`procexp`, `procexp64`, `procexp64a` のいずれかが実行中の間は拒否する** — 閉じてから再実行すること。設定可能な色カテゴリをテーマ化する:

- **到達可能**: プロセスの行ハイライト色 (`ColorOwn`, `ColorServices`, `ColorRelocatedDlls`, `ColorImmersive`, `ColorPacked`, `ColorJobs`, `ColorNet`, `ColorProtected`, `ColorNewProc`, `ColorDelProc`, `ColorSuspend`) のライトモード版と `*Dark` 版の両方, さらにグラフ背景 (`ColorGraphBk`, `ColorGraphBkDark`) — 合計24値。各バリアントは有効なパレットの対応する極方向へ混合される (ライトモードの塗りには明るい調, `*Dark` には暗い調)。そのため行の塗りはほぼ白へ飛び散らず, パレット自身の色调を保つ;
- **到達不能**: タイトルバー, メニューバー, ツールバー, リストビューの背景と文字色, およびグラフの線の色 — これらは `procexp.exe` にコンパイルされ, どの設定値からも公開されない。対象は実際に所有する行ハイライトとグラフ背景だけをテーマ化し, それ以上は主張しない。

Applyが変更できるすべての値は変更前にスナップショットとして取り込まれる (初回接触時の復元先 `%APPDATA%\Wintage\recovery\processexplorer\`) し, `-Revert` が正確に復元する。各値が元々存在しなかったかどうか, マーカーが存在が空だったかどうかを含めて。標準のSysinternalsディレクトリ外にあるポータブルフォルダは `paths.json` の正規キー `processexplorer` で記憶される (CLI引数 `-ProcessExplorerPath`; GUIでも選択できる)。

### ターミナルフォント (`fonts/terminal/`)

両方のターミナル対象は `%APPDATA%\Wintage\terminal-font.json` にある単一の正規タイポグラフィ設定を読む (`schema`, `fontSlug`, `family`, `size`, `renderingMode`)。ファイルが無い場合, 対象は同梱の既定値 (Windows向けのTerminus (TTF), 12 pt, 別名付き) を維持するため, 既存のマシンは変化しない。破損した設定はフェイルクローズドで処理される: 上書きは一切行われず, 対象は拒否する。

`fonts/terminal/catalog.json` は唯一のフォントカタログである: 同梱のオープンソース等幅フォント20ファミリーに加え, Wintageが名指しするが決して同梱しない2つのシステム書体 (Windows向けのTerminus (TTF), Consolas)。同梱の各エントリは上流のソース, 固定リビジョン, ライセンスID, ライセンスファイル, SHA-256を持つ。正確なファイルは `fonts/terminal/files/` に, ライセンス本文は `licenses/` に置かれている。実行時のWintageは完全オフラインで動作し, フォントを一切ダウンロードしない。

`tools/sync-terminal-fonts.ps1` はメンテナ専用ダウンローダである。`fonts/terminal/sources.json` (ファミリーごとに不変の成果物1つ) を読み, すべてのSHA-256を検証し, 不一致があれば拒否する。`-VerifyOnly` (既定) はネットワークなしでディスク上のツリーを検査し, `-Fetch -Write` は再収録する。ダウンロードしたフォントのバイトは信頼できないバイナリアセットとして扱う — ハッシュして書き込むだけで, 実行はしない。記録された置き換えが1つある: **Fantasque Sans Mono** が Liberation Mono を置き換える。Liberation Mono は固定されたバイナリリリースを公開していない (ソース `.sfd` のみ) ためである。

インストーラーは **フォントを閲覧するのみであり, インストールはしない。** TERMINAL FONTS タブは同梱の書体をプロセス固有の `PrivateFontCollection` に読み込み, ライブプレビューを表示する。これはシステムフォントの登録を **一切** 行わない。フォント, サイズ (7–24 pt), レンダリングモード (aliased/grayscale/cleartype) の選択はプレビューと設定だけを変える。フォントのインストールは明示的な **INSTALL SELECTED** 操作であり, Windows 独自のフォントインストーラーを開く。Windows の確認のあと, ユーザーは Refresh で再検査する。実際のターミナル変更が 일어나るのは, 明示的な **APPLY TERMINAL / APPLY CONHOST / APPLY BOTH** のあとだけである。

Windows Terminal には選択したインストール済みファミリーが選択したサイズで適用され, レンダリングモードは `profiles.defaults.antialiasingMode` に対応する。古典的な conhost はより厳しい。固定のセルグリッド上に描画するため, 選択した書体は Windows が解決できない限りレジストリ変更の前に拒否される (既定の書体と Consolas へのフォールバックは対象外)。Health と Reapply は設定済みの書体, サイズ, アンチエイリアシングを設定と突き合わせて検証するため, Apply のあとに設定を変更すると「健全」ではなくずれとして報告される。ターミナルの色のライフサイクルは手つかずのまま: Revert は Wintage 以前の所有値を正確に復元し, マシンからフォントを削除することはない。
<!-- source-digest: desktop/README.md sha256:15c96dac8494ab84 -->
