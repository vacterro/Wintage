# Wintage masaüstü uygulamaları için

Userscript web'i temalar. Bu da etrafındaki programları aynı paletlerden temalar,
böylece tarayıcı ile uygulamalar "koyu altın"ın ne demek olduğu konusunda
tartışmayı bırakır.

Buradaki her kararın arkasında tek bir kural var: **uygulamalar kendini
günceller ve bir güncelleme sessizce bir şeyi bozmamalı.** Bir hedefin kendi
profilinizde bir yeri varsa, tema oraya gider ve güncellemelerden sağ çıkar.
Yoksa, yükleyici yeniden çalıştırılmak üzere yazılır — ve kalıcı olduğunu iddia
etmek yerine bunu söyler.

## Arayüz

Konsol penceresi olmadan açmak için repo kökündeki **`Wintage Installer.vbs`**
dosyasına çift tıklayın veya tanılama için bunu doğrudan çalıştırın:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Renk çipleriyle tema listesi, bu makinede bulunan hedefler, canlı bir Win95
önizlemesi ve düzenlenebilir renk örnekleri olarak yirmi bir renk belirteci.
Herhangi bir örneği düzenlemek paleti **Custom** olarak çatallar; size ait bir
temayı arkanızdan değiştirmez. Sağdaki panel, metin taşıyan üç belirteç için
canlı WCAG kontrastını gösterir — orada FAIL olan bir palet zaten derleme
kapısı tarafından reddedilir, o yüzden Apply'dan önce görmek sonradan
görmekten iyidir.

Hedefler klavyeyle erişilebilen iki listeye bölünmüştür: **MY APPS** taşınabilir/
kaynak ağacı CodeNomad, SAIPENVIEW, SmartVac ve WildRift araçlarını içerir;
**POPULAR APPS** Windows, OBS, terminaller, editörler ve diğer kurulu yazılımları
içerir. ALL/NONE ve Apply/Revert, gruplamayı değiştirmeden iki listede de çalışır.

Pencere, kurulmak üzere olan paleti giyer. Bu mevcut en hızlı önizlemedir ve aracı
dürüst tutar: bu pencereyi okunmaz yapan bir palet görünür şekilde okunmazdır.

Apply, `install.ps1` dosyasına dışarı açılır (shell out). Bir temayı kuran tam
olarak tek bir kod yolu vardır, bu yüzden arayüz komut satırından sapamaz.

## Komut satırı

```powershell
.\desktop\install.ps1                                  # burada ne var, ne temalı, hangi paletle
.\desktop\install.ps1 -Target freebuff -Palette klite  # bir uygulama, bir palet
.\desktop\install.ps1 -Target all -Palette goldendefault # her şey
.\desktop\install.ps1 -Target all -WhatIf              # neyi değiştireceğini söyle, hiçbir şeye dokunma
.\desktop\install.ps1 -Target freebuff -Revert         # bir tanesini geri al
```

`-Palette` varsayılan olarak `goldendefault` (**Golden Default**) olur. Arayüz
aynı paletle açılır ve mevcut her hedefi kontrol eder. Zaten temalı bir uygulamayı
yeniden boyamak çalışırken mümkündür; ilk kurulum değildir, çünkü arşiv kullanımda.

## Her hedef aslında nasıl temalanır

