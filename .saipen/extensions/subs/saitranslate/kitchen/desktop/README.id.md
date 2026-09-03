# Wintage untuk aplikasi desktop

Skrip pengguna memberi tema pada web. Ini memberi tema pada program di sekitarnya, dari palet yang sama, sehingga peramban dan aplikasi berhenti berselisih tentang arti emas gelap.

Ada satu aturan di balik setiap keputusan di sini: **aplikasi memperbarui diri mereka sendiri, dan pembaruan tidak boleh diam-diam merusak apa pun.** Jika sebuah target memiliki tempat di profil Anda, tema pergi ke sana dan bertahan dari pembaruan. Jika tidak, penginstal ditulis untuk dijalankan ulang — dan mengatakannya, alih-alih berpura-pura sudah persisten.

## GUI

Klik dua kali **`Wintage Installer.vbs`** di root repo untuk membukanya tanpa jendela konsol, atau jalankan ini langsung untuk diagnostik:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Daftar tema dengan chip warna, target yang ditemukan di mesin ini, pratinjau Win95 langsung, dan semua dua puluh satu token warna sebagai swatch yang dapat diedit. Mengedit swatch mana pun memfokuskan palet menjadi **Custom** alih-alih mengubah tema bawaan di bawah Anda. Panel di kanan menampilkan kontras WCAG langsung untuk tiga token yang membawa teks — palet yang FAIL di sana ditolak oleh gerbang build pula, jadi lebih baik melihatnya sebelum Apply daripada sesudahnya.

Target dipisah menjadi dua daftar yang dapat diakses keyboard: **MY APPS** berisi alat portabel/sumber-pohon CodeNomad, SAIPENVIEW, SmartVac dan WildRift; **POPULAR APPS** berisi Windows, OBS, terminal, editor, dan perangkat lunak terpasang lainnya. ALL/NONE dan Apply/Revert beroperasi di kedua daftar tanpa mengubah pengelompokannya.

Jendela memakai palet yang akan dipasangnya. Itu pratinjau tercepat yang tersedia, dan itu menjaga alat tetap jujur: palet yang membuat jendela ini tak terbaca terlihat jelas tak terbaca.

Apply memanggil `install.ps1`. Hanya ada satu jalur kode yang memasang tema, sehingga GUI tidak mungkin melenceng dari baris perintah.

## Baris perintah

```powershell
.\desktop\install.ps1                                  # apa yang ada di sini, apa yang diberi tema, dengan palet apa
.\desktop\install.ps1 -Target freebuff -Palette klite  # satu aplikasi, satu palet
.\desktop\install.ps1 -Target all -Palette goldendefault # semuanya
.\desktop\install.ps1 -Target all -WhatIf              # katakan apa yang akan berubah, jangan sentuh apa pun
.\desktop\install.ps1 -Target freebuff -Revert         # batalkan satu
```

`-Palette` default ke `goldendefault` (**Golden Default**). GUI terbuka pada palet yang sama dan memeriksa setiap target yang tersedia. Mengecat ulang aplikasi yang sudah diberi tema berfungsi saat berjalan; pemasangan pertama tidak, karena arsip sedang digunakan.

## Sejauh mana setiap target dapat diberi tema

