done: v1.19.0, three browser-side rendering bugs, each with the cause named.
  reuters blank body  - our 0.001s animation rule caused reveal snapback: base opacity:0 + a fill-mode-less reveal animation ends instantly and the element falls back to invisible. animation-fill-mode: forwards, in both stylesheets. Mechanism reproduced in a real Chromium.
  steam artwork sides - url() backgrounds were preserved with no sense of size. html/body lose theirs outright; the repainter kills any covering >70% of the viewport in both dimensions.
  antigravity scrollbars - not ours and not overflow:scroll (that fix is installed and running). Monaco keeps its own scrollbar shells in the DOM permanently and our surface+bevel rules painted them. Shells handed back to the app.
Also: the theme-switch test was pinning DEFAULT_THEME, menu[0] and menu length - all things you own - and went red on your own changes; it reads them from the source now.
remaining: T-065 YouTube Studio analytics bars, T-058 Claude in-archive main patch.
awaiting: (1) reload reuters/steam and Antigravity to confirm. (2) YouTube: Studio > Analytics, devtools on one bar, send its class + computed background-color/background-image - one screenshot names the rule. (3) Claude's resources/app is GONE - the shim was undone between sessions, which is why it is unthemed; T-058 replaces that mechanism and needs Claude closed.
