/**
 * @name RemoveStickers
 * @author Wintage
 * @version 1.0.0
 * @description Completely disables sticker rendering in Discord (chat messages, picker button, and suggestions).
 * @source https://github.com/vacterro/Wintage
 */

module.exports = class RemoveStickers {
    constructor() {
        this.styleId = 'RemoveStickers-Wintage-CSS';
        this.observer = null;
    }

    static get I18N() {
        return {
            en: {
                description: 'Completely disables sticker rendering in Discord (chat messages, picker button, and suggestions).',
                panelTitle: 'RemoveStickers v1.0.0 (Wintage)',
                panelDesc: 'Hides all sticker renderings, the sticker picker button in the chat bar, sticker autocomplete popups, and removes empty sticker message rows.',
                detectedLang: 'Detected Discord language: {0}',
                started: '[RemoveStickers] Plugin started. Stickers are banished.',
                stopped: '[RemoveStickers] Plugin stopped.'
            },
            ru: {
                description: 'Полностью отключает рендеринг стикеров в Discord (в сообщениях, пикере и подсказках).',
                panelTitle: 'RemoveStickers v1.0.0 (Wintage)',
                panelDesc: 'Скрывает все стикеры в сообщениях чата, кнопку выбора стикеров в строке ввода, всплывающие подсказки стикеров и сворачивает пустые сообщения.',
                detectedLang: 'Обнаруженный язык Discord: {0}',
                started: '[RemoveStickers] Плагин запущен. Стикеры скрыты.',
                stopped: '[RemoveStickers] Плагин остановлен.'
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
        const loc = RemoveStickers.getLocale();
        if (loc.startsWith('ru') || loc.startsWith('be') || loc.startsWith('uk')) {
            return RemoveStickers.I18N.ru;
        }
        return RemoveStickers.I18N.en;
    }

    start() {
        this.injectCSS();
        this.startObserver();
        this.scanAndClean();
        this.updateCardDescription();
        const strings = RemoveStickers.getStrings();
        console.log(strings.started);
    }

    stop() {
        this.removeCSS();
        if (this.observer) {
            this.observer.disconnect();
            this.observer = null;
        }
        this.restoreElements();
        const strings = RemoveStickers.getStrings();
        console.log(strings.stopped);
    }

    getSettingsPanel() {
        const strings = RemoveStickers.getStrings();
        const loc = RemoveStickers.getLocale();
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
            const strings = RemoveStickers.getStrings();
            const cards = document.querySelectorAll('#RemoveStickers-card, [data-addon-id="RemoveStickers"]');
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
            /* Скрытие всех элементов стикеров в сообщениях */
            [class*="stickerNode-"],
            [class*="stickerContainer-"],
            [class*="stickers-"],
            [class*="stickerMessage-"],
            [class*="clickableSticker-"],
            [class*="lottieCanvas-"],
            [class*="pngImage-"][src*="stickers"],
            div[data-type="sticker"],
            div[aria-label*="sticker" i],
            div[aria-label*="стикер" i],
            [class*="messageListItem-"] [class*="sticker-"],
            /* Скрытие кнопки выбора стикеров в строке ввода */
            button[aria-label*="sticker picker" i],
            button[aria-label*="стикер" i],
            [class*="stickerButton-"],
            /* Скрытие стикеров в автокомплите / поиске */
            [class*="autocomplete-"] [class*="sticker-"],
            [class*="expressionPicker-"] [aria-controls*="sticker-picker"] {
                display: none !important;
                visibility: hidden !important;
                height: 0 !important;
                width: 0 !important;
                min-height: 0 !important;
                max-height: 0 !important;
                opacity: 0 !important;
                pointer-events: none !important;
            }

            /* Если в сообщении был ТОЛЬКО стикер и нет текста, сворачиваем пустоту */
            .wintage-sticker-only-message {
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
        if (!msgEl || !msgEl.classList) return;

        // Check if message contains stickers
        const hasStickers = msgEl.querySelector('[class*="sticker"], div[data-type="sticker"], [class*="clickableSticker"]');
        if (!hasStickers) return;

        // Check if message has real text content
        const textContent = msgEl.querySelector('[class*="messageContent-"]')?.textContent?.trim();
        const hasEmbeds = msgEl.querySelector('[class*="embedWrapper-"], [class*="attachment-"]');

        // If message is purely a sticker and nothing else, hide the entire row so no blank gap remains
        if (!textContent && !hasEmbeds) {
            msgEl.classList.add('wintage-sticker-only-message');
        }
    }

    scanAndClean() {
        const msgs = document.querySelectorAll('li[class*="messageListItem-"], [class*="message-"]');
        for (let i = 0; i < msgs.length; i++) {
            this.checkMessageElement(msgs[i]);
        }
    }

    restoreElements() {
        const marked = document.querySelectorAll('.wintage-sticker-only-message');
        for (let i = 0; i < marked.length; i++) {
            marked[i].classList.remove('wintage-sticker-only-message');
        }
    }

    startObserver() {
        const target = document.getElementById('app-mount') || document.body;
        this.observer = new MutationObserver((mutations) => {
            for (let i = 0; i < mutations.length; i++) {
                const m = mutations[i];
                for (let j = 0; j < m.addedNodes.length; j++) {
                    const node = m.addedNodes[j];
                    if (node.nodeType === Node.ELEMENT_NODE) {
                        if (node.matches?.('li[class*="messageListItem-"], [class*="message-"]')) {
                            this.checkMessageElement(node);
                        }
                        const items = node.querySelectorAll?.('li[class*="messageListItem-"], [class*="message-"]');
                        if (items) {
                            for (let k = 0; k < items.length; k++) {
                                this.checkMessageElement(items[k]);
                            }
                        }
                        if (node.id === 'RemoveStickers-card' || node.querySelector?.('#RemoveStickers-card, [data-addon-id="RemoveStickers"]')) {
                            this.updateCardDescription();
                        }
                    }
                }
            }
        });

        this.observer.observe(target, { childList: true, subtree: true });
    }
};