| target | mekanisme | bertahan dari pembaruan aplikasi |
|---|---|---|
| `windows` | `.theme` pengguna: mode sistem/aplikasi gelap, peran warna aksen dan klasik | ya — dipasang di folder Windows Themes lokal Anda |
| `browsers` | mendeteksi profil Chromium terpasang + portabel, menyiapkan tema chrome terpilih dan membuka halaman konfirmasi Tampermonkey/tema milik peramban | ya setelah satu **Load unpacked** per profil |
| `terminal` | skema Windows Terminal + default semua-profil, Consolas 12 aliased | ya — pengaturannya ada di profil Anda |
| `conhost` | default `HKCU\Console` + setiap profil cmd/PowerShell yang ada | ya — snapshot nilai-tersentuh persis |
| `obs` | varian OBS 30.2+ `.ovt` + ID tema `user.ini` aktif | ya — ia tinggal di profil Anda |
| `antigravity`, `vscode` | ekstensi tema warna di `~/.antigravity/extensions` / `~/.vscode/extensions` | **ya** — ia tinggal di profil Anda |
| `freebuff`, `antigravity-app`, `codenomad` | shim Electron, lihat di bawah | tidak — jalankan ulang penginstal |
| `claude` | shim Electron, ditambal di tempat — lihat di bawah | tidak — pembaruan membuat folder `app-<version>` baru |
| `mpchc` | registri, hanya tema gelap + tipografi OSD | tidak — MPC-HC menulis ulang pengaturannya saat keluar |
| `obsidian` | tema komunitas per vault, semua palet terpasang sekaligus | **ya** — ia tinggal di vault Anda |
| `saipenview` | menulis ulang nilai token `:root` sendiri di `style.css` | tidak — file sumber; jalankan ulang setelah pull |
| `discord` | CSS dilempar ke folder tema BetterDiscord sendiri | ya |
| `totalcmd`, `totalcmd2` | kunci `wincmd.ini` `[Colors]`; filter file-terbaru yang ada memakai warna tautan palet | ya — ini ini Anda |
| `smartvac`, `wildrift` | tabel token ditulis ulang di sumber aplikasi sendiri | tidak — file sumber; jalankan ulang setelah pull |

### Penghapusan iklan FreeBuff

FreeBuff (aplikasi desktop asisten AI) membawa jaringan iklannya sendiri: bundel renderer (`resources/orchestrator/ui/assets/index-*.js`) merender kartu `sponsored-ad` dan spanduk thread, dan orkestrator (`resources/orchestrator/orchestrator.js`) mengekspos rute `/api/ad/slot|impression|click` yang memanggil lelang iklan jarak jauh. Shim hanya memberi tema pada aplikasi; ia tidak menyentuh file-file itu.

`desktop/patch-freebuff-ads.js` memotong iklan secara level-byte:

- renderer: titik panggil kartu/spanduk iklan menjadi `null`, dan metode klien API `adSlot` / `adImpression` / `adClick` menjadi no-op — tidak ada yang merender, dan tidak ada permintaan `/api/ad/*` yang keluar dari renderer;
- orkestrator: ketiga rute `/api/ad/*` berhenti memanggil jaringan iklan, dan permintaan iklan inline giliran-langsung (`maybeRequestAd`) di-short-circuit.

Nama file bundel menyematkan hash build, jadi tambalan menemukan bundel saat ini dari `index.html` alih-alih mengirim payload yang terkunci-versi — itulah yang membuatnya bertahan dari pembaruan. File asli dibackup ke `_orig-backup-<timestamp>/` di direktori instal; `--revert` memulihkan yang terbaru.

**Versi masa depan ditangani di dua lapisan independen:**

1. **Tambalan byte dengan fallback regex.** Setiap target memiliki string persis untuk build saat ini *dan* fallback ekspresi-reguler yang berlabuh pada sesuatu yang tidak bisa diubah nama minifier — literal jalur `/api/ad/*`, diskriminator protokol `case"ad":`, kelas `sponsored-ad`, dan penempatan `variant:"banner"` / `variant:"card"`. Orkestrator tidak diminifikasi (nama terbaca seperti `maybeRequestAd` dan `app.ads.slotAd`), jadi string persisnya bertahan lama; bundel renderer diminifikasi, jadi fallback regex-nya mengambil alih begitu build berikutnya mengganti nama pengidentifikasinya.
2. **Blok level-shim (`targets/electron/shim.cjs`).** Sepenuhnya independen dari bundel: setiap fetch/XHR ke URL `/api/ad/` ditolak di dalam halaman, dan elemen apa pun yang kelasnya mengandung `sponsored-ad` disembunyikan begitu muncul. Bahkan bundel baru yang belum pernah dipelajari skrip ini tidak dapat memunculkan iklan.