| target | mechanism | survives an app update |
|---|---|---|
| `windows` | kullanıcı `.theme`: koyu sistem/uygulama modu, vurgu ve klasik renk rolleri | evet — yerel Windows Themes klasörünüze kurulur |
| `browsers` | kurulu + taşınabilir Chromium profillerini tespit eder, seçilen chrome temasını hazırlar ve tarayıcıya ait Tampermonkey/tema onay sayfalarını açar | her profil için bir kez **Load unpacked** sonrası evet |
| `terminal` | Windows Terminal şeması + tüm profiller için varsayılanlar, Consolas 12 aliased | evet — ayarlar profilinizde |
| `conhost` | `HKCU\Console` varsayılanları + mevcut her cmd/PowerShell profili | evet — dokunulan değerlerin tam anlık görüntüsü |
| `obs` | OBS 30.2+ `.ovt` varyantı + aktif `user.ini` tema kimliği | evet — profilinizde yaşar |
| `antigravity`, `vscode` | `~/.antigravity/extensions` / `~/.vscode/extensions` içinde renk teması eklentisi | **evet** — profilinizde yaşar |
| `freebuff`, `antigravity-app`, `codenomad` | Electron shim, aşağıya bakın | hayır — yükleyiciyi yeniden çalıştırın |
| `claude` | Electron shim, yerinde yamalanır — aşağıya bakın | hayır — bir güncelleme yeni bir `app-<version>` klasörü yapar |
| `mpchc` | kayıt defteri, yalnızca koyu tema + OSD tipografisi | hayır — MPC-HC çıkışta ayarlarını yeniden yazar |
| `obsidian` | kasa başına topluluk teması, tüm paletler aynı anda kurulur | **evet** — kasabınızda yaşar |
| `saipenview` | `style.css` içindeki kendi `:root` belirteç değerlerini yeniden yazar | hayır — bir kaynak dosya; pull sonrası yeniden çalıştırın |
| `discord` | CSS, BetterDiscord'un kendi tema klasörüne bırakılır | evet |
| `totalcmd`, `totalcmd2` | `wincmd.ini` `[Colors]` anahtarları; mevcut son dosya filtreleri palet bağlantı rengini kullanır | evet — sizin ini'niz |
| `smartvac`, `wildrift` | belirteç tablosu uygulamanın kendi kaynağında yeniden yazılır | hayır — bir kaynak dosya; pull sonrası yeniden çalıştırın |

### FreeBuff reklam kaldırma

FreeBuff (AI asistan masaüstü uygulaması) kendi reklam ağını getirir: renderer
paketi (`resources/orchestrator/ui/assets/index-*.js`) bir `sponsored-ad` kartı ve
bir konu başlığı banner'ı çizer ve orchestrator
(`resources/orchestrator/orchestrator.js`) uzak reklam müzayedesini çağıran
`/api/ad/slot|impression|click` rotalarını sunar. Shim yalnızca uygulamayı
temalar; o dosyalara dokunmaz.

`desktop/patch-freebuff-ads.js` reklamları bayt düzeyinde keser:

- renderer: reklam kartı/banner çağrı noktaları `null` olur ve `adSlot` /
  `adImpression` / `adClick` API istemci yöntemleri no-op olur — hiçbir şey
  çizilmez ve renderer'dan hiçbir `/api/ad/*` isteği çıkmaz;
- orchestrator: üç `/api/ad/*` rotası da reklam ağını çağırmayı bırakır ve canlı
  tur içi reklam isteği (`maybeRequestAd`) kısa devre edilir.

Paket dosya adı bir derleme hash'i gömer, bu yüzden yama sürüm kilitli bir yük
göndermek yerine güncel paketi `index.html` üzerinden keşfeder — onu güncellemelerden
kurtaran şey budur. Orijinaller, kurulum dizinindeki `_orig-backup-<timestamp>/`
klasörüne yedeklenir; `--revert` en yenisini geri yükler.

**Gelecek sürümler iki bağımsız katmanda ele alınır:**

1. **Regex geri dönüşlü bayt yaması.** Her hedefin güncel derleme için tam bir
   dizesi *ve* bir minifier'ın yeniden adlandıramayacağı şeylere dayalı bir
   düzenli ifade geri dönüşü vardır — `/api/ad/*` yol değişmezleri, `case"ad":`
   protokol ayırt edicisi, `sponsored-ad` sınıfı ve `variant:"banner"` /
   `variant:"card"` yerleşimleri. Orchestrator minified değildir (okunabilir
   adlar `maybeRequestAd` ve `app.ads.slotAd` gibi), bu yüzden tam dizeleri uzun
   süre dayanır; renderer paketi minified'dır, bu yüzden sonraki derleme
   tanımlayıcılarını yeniden adlandırdığı anda regex geri dönüşleri devreye girer.
