# Wintage para aplicações de desktop

O userscript tematiza a web. Isto tematiza os programas à volta dela, a partir das mesmas paletas, para que o navegador e as aplicações deixem de discordar sobre o que significa dourado-escuro.

Há uma regra por trás de cada decisão aqui: **as aplicações atualizam-se sozinhas, e uma atualização não deve quebrar nada silenciosamente.** Onde um alvo tem um lugar no seu próprio perfil, o tema vai para lá e sobrevive a atualizações. Onde não tem, o instalador é escrito para ser re-executado — e diz isso, em vez de fingir que persistiu.

## O GUI

Duplo clique em **`Wintage Installer.vbs`** na raiz do repositório para o abrir sem janela de consola, ou execute isto diretamente para diagnóstico:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Lista de temas com chips de cor, os alvos encontrados nesta máquina, uma pré-visualização Win95 em direto e todos os vinte e um tokens de cor como amostras editáveis. Editar qualquer amostra bifurca a paleta para **Custom** em vez de alterar um tema distribuído por baixo de si. O painel à direita mostra contraste WCAG em direto para os três tokens que transportam texto — uma paleta que falha aí é recusada pelo gate de build de qualquer forma, por isso é melhor vê-la antes do Apply do que depois.

Os alvos estão divididos em duas listas acessíveis por teclado: **MY APPS** contém as ferramentas portáteis/de árvore de código CodeNomad, SAIPENVIEW, SmartVac e WildRift; **POPULAR APPS** contém Windows, OBS, terminais, editores e o outro software instalado. ALL/NONE e Apply/Revert operam em ambas as listas sem alterar o seu agrupamento.

A janela usa a paleta que está prestes a instalar. Essa é a pré-visualização mais rápida disponível, e mantém a ferramenta honesta: uma paleta que torna esta janela ilegível é visivelmente ilegível.

Apply delega para `install.ps1`. Há exatamente um caminho de código que instala um tema, por isso o GUI não pode afastar-se da linha de comandos.

## A linha de comandos

```powershell
.\desktop\install.ps1                                  # o que está aqui, o que está tematizado, com que paleta
.\desktop\install.ps1 -Target freebuff -Palette klite  # uma aplicação, uma paleta
.\desktop\install.ps1 -Target all -Palette goldendefault # tudo
.\desktop\install.ps1 -Target all -WhatIf              # dizer o que mudaria, não tocar em nada
.\desktop\install.ps1 -Target freebuff -Revert         # desfazer um
```

`-Palette` tem como predefinição `goldendefault` (**Golden Default**). O GUI abre na mesma paleta e verifica todos os alvos disponíveis. Repintar uma aplicação já tematizada funciona enquanto esta está a correr; uma primeira instalação não, porque o arquivo está em uso.

## O que cada alvo pode ser tematizado de facto

| alvo | mecanismo | sobrevive a uma atualização da aplicação |
|---|---|---|
| `windows` | `.theme` de utilizador: modo escuro do sistema/aplicação, acento e funções de cores clássicas | sim — instalado na sua pasta local de Temas do Windows |
| `browsers` | deteta perfis Chromium instalados + portáteis, prepara o tema chrome selecionado e abre as páginas de confirmação do Tampermonkey/tema do navegador | sim, após um **Load unpacked** por perfil |
| `terminal` | esquema do Windows Terminal + predefinições de todos os perfis, Consolas 12 com aliasing | sim — as definições estão no seu perfil |
| `conhost` | predefinições de `HKCU\Console` + todos os perfis cmd/PowerShell existentes | sim — instantâneo exato dos valores tocados |
| `obs` | variante `.ovt` do OBS 30.2+ + ID de tema ativo no `user.ini` | sim — vive no seu perfil |
| `antigravity`, `vscode` | extensão de tema de cores em `~/.antigravity/extensions` / `~/.vscode/extensions` | **sim** — vive no seu perfil |
| `freebuff`, `antigravity-app`, `codenomad` | shim Electron, ver abaixo | não — re-execute o instalador |
| `claude` | shim Electron, corrigido no lugar — ver abaixo | não — uma atualização cria uma nova pasta `app-<version>` |
| `mpchc` | registo, tema escuro + tipografia do OSD apenas | não — o MPC-HC reescreve as suas definições ao sair |
| `obsidian` | tema comunitário por cofre, todas as paletas instaladas de uma vez | **sim** — vive no seu cofre |
| `saipenview` | reescreve os seus próprios valores de token `:root` no `style.css` | não — um ficheiro de código; re-execute após um pull |
| `discord` | CSS colocado na própria pasta de temas do BetterDiscord | sim |
| `totalcmd`, `totalcmd2` | chaves `[Colors]` do `wincmd.ini`; filtros de ficheiros recentes existentes usam a cor de link da paleta | sim — é o seu ini |
| `smartvac`, `wildrift` | tabela de tokens reescrita no próprio código da aplicação | não — um ficheiro de código; re-execute após um pull |