```powershell
node .\desktop\patch-freebuff-ads.js           # tambal (backup dulu)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # tambal + suara selesai kustom (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # penanda iklan apa yang dibawa build INI?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Ia berjalan otomatis sebagai bagian dari `install.ps1 -Target freebuff`, dan harus dijalankan ulang setelah setiap pembaruan FreeBuff (pembaruan memulihkan file stok). Jika build berubah bentuk, skrip menyebut target yang tidak lagi cocok — jalankan `--scan` untuk melihat apa yang masih dibawa build baru dan segarkan string di sana.

**Suara selesai FreeBuff.** Renderer memutar `chime-<hash>.mp3` saat giliran selesai. Tambalan menemukannya dengan cara yang sama menemukan bundel (nama menyematkan hash build), jadi `--sound <file>` memasang audio Anda sendiri (wav/mp3/ogg/flac/m4a/aac) di atasnya dan menyimpan file stok sebagai `chime-*.mp3.bak`; `--revert` memulihkannya. `--verify` melaporkan mana yang live.

### Tombol suara FreeBuff (GUI)

`WintageInstaller.ps1` memiliki tombol kecil **FB SOUND** di bawah tumpukan APPLY / REVERT. Ia hanya menyimpan *preferensi*; `install.ps1 -Target freebuff` membaca file yang sama dan menyerahkannya ke tambalan sebagai `--sound`, jadi iklan dan suara diterapkan dalam satu kali jalan:

- **Left-click** — pilih file audio (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) dan dengarkan langsung diputar: PCM WAV melalui System.Media.SoundPlayer, setiap format lain melalui WPF MediaPlayer (Media Foundation, async, jadi jendela tidak pernah membeku). Pilihan diingat di `%APPDATA%\Wintage\freebuff-sound.txt` (per-mesin, di luar checkout git, persis seperti folder sumber-pohon yang diingat).
- **Right-click** — kosongkan preferensi kembali ke chime stok FreeBuff (juga menghentikan pratinjau yang masih diputar).
- **COPY** — menyalin audio terpilih ke dalam repo itu sendiri (`sounds\freebuff.<ext>`, mempertahankan ekstensi sumber) dan mengarahkan ulang preferensi ke salinan itu, jadi suara bertahan meski file asli dihapus atau dipindahkan. Hanya aktif selama suara kustom disetel; menyalin ulang hanya menimpa salinan repo. Folder `sounds/` adalah konten yang bisa dilacak git biasa, jadi meng-commit-nya membuat suara bertahan dari klon ulang juga.

Hanya wadah audio yang dikenali yang dipratinjau — header disniff dulu, jadi pilihan non-audio diumumkan alih-alih diam-diam tidak memutar apa pun.

Tombol membaca `ON` selama suara kustom disetel; mengarahkan kursor padanya menampilkan jalurnya. Terapkan target `freebuff` setelahnya (centang FreeBuff + APPLY, atau jalankan `install.ps1 -Target freebuff` dari terminal) agar berlaku.

### Terminal

`terminal` menulis skema warna `Wintage` ke setiap file pengaturan Windows Terminal stabil, Preview, atau tak-dikemas yang terdeteksi dan memilihnya melalui `profiles.defaults`, bersama dengan Consolas 12 yang aman-konsol dan teks aliased. File asli disimpan byte-demi-byte di sampingnya dan `-Revert` memulihkannya.

`conhost` mencakup `cmd.exe` klasik, Windows PowerShell, profil konsol Git CMD/Bash, dan anak `HKCU\Console` lain yang ada. Ia menulis tabel 16-warna penuh palet ke default root dan setiap override yang ada, lalu memulihkan hanya nilai yang disentuhnya. Ia menerapkan Consolas di sana juga, karena Verdana proporsional bertabrakan di dalam kisi sel lebar-tetap yang dipakai kedua host terminal.

### Peramban dan Tampermonkey

`browsers` menemukan profil Chrome, Edge, Brave, Cent, Vivaldi dan Opera dari lokasi terpasang dan dari root portabel yang Anda arahkan (`-PortableRoot`, atau entri `portable` yang diingat di `paths.json`). Statusnya menampilkan jumlah profil dan berapa yang berisi Tampermonkey. Apply menyalin tema chrome peramban terpilih ke folder stabil `%LOCALAPPDATA%\Wintage\browser-theme`, meletakkan jalur itu di clipboard, dan membuka setiap profil persis di `chrome://extensions` plus halaman Install/Update skrip pengguna Wintage. Profil tanpa Tampermonkey juga mendapat halaman Chrome Web Store-nya.

