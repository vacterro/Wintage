# Wintage

**Win95 koyu altın vintage teması, tüm web için.** Her siteyi koyu altın-kahverengi bir Windows 95 uygulamasına dönüştüren bir Tampermonkey userscript'i: pikselsert 3D pahlar, sıfır yuvarlatılmış köşe, sıfır animasyon, hover flaşı yok, her yerde Verdana.

[🤍 Geliştiriciyi destekle](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Modern web, estetiği kullanılabilirlik pahasına optimize eder. Yuvarlatılmış köşeler görsel hiyerarşinin yerini, animasyonlar geri bildirimin yerini, gölgeler yapının yerini alır ve minimalizm genellikle beynin bir arayüzü anlamak için güvendiği ipuçlarını tam da kaldırır._

_Kullanıcı bir şeyin buton mu, etiket mi, kart mı yoksa sadece metin mi olduğunu tahmin etmek zorunda kalmamalı. Wintage net bir görsel dil geri getirir: kabartmalı butonlar, gömülü giriş alanları, keskin kenarlar, tutarlı tipografi, sıfır dikkat dağıtıcı ve anında durum değişimleri._

_Her öğe amacını ilk bakışta anlatır, bilişsel yükü azaltır ve web'i dekoratif baloncuklar koleksiyonu yerine yeniden hassas bir araç haline getirir._

[Changelog](CHANGELOG.md)

## Kurulum

1. [Tampermonkey](https://www.tampermonkey.net/)'i kurun (Chrome, Edge, Firefox, Opera, Safari).
2. **[Wintage'ı Kur](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** bağlantısına tıklayın — Tampermonkey kurulum sayfasını otomatik açar.
3. Tamam. Ziyaret ettiğiniz her site artık Windows 95, koyu altın sürümünde çalışıyor.

## Güncelleme

- **Otomatik:** script `@updateURL`/`@downloadURL` olarak bu depoyu gösterir, bu yüzden Tampermonkey düzenli güncelleme kontrollerinde yeni sürümleri alır.
- **Manuel güncelleme:** Tampermonkey → **Utilities → Check for userscript updates**, ya da kurulum bağlantısına tekrar tıklayın — eski sürümü doğrudan değiştirir, kaldırma gerekmez.
- **Eksik tema satırları eski script demektir:** menü gömülü tema kaydından üretilir ve sürüm testi her gömülü palet için tam olarak bir menü satırı ister. Menü aşağıdaki palet listesinden kısaysa tekrar **Install Wintage**'a tıklayın ve Tampermonkey'de **Update**'i onaylayın.

## On altı palet ve bir anahtar

Wintage artık tek bir palet değil. Altısı UI.md yapısının başka bir renk ailesine döndürülmüş hali (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom masaüstü kurucusundan düzenlenip kaydedilebilir ve dokuzu [FastPrompter](https://github.com/vacterro)'dan içe aktarılmıştır (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Her biri metin taşıyan üç token'da WCAG AA'yı geçer — build kapısı bunu yapmayan bir paleti reddeder.

Herhangi bir sayfada **Tampermonkey menüsünden** birini seçin; seçim site başına değil kullanıcı başına kaydedilir, bu yüzden tüm alan adlarında geçerlidir.

Paletler tek bir nedenle script'in dışında, `themes/*.json` içinde yaşar: Tampermonkey her güncellemede `wintage.user.js`'yi yeniden indirir, bu yüzden elle yazılmış bir palet kaybolurdu. Taze bir derlemeye şu komutla yeniden uygulayın:

```powershell
.\install-themes.ps1 -Latest
```

## Tarayıcının ötesinde

Aynı paletler masaüstü uygulamalarına kurulur — VS Code ve Antigravity renk teması olarak, Electron uygulamalarına (Freebuff, Antigravity agent app) bu userscript'in kullandığı stil sayfasını birebir enjekte eden bir shim aracılığıyla. Bunun için küçük bir arayüz vardır:

Depo kökündeki **`Wintage Installer.vbs`** dosyasına çift tıklayın. Arayüzü konsol penceresi olmadan açar. Eski `.cmd` başlatıcı aynı gizli ana bilgisayara yönlendirir; `desktop\WintageInstaller.ps1` tanılama için doğrudan çalıştırılabilir.

Her hedefin neleri başarabileceği ve başaramayacağı — mühürlü veya renkleri derlenmiş iki uygulama dahil — **[desktop/README.md](desktop/README.md)** içinde yazılıdır.

## Özellikler

- **Golden Default paleti** — derin kahve-siyah tuval `#1A1810`, altın metin `#D4C89A`, altın pah vurguları `#F0D060`. Yalnızca katı düz yüzeyler: gradyan yok, bulanıklık yok, şeffaflık efekti yok.
- **Klasik 3D pahlar** — butonlar kabartmalı, giriş alanları gömülü, basılan butonlar içeri çöker (otantik 1px etiket kaymasıyla). Kaydırma çubukları Win95 tarzında tam 16px, pahlı tutamaç ve butonlarla.
- **Yarıçap katili** — `border-radius: 0` her yerde zorlanır, çerçeve CSS değişkenleri dahil (Bootstrap, Material, YouTube, Reddit).
- **Hareket yasak** — tüm geçişler ve animasyonlar sıfırlanır. Durum değişimleri gerçek bir 1995 arayüzü gibi anlıktır.
- **Hover vurgusu tamamen kapalı** — beyaz flaş satırları yok, gri ton blokları yok:
  - doldurma özellikleri her okunabilir `:hover` kuralından cerrahi olarak çıkarılır (hover ile açılan menüler çalışmaya devam etsin diye `display`/`visibility`/`opacity` gibi işlevsel özellikler korunur);
  - okunamayan cross-origin stil sayfaları geçiş dondurma yedeğiyle etkisiz hale getirilir.
  Yalnızca gerçek kontroller (butonlar, bağlantılar, giriş alanları) anlık, temalı bir pah tepkisi korur.
- **Verdana her yerde %100 zorlanır** — giriş alanları ve textarea dahil, yazı tipi yumuşatma kapalı. Glifler harfe dönüşmesin diye ikon fontları hariç tutulur. `Verdana_m1` adında özel bir yazı tipi kuruluysa (ör. anti-aliasing'siz bir Verdana yaması) otomatik kullanılır; aksi halde normal Verdana.
- **Uyarlanabilir repainter** — hafif bir JS tarayıcı, açık "flaş" yüzeyleri ve temalanmamış koyu mod gri tonlarını vintage kahve ölçeğine dönüştürür ve düşük kontrastlı (koyu-üstüne-koyu) metni WCAG bilinçli eşiklerde altına çevirir. Görseller, videolar, canvas'lar ve oynatıcılar asla dokunulmaz.
- **Shadow DOM delme** — web bileşenlerini de (YouTube, Reddit ve diğerleri) bir `attachShadow` kancasıyla temalar.
- **Açılır pencereler uslu durur** — menüler, diyaloglar, ipuçları ve hover kartları yalnızca yeniden renklendirilir; script asla `opacity`/`z-index`/`visibility` dayatmaz, bu yüzden gizli site arayüzü gizli kalır.
- **Güvenlik bekçisi** — kritik akışlar asla yeniden biçimlendirilmesin diye script kendini OAuth, captcha, bankacılık ve ödeme sayfalarında devre dışı bırakır.

## Palet

Aşağıdaki tablo Golden Default paletinin 21 token'ından 10'unu gösterir. Gönderilen her palet 21'in tamamını tanımlar; kalan 11'i pah yapısını, ikincil metni, anlamsal renkleri (başarı/uyarı/tehlike), seçimi ve hedefe özel ayrıntıları kapsar.

| Token | Hex | Kullanımı |
|---|---|---|
| background | `#1A1810` | en dış arka plan |
| backgroundSoft | `#232018` | gövde / içerik arka planı |
| surface | `#332E22` | başlıklar, gezinme, paneller |
| surfaceRaised | `#3D372A` | butonlar, açılır pencereler, kaydırma tutamacı |
| surfaceAlt | `#453D30` | buton hover'ı |
| borderHighlight | `#F0D060` | pah kenarları, bağlantılar |
| borderDark | `#100E08` | gömülü kenarlar, çerçeveler |
| textPrimary | `#D4C89A` | birincil altın metin |
| textMuted | `#6E674E` | yer tutucular, devre dışı |
| link | `#F0D060` | bağlantılar, odak |

## Karşılık gelen tarayıcı teması

Masaüstü kurucusunun `browsers` hedefi yüklü ve taşınabilir Chromium profillerini algılar, Tampermonkey kapsamını raporlar, seçilen tarayıcı temasını hazırlar ve her profil için doğru kurulum/güncelleme sayfalarını açar. Chromium profil başına bir **Developer mode → Load unpacked** onayı ister; kurucu kararlı tema yolunu panoya kopyalar. Sonraki palet değişiklikleri o yolu yeniden kullanır.

## Bilinen davranışlar

- Hover efektlerini CSS `:hover` yerine JavaScript ile (sınıf değiştirerek) kuran siteler kendi vurgularını göstermeye devam edebilir.
- Cross-origin CSS'li nadir sitelerde, odaklanamayan bir öğeye tıklamak görsel durum değişimini fare oradan ayrılana kadar geciktirebilir (hover dondurma yedeği devreye girer). Gerçek butonlar ve bağlantılar hariçtir.
- Script bilinçli olarak statiktir: seçenek paneli yok, site başına anahtar yok. Farklı bir tat istiyorsanız fork edin ve yukarıdaki token'ları düzenleyin.

## Yeni sürüm yayınlama (bakımcılar için)

Önce `CHANGELOG.md`'nin en üstüne bir `## [x.y.z] - date` girişi ekleyin — olmadan `release.ps1` çalışmayı reddeder. Sonra:

```powershell
.\release.ps1 -Message "ne değişti"
```

`@version` patch numarasını yükseltir (Tampermonkey başlığı ve `W95_VERSION` damgası birlikte hareket eder), üretilen masaüstü temalarını yeniden oluşturur, sürüm kapısı paketinin tamamını çalıştırır ve commit'ler, etiketler ve gönderir — Tampermonkey istemcileri güncellemeyi otomatik alır. Daha büyük sürümler için `-Bump minor` veya `-Bump major` iletin.

## Lisans

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
