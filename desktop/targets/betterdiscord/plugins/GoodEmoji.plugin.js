/**
 * @name GoodEmoji
 * @author Wintage
 * @version 1.0.0
 * @description Converts crying, sad, and toxic emojis into cheerful and hilarious ones (😭->😂, 💀->🙂, 🥀->🌹, 🤡->👍).
 * @source https://github.com/vacterro/Wintage
 */

module.exports = class GoodEmoji {
    constructor() {
        this.observer = null;
        this.boundProcessNode = this.processNode.bind(this);
    }

    static get I18N() {
        return {
            en: {
                description: 'Converts crying, sad, and toxic emojis into cheerful and hilarious ones (😭->😂, 💀->🙂, 🥀->🌹, 🤡->👍).',
                panelTitle: 'GoodEmoji v1.0.0 (Wintage)',
                panelDesc: 'Transforms negative, crying, and toxic emojis into joyful and funny ones across chat messages, reactions, and tooltips.',
                detectedLang: 'Detected Discord language: {0}',
                activeRules: 'Active emoji replacement rules: {0}',
                started: '[GoodEmoji] Plugin started. All sad emojis will be brightened.',
                stopped: '[GoodEmoji] Plugin stopped.'
            },
            ru: {
                description: 'Превращает все плаксивые, грустные и токсичные эмодзи в позитивные и угарные (😭->😂, 💀->🙂, 🥀->🌹, 🤡->👍).',
                panelTitle: 'GoodEmoji v1.0.0 (Wintage)',
                panelDesc: 'Превращает негативные, плаксивые и токсичные эмодзи в веселые и позитивные в сообщениях чата, реакциях и подсказках.',
                detectedLang: 'Обнаруженный язык Discord: {0}',
                activeRules: 'Активных правил замены эмодзи: {0}',
                started: '[GoodEmoji] Плагин запущен. Грустные эмодзи заменяются на позитивные.',
                stopped: '[GoodEmoji] Плагин остановлен.'
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
        const loc = GoodEmoji.getLocale();
        if (loc.startsWith('ru') || loc.startsWith('be') || loc.startsWith('uk')) {
            return GoodEmoji.I18N.ru;
        }
        return GoodEmoji.I18N.en;
    }

    static get MAPPINGS() {
        return [
            // 1. Crying, tears, weeping, sad smiles
            { from: '😭', to: '😂', fromCodes: ['1f62d'], toCode: '1f602', names: ['sob', 'crying', 'loud_crying', 'слезы', 'рыдания', 'плач'] },
            { from: '😢', to: '😄', fromCodes: ['1f622'], toCode: '1f604', names: ['cry', 'tear', 'слеза', 'грусть'] },
            { from: '🥺', to: '😎', fromCodes: ['1f97a'], toCode: '1f60e', names: ['pleading_face', 'pleading', 'умоляющий', 'щенячьи_глазки'] },
            { from: '🥹', to: '😎', fromCodes: ['1f979'], toCode: '1f60e', names: ['face_holding_back_tears', 'holding_back_tears', 'слезы_радости', 'растроган'] },
            { from: '🥲', to: '🥰', fromCodes: ['1f972'], toCode: '1f970', names: ['smiling_face_with_tear', 'smiling_tear', 'улыбка_со_слезой', 'сквозь_слезы'] },
            { from: '😿', to: '😹', fromCodes: ['1f63f'], toCode: '1f639', names: ['crying_cat_face', 'crying_cat', 'плачущий_кот'] },
            { from: '😪', to: '😌', fromCodes: ['1f62a'], toCode: '1f60c', names: ['sleepy', 'сонный_со_слезой', 'усталость'] },

            // 2. Death, skulls, graveyard, doom
            { from: '💀', to: '🙂', fromCodes: ['1f480'], toCode: '1f642', names: ['skull', 'череп', 'скелет'] },
            { from: '☠️', to: '😊', fromCodes: ['2620-fe0f', '2620'], toCode: '1f60a', names: ['skull_crossbones', 'пиратский_череп', 'смерть'] },
            { from: '☠', to: '😊', fromCodes: ['2620'], toCode: '1f60a', names: ['skull_crossbones'] },
            { from: '⚰️', to: '🎁', fromCodes: ['26b0-fe0f', '26b0'], toCode: '1f381', names: ['coffin', 'гроб', 'похороны'] },
            { from: '⚰', to: '🎁', fromCodes: ['26b0'], toCode: '1f381', names: ['coffin'] },
            { from: '🪦', to: '🏆', fromCodes: ['1faa6'], toCode: '1f3c6', names: ['headstone', 'gravestone', 'надгробие', 'могила'] },
            { from: '👻', to: '🎈', fromCodes: ['1f47b'], toCode: '1f388', names: ['ghost', 'призрак', 'привидение'] },

            // 3. Wilted, decaying, rot
            { from: '🥀', to: '🌹', fromCodes: ['1f940'], toCode: '1f339', names: ['wilted_rose', 'wilted_flower', 'увядшая_роза', 'завядший_цветок'] },
            { from: '🍂', to: '🌸', fromCodes: ['1f342'], toCode: '1f338', names: ['fallen_leaf', 'увядший_лист', 'опавший_лист'] },

            // 4. Mockery, clowns, toxic sarcasm
            { from: '🤡', to: '👍', fromCodes: ['1f921'], toCode: '1f44d', names: ['clown', 'clown_face', 'клоун', 'цирк'] },
            { from: '🎪', to: '🎉', fromCodes: ['1f3aa'], toCode: '1f389', names: ['circus_tent', 'circus', 'шапито', 'цирк_уехал'] },

            // 5. Sadness, gloom, grief, depression
            { from: '🙁', to: '🙂', fromCodes: ['1f641'], toCode: '1f642', names: ['slight_frown', 'легкая_грусть'] },
            { from: '☹️', to: '😃', fromCodes: ['2639-fe0f', '2639'], toCode: '1f603', names: ['frowning2', 'frown', 'грусть'] },
            { from: '☹', to: '😃', fromCodes: ['2639'], toCode: '1f603', names: ['frowning2', 'frown'] },
            { from: '😞', to: '😁', fromCodes: ['1f61e'], toCode: '1f601', names: ['disappointed', 'разочарование'] },
            { from: '😔', to: '😌', fromCodes: ['1f614'], toCode: '1f60c', names: ['pensive', 'задумчивый', 'печаль'] },
            { from: '😟', to: '😉', fromCodes: ['1f61f'], toCode: '1f609', names: ['worried', 'беспокойство'] },
            { from: '😕', to: '😊', fromCodes: ['1f615'], toCode: '1f60a', names: ['confused', 'замешательство'] },
            { from: '🫤', to: '🙂', fromCodes: ['1f9e4'], toCode: '1f642', names: ['face_with_diagonal_mouth', 'скептицизм'] },
            { from: '😐', to: '🙂', fromCodes: ['1f610'], toCode: '1f642', names: ['neutral_face', 'покерфейс', 'нейтральный'] },
            { from: '😑', to: '😊', fromCodes: ['1f611'], toCode: '1f60a', names: ['expressionless', 'без_эмоций', 'игнор'] },
            { from: '😶', to: '🤗', fromCodes: ['1f636'], toCode: '1f917', names: ['no_mouth', 'без_рта', 'молчание'] },
            { from: '🫥', to: '✨', fromCodes: ['1fae5'], toCode: '2728', names: ['dotted_line_face', 'невидимка', 'пустота'] },

            // 6. Passive-aggressive, sneering, dismissive, cringe
            { from: '🙄', to: '😜', fromCodes: ['1f644'], toCode: '1f61c', names: ['rolling_eyes', 'закатывание_глаз'] },
            { from: '😒', to: '😉', fromCodes: ['1f612'], toCode: '1f609', names: ['unamused', 'недовольный', 'надменный', 'презрение'] },
            { from: '🤨', to: '🧐', fromCodes: ['1f928'], toCode: '1f9d0', names: ['raised_eyebrow', 'бровь', 'подозрение'] },
            { from: '🙃', to: '🙂', fromCodes: ['1f643'], toCode: '1f642', names: ['upside_down', 'перевернутый', 'пассивная_агрессия'] },
            { from: '😬', to: '😁', fromCodes: ['1f62c'], toCode: '1f601', names: ['grimacing', 'гримаса', 'кринж'] },
            { from: '🥱', to: '☕', fromCodes: ['1f971'], toCode: '2615', names: ['yawning', 'зевота', 'скучно'] },
            { from: '🫠', to: '🌞', fromCodes: ['1fae0'], toCode: '1f31e', names: ['melting_face', 'тающий', 'плавлюсь'] },
            { from: '🤦‍♂️', to: '👏', fromCodes: ['1f926-200d-2642-fe0f', '1f926-200d-2642'], toCode: '1f44f', names: ['man_facepalming', 'фейспалм_мужчина'] },
            { from: '🤦‍♀️', to: '👏', fromCodes: ['1f926-200d-2640-fe0f', '1f926-200d-2640'], toCode: '1f44f', names: ['woman_facepalming', 'фейспалм_женщина'] },
            { from: '🤦', to: '👏', fromCodes: ['1f926'], toCode: '1f44f', names: ['facepalm', 'фейспалм', 'рукалицо'] },
            { from: '🤷‍♂️', to: '🤝', fromCodes: ['1f937-200d-2642-fe0f', '1f937-200d-2642'], toCode: '1f91d', names: ['man_shrugging', 'пожатие_плечами_мужчина'] },
            { from: '🤷‍♀️', to: '🤝', fromCodes: ['1f937-200d-2640-fe0f', '1f937-200d-2640'], toCode: '1f91d', names: ['woman_shrugging', 'пожатие_плечами_женщина'] },
            { from: '🤷', to: '🤝', fromCodes: ['1f937'], toCode: '1f91d', names: ['shrug', 'пожатие_плечами', 'хз'] },
            { from: '🗑️', to: '✨', fromCodes: ['1f5d1-fe0f', '1f5d1'], toCode: '2728', names: ['wastebasket', 'мусорка', 'помойка'] },
            { from: '🗑', to: '✨', fromCodes: ['1f5d1'], toCode: '2728', names: ['wastebasket'] },

            // 7. Despair, agony, panic, overwhelming anxiety
            { from: '😣', to: '💪', fromCodes: ['1f623'], toCode: '1f4aa', names: ['persevere', 'страдание', 'терпение'] },
            { from: '😫', to: '🥳', fromCodes: ['1f62b'], toCode: '1f973', names: ['tired_face', 'нытье', 'усталость'] },
            { from: '😩', to: '🤪', fromCodes: ['1f629'], toCode: '1f92a', names: ['weary', 'изнеможение'] },
            { from: '😖', to: '🙌', fromCodes: ['1f616'], toCode: '1f64c', names: ['confounded', 'мучение'] },
            { from: '😰', to: '😌', fromCodes: ['1f630'], toCode: '1f60c', names: ['cold_sweat', 'холодный_пот', 'тревога'] },
            { from: '😨', to: '😇', fromCodes: ['1f628'], toCode: '1f607', names: ['fearful', 'испуг'] },
            { from: '😱', to: '🤩', fromCodes: ['1f631'], toCode: '1f929', names: ['scream', 'крик_ужаса', 'паника'] },
            { from: '😮‍💨', to: '😌', fromCodes: ['1f62e-200d-1f4a8'], toCode: '1f60c', names: ['face_exhaling', 'тяжкий_вздох'] },

            // 8. Anger, wrath, demonic hostility
            { from: '😡', to: '😸', fromCodes: ['1f621'], toCode: '1f638', names: ['rage', 'злость', 'ярость', 'гнев'] },
            { from: '😠', to: '😺', fromCodes: ['1f620'], toCode: '1f63a', names: ['angry', 'сердитый'] },
            { from: '🤬', to: '😇', fromCodes: ['1f92c'], toCode: '1f607', names: ['cursing_face', 'ругань', 'мат'] },
            { from: '😾', to: '😻', fromCodes: ['1f63e'], toCode: '1f63b', names: ['pouting_cat', 'сердитый_кот'] },
            { from: '👿', to: '🤠', fromCodes: ['1f47f'], toCode: '1f920', names: ['imp', 'злой_черт'] },
            { from: '😈', to: '😜', fromCodes: ['1f608'], toCode: '1f61c', names: ['smiling_imp', 'дьявол', 'чертенок'] },

            // 9. Disgust, sickness, poop
            { from: '🤮', to: '😋', fromCodes: ['1f92e'], toCode: '1f60b', names: ['vomiting', 'рвота', 'тошнота'] },
            { from: '🤢', to: '😋', fromCodes: ['1f922'], toCode: '1f60b', names: ['nauseated_face', 'мутит', 'зеленый'] },
            { from: '🤧', to: '🌸', fromCodes: ['1f927'], toCode: '1f338', names: ['sneezing_face', 'чихание', 'простуда'] },
            { from: '😷', to: '😎', fromCodes: ['1f637'], toCode: '1f60e', names: ['mask', 'маска', 'болезнь'] },
            { from: '🤒', to: '☀️', fromCodes: ['1f912'], toCode: '2600', names: ['thermometer_face', 'температура', 'градусник'] },
            { from: '🤕', to: '💖', fromCodes: ['1f915'], toCode: '1f496', names: ['head_bandage', 'бинт', 'травма'] },
            { from: '💩', to: '🧁', fromCodes: ['1f4a9'], toCode: '1f9c1', names: ['poop', 'shit', 'какашка', 'говно', 'дерьмо'] },

            // 10. Aggression, violence, weapons, broken hearts
            { from: '🖕', to: '✌️', fromCodes: ['1f595'], toCode: '270c', names: ['middle_finger', 'фак', 'средний_палец'] },
            { from: '👎', to: '👍', fromCodes: ['1f44e'], toCode: '1f44d', names: ['thumbsdown', 'дизлайк', 'палец_вниз'] },
            { from: '👊', to: '🤝', fromCodes: ['1f44a'], toCode: '1f91d', names: ['punch', 'fist', 'удар', 'кулак'] },
            { from: '🤛', to: '🤝', fromCodes: ['1f91b'], toCode: '1f91d', names: ['left_facing_fist', 'левый_кулак'] },
            { from: '🤜', to: '🤝', fromCodes: ['1f91c'], toCode: '1f91d', names: ['right_facing_fist', 'правый_кулак'] },
            { from: '💔', to: '❤️', fromCodes: ['1f494'], toCode: '2764', names: ['broken_heart', 'разбитое_сердце'] },
            { from: '🖤', to: '💖', fromCodes: ['1f5a4'], toCode: '1f496', names: ['black_heart', 'черное_сердце'] },
            { from: '💣', to: '🎆', fromCodes: ['1f4a3'], toCode: '1f386', names: ['bomb', 'бомба'] },
            { from: '💥', to: '🎉', fromCodes: ['1f4a5'], toCode: '1f389', names: ['collision', 'boom', 'взрыв', 'бабах'] },
            { from: '🔪', to: '🍰', fromCodes: ['1f52a'], toCode: '1f370', names: ['hocho', 'knife', 'нож'] },
            { from: '🗡️', to: '🪄', fromCodes: ['1f5e1-fe0f', '1f5e1'], toCode: '1fa84', names: ['dagger', 'кинжал'] },
            { from: '🗡', to: '🪄', fromCodes: ['1f5e1'], toCode: '1fa84', names: ['dagger'] },
            { from: '⚔️', to: '🎸', fromCodes: ['2694-fe0f', '2694'], toCode: '1f3b8', names: ['crossed_swords', 'мечи'] },
            { from: '⚔', to: '🎸', fromCodes: ['2694'], toCode: '1f3b8', names: ['crossed_swords'] },
            { from: '🪓', to: '🌲', fromCodes: ['1fa93'], toCode: '1f332', names: ['axe', 'топор'] },

            // 11. Innuendo -> positive fruits
            { from: '🍆', to: '🍎', fromCodes: ['1f346'], toCode: '1f34e', names: ['eggplant', 'aubergine', 'баклажан'] },
            { from: '🍑', to: '🍉', fromCodes: ['1f351'], toCode: '1f349', names: ['peach', 'персик'] },

            // 12. Negative cross marks, bans, refusal -> calm neutral marks
            { from: '❌', to: '⚪', fromCodes: ['274c'], toCode: '26aa', names: ['x', 'cross_mark', 'крестик', 'крест', 'отмена'] },
            { from: '❎', to: '🔘', fromCodes: ['274e'], toCode: '1f518', names: ['negative_squared_cross_mark', 'квадратный_крестик'] },
            { from: '✖️', to: '⚪', fromCodes: ['2716-fe0f', '2716'], toCode: '26aa', names: ['heavy_multiplication_x', 'умножение'] },
            { from: '✖', to: '⚪', fromCodes: ['2716'], toCode: '26aa', names: ['heavy_multiplication_x'] },
            { from: '🚫', to: '🔘', fromCodes: ['1f6ab'], toCode: '1f518', names: ['no_entry_sign', 'prohibited', 'запрещено'] },
            { from: '⛔', to: '⚪', fromCodes: ['26d4'], toCode: '26aa', names: ['no_entry', 'кирпич', 'въезд_запрещен'] },
            { from: '🛑', to: '🔘', fromCodes: ['1f6d1'], toCode: '1f518', names: ['octagonal_sign', 'stop', 'стоп'] }
        ];
    }

    start() {
        this.initMaps();
        this.processTree(document.body);
        this.startObserver();
        this.updateCardDescription();
        this.sweepInterval = setInterval(() => {
            const mount = document.getElementById('app-mount') || document.body;
            const imgs = mount.querySelectorAll('img.emoji, [class*="reaction"] img, img[class*="emoji"]');
            for (let i = 0; i < imgs.length; i++) {
                this.processImg(imgs[i]);
            }
        }, 2000);
        const strings = GoodEmoji.getStrings();
        console.log(strings.started);
    }

    stop() {
        if (this.sweepInterval) {
            clearInterval(this.sweepInterval);
            this.sweepInterval = null;
        }
        if (this.observer) {
            this.observer.disconnect();
            this.observer = null;
        }
        const strings = GoodEmoji.getStrings();
        console.log(strings.stopped);
    }

    getSettingsPanel() {
        const strings = GoodEmoji.getStrings();
        const loc = GoodEmoji.getLocale();
        const panel = document.createElement('div');
        panel.style.cssText = 'padding: 12px; font-family: Verdana, sans-serif; font-size: 12px; color: #e0dbcd; background: #24221f; border: 2px solid #5a5343;';
        panel.innerHTML = `
            <div style="font-weight: bold; font-size: 13px; margin-bottom: 6px; color: #dfcaa0;">${strings.panelTitle}</div>
            <div style="margin-bottom: 10px; color: #c8c0b0;">${strings.panelDesc}</div>
            <div style="padding: 8px; background: #1a1917; border: 1px solid #3d372e;">
                <div><b>${strings.detectedLang.replace('{0}', loc)}</b></div>
                <div style="margin-top: 4px; color: #a09888;">${strings.activeRules.replace('{0}', GoodEmoji.MAPPINGS.length)}</div>
            </div>
        `;
        return panel;
    }

    updateCardDescription() {
        try {
            const strings = GoodEmoji.getStrings();
            const cards = document.querySelectorAll('#GoodEmoji-card, [data-addon-id="GoodEmoji"]');
            cards.forEach(card => {
                const desc = card.querySelector('.bd-addon-description, .bd-description');
                if (desc && desc.textContent !== strings.description) {
                    desc.textContent = strings.description;
                }
            });
        } catch {}
    }

    initMaps() {
        this.unicodeToItem = {};
        this.nameToItem = {};
        this.codeToItem = {};
        this.textMap = {};
        const chars = [];

        for (const item of GoodEmoji.MAPPINGS) {
            this.textMap[item.from] = item.to;
            this.unicodeToItem[item.from] = item;
            chars.push(item.from.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));

            for (const code of item.fromCodes) {
                const c = code.toLowerCase();
                this.codeToItem[c] = item;
            }

            for (const name of item.names) {
                const n = name.toLowerCase();
                this.nameToItem[n] = item;
                this.nameToItem[':' + n + ':'] = item;
            }
        }

        chars.sort((a, b) => b.length - a.length);
        this.textRegex = new RegExp(chars.join('|'), 'gu');
    }

    processImg(img) {
        if (!img || !img.getAttribute) return;

        const src = img.getAttribute('src') || '';
        const alt = img.getAttribute('alt') || '';
        const aria = img.getAttribute('aria-label') || '';
        const title = img.getAttribute('title') || '';

        let matchedItem = null;

        // 1. Check alt (exact unicode or shortcode)
        if (alt) {
            if (this.unicodeToItem[alt]) {
                matchedItem = this.unicodeToItem[alt];
            } else {
                const cleanAlt = alt.replace(/^:+|:+$/g, '').toLowerCase();
                if (this.nameToItem[cleanAlt]) {
                    matchedItem = this.nameToItem[cleanAlt];
                }
            }
        }

        // 2. Check aria-label / title
        if (!matchedItem && aria) {
            if (this.unicodeToItem[aria]) {
                matchedItem = this.unicodeToItem[aria];
            } else {
                const cleanAria = aria.replace(/^:+|:+$/g, '').toLowerCase();
                if (this.nameToItem[cleanAria]) {
                    matchedItem = this.nameToItem[cleanAria];
                }
            }
        }
        if (!matchedItem && title) {
            if (this.unicodeToItem[title]) {
                matchedItem = this.unicodeToItem[title];
            } else {
                const cleanTitle = title.replace(/^:+|:+$/g, '').toLowerCase();
                if (this.nameToItem[cleanTitle]) {
                    matchedItem = this.nameToItem[cleanTitle];
                }
            }
        }

        // 3. Check src URL for hex codes
        if (!matchedItem && src) {
            for (const [code, item] of Object.entries(this.codeToItem)) {
                const pattern = new RegExp('([/_])' + code + '(\\.(?:svg|png|webp))', 'i');
                if (pattern.test(src)) {
                    matchedItem = item;
                    break;
                }
            }
        }

        // 4. Check parent reaction button
        if (!matchedItem) {
            const parent = img.closest?.('[class*="reaction"], [role="button"]');
            if (parent) {
                const pAria = parent.getAttribute('aria-label') || '';
                for (const item of GoodEmoji.MAPPINGS) {
                    if (pAria.includes(item.from)) {
                        matchedItem = item;
                        break;
                    }
                    for (const name of item.names) {
                        if (pAria.toLowerCase().includes(name)) {
                            matchedItem = item;
                            break;
                        }
                    }
                    if (matchedItem) break;
                }
            }
        }

        if (!matchedItem) return;

        const targetSrc = 'https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/svg/' + matchedItem.toCode + '.svg';
        if (img.dataset.goodEmojiReplaced === matchedItem.toCode && img.getAttribute('src') === targetSrc) {
            return;
        }

        if (img.hasAttribute('srcset')) {
            img.removeAttribute('srcset');
        }

        img.setAttribute('src', targetSrc);
        img.src = targetSrc;

        img.setAttribute('alt', matchedItem.to);
        if (img.hasAttribute('title') || title) {
            img.setAttribute('title', matchedItem.to);
        }
        if (img.hasAttribute('aria-label') || aria) {
            img.setAttribute('aria-label', matchedItem.to);
        }

        img.dataset.goodEmojiReplaced = matchedItem.toCode;
        img.dataset.goodEmojiDone = 'true';

        const reactionBtn = img.closest?.('[class*="reaction"], [role="button"]');
        if (reactionBtn) {
            const pAria = reactionBtn.getAttribute('aria-label');
            if (pAria && pAria.includes(matchedItem.from)) {
                reactionBtn.setAttribute('aria-label', pAria.replaceAll(matchedItem.from, matchedItem.to));
            }
        }
    }

    processReaction(reactionEl) {
        if (!reactionEl || !reactionEl.getAttribute) return;

        const imgs = reactionEl.querySelectorAll('img');
        for (let i = 0; i < imgs.length; i++) {
            this.processImg(imgs[i]);
        }

        const aria = reactionEl.getAttribute('aria-label') || '';
        if (aria && this.textRegex.test(aria)) {
            this.textRegex.lastIndex = 0;
            reactionEl.setAttribute('aria-label', aria.replace(this.textRegex, (match) => this.textMap[match] || match));
        }
    }

    processTextNode(node) {
        if (!node || !node.nodeValue) return;
        const val = node.nodeValue;
        if (!this.textRegex.test(val)) return;

        this.textRegex.lastIndex = 0;
        node.nodeValue = val.replace(this.textRegex, (match) => this.textMap[match] || match);
    }

    processNode(node) {
        if (!node) return;

        if (node.nodeType === Node.TEXT_NODE) {
            this.processTextNode(node);
            return;
        }

        if (node.nodeType === Node.ELEMENT_NODE) {
            const tag = node.tagName.toLowerCase();
            if (tag === 'script' || tag === 'style') return;

            if (tag === 'img') {
                this.processImg(node);
            }

            const imgs = node.querySelectorAll?.('img');
            if (imgs && imgs.length > 0) {
                for (let i = 0; i < imgs.length; i++) {
                    this.processImg(imgs[i]);
                }
            }

            const reactions = node.querySelectorAll?.('[class*="reaction"], [role="button"][aria-label]');
            if (reactions && reactions.length > 0) {
                for (let i = 0; i < reactions.length; i++) {
                    this.processReaction(reactions[i]);
                }
            }

            const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT, null, false);
            let currentText;
            while ((currentText = walker.nextNode())) {
                this.processTextNode(currentText);
            }
        }
    }

    processTree(root) {
        if (!root) return;
        const imgs = root.querySelectorAll('img');
        for (let i = 0; i < imgs.length; i++) {
            this.processImg(imgs[i]);
        }

        const reactions = root.querySelectorAll('[class*="reaction"], [role="button"][aria-label]');
        for (let i = 0; i < reactions.length; i++) {
            this.processReaction(reactions[i]);
        }

        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
        let textNode;
        while ((textNode = walker.nextNode())) {
            this.processTextNode(textNode);
        }
    }

    startObserver() {
        const target = document.getElementById('app-mount') || document.body;
        this.observer = new MutationObserver((mutations) => {
            for (let i = 0; i < mutations.length; i++) {
                const mutation = mutations[i];
                if (mutation.type === 'childList') {
                    for (let j = 0; j < mutation.addedNodes.length; j++) {
                        const node = mutation.addedNodes[j];
                        this.processNode(node);
                        if (node.nodeType === 1 && (node.id === 'GoodEmoji-card' || node.querySelector?.('#GoodEmoji-card, [data-addon-id="GoodEmoji"]'))) {
                            this.updateCardDescription();
                        }
                    }
                } else if (mutation.type === 'characterData') {
                    this.processTextNode(mutation.target);
                } else if (mutation.type === 'attributes') {
                    if (mutation.target.tagName?.toLowerCase() === 'img') {
                        this.processImg(mutation.target);
                    } else if (mutation.target.nodeType === 1) {
                        const imgs = mutation.target.querySelectorAll?.('img');
                        if (imgs) {
                            for (let k = 0; k < imgs.length; k++) {
                                this.processImg(imgs[k]);
                            }
                        }
                    }
                }
            }
        });

        this.observer.observe(target, {
            childList: true,
            subtree: true,
            characterData: true,
            attributes: true,
            attributeFilter: ['src', 'alt', 'aria-label', 'title']
        });
    }
};