### Remoção de anúncios do FreeBuff

O FreeBuff (aplicação de desktop de assistente de IA) traz a sua própria rede de anúncios: o bundle do renderer (`resources/orchestrator/ui/assets/index-*.js`) renderiza um cartão `sponsored-ad` e um banner de thread, e o orquestrador (`resources/orchestrator/orchestrator.js`) expõe rotas `/api/ad/slot|impression|click` que chamam o leilão de anúncios remoto. O shim apenas tematiza a aplicação; não toca nesses ficheiros.

`desktop/patch-freebuff-ads.js` corta os anúncios ao nível do byte:

- renderer: os pontos de chamada do cartão/banner de anúncio tornam-se `null`, e os métodos do cliente de API `adSlot` / `adImpression` / `adClick` tornam-se no-ops — nada é renderizado, e nenhum pedido `/api/ad/*` sai do renderer;
- orquestrador: as três rotas `/api/ad/*` deixam de chamar a rede de anúncios, e o pedido inline de anúncio da volta ao vivo (`maybeRequestAd`) é curto-circuitado.

O nome do bundle incorpora um hash de build, por isso o patch descobre o bundle atual a partir do `index.html` em vez de fornecer um payload bloqueado à versão — é isso que o faz sobreviver a atualizações. Os originais são copiados para `_orig-backup-<timestamp>/` na pasta de instalação; `--revert` restaura o mais recente.

**Versões futuras são tratadas em duas camadas independentes:**

1. **Patch de bytes com fallbacks de regex.** Cada alvo tem uma string exata para o build atual *e* um fallback de expressão regular ancorado naquilo que um minificador não pode renomear — os literais de caminho `/api/ad/*`, o discriminador de protocolo `case"ad":`, a classe `sponsored-ad` e as colocações `variant:"banner"` / `variant:"card"`. O orquestrador não é minificado (nomes legíveis como `maybeRequestAd` e `app.ads.slotAd`), por isso as suas strings exatas duram muito tempo; o bundle do renderer é minificado, por isso os seus fallbacks de regex assumem o controlo no momento em que o próximo build renomeia os seus identificadores.
2. **Bloqueio ao nível do shim (`targets/electron/shim.cjs`).** Independente do bundle por completo: qualquer fetch/XHR para um URL `/api/ad/` é rejeitado dentro da página, e qualquer elemento cuja classe contenha `sponsored-ad` é escondido no momento em que aparece. Mesmo um bundle totalmente novo que este script ainda não conhece não consegue mostrar um anúncio.