2. **Shim düzeyi engel (`targets/electron/shim.cjs`).** Paketten tamamen
   bağımsızdır: `/api/ad/` URL'sine herhangi bir fetch/XHR sayfa içinde reddedilir
   ve sınıfında `sponsored-ad` içeren herhangi bir öğe ortaya çıktığı anda
   gizlenir. Bu betiğin henüz öğrenmediği yepyeni bir paket bile bir reklam
   gösteremez.

```powershell
node .\desktop\patch-freebuff-ads.js           # yama (önce yedekler)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # yama + özel tamamlanma sesi (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # BU derleme hangi reklam işaretlerini taşıyor?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

`install.ps1 -Target freebuff` komutunun bir parçası olarak otomatik çalışır ve
her FreeBuff güncellemesinden sonra yeniden çalıştırılmalıdır (güncellemeler
stok dosyaları geri getirir). Bir derleme şekil değiştirirse, betik artık
eşleşmeyen hedefi adlandırır — yeni derlemenin hâlâ ne taşıdığını görmek için
`--scan` çalıştırın ve oradaki dizeleri tazeleyin.

**FreeBuff tamamlanma sesi.** Renderer, bir tur bittiğinde `chime-<hash>.mp3`
çalar. Yama onu paketi bulduğu şekilde bulur (ad bir derleme hash'i gömer), bu
yüzden `--sound <file>` kendi sesinizi (wav/mp3/ogg/flac/m4a/aac) üzerine kurar
ve stok dosyayı `chime-*.mp3.bak` olarak tutar; `--revert` onu geri yükler.
`--verify` hangisinin canlı olduğunu bildirir.

### FreeBuff ses düğmesi (arayüz)

`WintageInstaller.ps1` içinde APPLY / REVERT yığınının altında küçük bir **FB
SOUND** düğmesi vardır. Yalnızca bir *tercih* saklar; `install.ps1 -Target
freebuff` aynı dosyayı okur ve onu yamaya `--sound` olarak iletir, böylece
reklamlar ve ses tek çalıştırmada uygulanır:

- **Sol tık** — bir ses dosyası seçin (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac)
  ve hemen çalındığını duyun: PCM WAV System.Media.SoundPlayer üzerinden, diğer
  her format bir WPF MediaPlayer üzerinden (Media Foundation, asenkron, böylece
  pencere asla donmaz). Seçim `%APPDATA%\Wintage\freebuff-sound.txt` içinde
  hatırlanır (makine başına, git checkout'unun dışında, hatırlanan kaynak ağacı
  klasörleriyle tamamen aynı şekilde).
- **Sağ tık** — tercihi FreeBuff'ın stok zil sesine geri temizler (hâlâ
  çalmakta olan herhangi bir önizlemeyi de durdurur).
- **COPY** — seçilen sesi repo'nun kendisine kopyalar (`sounds\freebuff.<ext>`,
  kaynak uzantısını koruyarak) ve tercihi o kopyaya yönlendirir, böylece ses
  orijinal dosyanın silinmesinden veya taşınmasından kurtulur. Yalnızca özel bir
  ses ayarlıyken etkindir; yeniden kopyalama repo kopyasını basitçe üzerine
  yazar. `sounds/` klasörü düz git ile izlenebilir içeriktir, bu yüzden onu
  commit'lemek sesin yeniden klonlamalarda da hayatta kalmasını sağlar.

Yalnızca tanınan ses kapları önizlenir — önce başlık koklanır, bu yüzden ses
olmayan bir seçim sessizce hiçbir şey çalmak yerine bildirilir.

Özel bir ses ayarlıyken düğme `ON` okur; üzerine gelince yolu gösterir. Etkili
olması için ardından `freebuff` hedefini uygulayın (FreeBuff'u işaretleyin +
APPLY veya bir terminalden `install.ps1 -Target freebuff` çalıştırın).

### Terminaller

`terminal`, tespit edilen her kararlı, Preview veya paketsiz Windows Terminal
ayar dosyasına bir `Wintage` renk şeması yazar ve onu `profiles.defaults`
aracılığıyla, konsol güvenli Consolas 12 ve aliased metinle birlikte seçer.
Orijinal dosya, yanında bayt bayt korunur ve `-Revert` onu geri yükler.

`conhost`, klasik `cmd.exe`, Windows PowerShell, Git CMD/Bash konsol profillerini
ve mevcut diğer `HKCU\Console` alt öğelerini kapsar. Paletin tam 16 renkli
tablosunu hem kök varsayılanlarına hem de mevcut her geçersiz kılmaya yazar,
ardından yalnızca dokunduğu değerleri geri yükler. Oraya da Consolas uygular,
çünkü oransal Verdana, her iki terminal ana bilgisayarının kullandığı sabit
genişlikli hücre ızgarasının içinde çakışır.

### Tarayıcılar ve Tampermonkey

`browsers`, Chrome, Edge, Brave, Cent, Vivaldi ve Opera profillerini kurulu
konumlardan ve ona işaret ettiğiniz taşınabilir kökten (`-PortableRoot` veya
`paths.json` içindeki hatırlanan `portable` girişi) bulur. Durumu hem profil
sayısını hem de kaçının Tampermonkey içerdiğini gösterir. Apply, seçilen tarayıcı
chrome temasını kararlı `%LOCALAPPDATA%\Wintage\browser-theme` klasörüne kopyalar,
o yolu panoya koyar ve her ilgili profili `chrome://extensions` adresinde artı
Wintage kullanıcı betiği Install/Update sayfasını açar. Tampermonkey'i olmayan
profiller ayrıca Chrome Web Store sayfasını da alır.