Chromium dengan sengaja melarang pemasangan ekstensi off-store senyap di mesin Windows yang tidak dikelola. Pemasangan tema peramban pertama karena itu memerlukan satu konfirmasi **Developer mode → Load unpacked** per profil. Pilih jalur yang disalin; setelah itu, Wintage terus mengganti folder stabil yang sama saat palet berubah. Konfirmasi juga **Install/Update** di Tampermonkey. Tidak ada file `Preferences`, Secure Preferences atau LevelDB Tampermonkey yang diedit di belakang peramban. Jika Tampermonkey tidak ada, pasang dari tab toko yang terbuka dan segarkan tab `wintage.user.js` yang sudah terbuka untuk mendapatkan layar Install.

### Windows

`windows` memasang dan langsung mengaktifkan `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme` yang dialamatkan-konten. Ia mulai dari tema aktif dan mengganti hanya bagian warna, kursor, dan gaya-visual yang terdokumentasi. Wallpaper, suara, dan ikon desktop tetap tidak berubah; kursor dengan sengaja beralih ke skema `___CURRENT___` yang terpasang. Tema aktif pertama disimpan byte-demi-byte sebagai `Wintage.original.theme`; perubahan palet mempertahankan baseline itu, dan `-Revert` mengaktifkannya lagi. Kontrol Windows modern masih datang dari gaya visual Aero bertanda tangan — Wintage mengubah input mode gelap, aksen, dan warna sistem klasik yang didukungnya alih-alih mengganti file `.msstyles` yang dilindungi. Keterangan aktif dan nonaktif berbagi warna permukaan terangkat redup palet; sorotan terang tetap dicadangkan untuk tepi teks/seleksi. Aksen keterangan nonaktif sebelumnya di-snapshot terpisah dan dipulihkan persis oleh `-Revert`. Hash konten memberi Windows target asosiasi file baru ketika palet yang sama dibangun ulang, jadi menerapkan ulang palet yang diperbarui tidak disalahartikan sebagai no-op; file Wintage yang digantikan dihapus setelah Windows mengonfirmasi yang baru aktif.

### OBS Studio

`obs` menghasilkan varian OBS 30.2+ di atas basis Yami Classic yang dipelihara, memasangnya ke `%APPDATA%\obs-studio\themes`, dan menulis ID tema stabilnya ke `user.ini`, jadi palet Wintage terpilih sudah dipilih pada peluncuran berikutnya. Tutup OBS sebelum Apply atau Revert: OBS menulis ulang `user.ini` saat keluar. Apply pertama mem-backup pilihan sebelumnya dan tema bernama-sama byte-demi-byte.

### Aplikasi Electron

`resources/app.asar` dipindahkan ke `resources/app/app.asar` (saudara `app.asar.unpacked`-nya ikut pindah — pasangan itu berdasarkan nama file, dan memisahkannya merusak setiap modul native), dan `shim.cjs` kecil mengambil slot `resources/app` yang kosong. Shim menyuntikkan stylesheet lalu memuat arsip asli. **Tidak ada byte aplikasi yang ditulis ulang**, hanya direlokasi; `-Revert` memindahkannya langsung kembali.

Stylesheet tidak ditulis untuk aplikasi ini — ia diekstrak dari `wintage.user.js`, jadi setiap perbaikan bevel, scrollbar, dan tangga-tipe yang dibuat untuk peramban mendarat di sini juga, tanpa salinan kedua untuk membusuk.

Dua catatan yang layak diketahui sebelumnya:

- Pendekatan yang jelas — meletakkan `resources/app` di samping arsip dan mengandalkan Electron yang lebih memilihnya — **tidak berfungsi dan gagal senyap**. Electron mencari `app.asar` lebih dulu. Aplikasi menyala sempurna dan tema tidak pernah berjalan.
- Shim sengaja `.cjs`, bukan `.js`. `package.json`-nya disalin dari milik aplikasi agar aplikasi mempertahankan nama dan versinya (nama menentukan tempat userData tinggal — shim yang mengganti namanya memindahkan aplikasi ke profil kosong). Jika manifes itu menyatakan `"type": "module"`, shim `.js` mati pada `require` pertamanya.

### Aplikasi desktop Claude: in-place, dan bingkai yang benar-benar ia gambar

