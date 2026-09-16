/**
 * @name RemoveGIFS
 * @author Wintage
 * @version 1.0.0
 * @description Completely disables and removes all GIFs from Discord (chat messages, GIF picker, embeds, autoplay, suggestions).
 * @source https://github.com/vacterro/Wintage
 */

module.exports = class RemoveGIFS {
    constructor() {
        this.styleId = 'RemoveGIFS-Wintage-CSS';
        this.observer = null;
    }

    static get I18N() {
        return {
            en: {
                description: 'Completely disables and removes all GIFs from Discord (chat messages, GIF picker, embeds, autoplay, suggestions).',
                panelTitle: 'RemoveGIFS v1.0.0 (Wintage)',
                panelDesc: 'Hides all GIF renderings and embeds, the GIF picker button in the chat input bar, GIF tabs in expression pickers, autoplay GIF previews, and collapses GIF-only message rows.',
                detectedLang: 'Detected Discord language: {0}',
                started: '[RemoveGIFS] Plugin started. GIFs banished.',
                stopped: '[RemoveGIFS] Plugin stopped.'
            },
            ru: {
                description: 'Полностью отключает и удаляет любые гифки в Discord (в сообщениях, пикере гифок, эмбедах, автовоспроизведении и подсказках).',
                panelTitle: 'RemoveGIFS v1.0.0 (Wintage)',
                panelDesc: 'Скрывает воспроизведение и отображение гифок, кнопку GIF в строке ввода, вкладки гифок в меню выражений, автовоспроизведение превью и сворачивает сообщения, состоящие только из гифок.',
                detectedLang: 'Обнаруженный язык Discord: {0}',
                started: '[RemoveGIFS] Плагин запущен. Гифки вырезаны под ноль.',
                stopped: '[RemoveGIFS] Плагин остановлен.'
            }
        };
    }

    static getLocale() {
        try {
            const docLang = document.documentElement.lang || document.documentElement.getAttribute('lang');
            if (docLang) return docLang.toLowerCase();
        } catch {}
        try {
            const wp = typeof BdApi !== 'undefined' && BdApi.Webpack ? BdApi.Webpack.getModule(m => m?.default?.locale)?.default?.locale : null;
            if (wp) return wp.toLowerCase();
        } catch {}
        try {
            if (typeof navigator !== 'undefined' && navigator.language) return navigator.language.toLowerCase();
        } catch {}
        return 'en';
    }

    static getStrings() {
        const loc = RemoveGIFS.getLocale();
        if (loc.startsWith('ru') || loc.startsWith('be') || loc.startsWith('uk')) {
            return RemoveGIFS.I18N.ru;
        }
        return RemoveGIFS.I18N.en;
    }

    start() {
        try { this.injectCSS(); } catch {}
        try { this.startObserver(); } catch {}
        try { this.scanAndClean(); } catch {}
        try { this.updateCardDescription(); } catch {}
        try { console.log(RemoveGIFS.getStrings().started); } catch {}
    }

    stop() {
        try { this.removeCSS(); } catch {}
        try { if (this.observer) { this.observer.disconnect(); this.observer = null; } } catch {}
        try { this.restoreElements(); } catch {}
        try { console.log(RemoveGIFS.getStrings().stopped); } catch {}
    }

    getSettingsPanel() {
        const strings = RemoveGIFS.getStrings();
        const loc = RemoveGIFS.getLocale();
        const panel = document.createElement('div');
        panel.style.cssText = 'padding: 12px; font-family: Verdana, sans-serif; font-size: 12px; color: #e0dbcd; background: #24221f; border: 2px solid #5a5343;';
        panel.innerHTML = `
            <div style="font-weight: bold; font-size: 13px; margin-bottom: 6px; color: #dfcaa0;">${strings.panelTitle}</div>
            <div style="margin-bottom: 10px; color: #c8c0b0;">${strings.panelDesc}</div>
            <div style="padding: 8px; background: #1a1917; border: 1px solid #3d372e;">
                <div><b>${strings.detectedLang.replace('{0}', loc)}</b></div>
            </div>
        `;
        return panel;
    }

    updateCardDescription() {
        try {
            const strings = RemoveGIFS.getStrings();
            const cards = document.querySelectorAll('#RemoveGIFS-card, [data-addon-id="RemoveGIFS"]');
            cards.forEach(card => {
                const desc = card.querySelector('.bd-addon-description, .bd-description');
                if (desc && desc.textContent !== strings.description) {
                    desc.textContent = strings.description;
                }
            });
        } catch {}
    }

    get css() {
        return `
            /* Скрытие кнопки выбора GIF в строке ввода сообщения */
            button[aria-label*="gif" i],
            button[aria-label*="гиф" i],
            [class*="gifButton-"],
            [class*="gifPickerButton"],
            [class*="expression-picker-chat-input-button"][aria-label*="gif" i] {
                display: none !important;
            }

            /* Скрытие вкладок и панелей GIF в меню выражений */
            [aria-controls*="gif-picker"],
            [id*="gif-picker-tab"],
            [id*="gif-picker"],
            [class*="expressionPicker-"] [id*="gif"],
            [class*="expressionPicker-"] [aria-label*="gif" i],
            [class*="expressionPicker-"] [aria-label*="гиф" i] {
                display: none !important;
            }

            /* Скрытие GIF-тегов, иконок избранного и бейджей */
            [class*="gifTag-"],
            [class*="gifFavoriteButton-"],
            [class*="embedGIF-"],
            div[data-type*="gif" i] {
                display: none !important;
            }

            /* Скрытие GIF-изображений и видео-анимаций (картинки/видео с .gif в URL) */
            img[src*=".gif" i],
            video[poster*=".gif" i],
            video[src*=".gif" i] {
                display: none !important;
            }

            /* Скрытие Tenor и Giphy превью (без :has) */
            [class*="imageWrapper-"] img[src*="tenor.com"],
            [class*="imageWrapper-"] video[src*="tenor.com"],
            [class*="imageWrapper-"] img[src*="giphy.com"],
            [class*="imageWrapper-"] video[src*="giphy.com"],
            [class*="imageWrapper-"] img[src*=".gif" i],
            [class*="imageWrapper-"] video[src*=".gif" i] {
                display: none !important;
            }

            /* Скрытие Tenor/Giphy обёрток -- через :has (Chrome 105+) */
            @supports selector(:has(*)) {
                [class*="embedWrapper-"]:has(a[href*="tenor.com"]),
                [class*="embedWrapper-"]:has(a[href*="giphy.com"]),
                [class*="embedWrapper-"]:has(img[src*="tenor.com"]),
                [class*="embedWrapper-"]:has(img[src*="giphy.com"]),
                [class*="embedWrapper-"]:has(video[src*="tenor.com"]),
                [class*="embedWrapper-"]:has(video[src*="giphy.com"]),
                [class*="embedWrapper-"]:has(img[src*=".gif" i]),
                [class*="embedWrapper-"]:has(video[src*=".gif" i]),
                [class*="embedWrapper-"]:has(video[poster*=".gif" i]),
                [class*="embedWrapper-"]:has([class*="gifTag-"]),
                [class*="embedWrapper-"]:has([class*="embedGIF-"]) {
                    display: none !important;
                }
            }

            /* Прямые ссылки на GIF-провайдеры внутри чата */
            a[href*="tenor.com/view/"],
            a[href*="giphy.com/gifs/"] {
                display: none !important;
            }

            /* Скрытие гифок в автодополнении */
            [class*="autocomplete-"] [class*="gif"] {
                display: none !important;
            }

            /* Если в сообщении была ТОЛЬКО гифка и нет текста, сворачиваем пустое сообщение */
            .wintage-gif-only-message {
                display: none !important;
            }
        `;
    }

    injectCSS() {
        if (typeof BdApi !== 'undefined' && BdApi.DOM?.addStyle) {
            BdApi.DOM.addStyle(this.styleId, this.css);
        } else {
            let el = document.getElementById(this.styleId);
            if (!el) {
                el = document.createElement('style');
                el.id = this.styleId;
                document.head.appendChild(el);
            }
            el.textContent = this.css;
        }
    }

    removeCSS() {
        if (typeof BdApi !== 'undefined' && BdApi.DOM?.removeStyle) {
            BdApi.DOM.removeStyle(this.styleId);
        } else {
            const el = document.getElementById(this.styleId);
            if (el) el.remove();
        }
    }

    checkMessageElement(msgEl) {
        try {
            if (!msgEl || !msgEl.classList) return;
            let hasGif = null;
            try {
                hasGif = msgEl.querySelector(
                    'img[src*=".gif" i], video[src*=".gif" i], video[poster*=".gif" i], ' +
                    'a[href*="tenor.com"], a[href*="giphy.com"], [class*="gifTag"], ' +
                    '[class*="embedGIF"], div[data-type*="gif" i]'
                );
            } catch { return; }
            if (!hasGif) return;
            let rawText = '';
            try { rawText = msgEl.querySelector('[class*="messageContent-"]')?.textContent?.trim() || ''; } catch {}
            const cleanedText = rawText
                .replace(/https?:\/\/(?:www\.)?(?:tenor\.com|giphy\.com)\S+/gi, '')
                .replace(/https?:\/\/\S+\.gif(?:\?\S*)?/gi, '')
                .trim();
            let nonGifEmbeds = false;
            try {
                nonGifEmbeds = Array.from(msgEl.querySelectorAll('[class*="embedWrapper-"], [class*="attachment-"]')).some(embed => {
                    let isGifEmbed = false;
                    try {
                        isGifEmbed = !!embed.querySelector(
                            'img[src*=".gif" i], video[src*=".gif" i], a[href*="tenor.com"], a[href*="giphy.com"]'
                        );
                    } catch {}
                    return !isGifEmbed;
                });
            } catch {}
            if (!cleanedText && !nonGifEmbeds) {
                msgEl.classList.add('wintage-gif-only-message');
            }
        } catch {}
    }

    scanAndClean() {
        const msgs = document.querySelectorAll('li[class*="messageListItem-"], [class*="message-"]');
        for (let i = 0; i < msgs.length; i++) {
            this.checkMessageElement(msgs[i]);
        }
    }

    restoreElements() {
        const marked = document.querySelectorAll('.wintage-gif-only-message');
        for (let i = 0; i < marked.length; i++) {
            marked[i].classList.remove('wintage-gif-only-message');
        }
    }

    startObserver() {
        const target = document.getElementById('app-mount') || document.body;
        if (!target) return;
        try {
            this.observer = new MutationObserver((mutations) => {
                try {
                    for (let i = 0; i < mutations.length; i++) {
                        const m = mutations[i];
                        for (let j = 0; j < m.addedNodes.length; j++) {
                            const node = m.addedNodes[j];
                            if (!node || node.nodeType !== Node.ELEMENT_NODE) continue;
                            try { if (node.matches?.('li[class*="messageListItem-"], [class*="message-"]')) this.checkMessageElement(node); } catch {}
                            try {
                                const items = node.querySelectorAll?.('li[class*="messageListItem-"], [class*="message-"]');
                                if (items) for (let k = 0; k < items.length; k++) this.checkMessageElement(items[k]);
                            } catch {}
                            try {
                                if (node.id === 'RemoveGIFS-card' || node.querySelector?.('#RemoveGIFS-card, [data-addon-id="RemoveGIFS"]')) this.updateCardDescription();
                            } catch {}
                        }
                    }
                } catch {}
            });
            this.observer.observe(target, { childList: true, subtree: true });
        } catch {}
    }
};