Chromium, yönetilmeyen bir Windows makinesine mağaza dışı sessiz eklenti
kurulumunu bilerek yasaklar. Bu yüzden ilk tarayıcı teması kurulumu, her profil
için bir **Developer mode → Load unpacked** onayı gerektirir. Kopyalanan yolu
seçin; bundan sonra Wintage, paletler değiştiğinde aynı kararlı klasörü
değiştirmeye devam eder. Tampermonkey'de de **Install/Update** onaylayın.
Tarayıcının arkasından hiçbir tarayıcı `Preferences`, Secure Preferences veya
Tampermonkey LevelDB dosyası düzenlenmez. Tampermonkey yoksa, açılan mağaza
sekmesinden kurun ve zaten açık olan `wintage.user.js` sekmesini yenileyerek
Install ekranını alın.

### Windows

`windows`, içerik adresli bir
`%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme` dosyası kurar ve
hemen etkinleştirir. Etkin temadan başlar ve yalnızca belgelenmiş renk, imleç ve
görsel stil bölümlerini değiştirir. Duvar kağıdı, sesler ve masaüstü simgeleri
değişmeden kalır; imleçler bilerek kurulu `___CURRENT___` şemasına geçer. İlk
etkin tema `Wintage.original.theme` olarak bayt bayt kaydedilir; palet değişiklikleri
o taban çizgisini korur ve `-Revert` onu yeniden etkinleştirir. Modern Windows
denetimleri hâlâ imzalı Aero görsel stilinden gelir — Wintage, korumalı `.msstyles`
dosyalarını değiştirmek yerine desteklenen koyu modu, vurgusunu ve klasik sistem
rengi girdilerini değiştirir. Etkin ve etkin olmayan başlıklar paletin yumuşatılmış
yükseltilmiş yüzey rengini paylaşır; parlak vurgu metin/seçim kenarları için
ayrılmış kalır. Önceki etkin olmayan başlık vurgusu ayrıca anlık görüntülenir ve
`-Revert` tarafından tam olarak geri yüklenir. İçerik hash'i Windows'a aynı palet
yeniden derlendiğinde yeni bir dosya ilişkilendirme hedefi verir, bu yüzden güncel
bir paleti yeniden uygulamak no-op ile karıştırılmaz; eskimiş Wintage dosyası,
Windows yeninin etkin olduğunu onayladıktan sonra kaldırılır.

