# saitranslate scratch: desktop/README.md delta, batch 2 of 3 (hi, hr, hu, id, it, ja, ko, nl, no, pl)
DOC = {
    'hi': {
        'fonts_head': '### फ़ॉन्ट: नाम से, कभी इंस्टॉल नहीं',
        'q': [
            '`qbittorrent` एक **अनपैक्ड** Qt UI थीम `%APPDATA%\\qBittorrent\\themes\\wintage` में लिखता है — एक `config.json` (जिसमें `Palette.*` की भूमिकाएँ और qBittorrent के अपने संदर्भ रंग: ट्रांसफ़र सूची की अवस्थाएँ, लॉग गंभीरता) और उसके पास एक `stylesheet.qss` (2px की बेवेल, सीधे कोने और Verdana, जिन्हें कोई पैलेट व्यक्त नहीं कर सकती) — फिर `General\\CustomUIThemePath` को उसी `config.json` पर इंगित करता है और `General\\UseCustomUITheme=true` सेट करता है।',
            'जान-बूझकर `.qbtheme` बंडल के बजाय अनपैक्ड: `.qbtheme` एक Qt Resource Collection फ़ाइल है और उसे बनाने के लिए मशीन पर मिलते मेजर वर्शन का `rcc` बाइनरी चाहिए, यानी दो टेक्स्ट फ़ाइलों के लिए कंपाइलर पर निर्भरता। qBittorrent फ़ोल्डर रूप को मूल रूप से पढ़ता है (`FolderThemeSource`)।',
            'Apply या Revert से पहले qBittorrent बंद करें: वह बाहर निकलते समय पूरी `qBittorrent.ini` फिर से लिखता है, इसलिए चलते समय किया गया संपादन बंद होते ही खो जाता है — यह टारगेट उस अवस्था में चलने से मना कर देता है, बजाय ऐसी सफलता बताने के जिसे अगला एग्ज़िट मिटा दे। `-Revert` उन दो INI कुंजियों को Wintage से ठीक पहले के मान पर लौटाता है (या न होने पर हटा देता है) और उसी नाम का थीम फ़ोल्डर बाइट-दर-बाइट वापस रख देता है; Apply के बाद की असंबंधित `qBittorrent.ini` एडिट बची रहती हैं।',
            'अप्राप्य: टूलबार और ट्रे आइकन qBittorrent के अपने कंपाइल किए गए रिसोर्स बंडल से आते हैं, इसलिए वे अपने मूल रंग बनाए रखते हैं।',
        ],
        'f': [
            'UI.md का पहला नियम Verdana **बिना एंटी-अलायसिंग** मांगता है। Qt स्टाइलशीट में इसके लिए कोई प्रॉपर्टी नहीं है, और MPC-HC का `OSDFont` केवल एक GDI फ़ेस नाम है — एकमात्र लीवर फ़ेस ही है। रेपो रूट में मौजूद `Verdana_m1.ttf` Verdana की प्रति है जिसमें 3–30 ppem पर पहले से रेंडर किए गए 1bpp बिटमैप स्ट्राइक हैं, जिन्हें रेंडरर आउटलाइन को स्मूद करने के बजाय चुनता है।',
            '`qbittorrent` और `obs` की स्टाइलशीट `Verdana_m1, Verdana` लिखती हैं, और `mpchc` वही नाम लिखता है जिसे मशीन वास्तव में हल करती है। **इंस्टॉलर कभी फ़ॉन्ट इंस्टॉल या अनइंस्टॉल नहीं करता**, और यह अधूरा काम नहीं बल्कि जान-बूझकर है:',
            'फ़ॉन्ट फ़ैमिली (फ़ैमिली, स्टाइल) से हल होती है। Regular + Bold + Italic रजिस्टर करें तो हर उपभोक्ता सही हल करता है; **एक** सदस्य अनरजिस्टर करें तो उस फ़ैमिली को मांगने वाला हर उपभोक्ता बचे हुए सदस्य पर पहुँच जाता है। ऐसी मशीन पर जो `HKLM\\...\\FontSubstitutes` के ज़रिए `MS Shell Dlg 2` — Windows का डायलॉग फ़ॉन्ट — को उसी फ़ैमिली पर अलियास करती है, Regular हटाने से **पूरा डेस्कटॉप इटैलिक** हो जाता है, उन विंडो शीर्षकों समेत जो DWM पहले ही कैश कर चुका है, और वापस पाने के लिए लॉग-ऑफ़ ज़रूरी है। इसे कोई रेफ़रेंस काउंटिंग ठीक नहीं करती: असर पूरी मशीन पर है और थीम इंस्टॉलर का वहाँ कोई काम नहीं।',
            'इसलिए फ़ेस एक बार का, स्पष्ट उपयोगकर्ता-कार्य है: `Verdana_m1.ttf` पर राइट-क्लिक → **Install** (प्रति-उपयोगकर्ता, एडमिन की ज़रूरत नहीं), फिर टारगेट दोबारा लागू करें। फ़ेस न हो तो टारगेट एक बार बता देते हैं, समाधान बताते हैं, और साधारण Verdana पर लौट जाते हैं — एंटी-अलायस्ड, पर आपकी पीठ पीछे मशीन पर कुछ नहीं किया जाता।',
        ],
    },
    'hr': {
        'fonts_head': '### Fontovi: imenovani, nikad instalirani',
        'q': [
            '`qbittorrent` zapisuje **raspakirani** Qt UI motiv u `%APPDATA%\\qBittorrent\\themes\\wintage` — `config.json` (role `Palette.*` plus vlastite kontekstne boje qBittorrenta: stanja popisa prijenosa, ozbiljnosti dnevnika) i uz njega `stylesheet.qss` (2px kosine, pravi kutovi i Verdana, što paleta ne može izraziti) — zatim usmjerava `General\\CustomUIThemePath` na taj `config.json` i postavlja `General\\UseCustomUITheme=true`.',
            'Raspakirano, a ne kao `.qbtheme` paket, namjerno: `.qbtheme` je datoteka vrste Qt Resource Collection i za izradu bi na stroju trebao `rcc` s istom glavnom verzijom, dakle ovisnost o prevoditelju zbog dvije tekstualne datoteke. qBittorrent čita oblik mape izvorno (`FolderThemeSource`).',
            'Zatvorite qBittorrent prije Apply ili Revert: pri izlasku prepisuje cijeli `qBittorrent.ini`, pa se izmjena načinjena dok radi gubi pri zatvaranju — cilj odbija raditi u tom stanju umjesto da prijavi uspjeh koji sljedeći izlazak briše. `-Revert` vraća dva INI ključa na njihove točne vrijednosti prije Wintagea (ili ih uklanja ako nisu postojali) i vraća svaku istoimenu mapu motiva bajt po bajt; nepovezane izmjene `qBittorrent.ini` načinjene nakon Applyja ostaju.',
            'Nedostupno: ikone alatne trake i sistemske trake dolaze iz vlastitog prevedenog paketa resursa qBittorrenta, pa zadržavaju izvorne boje.',
        ],
        'f': [
            'Prvi zakon u UI.md traži Verdanu **bez zaglađivanja rubova**. Qt stil nema svojstvo za to, a `OSDFont` u MPC-HC-u samo je naziv GDI pisma — jedina poluga je samo pismo. `Verdana_m1.ttf` u korijenu repozitorija kopija je Verdane s unaprijed iscrtanim 1bpp bitmapnim rezovima pri 3–30 ppem, koje iscrtavač radije koristi od zaglađivanja obrisa.',
            'Stilovi `qbittorrent` i `obs` navode `Verdana_m1, Verdana`, a `mpchc` navodi ono od dvoga koje stroj doista razriješi. **Instalater nikad ne instalira ni ne uklanja font**, i to je namjerno, a ne nedovršeno:',
            'Obitelj fonta razrješava se po (obitelj, rez). Registrirajte Regular + Bold + Italic i svaki će je potrošač ispravno razriješiti; odjavite **jednog** člana i svaki potrošač koji traži tu obitelj pokazat će na preostalog člana. Na stroju koji `MS Shell Dlg 2` — Windowsov font dijaloga — preko `HKLM\\...\\FontSubstitutes` poistovjećuje s tom obitelji, uklanjanje Regularа okreće **cijelu radnu površinu u kurziv**, uključujući naslove prozora koje je DWM već predmemorio, a za povratak je potrebna odjava. Nikakvo brojanje referenci to ne rješava: domet je na cijelom stroju, a instalater motiva ondje nema što raditi.',
            'Pismo je zato jednokratna, izričita radnja korisnika: desni klik na `Verdana_m1.ttf` → **Install** (po korisniku, bez administratora), zatim ponovno primijenite cilj. Ako pismo nedostaje, ciljevi to kažu jednom, navedu rješenje i vrate se na standardnu Verdanu — zaglađenu, ali na stroju se ništa ne čini iza vaših leđa.',
        ],
    },
    'hu': {
        'fonts_head': '### Betűtípusok: megnevezve, sosem telepítve',
        'q': [
            'A `qbittorrent` egy **kicsomagolt** Qt felületi témát ír a `%APPDATA%\\qBittorrent\\themes\\wintage` mappába — egy `config.json`-t (a `Palette.*` szerepek, valamint a qBittorrent saját kontextusszínei: átviteli lista állapotai, naplósúlyosságok), mellé pedig egy `stylesheet.qss`-t (a 2px-es ferde élek, a derékszögű sarkok és a Verdana, amit egy paletta nem tud kifejezni) — majd a `General\\CustomUIThemePath` kulcsot erre a `config.json`-ra állítja, és bekapcsolja a `General\\UseCustomUITheme=true` értéket.',
            'Kicsomagolva, nem `.qbtheme` csomagként — szándékosan: a `.qbtheme` Qt Resource Collection fájl, előállításához egyező főverziójú `rcc` bináris kellene a gépre, azaz fordítófüggőség két szövegfájl kedvéért. A qBittorrent a mappás formát natívan olvassa (`FolderThemeSource`).',
            'Apply vagy Revert előtt zárja be a qBittorrentet: kilépéskor az egész `qBittorrent.ini`-t újraírja, így a futás közben végzett módosítás bezáráskor elveszik — a cél inkább megtagadja a működést ebben az állapotban, mint hogy olyan sikert jelentsen, amelyet a következő kilépés töröl. A `-Revert` visszaállítja a két INI-kulcsot a Wintage előtti pontos értékére (vagy eltávolítja őket, ha nem voltak), és bájtpontosan visszatesz minden azonos nevű témamappát; az Apply után végzett, nem kapcsolódó `qBittorrent.ini`-módosítások megmaradnak.',
            'Nem érhető el: az eszköztár- és tálcaikonok a qBittorrent saját fordított erőforráscsomagjából származnak, ezért megtartják eredeti színeiket.',
        ],
        'f': [
            'Az UI.md első törvénye Verdanát kér **él-lesimítás nélkül**. Qt stíluslapnak nincs erre tulajdonsága, az MPC-HC `OSDFont` értéke pedig csupán egy GDI betűnév — az egyetlen eszköz maga a betűtípus. A repó gyökerében lévő `Verdana_m1.ttf` a Verdana másolata, előre renderelt 1bpp bittérképes metszetekkel 3–30 ppem méretben; a renderelő ezeket előnyben részesíti a körvonal lesimításával szemben.',
            'A `qbittorrent` és `obs` stíluslapok a `Verdana_m1, Verdana` nevet adják meg, az `mpchc` pedig azt, amelyiket a gép valóban felold. **A telepítő soha nem telepít és nem távolít el betűtípust**, és ez szándékos, nem befejezetlen:',
            'A betűcsalád a (család, metszet) párral oldódik fel. Regisztráljon Regular + Bold + Italic metszetet, és minden fogyasztó helyesen oldja fel; törölje **egy** tag regisztrációját, és minden fogyasztó, amely ezt a családot kéri, egy megmaradt tagra mutat. Olyan gépen, amely a `MS Shell Dlg 2`-t — a Windows párbeszédablak-betűjét — a `HKLM\\...\\FontSubstitutes` kulcson át erre a családra álnevesíti, a Regular eltávolítása **a teljes asztalt dőltre** váltja, azokkal az ablakcímekkel együtt, amelyeket a DWM már gyorsítótárazott, és visszanyerni csak kijelentkezéssel lehet. Ezen semmilyen referenciaszámlálás nem segít: a hatókör az egész gépre terjed, és egy tématelepítőnek ott nincs keresnivalója.',
            'A betűtípus ezért egyszeri, kifejezett felhasználói művelet: jobb kattintás a `Verdana_m1.ttf`-re → **Install** (felhasználónként, rendszergazda nélkül), majd alkalmazza újra a célt. Ha a betűtípus hiányzik, a célok egyszer jelzik, megnevezik a megoldást, és visszaállnak a szokásos Verdanára — lesimítva, de semmi nem történik a gépen a hátad mögött.',
        ],
    },
    'id': {
        'fonts_head': '### Font: disebut namanya, tidak pernah dipasang',
        'q': [
            '`qbittorrent` menulis tema UI Qt **yang tidak dipaketkan** ke `%APPDATA%\\qBittorrent\\themes\\wintage` — sebuah `config.json` (peran `Palette.*` plus warna konteks milik qBittorrent sendiri: keadaan daftar transfer, tingkat keparahan log) dan `stylesheet.qss` di sebelahnya (bevel 2px, sudut siku, dan Verdana, yang tidak bisa diungkapkan palet) — lalu mengarahkan `General\\CustomUIThemePath` ke `config.json` itu dan menyetel `General\\UseCustomUITheme=true`.',
            'Tidak dipaketkan, bukan dalam bundel `.qbtheme` — memang disengaja: `.qbtheme` adalah berkas Qt Resource Collection dan untuk membuatnya diperlukan biner `rcc` dengan versi mayor yang cocok di mesin, artinya ketergantungan kompilator demi dua berkas teks. qBittorrent membaca bentuk folder secara asli (`FolderThemeSource`).',
            'Tutup qBittorrent sebelum Apply atau Revert: ia menulis ulang seluruh `qBittorrent.ini` saat keluar, sehingga perubahan yang dilakukan saat ia berjalan terbuang saat ditutup — target menolak berjalan dalam keadaan itu daripada melaporkan keberhasilan yang dihapus oleh penutupan berikutnya. `-Revert` mengembalikan dua kunci INI ke nilai persisnya sebelum Wintage (atau menghapusnya jika tidak ada) dan mengembalikan folder tema bernama sama secara bita demi bita; perubahan `qBittorrent.ini` lain yang dibuat setelah Apply tetap bertahan.',
            'Tidak terjangkau: ikon bilah alat dan baki berasal dari bundel sumber daya terkompilasi qBittorrent sendiri, jadi keduanya mempertahankan warna aslinya.',
        ],
        'f': [
            'Hukum 1 di UI.md meminta Verdana **tanpa penghalusan tepi**. Stylesheet Qt tidak punya properti untuk itu, dan `OSDFont` MPC-HC hanyalah nama muka GDI — satu-satunya tuas adalah muka font itu sendiri. `Verdana_m1.ttf` di akar repo adalah salinan Verdana yang membawa goresan bitmap 1bpp yang sudah dirender pada 3–30 ppem, yang dipakai perender alih-alih menghaluskan garis luarnya.',
            'Stylesheet `qbittorrent` dan `obs` menyebut `Verdana_m1, Verdana`, dan `mpchc` menyebut salah satu yang benar-benar diresolusi mesin. **Pemasang tidak pernah memasang atau mencopot font**, dan itu memang disengaja, bukan belum selesai:',
            'Keluarga font diresolusi berdasarkan (keluarga, gaya). Daftarkan Regular + Bold + Italic dan setiap pemakai akan meresolusi dengan benar; cabut pendaftaran **satu** anggotanya dan setiap pemakai yang meminta keluarga itu akan menunjuk ke anggota yang tersisa. Pada mesin yang mengalias `MS Shell Dlg 2` — font dialog Windows — ke keluarga itu melalui `HKLM\\...\\FontSubstitutes`, menghapus Regular membuat **seluruh desktop menjadi miring**, termasuk judul jendela yang sudah di-cache DWM, dan perlu logoff untuk mengembalikannya. Tidak ada penghitungan referensi yang memperbaikinya: radiusnya seluas mesin, dan pemasang tema tidak punya urusan di sana.',
            'Jadi muka font adalah tindakan pengguna sekali dan eksplisit: klik kanan `Verdana_m1.ttf` → **Install** (per pengguna, tanpa admin), lalu terapkan ulang target. Bila muka font tidak ada, target mengatakannya sekali, menyebut solusinya, dan kembali ke Verdana bawaan — dihaluskan, tapi tidak ada yang dikerjakan pada mesin di belakang Anda.',
        ],
    },
    'it': {
        'fonts_head': '### Font: nominati, mai installati',
        'q': [
            '`qbittorrent` scrive un tema UI Qt **non impacchettato** in `%APPDATA%\\qBittorrent\\themes\\wintage` — un `config.json` (i ruoli `Palette.*` più i colori di contesto propri di qBittorrent: stati della lista trasferimenti, gravità del registro) e accanto uno `stylesheet.qss` (gli smussi da 2px, gli angoli squadrati e Verdana, che una palette non può esprimere) — poi punta `General\\CustomUIThemePath` a quel `config.json` e imposta `General\\UseCustomUITheme=true`.',
            'Non impacchettato invece che come bundle `.qbtheme`, di proposito: un `.qbtheme` è un file Qt Resource Collection e per produrlo servirebbe sulla macchina un binario `rcc` con la stessa versione maggiore, cioè una dipendenza da compilatore per due file di testo. qBittorrent legge la forma a cartella in modo nativo (`FolderThemeSource`).',
            'Chiudi qBittorrent prima di Apply o Revert: riscrive l’intero `qBittorrent.ini` all’uscita, quindi una modifica fatta mentre è in esecuzione viene persa alla chiusura — il target si rifiuta di funzionare in quello stato invece di riportare un successo che l’uscita successiva cancella. `-Revert` riporta le due chiavi INI ai loro valori esatti precedenti a Wintage (o le rimuove se non c’erano) e rimette a posto byte per byte ogni cartella di tema con lo stesso nome; le modifiche non correlate a `qBittorrent.ini` fatte dopo Apply sopravvivono.',
            'Non raggiungibile: le icone della barra degli strumenti e dell’area di notifica provengono dal bundle di risorse compilato di qBittorrent, quindi mantengono i colori originali.',
        ],
        'f': [
            'La legge 1 di UI.md chiede Verdana **senza antialiasing**. Un foglio di stile Qt non ha una proprietà per farlo, e `OSDFont` di MPC-HC è solo un nome di carattere GDI — l’unica leva è il carattere stesso. `Verdana_m1.ttf` nella radice del repository è una copia di Verdana con tratti bitmap 1bpp pre-renderizzati a 3–30 ppem, che un motore di rendering preferisce al lisciamento del contorno.',
            'I fogli di stile `qbittorrent` e `obs` nominano `Verdana_m1, Verdana`, e `mpchc` nomina quella delle due che la macchina risolve davvero. **L’installer non installa né disinstalla mai un font**, ed è una scelta deliberata, non un lavoro incompiuto:',
            'Una famiglia di caratteri si risolve per (famiglia, stile). Registra Regular + Bold + Italic e ogni consumatore risolve correttamente; deregistra **un** membro e ogni consumatore che chiede quella famiglia punterà a un membro sopravvissuto. Su una macchina che aliasa `MS Shell Dlg 2` — il font delle finestre di dialogo di Windows — a quella famiglia tramite `HKLM\\...\\FontSubstitutes`, rimuovere Regular rende **l’intero desktop in corsivo**, comprese le barre del titolo che il DWM ha già messo in cache, e serve una disconnessione per riaverle. Nessun conteggio dei riferimenti lo risolve: il raggio d’azione è su tutta la macchina e un installer di temi non ha nulla da fare lì.',
            'Il carattere è quindi un’azione una tantum ed esplicita dell’utente: clic destro su `Verdana_m1.ttf` → **Install** (per utente, senza amministratore), poi riapplica il target. Se il carattere manca, i target lo dicono una volta, nominano la soluzione e ripiegano sulla Verdana standard — con antialiasing, ma nulla viene fatto alla macchina alle tue spalle.',
        ],
    },
    'ja': {
        'fonts_head': '### フォント: 名前を挙げるだけで、決してインストールしない',
        'q': [
            '`qbittorrent` は**展開済み**の Qt UI テーマを `%APPDATA%\\qBittorrent\\themes\\wintage` に書き込みます — `config.json`（`Palette.*` の役割に加え、qBittorrent 自身の文脈色：転送リストの状態、ログの重要度）と、その隣の `stylesheet.qss`（2px の面取り、直角の角、そしてパレットでは表現できない Verdana）です — その後 `General\\CustomUIThemePath` をその `config.json` に向け、`General\\UseCustomUITheme=true` を設定します。',
            'あえて `.qbtheme` バンドルではなく展開形式にしています。`.qbtheme` は Qt Resource Collection ファイルで、生成するには同じメジャーバージョンの `rcc` バイナリがマシンに必要となり、テキストファイル 2 つのためにコンパイラ依存を持ち込むことになります。qBittorrent はフォルダ形式をネイティブに読み込みます（`FolderThemeSource`）。',
            'Apply や Revert の前に qBittorrent を終了してください。終了時に `qBittorrent.ini` 全体を書き直すため、起動中に行った編集は終了時に破棄されます — このターゲットはその状態での実行を拒否し、次回の終了で消える「成功」を報告したりはしません。`-Revert` は 2 つの INI キーを Wintage 以前の正確な値に戻し（存在しなかった場合は削除し）、同名のテーマフォルダをバイト単位で復元します。Apply 後に加えた無関係な `qBittorrent.ini` の編集は残ります。',
            '到達不可：ツールバーとトレイのアイコンは qBittorrent 自身のコンパイル済みリソースバンドル由来なので、標準の色のままです。',
        ],
        'f': [
            'UI.md の第一法則は、**アンチエイリアスなし**の Verdana を求めます。Qt スタイルシートにそのためのプロパティはなく、MPC-HC の `OSDFont` は単なる GDI の書体名です — 唯一の手段は書体そのものです。リポジトリ直下の `Verdana_m1.ttf` は Verdana の複製で、3–30 ppem の事前レンダリング済み 1bpp ビットマップストライクを持ち、レンダラは輪郭を滑らかにする代わりにこれを使います。',
            '`qbittorrent` と `obs` のスタイルシートは `Verdana_m1, Verdana` を指定し、`mpchc` はマシンが実際に解決する方を指定します。**インストーラはフォントをインストールもアンインストールもしません**。これは未完成ではなく意図的です：',
            'フォントファミリは（ファミリ、スタイル）で解決されます。Regular + Bold + Italic を登録すればどの利用側も正しく解決しますが、**1 つ**のメンバーを解除すると、そのファミリを求めるすべての利用側が残ったメンバーを指すようになります。`HKLM\\...\\FontSubstitutes` 経由で `MS Shell Dlg 2` — Windows のダイアログフォント — をそのファミリに別名付けしているマシンでは、Regular を削除すると DWM が既にキャッシュしたウィンドウタイトルを含め**デスクトップ全体が斜体**になり、元に戻すにはログオフが必要です。参照カウントでは解決しません：影響範囲はマシン全体に及び、テーマインストーラの領分ではありません。',
            'したがって書体は一度きりの明示的なユーザー操作です：`Verdana_m1.ttf` を右クリック → **Install**（ユーザー単位、管理者不要）、そのうえでターゲットを再適用してください。書体がなければターゲットが一度だけその旨を告げ、対処法を示し、標準の Verdana にフォールバックします — アンチエイリアスは効きますが、あなたの知らないうちにマシンへ手を入れることはありません。',
        ],
    },
    'ko': {
        'fonts_head': '### 글꼴: 이름만 지정하고, 절대 설치하지 않습니다',
        'q': [
            '`qbittorrent` 는 **압축을 풀어 둔** Qt UI 테마를 `%APPDATA%\\qBittorrent\\themes\\wintage` 에 씁니다 — `config.json`( `Palette.*` 역할과 qBittorrent 자체의 상황별 색상: 전송 목록 상태, 로그 심각도)과 그 옆의 `stylesheet.qss`(2px 베벨, 직각 모서리, 그리고 팔레트가 표현할 수 없는 Verdana)입니다 — 그런 다음 `General\\CustomUIThemePath` 를 그 `config.json` 으로 지정하고 `General\\UseCustomUITheme=true` 를 설정합니다.',
            '`.qbtheme` 번들 대신 압축을 푼 형태를 쓴 것은 의도적입니다. `.qbtheme` 는 Qt Resource Collection 파일이라 만들려면 같은 주 버전의 `rcc` 실행 파일이 그 컴퓨터에 있어야 하므로, 텍스트 파일 두 개 때문에 컴파일러 의존성이 생깁니다. qBittorrent 는 폴더 형태를 기본으로 읽습니다(`FolderThemeSource`).',
            'Apply 나 Revert 전에 qBittorrent 를 닫으십시오. 종료할 때 `qBittorrent.ini` 전체를 다시 쓰므로 실행 중에 한 편집은 닫을 때 버려집니다 — 이 대상은 그 상태에서 실행을 거부하며, 다음 종료가 지워 버릴 성공을 보고하지 않습니다. `-Revert` 는 두 INI 키를 Wintage 이전의 정확한 값으로 되돌리고(없었으면 제거합니다) 같은 이름의 테마 폴더를 바이트 단위로 되돌립니다. Apply 이후에 한 무관한 `qBittorrent.ini` 편집은 그대로 남습니다.',
            '도달할 수 없음: 도구 모음과 트레이 아이콘은 qBittorrent 자체의 컴파일된 리소스 번들에서 오므로 기본 색을 유지합니다.',
        ],
        'f': [
            'UI.md 의 첫 번째 법칙은 **안티앨리어싱 없는** Verdana 를 요구합니다. Qt 스타일시트에는 그런 속성이 없고, MPC-HC 의 `OSDFont` 는 그냥 GDI 서체 이름입니다 — 유일한 수단은 서체 자체입니다. 저장소 루트의 `Verdana_m1.ttf` 는 3–30 ppem 의 미리 렌더링된 1bpp 비트맵 스트라이크를 담은 Verdana 복사본이며, 렌더러는 윤곽을 부드럽게 하는 대신 이것을 사용합니다.',
            '`qbittorrent` 와 `obs` 스타일시트는 `Verdana_m1, Verdana` 를 지정하고, `mpchc` 는 컴퓨터가 실제로 해석하는 쪽을 지정합니다. **설치 프로그램은 글꼴을 설치하거나 제거하지 않습니다**. 이것은 미완성이 아니라 의도입니다:',
            '글꼴 패밀리는 (패밀리, 스타일)로 해석됩니다. Regular + Bold + Italic 를 등록하면 모든 사용자가 올바르게 해석하지만, 멤버 **하나**를 등록 해제하면 그 패밀리를 요청하는 모든 사용자가 남은 멤버를 가리키게 됩니다. `HKLM\\...\\FontSubstitutes` 를 통해 `MS Shell Dlg 2` — Windows 대화 상자 글꼴 — 를 그 패밀리에 별칭한 컴퓨터에서는 Regular 를 제거하면 DWM 이 이미 캐시한 창 제목까지 포함해 **바탕 화면 전체가 기울임꼴**이 되고, 되돌리려면 로그오프가 필요합니다. 참조 카운팅으로는 해결되지 않습니다. 영향 범위가 컴퓨터 전체이고, 테마 설치 프로그램이 거기에 관여할 일은 없습니다.',
            '그래서 서체는 사용자가 한 번 명시적으로 하는 작업입니다: `Verdana_m1.ttf` 를 마우스 오른쪽 단추로 클릭 → **Install**(사용자 단위, 관리자 불필요), 그다음 대상을 다시 적용하십시오. 서체가 없으면 대상이 한 번 알리고 해결책을 말한 뒤 기본 Verdana 로 물러납니다 — 안티앨리어싱되지만, 몰래 컴퓨터를 건드리지는 않습니다.',
        ],
    },
    'nl': {
        'fonts_head': '### Lettertypen: genoemd, nooit geïnstalleerd',
        'q': [
            '`qbittorrent` schrijft een **uitgepakt** Qt UI-thema naar `%APPDATA%\\qBittorrent\\themes\\wintage` — een `config.json` (de `Palette.*`-rollen plus qBittorrents eigen contextkleuren: statussen van de overdrachtslijst, logboekernst) en ernaast een `stylesheet.qss` (de 2px-afschuiningen, de rechte hoeken en Verdana, wat een palet niet kan uitdrukken) — en wijst daarna `General\\CustomUIThemePath` naar die `config.json` en zet `General\\UseCustomUITheme=true`.',
            'Uitgepakt in plaats van een `.qbtheme`-bundel, met opzet: een `.qbtheme` is een Qt Resource Collection-bestand en zou een `rcc`-binair bestand met hetzelfde hoofdversienummer op de machine vereisen, dus een compilerafhankelijkheid voor twee tekstbestanden. qBittorrent leest de mapvorm native (`FolderThemeSource`).',
            'Sluit qBittorrent voordat je Apply of Revert gebruikt: het herschrijft bij afsluiten de hele `qBittorrent.ini`, dus een wijziging die tijdens het draaien is gemaakt gaat bij het sluiten verloren — het doel weigert in die toestand te werken in plaats van een succes te melden dat de volgende afsluiting wist. `-Revert` zet de twee INI-sleutels terug op hun exacte waarden van vóór Wintage (of verwijdert ze als ze er niet waren) en zet een gelijknamige themamap byte voor byte terug; niet-gerelateerde wijzigingen in `qBittorrent.ini` na Apply blijven bestaan.',
            'Niet bereikbaar: de pictogrammen in de werkbalk en het systeemvak komen uit qBittorrents eigen gecompileerde bronnenbundel en behouden dus hun oorspronkelijke kleuren.',
        ],
        'f': [
            'Wet 1 van UI.md vraagt om Verdana **zonder antialiasing**. Een Qt-stylesheet heeft daar geen eigenschap voor, en `OSDFont` van MPC-HC is slechts een GDI-lettertypenaam — de enige hefboom is het lettertype zelf. `Verdana_m1.ttf` in de hoofdmap van de repo is een kopie van Verdana met vooraf gerenderde 1bpp-bitmapstrepen op 3–30 ppem, die een renderer verkiest boven het gladstrijken van de omtrek.',
            'De stylesheets van `qbittorrent` en `obs` noemen `Verdana_m1, Verdana`, en `mpchc` noemt degene die de machine werkelijk resolveert. **De installer installeert of verwijdert nooit een lettertype**, en dat is opzet en niet onaf:',
            'Een lettertypefamilie wordt geresolveerd op (familie, stijl). Registreer Regular + Bold + Italic en elke gebruiker resolveert correct; deregistreer **één** lid en elke gebruiker die die familie opvraagt, wijst naar een overlevend lid. Op een machine die `MS Shell Dlg 2` — het Windows-dialoogvensterlettertype — via `HKLM\\...\\FontSubstitutes` aan die familie aliast, zet het verwijderen van Regular **het hele bureaublad cursief**, inclusief venstertitels die de DWM al heeft gecachet, en een afmelding is nodig om dat terug te draaien. Geen enkele referentietelling lost dat op: de schade reikt machinebreed en een thema-installer heeft daar niets te zoeken.',
            'Het lettertype is daarom een eenmalige, uitdrukkelijke gebruikershandeling: rechtsklik op `Verdana_m1.ttf` → **Install** (per gebruiker, geen beheerder nodig) en pas daarna het doel opnieuw toe. Ontbreekt het lettertype, dan zeggen de doelen dat één keer, noemen de oplossing en vallen terug op standaard-Verdana — gladgestreken, maar er gebeurt niets met de machine achter je rug.',
        ],
    },
    'no': {
        'fonts_head': '### Skrifter: navngitt, aldri installert',
        'q': [
            '`qbittorrent` skriver et **utpakket** Qt-uitema til `%APPDATA%\\qBittorrent\\themes\\wintage` — en `config.json` (rollene `Palette.*` pluss qBittorrents egne kontekstfarger: tilstander i overføringslisten, loggalvorlighet) og en `stylesheet.qss` ved siden av (2px-fasene, de rette hjørnene og Verdana, som en palett ikke kan uttrykke) — og peker deretter `General\\CustomUIThemePath` på den `config.json` og setter `General\\UseCustomUITheme=true`.',
            'Utpakket i stedet for en `.qbtheme`-pakke, med vilje: en `.qbtheme` er en Qt Resource Collection-fil og ville kreve en `rcc`-binærfil med samme hovedversjon på maskinen for å bli laget, altså en kompilatoravhengighet for to tekstfiler. qBittorrent leser mappeformen innebygd (`FolderThemeSource`).',
            'Lukk qBittorrent før Apply eller Revert: den skriver hele `qBittorrent.ini` på nytt ved avslutning, så en endring gjort mens den kjører blir forkastet ved lukking — målet nekter å kjøre i den tilstanden i stedet for å rapportere en suksess som neste avslutning sletter. `-Revert` fører de to INI-nøklene tilbake til sine nøyaktige verdier før Wintage (eller fjerner dem hvis de ikke fantes) og legger en eventuell temamappe med samme navn tilbake byte for byte; urelaterte endringer i `qBittorrent.ini` gjort etter Apply overlever.',
            'Ikke tilgjengelig: ikonene i verktøylinjen og systemkurven kommer fra qBittorrents egen kompilerte ressursbunt, så de beholder originalfargene.',
        ],
        'f': [
            'Lov 1 i UI.md krever Verdana **uten kantutjevning**. Et Qt-stilark har ingen egenskap for det, og MPC-HCs `OSDFont` er bare et GDI-navn — den eneste spaken er selve skriften. `Verdana_m1.ttf` i repoets rot er en kopi av Verdana med forhåndsrendrede 1bpp-bitmapsnitt ved 3–30 ppem, som en renderer foretrekker framfor å jevne ut omrisset.',
            'Stilarkene til `qbittorrent` og `obs` oppgir `Verdana_m1, Verdana`, og `mpchc` oppgir den av de to maskinen faktisk løser opp. **Installasjonsprogrammet installerer eller avinstallerer aldri en skrift**, og det er med vilje snarere enn uferdig:',
            'En skriftfamilie løses opp etter (familie, snitt). Registrer Regular + Bold + Italic, og enhver forbruker løser opp riktig; avregistrer **ett** medlem, og enhver forbruker som ber om den familien peker på et gjenlevende medlem. På en maskin som aliaser `MS Shell Dlg 2` — Windows-dialogskriften — til den familien via `HKLM\\...\\FontSubstitutes`, gjør fjerning av Regular **hele skrivebordet kursivt**, inkludert vindusittler DWM allerede har bufret, og det kreves utlogging for å få det tilbake. Ingen referansetelling fikser det: skadeomfanget er maskinomfattende, og et temainstallasjonsprogram har ingenting der å gjøre.',
            'Skriften er derfor en engangs, uttrykkelig brukerhandling: høyreklikk på `Verdana_m1.ttf` → **Install** (per bruker, ingen administrator), og bruk deretter målet på nytt. Mangler skriften, sier målene det én gang, navngir løsningen og faller tilbake på vanlig Verdana — kantutjevnet, men ingenting gjøres med maskinen bak ryggen din.',
        ],
    },
    'pl': {
        'fonts_head': '### Czcionki: nazwane, nigdy nie instalowane',
        'q': [
            '`qbittorrent` zapisuje **rozpakowany** motyw interfejsu Qt w `%APPDATA%\\qBittorrent\\themes\\wintage` — plik `config.json` (role `Palette.*` oraz własne kolory kontekstowe qBittorrenta: stany listy transferów, wagi dziennika) i obok niego `stylesheet.qss` (2px fazowania, proste narożniki i Verdana, czego paleta nie potrafi wyrazić) — a następnie kieruje `General\\CustomUIThemePath` na ten `config.json` i ustawia `General\\UseCustomUITheme=true`.',
            'Rozpakowany, a nie jako pakiet `.qbtheme` — celowo: `.qbtheme` to plik Qt Resource Collection i do jego wytworzenia potrzebny byłby na maszynie plik `rcc` o zgodnej wersji głównej, czyli zależność od kompilatora dla dwóch plików tekstowych. qBittorrent czyta postać folderu natywnie (`FolderThemeSource`).',
            'Zamknij qBittorrent przed Apply lub Revert: przy zakończeniu nadpisuje cały `qBittorrent.ini`, więc zmiana wykonana podczas jego pracy przepada przy zamknięciu — cel odmawia działania w tym stanie, zamiast zgłaszać sukces, który zmiecie następne zakończenie. `-Revert` przywraca dwa klucze INI do dokładnych wartości sprzed Wintage (albo je usuwa, jeśli ich nie było) i odkłada z powrotem każdy folder motywu o tej samej nazwie, bajt po bajcie; niezwiązane zmiany w `qBittorrent.ini` wykonane po Apply przetrwają.',
            'Nieosiągalne: ikony paska narzędzi i zasobnika pochodzą z własnego skompilowanego pakietu zasobów qBittorrenta, więc zachowują oryginalne kolory.',
        ],
        'f': [
            'Prawo 1 z UI.md wymaga Verdany **bez wygładzania**. Arkusz stylów Qt nie ma na to właściwości, a `OSDFont` w MPC-HC to zwykła nazwa kroju GDI — jedyną dźwignią jest sam krój. `Verdana_m1.ttf` w katalogu głównym repozytorium to kopia Verdany z wstępnie wyrenderowanymi bitmapowymi krojami 1bpp przy 3–30 ppem, których moduł renderujący używa zamiast wygładzania konturu.',
            'Arkusze stylów `qbittorrent` i `obs` wskazują `Verdana_m1, Verdana`, a `mpchc` wskazuje ten z dwóch, który maszyna faktycznie rozwiąże. **Instalator nigdy nie instaluje ani nie odinstalowuje czcionki** i jest to zamierzone, a nie niedokończone:',
            'Rodzina czcionek jest rozwiązywana przez parę (rodzina, krój). Zarejestruj Regular + Bold + Italic, a każdy odbiorca rozwiąże ją poprawnie; wyrejestruj **jeden** element, a każdy odbiorca proszący o tę rodzinę wskaże na ocalały element. Na maszynie, która aliasuje `MS Shell Dlg 2` — czcionkę okien dialogowych Windows — do tej rodziny przez `HKLM\\...\\FontSubstitutes`, usunięcie Regular pochyla **cały pulpit**, łącznie z tytułami okien, które DWM już zbuforował, a przywrócenie wymaga wylogowania. Żadne liczenie odwołań tego nie naprawi: zasięg jest maszynowy, a instalator motywów nie ma tam czego szukać.',
            'Krój jest więc jednorazowym, wyraźnym działaniem użytkownika: kliknij prawym przyciskiem `Verdana_m1.ttf` → **Install** (dla użytkownika, bez administratora), a potem zastosuj cel ponownie. Jeśli kroju nie ma, cele powiedzą o tym raz, wskażą rozwiązanie i cofną się do zwykłej Verdany — wygładzonej, ale nic nie dzieje się na maszynie za twoimi plecami.',
        ],
    },
}
