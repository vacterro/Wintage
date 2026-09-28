# saitranslate scratch: desktop/README.md delta, batch 3 of 3 (pt, ro, sk, sv, th, tr, uk, vi, zh)
DOC = {
    'pt': {
        'fonts_head': '### Fontes: nomeadas, nunca instaladas',
        'q': [
            '`qbittorrent` escreve um tema de interface Qt **desempacotado** em `%APPDATA%\\qBittorrent\\themes\\wintage` — um `config.json` (as funções `Palette.*` mais as cores de contexto do próprio qBittorrent: estados da lista de transferências, gravidades do registro) e um `stylesheet.qss` ao lado (os biséis de 2px, os cantos retos e a Verdana, que uma paleta não consegue expressar) — e depois aponta `General\\CustomUIThemePath` para esse `config.json` e define `General\\UseCustomUITheme=true`.',
            'Desempacotado em vez de um pacote `.qbtheme`, de propósito: um `.qbtheme` é um arquivo Qt Resource Collection e exigiria um binário `rcc` de versão principal correspondente na máquina para ser produzido, ou seja, uma dependência de compilador para dois arquivos de texto. O qBittorrent lê a forma de pasta nativamente (`FolderThemeSource`).',
            'Feche o qBittorrent antes de Apply ou Revert: ele reescreve todo o `qBittorrent.ini` ao sair, então uma edição feita enquanto ele roda é descartada ao fechar — o alvo se recusa a rodar nesse estado em vez de relatar um sucesso que a próxima saída apaga. `-Revert` devolve as duas chaves do INI aos seus valores exatos de antes do Wintage (ou as remove, se não existiam) e recoloca qualquer pasta de tema de mesmo nome byte a byte; edições não relacionadas no `qBittorrent.ini` feitas depois do Apply sobrevivem.',
            'Não alcançável: os ícones da barra de ferramentas e da bandeja vêm do próprio pacote de recursos compilado do qBittorrent, então mantêm as cores originais.',
        ],
        'f': [
            'A lei 1 do UI.md pede Verdana **sem suavização**. Uma folha de estilos Qt não tem propriedade para isso, e o `OSDFont` do MPC-HC é apenas um nome de fonte GDI — a única alavanca é a própria fonte. O `Verdana_m1.ttf` na raiz do repositório é uma cópia da Verdana com traços de bitmap 1bpp pré-renderizados a 3–30 ppem, que um renderizador prefere em vez de suavizar o contorno.',
            'As folhas de estilo de `qbittorrent` e `obs` nomeiam `Verdana_m1, Verdana`, e `mpchc` nomeia a que a máquina realmente resolver. **O instalador nunca instala nem desinstala uma fonte**, e isso é deliberado e não inacabado:',
            'Uma família de fontes é resolvida por (família, estilo). Registre Regular + Bold + Italic e todo consumidor resolverá corretamente; desregistre **um** membro e todo consumidor que pedir essa família passará a apontar para um membro sobrevivente. Numa máquina que alias `MS Shell Dlg 2` — a fonte de diálogos do Windows — a essa família via `HKLM\\...\\FontSubstitutes`, remover Regular deixa **a área de trabalho inteira em itálico**, incluindo títulos de janela que o DWM já tem em cache, e é preciso sair da sessão para recuperar. Nenhuma contagem de referências resolve isso: o alcance é de máquina inteira e um instalador de temas não tem nada a fazer ali.',
            'A fonte é, portanto, uma ação pontual e explícita do usuário: clique com o botão direito em `Verdana_m1.ttf` → **Install** (por usuário, sem administrador) e reaplique o alvo. Se a fonte estiver ausente, os alvos avisam uma vez, nomeiam a solução e recorrem à Verdana padrão — suavizada, mas nada é feito na máquina pelas suas costas.',
        ],
    },
    'ro': {
        'fonts_head': '### Fonturi: numite, niciodată instalate',
        'q': [
            '`qbittorrent` scrie o temă de interfață Qt **neîmpachetată** în `%APPDATA%\\qBittorrent\\themes\\wintage` — un `config.json` (rolurile `Palette.*` plus culorile proprii de context ale qBittorrent: stările listei de transferuri, gravitățile jurnalului) și un `stylesheet.qss` alături (teșiturile de 2px, colțurile drepte și Verdana, pe care o paletă nu le poate exprima) — apoi îndreaptă `General\\CustomUIThemePath` către acel `config.json` și setează `General\\UseCustomUITheme=true`.',
            'Neîmpachetat, nu ca pachet `.qbtheme`, intenționat: un `.qbtheme` este un fișier Qt Resource Collection și ar cere pe mașină un binar `rcc` cu aceeași versiune majoră, adică o dependență de compilator pentru două fișiere text. qBittorrent citește forma de dosar nativ (`FolderThemeSource`).',
            'Închide qBittorrent înainte de Apply sau Revert: rescrie tot `qBittorrent.ini` la ieșire, așa că o modificare făcută cât rulează se pierde la închidere — ținta refuză să ruleze în această stare în loc să raporteze un succes pe care următoarea ieșire îl șterge. `-Revert` readuce cele două chei INI la valorile lor exacte de dinainte de Wintage (sau le elimină dacă lipseau) și pune la loc orice dosar de temă cu același nume, octet cu octet; modificările nelegate din `qBittorrent.ini` făcute după Apply supraviețuiesc.',
            'Inaccesibil: pictogramele din bara de instrumente și din zona de notificare provin din pachetul de resurse compilat al qBittorrent, așa că își păstrează culorile originale.',
        ],
        'f': [
            'Prima lege din UI.md cere Verdana **fără netezirea marginilor**. Un stylesheet Qt nu are proprietate pentru asta, iar `OSDFont` din MPC-HC este doar un nume de font GDI — singura pârghie este fontul însuși. `Verdana_m1.ttf` din rădăcina depozitului este o copie a Verdanei cu trasee bitmap 1bpp prerandate la 3–30 ppem, pe care un motor de randare le preferă netezirii conturului.',
            'Stylesheet-urile `qbittorrent` și `obs` numesc `Verdana_m1, Verdana`, iar `mpchc` numește pe care dintre ele o rezolvă efectiv mașina. **Instalatorul nu instalează și nu dezinstalează niciodată un font**, iar asta e deliberat, nu neterminat:',
            'O familie de fonturi se rezolvă după (familie, stil). Înregistrează Regular + Bold + Italic și fiecare consumator o rezolvă corect; dezînregistrează **un** membru și fiecare consumator care cere acea familie va indica un membru supraviețuitor. Pe o mașină care alias-ează `MS Shell Dlg 2` — fontul ferestrelor de dialog Windows — către acea familie prin `HKLM\\...\\FontSubstitutes`, eliminarea lui Regular face **întregul desktop cursiv**, inclusiv titlurile ferestrelor pe care DWM le-a pus deja în cache, iar revenirea cere delogare. Niciun numărător de referințe nu rezolvă asta: raza de impact este la nivel de mașină, iar un instalator de teme nu are ce căuta acolo.',
            'Așadar fontul este o acțiune unică, explicită, a utilizatorului: clic dreapta pe `Verdana_m1.ttf` → **Install** (per utilizator, fără administrator), apoi reaplică ținta. Dacă fontul lipsește, țintele spun asta o dată, numesc soluția și revin la Verdana standard — netezită, dar nimic nu se face pe mașină pe la spatele tău.',
        ],
    },
    'sk': {
        'fonts_head': '### Písma: pomenované, nikdy nenainštalované',
        'q': [
            '`qbittorrent` zapisuje **rozbalenú** Qt tému rozhrania do `%APPDATA%\\qBittorrent\\themes\\wintage` — súbor `config.json` (roly `Palette.*` plus vlastné kontextové farby qBittorrentu: stavy zoznamu prenosov, závažnosti denníka) a vedľa neho `stylesheet.qss` (2px skosenia, pravé rohy a Verdana, čo paleta nedokáže vyjadriť) — potom nasmeruje `General\\CustomUIThemePath` na tento `config.json` a nastaví `General\\UseCustomUITheme=true`.',
            'Rozbalene, a nie ako balík `.qbtheme` — zámerne: `.qbtheme` je súbor typu Qt Resource Collection a na jeho vytvorenie by bol na stroji potrebný `rcc` so zhodnou hlavnou verziou, teda závislosť na prekladači kvôli dvom textovým súborom. qBittorrent číta priečinkovú podobu natívne (`FolderThemeSource`).',
            'Pred Apply alebo Revert qBittorrent zatvorte: pri ukončení prepisuje celý `qBittorrent.ini`, takže úprava vykonaná počas behu sa pri zatvorení zahodí — cieľ v takom stave odmietne pracovať, namiesto toho, aby hlásil úspech, ktorý nasledujúce ukončenie zmaže. `-Revert` vráti dva kľúče v INI na presné hodnoty pred Wintage (alebo ich odstráni, ak neboli) a vráti každý rovnomenný priečinok témy bajt po bajte; nesúvisiace úpravy `qBittorrent.ini` vykonané po Apply ostanú.',
            'Nedostupné: ikony panela nástrojov a oznamovacej oblasti pochádzajú z vlastného skompilovaného balíka zdrojov qBittorrentu, takže si zachovávajú pôvodné farby.',
        ],
        'f': [
            'Prvý zákon v UI.md žiada Verdanu **bez vyhladzovania hrán**. Qt stylesheet na to nemá vlastnosť a `OSDFont` v MPC-HC je len názov GDI rezu — jedinou pákou je samotný rez. `Verdana_m1.ttf` v koreni repozitára je kópia Verdany s predvykreslenými 1bpp bitmapovými rezmi pri 3–30 ppem, ktoré vykresľovací engine použije pred vyhladením obrysu.',
            'Stylesheety `qbittorrent` a `obs` uvádzajú `Verdana_m1, Verdana` a `mpchc` uvádza ten z dvoch, ktorý stroj skutočne rozlíši. **Inštalátor písmo nikdy nenainštaluje ani neodstráni**, a to je zámer, nie nedokončená práca:',
            'Rodina písma sa rozlišuje podľa (rodina, rez). Zaregistrujte Regular + Bold + Italic a každý spotrebiteľ ju rozlíši správne; odregistrujte **jedného** člena a každý spotrebiteľ žiadajúci túto rodinu sa presmeruje na prežívajúceho člena. Na stroji, ktorý na túto rodinu cez `HKLM\\...\\FontSubstitutes` aliasuje `MS Shell Dlg 2` — dialógové písmo Windows —, odstránenie Regularu prepne **celú plochu do kurzívy**, vrátane titulkov okien, ktoré má DWM už v pamäti, a späť to vráti len odhlásenie. Žiadne počítanie referencií to nespraví: dopad je v rámci celého stroja a inštalátor tém tam nemá čo robiť.',
            'Rez je preto jednorazová, výslovná akcia používateľa: kliknite pravým na `Verdana_m1.ttf` → **Install** (pre používateľa, bez správcu) a potom cieľ znova použite. Ak rez chýba, ciele to raz povedia, pomenujú riešenie a vrátia sa k štandardnej Verdanе — vyhladenej, ale na stroji sa nič nerobí za vašim chrbtom.',
        ],
    },
    'sv': {
        'fonts_head': '### Typsnitt: namngivna, aldrig installerade',
        'q': [
            '`qbittorrent` skriver ett **uppackat** Qt-gränssnittstema till `%APPDATA%\\qBittorrent\\themes\\wintage` — en `config.json` (rollerna `Palette.*` plus qBittorrents egna kontextfärger: tillstånd i överföringslistan, loggarnas allvarlighetsgrad) och en `stylesheet.qss` bredvid (2px-fasningarna, de raka hörnen och Verdana, som en palett inte kan uttrycka) — och pekar sedan `General\\CustomUIThemePath` mot den `config.json` och sätter `General\\UseCustomUITheme=true`.',
            'Uppackat i stället för ett `.qbtheme`-paket, med avsikt: en `.qbtheme` är en Qt Resource Collection-fil och skulle kräva en `rcc`-binär med matchande huvudversion på maskinen för att tillverkas, alltså ett kompilatorberoende för två textfiler. qBittorrent läser mappformen inbyggt (`FolderThemeSource`).',
            'Stäng qBittorrent före Apply eller Revert: den skriver om hela `qBittorrent.ini` vid avslut, så en ändring gjord medan den körs kastas när den stängs — målet vägrar köra i det tillståndet i stället för att rapportera en framgång som nästa avslut raderar. `-Revert` för tillbaka de två INI-nycklarna till sina exakta värden före Wintage (eller tar bort dem om de saknades) och lägger tillbaka en temamapp med samma namn byte för byte; orelaterade ändringar i `qBittorrent.ini` gjorda efter Apply överlever.',
            'Inte nåbart: ikonerna i verktygsfältet och i aktivitetsfältet kommer från qBittorrents egen kompilerade resursbunt, så de behåller sina ursprungliga färger.',
        ],
        'f': [
            'Lag 1 i UI.md begär Verdana **utan kantutjämning**. Ett Qt-formatmall har ingen egenskap för det, och MPC-HCs `OSDFont` är bara ett GDI-namn — den enda hävstången är själva typsnittet. `Verdana_m1.ttf` i repots rot är en kopia av Verdana med förrenderade 1bpp-bitmapstämplar vid 3–30 ppem, som en renderare föredrar framför att jämna ut konturen.',
            'Formatmallarna för `qbittorrent` och `obs` anger `Verdana_m1, Verdana`, och `mpchc` anger den av de två som maskinen faktiskt löser upp. **Installationsprogrammet installerar eller avinstallerar aldrig ett typsnitt**, och det är med avsikt snarare än ofärdigt:',
            'En typsnittsfamilj löses upp efter (familj, snitt). Registrera Regular + Bold + Italic, och varje konsument löser upp rätt; avregistrera **en** medlem och varje konsument som efterfrågar familjen pekar på en överlevande medlem. På en maskin som aliasar `MS Shell Dlg 2` — Windows dialogtypsnitt — till den familjen via `HKLM\\...\\FontSubstitutes`, gör borttagning av Regular **hela skrivbordet kursivt**, inklusive fönstertitlar som DWM redan cachelagrat, och en utloggning krävs för att få tillbaka det. Ingen referensräkning åtgärdar det: skadeområdet är maskinbrett och ett temainstallationsprogram har inget där att göra.',
            'Typsnittet är därför en engångs, uttrycklig användaråtgärd: högerklicka på `Verdana_m1.ttf` → **Install** (per användare, ingen administratör), och använd sedan målet igen. Saknas typsnittet säger målen det en gång, namnger lösningen och faller tillbaka på vanliga Verdana — kantutjämnad, men ingenting görs med maskinen bakom din rygg.',
        ],
    },
    'th': {
        'fonts_head': '### ฟอนต์: อ้างชื่อ ไม่ติดตั้ง',
        'q': [
            '`qbittorrent` เขียนธีม UI ของ Qt **แบบไม่แพ็ก** ลงใน `%APPDATA%\\qBittorrent\\themes\\wintage` — ไฟล์ `config.json` (บทบาท `Palette.*` บวกสีบริบทของ qBittorrent เอง: สถานะของรายการถ่ายโอน ความรุนแรงของบันทึก) และ `stylesheet.qss` ข้าง ๆ กัน (ขอบเอียง 2px มุมฉาก และ Verdana ซึ่งพาเลตต์แสดงออกไม่ได้) — จากนั้นชี้ `General\\CustomUIThemePath` ไปที่ `config.json` นั้นและตั้ง `General\\UseCustomUITheme=true`',
            'ตั้งใจใช้แบบไม่แพ็กแทนบันเดิล `.qbtheme`: ไฟล์ `.qbtheme` เป็นไฟล์ Qt Resource Collection และต้องใช้ไบนารี `rcc` เวอร์ชันหลักที่ตรงกันบนเครื่องเพื่อสร้าง ซึ่งกลายเป็นการพึ่งพาตัวคอมไพเลอร์เพียงเพื่อไฟล์ข้อความสองไฟล์ ส่วน qBittorrent อ่านรูปแบบโฟลเดอร์ได้เองโดยตรง (`FolderThemeSource`)',
            'ปิด qBittorrent ก่อนกด Apply หรือ Revert: มันเขียน `qBittorrent.ini` ใหม่ทั้งไฟล์ตอนปิด การแก้ไขที่ทำขณะมันทำงานจึงถูกทิ้งตอนปิด — เป้านี้จึงปฏิเสธที่จะทำงานในสภาพนั้น แทนที่จะรายงานความสำเร็จที่การปิดครั้งถัดไปลบทิ้ง `-Revert` คืนค่าคีย์ INI สองคีย์กลับเป็นค่าเดิมก่อน Wintage อย่างแม่นยำ (หรือลบทิ้งถ้าเดิมไม่มี) และวางโฟลเดอร์ธีมชื่อเดียวกันกลับแบบไบต์ต่อไบต์ ส่วนการแก้ไข `qBittorrent.ini` อื่น ๆ ที่ทำหลัง Apply จะอยู่ต่อ',
            'ไปไม่ถึง: ไอคอนบนแถบเครื่องมือและถาดระบบมาจากชุดทรัพยากรที่คอมไพล์ไว้ของ qBittorrent เอง จึงคงสีเดิมไว้',
        ],
        'f': [
            'กฎข้อแรกใน UI.md ต้องการ Verdana **โดยไม่เปิดการปรับขอบให้เรียบ** สไตล์ชีตของ Qt ไม่มีพร็อพเพอร์ตี้นั้น และ `OSDFont` ของ MPC-HC ก็เป็นเพียงชื่อฟอนต์ GDI — คันโยกเดียวคือตัวฟอนต์เอง `Verdana_m1.ttf` ที่รากของรีโปคือสำเนาของ Verdana ที่มีสไตรก์บิตแมป 1bpp เรนเดอร์ไว้ล่วงหน้าที่ 3–30 ppem ซึ่งตัวเรนเดอร์จะเลือกใช้แทนการปรับเส้นรอบนอกให้เรียบ',
            'สไตล์ชีตของ `qbittorrent` และ `obs` ระบุ `Verdana_m1, Verdana` และ `mpchc` ระบุตัวที่เครื่องแก้ได้จริง **ตัวติดตั้งไม่เคยติดตั้งหรือถอนฟอนต์** และนั่นคือความตั้งใจ ไม่ใช่งานค้าง:',
            'ตระกูลฟอนต์ถูกแก้ด้วยคู่ (ตระกูล, สไตล์) ลงทะเบียน Regular + Bold + Italic แล้วผู้ใช้ทั้งหมดจะแก้ได้ถูกต้อง แต่ถ้าถอนการลงทะเบียน **หนึ่ง** สมาชิก ทุกผู้ใช้ที่ขอตระกูลนั้นจะชี้ไปยังสมาชิกที่เหลือ บนเครื่องที่ทำ alias `MS Shell Dlg 2` — ฟอนต์กล่องโต้ตอบของ Windows — ไปยังตระกูลนั้นผ่าน `HKLM\\...\\FontSubstitutes` การลบ Regular จะทำให้ **ทั้งเดสก์ท็อปเป็นตัวเอียง** รวมถึงชื่อหน้าต่างที่ DWM แคชไว้แล้ว และต้องออกจากระบบจึงจะกลับมาได้ ไม่มีการนับรีเฟอเรนซ์ใดแก้ได้ เพราะขอบเขตความเสียหายกินทั้งเครื่อง และตัวติดตั้งธีมไม่ควรเข้าไปยุ่ง',
            'ฟอนต์จึงเป็นการกระทำของผู้ใช้ครั้งเดียวและชัดเจน: คลิกขวาที่ `Verdana_m1.ttf` → **Install** (ต่อผู้ใช้ ไม่ต้องใช้ผู้ดูแลระบบ) แล้วติดตั้งเป้าอีกครั้ง ถ้าฟอนต์หาย เป้าจะบอกครั้งเดียว ระบุวิธีแก้ และถอยกลับไปใช้ Verdana ปกติ — แบบปรับขอบให้เรียบ แต่ไม่มีอะไรถูกทำกับเครื่องคุณลับหลัง',
        ],
    },
    'tr': {
        'fonts_head': '### Yazı tipleri: adıyla anılır, asla kurulmaz',
        'q': [
            '`qbittorrent`, **paketlenmemiş** bir Qt arayüz temasını `%APPDATA%\\qBittorrent\\themes\\wintage` içine yazar — bir `config.json` ( `Palette.*` rolleri ile qBittorrent’in kendi bağlam renkleri: aktarım listesi durumları, günlük önem düzeyleri) ve yanına bir `stylesheet.qss` (2px pah kırıkları, dik köşeler ve bir paletin ifade edemeyeceği Verdana) — ardından `General\\CustomUIThemePath` anahtarını bu `config.json` dosyasına yöneltir ve `General\\UseCustomUITheme=true` ayarını yapar.',
            '`.qbtheme` paketi yerine paketlenmemiş, bilerek: `.qbtheme` bir Qt Resource Collection dosyasıdır ve üretilebilmesi için makinede aynı ana sürümde bir `rcc` ikili dosyası gerekirdi; yani iki metin dosyası için derleyici bağımlılığı. qBittorrent klasör biçimini doğrudan okur (`FolderThemeSource`).',
            'Apply veya Revert öncesi qBittorrent’i kapatın: çıkarken tüm `qBittorrent.ini` dosyasını yeniden yazar, dolayısıyla çalışırken yapılan bir düzenleme kapanışta kaybolur — hedef bu durumda çalışmayı reddeder, bir sonraki çıkışın sileceği bir başarı bildirmez. `-Revert` iki INI anahtarını Wintage öncesi tam değerlerine döndürür (yoklarsa kaldırır) ve aynı adlı tema klasörünü bayt bayt geri koyar; Apply sonrası yapılan ilgisiz `qBittorrent.ini` düzenlemeleri korunur.',
            'Erişilemez: araç çubuğu ve sistem tepsisi simgeleri qBittorrent’in kendi derlenmiş kaynak paketinden gelir, dolayısıyla özgün renklerini korur.',
        ],
        'f': [
            'UI.md’nin 1. yasası Verdana’yı **kenar yumuşatma olmadan** ister. Qt stil sayfasında bunun için bir özellik yoktur ve MPC-HC’nin `OSDFont` değeri düz bir GDI yüz adıdır — tek kaldıraç yüzün kendisidir. Depo kökündeki `Verdana_m1.ttf`, Verdana’nın 3–30 ppem’de önceden oluşturulmuş 1bpp bitmap vuruşları taşıyan bir kopyasıdır; bir oluşturucu bunları dış hattı yumuşatmaya tercih eder.',
            '`qbittorrent` ve `obs` stil sayfaları `Verdana_m1, Verdana` adını verir, `mpchc` ise makinenin gerçekten çözümlediğini. **Kurulum aracı bir yazı tipini asla kurmaz ya da kaldırmaz** ve bu yarım kalmışlık değil bilinçli bir tercihtir:',
            'Bir yazı tipi ailesi (aile, stil) çiftiyle çözümlenir. Regular + Bold + Italic kaydedin, her tüketici doğru çözümler; **tek** üyeyi kayıttan düşürün, o aileyi isteyen her tüketici hayatta kalan bir üyeye yönelir. `MS Shell Dlg 2` — Windows iletişim kutusu yazı tipi — adresini `HKLM\\...\\FontSubstitutes` üzerinden bu aileye takma adla bağlayan bir makinede, Regular’ı kaldırmak DWM’in önbelleğe aldığı pencere başlıkları dahil **tüm masaüstünü italik** yapar ve geri almak için oturumu kapatmak gerekir. Hiçbir başvuru sayımı bunu düzeltmez: etki alanı makine genelindedir ve bir tema kurulum aracının orada işi yoktur.',
            'Bu yüzden yüz, kullanıcının bir kez yaptığı açık bir eylemdir: `Verdana_m1.ttf` dosyasına sağ tıklayın → **Install** (kullanıcı başına, yönetici gerekmez), sonra hedefi yeniden uygulayın. Yüz yoksa hedefler bunu bir kez söyler, çözümü adlandırır ve stok Verdana’ya döner — yumuşatılmış, ama arkanızdan makinede hiçbir şey yapılmaz.',
        ],
    },
    'uk': {
        'fonts_head': '### Шрифти: названі, ніколи не встановлені',
        'q': [
            '`qbittorrent` записує **нерозпаковану** тему інтерфейсу Qt у `%APPDATA%\\qBittorrent\\themes\\wintage` — файл `config.json` (ролі `Palette.*` плюс власні контекстні кольори qBittorrent: стани списку передач, рівні журналу) і поряд `stylesheet.qss` (фаски 2px, прямі кути й Verdana, які палітра не може виразити) — далі спрямовує `General\\CustomUIThemePath` на цей `config.json` і встановлює `General\\UseCustomUITheme=true`.',
            'Нерозпаковано, а не як пакет `.qbtheme` — свідомо: `.qbtheme` є файлом Qt Resource Collection, і для його створення на машині знадобився б `rcc` з такою ж основною версією, тобто залежність від компілятора заради двох текстових файлів. qBittorrent читає теку як форму нативно (`FolderThemeSource`).',
            'Закрийте qBittorrent перед Apply або Revert: він перезаписує весь `qBittorrent.ini` під час виходу, тож редагування, зроблене під час роботи, зникає при закритті — ціль відмовляється працювати в такому стані замість того, щоб звітувати про успіх, який зітре наступний вихід. `-Revert` повертає два ключі INI до точних значень перед Wintage (або видаляє їх, якщо їх не було) і повертає будь-яку однойменну теку теми байт за байтом; не пов’язані з ним правки `qBittorrent.ini`, зроблені після Apply, зберігаються.',
            'Недосяжно: піктограми панелі інструментів і системного лотка походять із власного скомпільованого пакета ресурсів qBittorrent, тож зберігають початкові кольори.',
        ],
        'f': [
            'Перший закон UI.md вимагає Verdana **без згладжування**. У стилі Qt немає властивості для цього, а `OSDFont` у MPC-HC — лише назва гарнітури GDI, тож єдиний важіль — сама гарнітура. `Verdana_m1.ttf` у корені репозиторію — копія Verdana з попередньо відрендереними 1bpp растровими штрихами за 3–30 ppem, які візуалізатор використовує замість згладжування контуру.',
            'Стилі `qbittorrent` і `obs` називають `Verdana_m1, Verdana`, а `mpchc` називає ту з двох, яку машина справді розпізнає. **Інсталятор ніколи не встановлює й не видаляє шрифт**, і це свідомо, а не недороблено:',
            'Гарнітура розпізнається за парою (родина, стиль). Зареєструйте Regular + Bold + Italic, і кожен споживач розпізнає правильно; скасуйте реєстрацію **одного** члена, і кожен споживач, що просить цю родину, вкаже на того, хто залишився. На машині, яка через `HKLM\\...\\FontSubstitutes` псевдонімить `MS Shell Dlg 2` — діалоговий шрифт Windows — на цю родину, видалення Regular робить **увесь робочий стіл курсивним**, разом із заголовками вікон, які DWM уже закешував, і повернути це можна лише виходом із системи. Жодне підрахування посилань цього не виправить: радіус ураження — на всю машину, і інсталяторові тем там немає чого робити.',
            'Тож гарнітура — це одноразова, явна дія користувача: клацніть правою кнопкою на `Verdana_m1.ttf` → **Install** (для користувача, без адміністратора), потім застосуйте ціль знову. Якщо гарнітури немає, цілі скажуть це один раз, назвуть рішення й повернуться до стандартної Verdana — зі згладжуванням, але нічого не робиться на машині за вашою спиною.',
        ],
    },
    'vi': {
        'fonts_head': '### Phông chữ: gọi tên, không bao giờ cài đặt',
        'q': [
            '`qbittorrent` ghi một giao diện Qt **chưa đóng gói** vào `%APPDATA%\\qBittorrent\\themes\\wintage` — một `config.json` (các vai trò `Palette.*` cùng các màu ngữ cảnh riêng của qBittorrent: trạng thái danh sách truyền, mức độ nghiêm trọng của nhật ký) và một `stylesheet.qss` bên cạnh (các góc vát 2px, góc vuông và Verdana, những thứ mà bảng màu không thể diễn đạt) — rồi trỏ `General\\CustomUIThemePath` tới `config.json` đó và đặt `General\\UseCustomUITheme=true`.',
            'Chưa đóng gói thay vì gói `.qbtheme`, là cố ý: `.qbtheme` là tệp Qt Resource Collection và để tạo ra nó cần một tệp nhị phân `rcc` cùng phiên bản chính trên máy, tức là phụ thuộc trình biên dịch chỉ vì hai tệp văn bản. qBittorrent đọc dạng thư mục theo cách gốc (`FolderThemeSource`).',
            'Hãy đóng qBittorrent trước khi Apply hoặc Revert: nó ghi lại toàn bộ `qBittorrent.ini` khi thoát, nên thay đổi thực hiện lúc nó đang chạy sẽ bị bỏ khi đóng — mục tiêu từ chối chạy trong trạng thái đó thay vì báo thành công mà lần thoát kế tiếp sẽ xóa. `-Revert` trả hai khóa INI về đúng giá trị trước Wintage (hoặc xóa chúng nếu trước đó không có) và đặt lại nguyên từng byte thư mục giao diện cùng tên; những sửa đổi không liên quan trong `qBittorrent.ini` thực hiện sau Apply vẫn được giữ.',
            'Không thể với tới: biểu tượng trên thanh công cụ và khay hệ thống đến từ gói tài nguyên đã biên dịch của chính qBittorrent, nên giữ nguyên màu gốc.',
        ],
        'f': [
            'Điều luật 1 trong UI.md yêu cầu Verdana **không khử răng cưa**. Bảng kiểu Qt không có thuộc tính cho việc đó, còn `OSDFont` của MPC-HC chỉ là một tên phông GDI — đòn bẩy duy nhất là chính phông chữ. Tệp `Verdana_m1.ttf` ở gốc kho là bản sao của Verdana mang các nét bitmap 1bpp đã kết xuất trước ở 3–30 ppem, mà bộ kết xuất dùng thay vì làm mịn đường viền.',
            'Bảng kiểu của `qbittorrent` và `obs` ghi `Verdana_m1, Verdana`, còn `mpchc` ghi cái mà máy thực sự phân giải. **Trình cài đặt không bao giờ cài hay gỡ một phông chữ**, và đó là chủ ý chứ không phải việc dở dang:',
            'Một họ phông được phân giải theo cặp (họ, kiểu). Đăng ký Regular + Bold + Italic thì mọi bên dùng đều phân giải đúng; hủy đăng ký **một** thành viên thì mọi bên yêu cầu họ đó sẽ trỏ sang một thành viên còn lại. Trên máy ánh xạ bí danh `MS Shell Dlg 2` — phông hộp thoại của Windows — sang họ đó qua `HKLM\\...\\FontSubstitutes`, việc gỡ Regular khiến **toàn bộ màn hình nền thành chữ nghiêng**, kể cả tiêu đề cửa sổ mà DWM đã lưu đệm, và phải đăng xuất mới lấy lại được. Không cách đếm tham chiếu nào sửa được: phạm vi ảnh hưởng toàn máy, và trình cài đặt giao diện không có việc gì ở đó.',
            'Vì vậy phông chữ là hành động một lần, do người dùng chủ động: nhấp chuột phải vào `Verdana_m1.ttf` → **Install** (theo người dùng, không cần quản trị), rồi áp dụng lại mục tiêu. Nếu thiếu phông, các mục tiêu sẽ nói một lần, chỉ ra cách khắc phục và lùi về Verdana mặc định — có khử răng cưa, nhưng không có gì được làm trên máy sau lưng bạn.',
        ],
    },
    'zh': {
        'fonts_head': '### 字体：只引用名称，从不安装',
        'q': [
            '`qbittorrent` 会把一份**未打包**的 Qt 界面主题写入 `%APPDATA%\\qBittorrent\\themes\\wintage`：一个 `config.json`（`Palette.*` 各项角色，加上 qBittorrent 自身的上下文颜色：传输列表状态、日志级别），以及旁边一个 `stylesheet.qss`（2px 斜面、直角边角，以及调色板无法表达的 Verdana）；随后把 `General\\CustomUIThemePath` 指向该 `config.json` 并设置 `General\\UseCustomUITheme=true`。',
            '刻意采用未打包形式而非 `.qbtheme` 包：`.qbtheme` 是 Qt Resource Collection 文件，生成它需要机器上有一个主版本号匹配的 `rcc` 可执行文件，为了两个文本文件而引入编译器依赖并不划算。qBittorrent 原生支持读取文件夹形式（`FolderThemeSource`）。',
            '在 Apply 或 Revert 之前请关闭 qBittorrent：它在退出时会重写整个 `qBittorrent.ini`，因此运行期间所做的修改会在关闭时被丢弃——该目标在此状态下会拒绝执行，而不是报告一个会被下次退出抹掉的“成功”。`-Revert` 会把两个 INI 键恢复为 Wintage 之前的精确值（若原本不存在则删除），并把任何同名主题文件夹按字节原样放回；Apply 之后对 `qBittorrent.ini` 所做的无关修改仍会保留。',
            '无法覆盖：工具栏与托盘图标来自 qBittorrent 自身已编译的资源包，因此会保持原有配色。',
        ],
        'f': [
            'UI.md 的第一条法则要求 Verdana 且**不做抗锯齿**。Qt 样式表没有对应属性，而 MPC-HC 的 `OSDFont` 只是一个 GDI 字体名——唯一的着力点就是字体本身。仓库根目录的 `Verdana_m1.ttf` 是 Verdana 的副本，带有在 3–30 ppem 预渲染的 1bpp 位图笔画，渲染器会优先使用它而不是平滑轮廓。',
            '`qbittorrent` 与 `obs` 的样式表写的是 `Verdana_m1, Verdana`，而 `mpchc` 写的是机器实际能解析的那一个。**安装器从不安装或卸载字体**，这是有意为之，而不是尚未完成：',
            '字体族按（族、字形）进行解析。注册 Regular + Bold + Italic，所有使用方都能正确解析；但只要注销**其中一员**，所有请求该字体族的使用方都会转向仍然存在的那一员。在通过 `HKLM\\...\\FontSubstitutes` 把 `MS Shell Dlg 2`（Windows 对话框字体）别名到该字体族的机器上，移除 Regular 会让**整个桌面上所有文字变成斜体**，包括 DWM 已经缓存的窗口标题，且必须注销登录才能恢复。任何引用计数都解决不了：影响范围是全机器级别的，主题安装器没有资格涉足那里。',
            '因此字体是用户一次性、明确的操作：右键 `Verdana_m1.ttf` → **Install**（按用户安装，无需管理员），然后重新应用目标。如果字体缺失，目标会提醒一次、指出解决办法，并回退到系统自带 Verdana——带抗锯齿，但不会在你背后对机器做任何改动。',
        ],
    },
}
