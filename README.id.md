# Wintage

**Tema Vintage Win95 Emas Gelap untuk seluruh web.** Skrip pengguna Tampermonkey yang menata ulang setiap situs menjadi aplikasi Windows 95 cokelat keemasan gelap: bevel 3D setajam piksel, nol sudut membulat, nol animasi, tanpa kilatan hover, Verdana di mana-mana.

[🤍 Dukung Pengembang](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Web modern mengoptimalkan estetika dengan mengorbankan kegunaan. Sudut membulat menggantikan hierarki visual, animasi menggantikan umpan balik, bayangan menggantikan struktur, dan minimalisme sering menghilangkan isyarat yang justru diandalkan otak kita untuk memahami antarmuka._

_Pengguna seharusnya tidak perlu menebak apakah sesuatu itu tombol, label, kartu, atau teks biasa. Wintage menghadirkan kembali bahasa visual yang eksplisit: tombol timbul, kolom input cekung, batas tajam, tipografi konsisten, nol gangguan, dan perubahan status seketika._

_Setiap elemen menyampaikan tujuannya dalam sekali pandang, mengurangi beban kognitif dan membuat web terasa seperti instrumen presisi lagi, bukan kumpulan gelembung dekoratif._

[Log Perubahan](CHANGELOG.md)

## Instalasi

1. Pasang [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Klik **[Pasang Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey otomatis membuka halaman pemasangannya.
3. Selesai. Setiap situs yang Anda kunjungi kini menjalankan Windows 95, edisi Emas Gelap.

## Pembaruan

- **Otomatis:** skrip membawa `@updateURL`/`@downloadURL` yang menunjuk ke repo ini, jadi Tampermonkey mengambil versi baru pada pemeriksaan pembaruan rutinnya.
- **Penyegaran manual:** Tampermonkey → **Utilities → Check for userscript updates**, atau cukup klik lagi tautan pemasangan — ini menggantikan versi lama di tempatnya, tanpa perlu uninstall.
- **Baris tema yang hilang berarti skrip lama:** menu dihasilkan dari registri tema tertanam dan uji rilis mensyaratkan tepat satu baris menu untuk setiap palet tertanam. Jika menu lebih pendek dari daftar palet di bawah, klik **Install Wintage** lagi dan konfirmasi **Update** di Tampermonkey.

## Enam belas palet, dan sebuah saklar

Wintage tidak lagi satu palet. Enam di antaranya adalah struktur milik UI.md yang diputar ke famili corak lain (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom dapat diedit dan disimpan dari penginstal desktop, dan sembilan diimpor dari [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Semuanya meloloskan WCAG AA pada tiga token yang membawa teks — gerbang build menolak palet yang tidak melakukannya.

Pilih satu dari **menu Tampermonkey** di halaman mana pun; pilihan disimpan per pengguna, bukan per situs, jadi berlaku di semua domain.

Palet berada di `themes/*.json`, di luar skrip, dengan satu alasan: Tampermonkey mengunduh ulang `wintage.user.js` pada setiap pembaruan, jadi palet yang diedit dengan tangan ke dalamnya akan hilang. Terapkan kembali ke build baru dengan:

```powershell
.\install-themes.ps1 -Latest
```

## Di luar peramban

Palet yang sama terpasang ke aplikasi desktop — VS Code dan Antigravity sebagai tema warna, aplikasi Electron (Freebuff, aplikasi agen Antigravity) melalui shim yang menyuntikkan stylesheet persis yang digunakan skrip pengguna ini. Ada GUI kecil untuk itu:

Klik dua kali **`Wintage Installer.vbs`** di root repo. Ia membuka GUI tanpa jendela konsol. Peluncur `.cmd` lama meneruskan ke host tersembunyi yang sama; `desktop\WintageInstaller.ps1` tetap bisa dijalankan langsung untuk diagnostik.

Apa yang dapat dan tidak dapat dijangkau setiap target — termasuk dua aplikasi yang terkunci rapat atau warnanya terkompilasi — tertulis di **[desktop/README.md](desktop/README.md)**.

## Fitur

- **Palet Golden Default** — kanvas cokelat-hitam pekat `#1A1810`, teks emas `#D4C89A`, sorotan bevel emas `#F0D060`. Hanya permukaan datar solid: tanpa gradien, tanpa blur, tanpa efek transparansi.
- **Bevel 3D klasik** — tombol timbul, input cekung, tombol yang ditekan terbenam (dengan pergeseran label 1px otentik). Scrollbar penuh bergaya Win95 16px, dengan thumb dan tombol berbevel.
- **Pembunuh radius** — `border-radius: 0` diberlakukan di mana-mana, termasuk variabel CSS framework (Bootstrap, Material, YouTube, Reddit).
- **Gerak dilarang** — semua transisi dan animasi di-nol-kan. Perubahan status seketika, seperti UI 1995 sungguhan.
- **Sorotan hover dinonaktifkan sepenuhnya** — tanpa baris kilatan putih, tanpa blok rona abu-abu:
  - properti cat dibuang secara bedah dari setiap aturan CSS `:hover` yang terbaca (properti fungsional seperti `display`/`visibility`/`opacity` dipertahankan, jadi menu yang terbuka saat hover tetap berfungsi);
  - stylesheet lintas-asal yang tak terbaca dinetralkan oleh fallback pembekuan transisi.
  Hanya kontrol sungguhan (tombol, tautan, input) yang mempertahankan respons bevel bertema seketika.
- **Verdana dipaksakan 100% di mana-mana** — termasuk input dan textarea, dengan smoothing font dimatikan. Font ikon dikecualikan agar glif tidak berubah menjadi huruf. Jika Anda punya font kustom terpasang bernama `Verdana_m1` (mis. patch Verdana tanpa anti-aliasing), font itu dipakai otomatis; jika tidak, Verdana biasa.
- **Repainter adaptif** — pembersih JS ringan mengubah permukaan "kilatan" terang dan abu-abu mode gelap yang tak bertema menjadi skala cokelat vintage, dan memperbaiki teks kontras-rendah (gelap-di-atas-gelap) menjadi emas, pada ambang sadar-WCAG. Gambar, video, canvas, dan pemutar tidak pernah disentuh.
- **Tembus Shadow DOM** — juga memberi tema pada komponen web (YouTube, Reddit, dan lainnya) melalui hook `attachShadow`.
- **Popup berperilaku baik** — menu, dialog, tooltip, dan hovercard hanya diwarnai ulang; skrip tidak pernah memaksa `opacity`/`z-index`/`visibility`, jadi UI situs yang tersembunyi tetap tersembunyi.
- **Pengaman** — skrip menonaktifkan dirinya sendiri di halaman OAuth, captcha, perbankan, dan pembayaran agar alur kritis tidak pernah ditata ulang.

## Palet

Tabel di bawah menampilkan 10 dari 21 token palet Golden Default. Setiap palet yang dikirimkan mendefinisikan semua 21; 11 sisanya mencakup struktur bevel, teks sekunder, warna semantik (sukses/peringatan/bahaya), seleksi, dan spesifik per target.

| Token | Hex | Digunakan untuk |
|---|---|---|
| background | `#1A1810` | latar paling luar |
| backgroundSoft | `#232018` | latar body / konten |
| surface | `#332E22` | header, nav, panel |
| surfaceRaised | `#3D372A` | tombol, popup, thumb scrollbar |
| surfaceAlt | `#453D30` | hover tombol |
| borderHighlight | `#F0D060` | tepi 3D kiri-atas |
| borderDark | `#100E08` | tepi 3D kanan-bawah |
| textPrimary | `#D4C89A` | teks emas primer |
| textMuted | `#6E674E` | placeholder, nonaktif |
| link | `#F0D060` | tautan, fokus |

## Tema peramban yang serasi

Target `browsers` di penginstal desktop mendeteksi profil Chromium terpasang dan portabel, melaporkan cakupan Tampermonkey, menyiapkan tema peramban yang dipilih, dan membuka halaman instal/pembaruan yang tepat untuk setiap profil. Chromium memerlukan satu konfirmasi **Developer mode → Load unpacked** per profil; penginstal menyalin jalur tema stabil ke clipboard. Perubahan palet berikutnya memakai ulang jalur itu.

## Perilaku yang diketahui

- Situs yang membangun efek hover di JavaScript (toggle kelas) alih-alih CSS `:hover` mungkin masih menampilkan sorotannya sendiri.
- Pada situs langka yang CSS-nya lintas-asal, mengklik elemen yang tidak dapat difokuskan dapat menunda perubahan status visualnya hingga mouse meninggalkannya (fallback pembekuan hover yang bekerja). Tombol dan tautan sungguhan dikecualikan.
- Skrip statis oleh desain: tanpa panel opsi, tanpa toggle per situs. Fork dan edit token di bagian atas jika Anda menginginkan rasa yang berbeda.

## Merilis versi baru (untuk pemelihara)

Edit `wintage.user.js`, lalu jalankan:

```powershell
.\release.ps1 -Message "apa yang berubah"
```

Ini menaikkan nomor patch `@version`, melakukan commit, dan push — klien Tampermonkey mengambil pembaruan secara otomatis. Berikan `-Bump minor` atau `-Bump major` untuk rilis yang lebih besar.

## Lisensi

[MIT](LICENSE)

<!-- source-digest: README.md sha256:ee7c6a2a1626faed -->