```powershell
node .\desktop\patch-freebuff-ads.js           # patch (faz backup primeiro)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patch + som de conclusão personalizado (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # que marcadores de anúncio este build carrega?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

É executado automaticamente como parte de `install.ps1 -Target freebuff`, e deve ser re-executado após cada atualização do FreeBuff (as atualizações restauram os ficheiros de stock). Se um build mudar de forma, o script nomeia o alvo que já não corresponde — execute `--scan` para ver o que o novo build ainda carrega e atualize as strings lá.

**Som de conclusão do FreeBuff.** O renderer reproduz `chime-<hash>.mp3` quando uma volta termina. O patch encontra-o da mesma forma que encontra o bundle (o nome incorpora um hash de build), por isso `--sound <file>` instala o seu próprio áudio (wav/mp3/ogg/flac/m4a/aac) por cima e mantém o ficheiro de stock como `chime-*.mp3.bak`; `--revert` restaura-o. `--verify` informa qual está ativo.

### Botão de som do FreeBuff (GUI)

`WintageInstaller.ps1` tem um pequeno botão **FB SOUND** sob a pilha APPLY / REVERT. Ele apenas armazena uma *preferência*; `install.ps1 -Target freebuff` lê o mesmo ficheiro e passa-o ao patch como `--sound`, por isso os anúncios e o som são aplicados numa execução:

- **Clique esquerdo** — escolha um ficheiro de áudio (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) e ouça-o imediatamente: PCM WAV através de System.Media.SoundPlayer, todos os outros formatos através de um WPF MediaPlayer (Media Foundation, assíncrono, para a janela nunca congelar). A escolha é lembrada em `%APPDATA%\Wintage\freebuff-sound.txt` (por máquina, fora do checkout git, exatamente como as pastas de código-fonte lembradas).
- **Clique direito** — limpe a preferência de volta para o chime de stock do FreeBuff (também para qualquer pré-visualização que ainda esteja a tocar).
- **COPY** — copia o áudio escolhido para o próprio repositório (`sounds\freebuff.<ext>`, mantendo a extensão de origem) e re-aponta a preferência para essa cópia, para que o som sobreviva à eliminação ou mudança do ficheiro original. Ativado apenas enquanto um som personalizado está definido; re-copiar simplesmente sobrescreve a cópia do repositório. A pasta `sounds/` é conteúdo git-rastreável normal, por isso cometê-la faz o som sobreviver também a re-clones.

Apenas contentores de áudio reconhecidos são pré-visualizados — o cabeçalho é sondado primeiro, para que uma escolha não-audio seja anunciada em vez de tocar silenciosamente nada.

O botão lê `ON` enquanto um som personalizado está definido; pairar sobre ele mostra o caminho. Aplique o alvo `freebuff` depois (marque FreeBuff + APPLY, ou execute `install.ps1 -Target freebuff` a partir de um terminal) para que tenha efeito.

### Terminais

`terminal` escreve um esquema de cores `Wintage` em todos os ficheiros de definições do Windows Terminal detetados (estável, Preview ou não-empacotado) e seleciona-o através de `profiles.defaults`, juntamente com Consolas 12 seguro para consola e texto com aliasing. O ficheiro original é mantido byte-por-byte ao lado e `-Revert` restaura-o.

`conhost` cobre o `cmd.exe` clássico, o Windows PowerShell, perfis de consola Git CMD/Bash e outros filhos existentes de `HKCU\Console`. Escreve a tabela completa de 16 cores da paleta tanto nas predefinições de raiz como em cada override existente, depois restaura apenas os valores que tocou. Aplica Consolas também aí, porque a Verdana proporcional colide dentro da grelha de células de largura fixa usada por ambos os hosts de terminal.

### Navegadores e Tampermonkey

`browsers` encontra perfis Chrome, Edge, Brave, Cent, Vivaldi e Opera a partir de localizações instaladas e do root portátil para onde o apontar (`-PortableRoot`, ou a entrada `portable` lembrada no `paths.json`). O seu status mostra tanto o número de perfis como quantos contêm Tampermonkey. Apply copia o tema chrome do navegador escolhido para a pasta estável `%LOCALAPPDATA%\Wintage\browser-theme`, coloca esse caminho na área de transferência e abre cada perfil exato em `chrome://extensions` mais a página Install/Update do userscript Wintage. Perfis sem Tampermonkey também recebem a sua página do Chrome Web Store.