### OBS Studio

`obs`, korunan Yami Classic tabanı üzerinde bir OBS 30.2+ varyantı üretir, onu
`%APPDATA%\obs-studio\themes` içine kurar ve kararlı tema kimliğini `user.ini`
dosyasına yazar, böylece seçilen Wintage paleti bir sonraki başlatmada zaten
seçili olur. Apply veya Revert'ten önce OBS'yi kapatın: OBS çıkışta `user.ini`
dosyasını yeniden yazar. İlk uygulama hem önceki seçimi hem de aynı adlı temayı
bayt bayt yedekler.

### Electron uygulamaları

`resources/app.asar`, `resources/app/app.asar` konumuna taşınır (`app.asar.unpacked`
kardeşi onunla birlikte taşınır — bu eşleştirme dosya adına dayalıdır ve ayırmak
her yerel modülü kırar) ve küçük bir `shim.cjs`, boşalan `resources/app` yuvasını
alır. Shim, stil sayfasını enjekte eder ve sonra orijinal arşivi yükler. **Hiçbir
uygulama baytı yeniden yazılmaz**, yalnızca yeniden konumlandırılır; `-Revert` onu
doğrudan geri taşır.

Bu uygulamalar için stil sayfası yazılmaz — `wintage.user.js` dosyasından
çıkarılır, bu yüzden tarayıcı için yapılan her bevel, kaydırma çubuğu ve tip
merdiveni düzeltmesi, çürüyecek ikinci bir kopya olmadan buraya da gelir.

Önceden bilmeye değer iki not:

- Bariz yaklaşım — `resources/app` öğesini arşivin yanına bırakıp Electron'un onu
  tercih etmesine güvenmek — **çalışmaz ve sessizce başarısız olur**. Electron
  önce `app.asar` öğesini arar. Uygulama kusursuz başlar ve tema asla çalışmaz.
- Shim bilerek `.cjs`'dir, `.js` değil. Onun `package.json` dosyası uygulamanın
  kendisinden kopyalanır, böylece uygulama adını ve sürümünü korur (ad, userData'nın
  nerede yaşayacağına karar verir — onu yeniden adlandıran bir shim, uygulamayı boş
  bir profile taşır). Bu manifest `"type": "module"` diyorsa, bir `.js` shim ilk
  `require`'da ölür.

### Claude'ın masaüstü uygulaması: yerinde ve gerçekten çizdiği çerçeve

Claude yukarıdaki yeniden konumlandırmayı kullanamaz, çünkü `OnlyLoadAppFromAsar`
sabit olarak açıktır — Electron `resources/app.asar` öğesini ve başka hiçbir şeyi
yükler, bu yüzden `resources/app` içindeki bir shim asla çalışamaz. Bunun yerine
**yerinde** yamalanır: arşiv yedeklenir, onun `package.json` `main` alanı
`"../wintage-shim.cjs"` olarak yeniden yazılır (aynı bayt uzunluğuna dolgulanır,
böylece arşivdeki her ofset geçerli kalır) ve dosya başına bütünlük hash'i buna
uyacak şekilde güncellenir. `-Revert` yedeği geri yükler.

