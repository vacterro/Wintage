# Wintage

**Tema Vintage Win95 em dourado-escuro para toda a web.** Um userscript Tampermonkey que transforma todos os sites numa aplicação Windows 95 castanho-dourada escura: chanfros 3D nítidos a píxeis, zero cantos arredondados, zero animações, sem flash de hover, Verdana em todo o lado.

[🤍 Apoiar o desenvolvedor](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_A web moderna optimiza a estética à custa da usabilidade. Cantos arredondados substituem a hierarquia visual, animações substituem o feedback, sombras substituem a estrutura, e o minimalismo remove frequentemente exatamente os sinais em que o cérebro se apoia para compreender uma interface._

_O utilizador não deve adivinhar se algo é um botão, um rótulo, um cartão ou apenas texto. O Wintage devolve uma linguagem visual inequívoca: botões em relevo, campos de entrada rebaixados, arestas nítidas, tipografia consistente, zero distração e mudanças de estado instantâneas._

_Cada elemento comunica o seu propósito à primeira vista, reduzindo a carga cognitiva e tornando a web novamente um instrumento preciso em vez de uma coleção de bolhas decorativas._

[Changelog](CHANGELOG.md)

## Instalação

1. Instale o [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Clique em **[Instalar Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — o Tampermonkey abre a página de instalação automaticamente.
3. Pronto. Todos os sites que visita estão agora a correr Windows 95, edição dourado-escura.

## Atualização

- **Automática:** o script tem `@updateURL`/`@downloadURL` a apontar para este repositório, por isso o Tampermonkey obtém novas versões nas suas verificações regulares de atualizações.
- **Atualizar manualmente:** Tampermonkey → **Utilities → Check for userscript updates**, ou simplesmente clique novamente no link de instalação — substitui a versão antiga diretamente, sem desinstalar.
- **Linhas de tema em falta significam script antigo:** o menu é gerado a partir do registo de temas incorporado, e o teste de lançamento exige exatamente uma linha de menu por paleta incorporada. Se o menu estiver mais curto que a lista de paletas abaixo, clique novamente em **Install Wintage** e confirme **Update** no Tampermonkey.

## Dezasseis paletas e um interruptor

O Wintage já não é uma paleta única. Seis são a estrutura do UI.md rodada para outra família de tons (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom pode ser editada e guardada a partir do instalador de desktop, e nove são importadas do [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Cada uma passa WCAG AA nos três tokens que transportam texto — o portão de build rejeita uma paleta que não o faça.

Escolha uma a partir do **menu Tampermonkey** em qualquer página; a escolha é guardada por utilizador, não por site, por isso aplica-se em todos os domínios.

As paletas vivem em `themes/*.json`, fora do script, por uma razão: o Tampermonkey re-descarrega `wintage.user.js` em cada atualização, portanto uma paleta escrita à mão desapareceria. Reaplique-as sobre uma build nova com:

```powershell
.\install-themes.ps1 -Latest
```

## Para além do navegador

As mesmas paletas instalam-se em aplicações de desktop — VS Code e Antigravity como temas de cores, aplicações Electron (Freebuff, Antigravity agent app) através de um shim que injeta exatamente a folha de estilos que este userscript usa. Existe uma pequena GUI para isso:

Clique duas vezes em **`Wintage Installer.vbs`** na raiz do repositório. Abre a GUI sem janela de consola. O antigo launcher `.cmd` reencaminha para o mesmo host oculto; `desktop\WintageInstaller.ps1` pode ser executado diretamente para diagnósticos.

O que cada alvo consegue e não consegue alcançar — incluindo as duas aplicações seladas ou com cores compiladas — está descrito em **[desktop/README.md](desktop/README.md)**.

## Funcionalidades

- **Paleta Golden Default** — tela castanho-preto profundo `#1A1810`, texto dourado `#D4C89A`, realces de chanfro dourados `#F0D060`. Apenas superfícies planas sólidas: sem gradientes, sem desfoque, sem efeitos de transparência.
- **Chanfros 3D clássicos** — botões em relevo, campos de entrada rebaixados, botões pressionados empurram para dentro (com o autêntico deslocamento do rótulo de 1px). Barras de rolagem completas de 16px estilo Win95, com polegar e botões chanfrados.
- **Matador de raios** — `border-radius: 0` aplicado em todo o lado, incluindo variáveis CSS de frameworks (Bootstrap, Material, YouTube, Reddit).
- **Movimento proibido** — todas as transições e animações zeradas. As mudanças de estado são instantâneas, como uma verdadeira interface de 1995.
- **Destaque de hover completamente desativado** — sem linhas de flash branco, sem blocos de tons cinza:
  - as propriedades de preenchimento são cirurgicamente removidas de cada regra CSS `:hover` legível (propriedades funcionais como `display`/`visibility`/`opacity` são mantidas, para que menus abertos por hover continuem a funcionar);
  - folhas de estilo cross-origin ilegíveis são neutralizadas por um fallback de congelamento de transições.
  Apenas controlos reais (botões, links, campos de entrada) mantêm uma resposta de chanfro temática instantânea.
- **Verdana forçado a 100% em todo o lado** — incluindo campos de entrada e textareas, com suavização de fonte desativada. Fontes de ícones são excluídas para que os glifos não virem letras. Se tiver uma fonte personalizada instalada com o nome `Verdana_m1` (por exemplo, um patch de Verdana sem anti-aliasing), é usada automaticamente; caso contrário, Verdana normal.
- **Repainter adaptativo** — um sweeper JS leve converte superfícies claras "flash" e cinzas de modo escuro não tematizadas na escala castanha vintage, e corrige texto de baixo contraste (escuro-sobre-escuro) para dourado em limiares conscientes de WCAG. Imagens, vídeos, canvas e players nunca são tocados.
- **Perfuração Shadow DOM** — também temática componentes web (YouTube, Reddit e companhia) através de um hook `attachShadow`.
- **Popups comportam-se** — menus, diálogos, tooltips e hovercards são apenas recoloridos; o script nunca força `opacity`/`z-index`/`visibility`, por isso UI oculto do site permanece oculto.
- **Guarda de segurança** — o script desativa-se em páginas de OAuth, captcha, bancos e pagamentos para que fluxos críticos nunca sejam reestilizados.

## Paleta

A tabela abaixo mostra 10 dos 21 tokens da paleta Golden Default. Cada paleta enviada define todos os 21; os restantes 11 cobrem estrutura de chanfro, texto secundário, cores semânticas (sucesso/aviso/perigo), seleção e especificidades por alvo.

| Token | Hex | Utilizado para |
|---|---|---|
| background | `#1A1810` | fundo mais externo |
| backgroundSoft | `#232018` | fundo do corpo / conteúdo |
| surface | `#332E22` | cabeçalhos, navegação, painéis |
| surfaceRaised | `#3D372A` | botões, popups, polegar da barra de rolagem |
| surfaceAlt | `#453D30` | hover do botão |
| borderHighlight | `#F0D060` | arestas de chanfro, links |
| borderDark | `#100E08` | arestas rebaixadas, limites |
| textPrimary | `#D4C89A` | texto dourado primário |
| textMuted | `#6E674E` | placeholders, desativado |
| link | `#F0D060` | links, foco |

## Tema de navegador correspondente

O alvo `browsers` do instalador de desktop deteta perfis Chromium instalados e portáteis, reporta a cobertura do Tampermonkey, prepara o tema de navegador selecionado e abre as páginas de instalação/atualização corretas para cada perfil. O Chromium exige uma confirmação **Developer mode → Load unpacked** por perfil; o instalador copia o caminho estável do tema para a área de transferência. Alterações posteriores de paleta reutilizam esse caminho.

## Comportamentos conhecidos

- Sites que constroem efeitos de hover em JavaScript (via troca de classes) em vez de CSS `:hover` podem continuar a mostrar o seu próprio destaque.
- Em sites raros com CSS cross-origin, um clique num elemento não focável pode atrasar a mudança visual de estado até o rato o abandonar (o fallback de congelamento de hover entra em ação). Botões e links reais estão excluídos.
- O script é deliberadamente estático: sem painel de opções, sem interruptores por site. Faça fork e edite os tokens acima se quiser outro sabor.

## Lançar uma nova versão (para mantenedores)

Edite `wintage.user.js`, depois execute:

```powershell
.\release.ps1 -Message "o que mudou"
```

Ele incrementa o número `@version` de patch, commita e envia — os clientes Tampermonkey obtêm a atualização automaticamente. Para lançamentos maiores passe `-Bump minor` ou `-Bump major`.

## Licença

[MIT](LICENSE)

<!-- source-digest: README.md sha256:ee7c6a2a1626faed -->