Claude tidak dapat menggunakan relokasi di atas, karena `OnlyLoadAppFromAsar` terkunci aktif — Electron memuat `resources/app.asar` dan tidak yang lain, jadi shim di `resources/app` tidak akan pernah berjalan. Ia ditambal **in place** sebagai gantinya: arsip di-backup, `main` `package.json`-nya ditulis ulang ke `"../wintage-shim.cjs"` (dipadding ke panjang byte yang sama, sehingga setiap offset di arsip tetap valid), dan hash integritas per-file diperbarui agar cocok. `-Revert` memulihkan backup.

Penginstal membaca fuse **sebelum memindahkan apa pun** dan menolak dengan alasan saat fuse memblokirnya — `EnableEmbeddedAsarIntegrityValidation` akan membuat penulisan ulang di atas gagal saat peluncuran, bukan saat pemasangan. Periksa aplikasi apa pun sendiri:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Bagian kedua ini masalah yang jauh lebih senyap. `BrowserWindow` Claude merender cangkang tipis dan **seluruh aplikasi yang terlihat adalah `WebContentsView`** yang melekat padanya. Shim dulu mengait `browser-window-created`, jadi ia menyuntikkan stylesheet ke cangkang, melaporkan sukses ke `wintage-status.txt`, dan tidak mengubah apa pun yang bisa Anda lihat. Ia kini mengait `web-contents-created`, yang mencakup konten jendela, `WebContentsView`s, `BrowserView`s, tamu `<webview>` dan popup sekaligus.

### Obsidian

Tema komunitas ditulis ke `.obsidian/themes/` setiap vault — keenam belas palet sekaligus, persis seperti target VS Code, jadi Anda beralih di antara mereka di **Settings → Appearance** tanpa menjalankan ulang apa pun. Template diturunkan dari tema buatan tangan `VintageWin95` yang sudah ada di vault, setiap warna diganti dengan token yang sebanding. `-Palette <slug>` menentukan mana yang aktif saat pemasangan; `appearance.json` di-backup dulu, dan `-Revert` hanya menghapus tema `Wintage *` dan memulihkan pilihan Anda sebelumnya — tema buatan tangan di vault yang sama tidak pernah disentuh.

### SAIPENVIEW

Frontend-nya sudah mendeklarasikan nama token Wintage di `:root`-nya sendiri, jadi tambalan ini menulis ulang **hanya nilai token** — tidak pernah selektor, font, lebar batas, atau padding. Tidak ada yang memengaruhi box model yang berubah, jadi teks tidak bisa bergeser. Itu disengaja: pendekatan sebelumnya menambahkan seluruh stylesheet peramban di atas, dan `wintage.css` ditulis untuk halaman web arbitrer — selektor universal memaksa font, tangga ukuran, batas 2px, dan tinggi kontrol. Pada aplikasi yang sudah memiliki tata letaknya sendiri, itu memindahkan segalanya.

Diverifikasi dengan menopengi setiap hex dan mem-diff terhadap backup: identik secara struktural, hanya literal warna yang berbeda. `--link` dilaporkan tidak dideklarasikan di sana (tautan markdown-nya membaca `--accentTeal`, yang ini set) alih-alih disuntikkan — menambahkan variabel yang tidak pernah dibaca aplikasi hanya akan menjadi beban mati.

### MPC-HC (K-Lite)

Win32 native, tanpa stylesheet dan tanpa titik injeksi, dan warna tema gelapnya terkompilasi ke dalam program — tidak ada nilai registri yang mengeksposnya. Jadi target ini **tidak dapat membawa palet**. Yang ia lakukan: menyalakan tema gelap dan menerapkan aturan tipografi UI.md ke OSD, satu-satunya permukaan yang diizinkan MPC-HC dikendalikan pengguna. Pengaturan sebelumnya diekspor ke `desktop/backup/mpc-hc-settings.reg` dulu.

Tutup MPC-HC sebelum menerapkan: ia menulis ulang pengaturannya saat keluar.

## Membangun ulang

Semuanya di bawah `desktop/out/` dihasilkan dari `themes/*.json`. Itu tidak dilacak di git (T-160), jadi klon segar harus membangunnya sekali sebelum memasang:

```powershell
node ..\tools\build-desktop.js          # bangun ulang semua target
node ..\tools\build-desktop.js --check  # exit 1 jika ada yang basi
```

`release.ps1` menjalankan build dan setiap gerbang, jadi rilis tidak dapat mengirimkan output yang melenceng dari palet.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