Yükleyici, **herhangi bir şeyi taşımadan önce** füzeleri hâlâ okur ve onu
engellediklerinde bir gerekçeyle reddeder — `EnableEmbeddedAsarIntegrityValidation`
yukarıdaki yeniden yazmayı kurulumda değil başlatmada başarısız kılardı. Herhangi
bir uygulamayı kendiniz kontrol edin:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Bunun ikinci yarısı çok daha sessiz bir sorundu. Claude'ın `BrowserWindow` öğesi
ince bir kabuk çizer ve **görünür uygulamanın tamamı ona bağlı bir
`WebContentsView`**'dir. Shim eskiden `browser-window-created` olayına bağlanırdı,
bu yüzden stil sayfasını kabuğa enjekte eder, `wintage-status.txt` dosyasına
başarı bildirir ve görebileceğiniz hiçbir şeyi değiştirmezdi. Artık
`web-contents-created` olayına bağlanır; bu, pencere içeriklerini,
`WebContentsView`'ları, `BrowserView`'ları, `<webview>` misafirlerini ve açılır
pencereleri de kapsar.

### Obsidian

Her kasanın `.obsidian/themes/` klasörüne bir topluluk teması yazılır — on altı
paletin tamamı aynı anda, tam VS Code hedefi gibi, böylece hiçbir şeyi yeniden
çalıştırmadan **Settings → Appearance** içinde aralarında geçiş yaparsınız. Şablon,
kasada zaten olan elle yapılmış `VintageWin95` temasından türetildi; her renk,
eşit olduğu belirteçle değiştirildi. `-Palette <slug>`, hangisinin kurulumda aktif
olacağını ayarlar; `appearance.json` önce yedeklenir ve `-Revert` yalnızca
`Wintage *` temalarını kaldırır ve önceki seçiminizi geri yükler — aynı kasada
elle yapılmış bir temaya asla dokunulmaz.

### SAIPENVIEW

Ön ucu, Wintage belirteç adlarını kendi `:root` içinde zaten bildirir, bu yüzden
bu yama **yalnızca belirteç değerlerini** yeniden yazar — asla bir seçici, bir
yazı tipi, bir kenarlık genişliği veya bir dolgu. Kutu modelini etkileyen hiçbir
şey değişmez, bu yüzden metin kayamaz. Bu bilinçlidir: önceki yaklaşım tüm tarayıcı
stil sayfasını üste ekliyordu ve `wintage.css`, rastgele web sayfaları için
yazılmıştır — yazı tipini, boyut merdivenini, 2px kenarlıkları ve denetim
yüksekliklerini zorlayan evrensel seçiciler. Kendi düzenine sahip bir uygulamada
bu her şeyi oynatır.

Her hex'in maskelenmesi ve yedekle karşılaştırılmasıyla doğrulandı: yapısal olarak
aynı, yalnızca renk değişmezleri farklı. `--link` orada bildirilmediği için
enjekte edilmek yerine bildirilmez (onun markdown bağlantıları `--accentTeal` okur,
ki bu bunu ayarlar) — uygulamanın asla okumadığı bir değişken eklemek ölü ağırlık
olurdu.

### MPC-HC (K-Lite)

Yerel Win32, stil sayfası ve enjeksiyon noktası yok ve koyu temasının renkleri
programa derlenmiş — hiçbir kayıt defteri değeri onları ifşa etmez. Bu yüzden bu
hedef **bir palet taşıyamaz**. Yaptığı şey: koyu temayı açar ve OSD'ye UI.md
tipografi kurallarını uygular; OSD, MPC-HC'nin kullanıcının kontrol etmesine izin
verdiği tek yüzeydir. Önceki ayarlar önce `desktop/backup/mpc-hc-settings.reg`
dosyasına aktarılır.

Uygulamadan önce MPC-HC'yi kapatın: çıkışta ayarlarını yeniden yazar.

## Yeniden derleme

`desktop/out/` altındaki her şey `themes/*.json` dosyalarından üretilir. Git'te
izlenmez (T-160), bu yüzden taze bir klon kurulumdan önce bir kez derlemelidir:

```powershell
node ..\tools\build-desktop.js          # tüm hedefleri yeniden derle
node ..\tools\build-desktop.js --check  # bir şey bayatlaşmışsa 1 çıkış kodu
```

`release.ps1` derlemeyi ve her kapıyı çalıştırır, bu yüzden bir sürüm paletlerden
sapmış çıktı gönderemez.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