O Chromium proíbe deliberadamente a instalação silenciosa de extensões fora da loja numa máquina Windows não gerida. A primeira instalação de tema de navegador precisa, portanto, de uma confirmação **Developer mode → Load unpacked** por perfil. Escolha o caminho copiado; depois disso, o Wintage continua a substituir a mesma pasta estável quando as paletas mudam. Confirme também **Install/Update** no Tampermonkey. Nenhum `Preferences`, Secure Preferences ou ficheiro LevelDB do Tampermonkey do navegador é editado pelas costas do navegador. Se o Tampermonkey não estivesse presente, instale-o a partir do separador da loja aberto e atualize o separador `wintage.user.js` já aberto para obter o ecrã de Instalação.

### Windows

`windows` instala e ativa imediatamente um `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme` endereçado por conteúdo. Começa a partir do tema ativo e substitui apenas as secções documentadas de cor, cursor e estilo visual. O papel de parede, os sons e os ícones do ambiente de trabalho permanecem inalterados; os cursores mudam intencionalmente para o esquema `___CURRENT___` instalado. O primeiro tema ativo é guardado byte-por-byte como `Wintage.original.theme`; mudanças de paleta mantêm essa linha de base, e `-Revert` ativa-o novamente. Os controlos modernos do Windows ainda vêm do estilo visual Aero assinado — o Wintage altera o seu modo escuro suportado, acento e entradas de cores clássicas do sistema em vez de substituir ficheiros `.msstyles` protegidos. As legendas ativas e inativas partilham a cor de superfície elevada e suave da paleta; o destaque brilhante fica reservado para os limites de texto/seleção. O acento de legenda inativa anterior é fotografado separadamente e restaurado exatamente por `-Revert`. O hash de conteúdo dá ao Windows um novo alvo de associação de ficheiros quando a mesma paleta é reconstruída, para que reaplicar uma paleta atualizada não seja confundido com um no-op; o ficheiro Wintage substituído é removido depois de o Windows confirmar o novo ativo.

### OBS Studio

`obs` gera uma variante OBS 30.2+ sobre a base mantida Yami Classic, instala-a em `%APPDATA%\obs-studio\themes` e escreve o seu ID de tema estável no `user.ini`, para que a paleta Wintage escolhida já esteja selecionada no próximo arranque. Feche o OBS antes de Apply ou Revert: o OBS reescreve o `user.ini` ao sair. O primeiro apply faz backup tanto da seleção anterior como de qualquer tema com o mesmo nome byte-por-byte.

### Aplicações Electron

`resources/app.asar` é movido para `resources/app/app.asar` (o seu irmão `app.asar.unpacked` move-se com ele — esse emparelhamento é por nome de ficheiro, e separá-lo quebra todos os módulos nativos), e um pequeno `shim.cjs` ocupa o slot `resources/app` desocupado. O shim injeta a folha de estilos e depois carrega o arquivo original. **Nenhum byte da aplicação é reescrito**, apenas realocado; `-Revert` move-o diretamente de volta.

A folha de estilos não é escrita para estas aplicações — é extraída de `wintage.user.js`, por isso cada correção de bevel, scrollbar e escada de tipos feita para o navegador também chega aqui, sem segunda cópia para apodrecer.

Duas notas que vale a pena ter antecipadamente:

- A abordagem óbvia — colocar `resources/app` ao lado do arquivo e confiar em o Electron o preferir — **não funciona e falha silenciosamente**. O Electron procura `app.asar` primeiro. A aplicação inicia perfeitamente e o tema nunca corre.
- O shim é `.cjs`, não `.js`, de propósito. O seu `package.json` é copiado do próprio da aplicação para que esta mantenha o seu nome e versão (o nome decide onde vive o userData — um shim que o renomeie move a aplicação para um perfil vazio). Se esse manifesto disser `"type": "module"`, um shim `.js` morre no seu primeiro `require`.

### A aplicação de desktop do Claude: no lugar, e o quadro em que realmente desenha

O Claude não pode usar a realocação acima, porque `OnlyLoadAppFromAsar` está fundido — o Electron carrega `resources/app.asar` e mais nada, por isso um shim em `resources/app` nunca pode correr. É corrigido **no lugar** em vez disso: o arquivo é copiado, o seu `main` no `package.json` é reescrito para `"../wintage-shim.cjs"` (preenchido para o mesmo comprimento de bytes, para que cada offset no arquivo permaneça válido), e o hash de integridade por ficheiro é atualizado para corresponder. `-Revert` restaura o backup.

O instalador ainda lê os fuses **antes de mover qualquer coisa** e recusa com uma razão quando estes o bloqueiam — `EnableEmbeddedAsarIntegrityValidation` faria a reescrita acima falhar no arranque em vez de na instalação. Verifique qualquer aplicação você mesmo:

```powershell
node ..\tools\electron-fuses.js "<caminho para o exe da aplicação>"
```

A segunda metade disto foi um problema muito mais silencioso. O `BrowserWindow` do Claude renderiza uma casca fina e **toda a aplicação visível é uma `WebContentsView`** anexada a ela. O shim costumava enganchar `browser-window-created`, por isso injetava a folha de estilos na casca, reportava sucesso ao `wintage-status.txt` e não mudava nada que pudesse ver. Agora engancha `web-contents-created`, que cobre conteúdos de janela, `WebContentsView`s, `BrowserView`s, convidados `<webview>` e popups igualmente.

### Obsidian

Um tema comunitário é escrito no `.obsidian/themes/` de cada cofre — todas as dezasseis paletas de uma vez, exatamente como o alvo VS Code, para que alterne entre elas em **Settings → Appearance** sem re-executar nada. O template foi derivado do tema `VintageWin95` feito à mão que já estava no cofre, cada cor substituída pelo token a que equivalia. `-Palette <slug>` define qual está ativo na instalação; `appearance.json` é copiado primeiro, e `-Revert` remove apenas os temas `Wintage *` e restaura a sua escolha anterior — um tema feito à mão no mesmo cofre nunca é tocado.

### SAIPENVIEW

O seu frontend já declara os nomes de token do Wintage no seu próprio `:root`, por isso este patch reescreve **apenas os valores de token** — nunca um seletor, uma fonte, uma largura de borda ou um padding. Nada que afete o box model muda, por isso o texto não pode deslocar-se. Isso é deliberado: a abordagem anterior anexava toda a folha de estilos do navegador por cima, e o `wintage.css` é escrito para páginas web arbitrárias — seletores universais que forçam a fonte, a escada de tamanhos, bordas de 2px e alturas de controlo. Numa aplicação que já tem o seu próprio layout, isso move tudo.

Verificado mascarando cada hex e comparando com o backup: estruturalmente idêntico, apenas literais de cor diferem. `--link` é reportado como não declarado lá (os seus links markdown leem `--accentTeal`, que isto define) em vez de injetado — adicionar uma variável que a aplicação nunca lê seria peso morto.

### MPC-HC (K-Lite)

Win32 nativo, sem folha de estilos e sem ponto de injeção, e as cores do seu tema escuro são compiladas no programa — nenhum valor de registo as expõe. Portanto, este alvo **não pode carregar uma paleta**. O que faz: ativa o tema escuro e aplica as regras de tipografia do UI.md ao OSD, que é a única superfície que o MPC-HC deixa um utilizador controlar. As definições anteriores são exportadas para `desktop/backup/mpc-hc-settings.reg` primeiro.

Feche o MPC-HC antes de aplicar: ele reescreve as suas definições ao sair.

## Reconstrução

Tudo sob `desktop/out/` é gerado a partir de `themes/*.json`. Não é rastreado no git (T-160), por isso um clone novo deve construir uma vez antes de instalar:

```powershell
node ..\tools\build-desktop.js          # reconstruir todos os alvos
node ..\tools\build-desktop.js --check  # sair 1 se algo estiver obsoleto
```

`release.ps1` executa o build e todos os gates, por isso um release não pode enviar output que se desviou das paletas.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
