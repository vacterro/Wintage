/**
 * @name GoodEmoji
 * @author Wintage
 * @version 1.1.0
 * @description Converts crying, sad, and toxic emojis into cheerful and hilarious ones (😭->😂, 💀->🙂, 🥀->🌹, 🤡->👍, 🖕->✌️).
 * @source https://github.com/vacterro/Wintage
 */

module.exports = class GoodEmoji {
    constructor() {
        this.observer = null;
        this.sweepTimer = null;
        this.boundProcessNode = this.processNode.bind(this);
    }

    // PERF-004 (SRC-018:R016): the bounded reconciliation window. A route change
    // is worth ONE scan at the minimum delay; a burst widens it up to the max via
    // requestReconcile. Neither is a fixed heartbeat -- no timer exists while the
    // page is idle.
    static get RECONCILE_MIN_MS() { return 250; }
    static get RECONCILE_MAX_MS() { return 5000; }

    static get I18N() {
        return {
            en: {
                description: 'Converts crying, sad, and toxic emojis into cheerful and hilarious ones (😭->😂, 💀->🙂, 🥀->🌹, 🤡->👍, 🖕->✌️).',
                panelTitle: 'GoodEmoji v1.1.0 (Wintage)',
                panelDesc: 'Transforms negative, crying, and toxic emojis into joyful and funny ones across chat messages, reactions, tooltips, and popouts.',
                detectedLang: 'Detected Discord language: {0}',
                activeRules: 'Active emoji replacement rules: {0}',
                started: '[GoodEmoji] Plugin started. All sad and toxic emojis will be brightened.',
                stopped: '[GoodEmoji] Plugin stopped.'
            },
            ru: {
                description: 'Превращает все плаксивые, грустные и токсичные эмодзи в позитивные и угарные (😭->😂, 💀->🙂, 🥀->🌹, 🤡->👍, 🖕->✌️).',
                panelTitle: 'GoodEmoji v1.1.0 (Wintage)',
                panelDesc: 'Превращает негативные, плаксивые и токсичные эмодзи в веселые и позитивные в сообщениях чата, реакциях, подсказках и всплывающих окнах.',
                detectedLang: 'Обнаруженный язык Discord: {0}',
                activeRules: 'Активных правил замены эмодзи: {0}',
                started: '[GoodEmoji] Плагин запущен. Грустные и токсичные эмодзи заменяются на позитивные.',
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
            { from: '😭', to: '😂', fromCodes: ['1f62d'], toCode: '1f602', toShortcode: 'joy', names: ['sob', 'crying', 'loud_crying', 'слезы', 'рыдания', 'плач'] },
            { from: '😢', to: '😄', fromCodes: ['1f622'], toCode: '1f604', toShortcode: 'smile', names: ['cry', 'tear', 'слеза', 'грусть'] },
            { from: '🥺', to: '😎', fromCodes: ['1f97a'], toCode: '1f60e', toShortcode: 'sunglasses', names: ['pleading_face', 'pleading', 'умоляющий', 'щенячьи_глазки'] },
            { from: '🥹', to: '😎', fromCodes: ['1f979'], toCode: '1f60e', toShortcode: 'sunglasses', names: ['face_holding_back_tears', 'holding_back_tears', 'слезы_радости', 'растроган'] },
            { from: '🥲', to: '🥰', fromCodes: ['1f972'], toCode: '1f970', toShortcode: 'smiling_face_with_3_hearts', names: ['smiling_face_with_tear', 'smiling_tear', 'улыбка_со_слезой', 'сквозь_слезы'] },
            { from: '😿', to: '😹', fromCodes: ['1f63f'], toCode: '1f639', toShortcode: 'joy_cat', names: ['crying_cat_face', 'crying_cat', 'плачущий_кот'] },
            { from: '😪', to: '😌', fromCodes: ['1f62a'], toCode: '1f60c', toShortcode: 'relieved', names: ['sleepy', 'сонный_со_слезой', 'усталость'] },
            { from: '😥', to: '😌', fromCodes: ['1f625'], toCode: '1f60c', toShortcode: 'relieved', names: ['disappointed_relieved', 'грусть_со_слезой', 'облегчение'] },
            { from: '😓', to: '😅', fromCodes: ['1f613'], toCode: '1f605', toShortcode: 'sweat_smile', names: ['sweat', 'холодный_пот_грусть', 'пот'] },
            { from: '💧', to: '✨', fromCodes: ['1f4a7'], toCode: '2728', toShortcode: 'sparkles', names: ['droplet', 'капля', 'слеза'] },

            // 2. Death, skulls, graveyard, doom
            { from: '💀', to: '🙂', fromCodes: ['1f480'], toCode: '1f642', toShortcode: 'slight_smile', names: ['skull', 'череп', 'скелет'] },
            { from: '☠️', to: '😊', fromCodes: ['2620-fe0f', '2620'], toCode: '1f60a', toShortcode: 'blush', names: ['skull_crossbones', 'пиратский_череп', 'смерть'] },
            { from: '☠', to: '😊', fromCodes: ['2620'], toCode: '1f60a', toShortcode: 'blush', names: ['skull_crossbones'] },
            { from: '⚰️', to: '🎁', fromCodes: ['26b0-fe0f', '26b0'], toCode: '1f381', toShortcode: 'gift', names: ['coffin', 'гроб', 'похороны'] },
            { from: '⚰', to: '🎁', fromCodes: ['26b0'], toCode: '1f381', toShortcode: 'gift', names: ['coffin'] },
            { from: '🪦', to: '🏆', fromCodes: ['1faa6'], toCode: '1f3c6', toShortcode: 'trophy', names: ['headstone', 'gravestone', 'надгробие', 'могила'] },
            { from: '👻', to: '🎈', fromCodes: ['1f47b'], toCode: '1f388', toShortcode: 'balloon', names: ['ghost', 'призрак', 'привидение'] },
            { from: '🧟', to: '🕺', fromCodes: ['1f9df', '1f9df-200d-2642-fe0f', '1f9df-200d-2640-fe0f'], toCode: '1f57a', toShortcode: 'dancer', names: ['zombie', 'зомби', 'мертвец', 'man_zombie', 'woman_zombie'] },
            { from: '🧛', to: '🦸', fromCodes: ['1f9db', '1f9db-200d-2642-fe0f', '1f9db-200d-2640-fe0f'], toCode: '1f9b8', toShortcode: 'superhero', names: ['vampire', 'вампир', 'man_vampire', 'woman_vampire'] },
            { from: '🦴', to: '🥖', fromCodes: ['1f9b4'], toCode: '1f956', toShortcode: 'french_bread', names: ['bone', 'кость', 'кости'] },
            { from: '🩸', to: '🍓', fromCodes: ['1fa78'], toCode: '1f353', toShortcode: 'strawberry', names: ['drop_of_blood', 'blood', 'кровь', 'капля_крови'] },
            { from: '🕳️', to: '🪅', fromCodes: ['1f573-fe0f', '1f573'], toCode: '1fa85', toShortcode: 'pinata', names: ['hole', 'яма', 'дыра', 'могила'] },
            { from: '🕳', to: '🪅', fromCodes: ['1f573'], toCode: '1fa85', toShortcode: 'pinata', names: ['hole'] },

            // 3. Wilted, decaying, filth, pests
            { from: '🥀', to: '🌹', fromCodes: ['1f940'], toCode: '1f339', toShortcode: 'rose', names: ['wilted_rose', 'wilted_flower', 'увядшая_роза', 'завядший_цветок'] },
            { from: '🍂', to: '🌸', fromCodes: ['1f342'], toCode: '1f338', toShortcode: 'cherry_blossom', names: ['fallen_leaf', 'увядший_лист', 'опавший_лист'] },
            { from: '🪰', to: '🦋', fromCodes: ['1fab0'], toCode: '1f98b', toShortcode: 'butterfly', names: ['fly', 'муха'] },
            { from: '🪳', to: '🐞', fromCodes: ['1fab3'], toCode: '1f41e', toShortcode: 'beetle', names: ['cockroach', 'roach', 'таракан'] },
            { from: '🐀', to: '🐹', fromCodes: ['1f400'], toCode: '1f439', toShortcode: 'hamster', names: ['rat', 'крыса'] },
            { from: '🐁', to: '🐹', fromCodes: ['1f401'], toCode: '1f439', toShortcode: 'hamster', names: ['mouse2', 'мышь'] },

            // 4. Mockery, clowns, toxic sarcasm, trolling memes
            { from: '🤡', to: '👍', fromCodes: ['1f921'], toCode: '1f44d', toShortcode: 'thumbsup', names: ['clown', 'clown_face', 'клоун', 'цирк'] },
            { from: '🎪', to: '🎉', fromCodes: ['1f3aa'], toCode: '1f389', toShortcode: 'tada', names: ['circus_tent', 'circus', 'шапито', 'цирк_уехал'] },
            { from: '🤓', to: '😎', fromCodes: ['1f913'], toCode: '1f60e', toShortcode: 'sunglasses', names: ['nerd', 'nerd_face', 'ботан', 'задрот', 'очкарик', 'душнила'] },
            { from: '💅', to: '✨', fromCodes: ['1f485'], toCode: '2728', toShortcode: 'sparkles', names: ['nail_care', 'nail_polish', 'ноготочки', 'маникюр'] },
            { from: '🫵', to: '👏', fromCodes: ['1fa75'], toCode: '1f44f', toShortcode: 'clap', names: ['point_up_2', 'index_pointing_at_the_viewer', 'ты', 'палец_на_тебя'] },
            { from: '🤏', to: '👌', fromCodes: ['1f90f'], toCode: '1f44c', toShortcode: 'ok_hand', names: ['pinching_hand', 'щепотка', 'чуть_чуть', 'микро'] },
            { from: '🤥', to: '🤝', fromCodes: ['1f925'], toCode: '1f91d', toShortcode: 'handshake', names: ['lying_face', 'ложь', 'вранье', 'пиноккио'] },
            { from: '🤫', to: '🎶', fromCodes: ['1f92b'], toCode: '1f3b6', toShortcode: 'notes', names: ['shushing_face', 'тсс', 'заткнись', 'молчи'] },
            { from: '🤐', to: '😃', fromCodes: ['1f910'], toCode: '1f603', toShortcode: 'smiley', names: ['zipper_mouth_face', 'рот_на_замке', 'закрой_рот'] },
            { from: '📉', to: '📈', fromCodes: ['1f4c9'], toCode: '1f4c8', toShortcode: 'chart_with_upwards_trend', names: ['chart_with_downwards_trend', 'падение', 'график_вниз', 'спад'] },
            { from: '🪫', to: '🔋', fromCodes: ['1faab'], toCode: '1f50b', toShortcode: 'battery', names: ['low_battery', 'севшая_батарейка', 'разряжен'] },

            // 5. Sadness, gloom, grief, depression
            { from: '🙁', to: '🙂', fromCodes: ['1f641'], toCode: '1f642', toShortcode: 'slight_smile', names: ['slight_frown', 'легкая_грусть'] },
            { from: '☹️', to: '😃', fromCodes: ['2639-fe0f', '2639'], toCode: '1f603', toShortcode: 'smiley', names: ['frowning2', 'frown', 'грусть'] },
            { from: '☹', to: '😃', fromCodes: ['2639'], toCode: '1f603', toShortcode: 'smiley', names: ['frowning2', 'frown'] },
            { from: '😞', to: '😁', fromCodes: ['1f61e'], toCode: '1f601', toShortcode: 'grin', names: ['disappointed', 'разочарование'] },
            { from: '😔', to: '😌', fromCodes: ['1f614'], toCode: '1f60c', toShortcode: 'relieved', names: ['pensive', 'задумчивый', 'печаль'] },
            { from: '😟', to: '😉', fromCodes: ['1f61f'], toCode: '1f609', toShortcode: 'wink', names: ['worried', 'беспокойство'] },
            { from: '😕', to: '😊', fromCodes: ['1f615'], toCode: '1f60a', toShortcode: 'blush', names: ['confused', 'замешательство'] },
            { from: '🫤', to: '🙂', fromCodes: ['1f9e4'], toCode: '1f642', toShortcode: 'slight_smile', names: ['face_with_diagonal_mouth', 'скептицизм'] },
            { from: '😐', to: '🙂', fromCodes: ['1f610'], toCode: '1f642', toShortcode: 'slight_smile', names: ['neutral_face', 'покерфейс', 'нейтральный'] },
            { from: '😑', to: '😊', fromCodes: ['1f611'], toCode: '1f60a', toShortcode: 'blush', names: ['expressionless', 'без_эмоций', 'игнор'] },
            { from: '😶', to: '🤗', fromCodes: ['1f636'], toCode: '1f917', toShortcode: 'hugging', names: ['no_mouth', 'без_рта', 'молчание'] },
            { from: '🫥', to: '✨', fromCodes: ['1fae5'], toCode: '2728', toShortcode: 'sparkles', names: ['dotted_line_face', 'невидимка', 'пустота'] },
            { from: '😦', to: '🙂', fromCodes: ['1f626'], toCode: '1f642', toShortcode: 'slight_smile', names: ['frowning', 'растерянность', 'опешил'] },
            { from: '😧', to: '😃', fromCodes: ['1f627'], toCode: '1f603', toShortcode: 'smiley', names: ['anguished', 'тоска', 'мука'] },
            { from: '🫨', to: '🤩', fromCodes: ['1fae8'], toCode: '1f929', toShortcode: 'star_struck', names: ['shaking_face', 'трясущееся_лицо', 'шок'] },

            // 6. Passive-aggressive, sneering, dismissive, cringe
            { from: '🙄', to: '😜', fromCodes: ['1f644'], toCode: '1f61c', toShortcode: 'stuck_out_tongue_winking_eye', names: ['rolling_eyes', 'закатывание_глаз'] },
            { from: '😒', to: '😉', fromCodes: ['1f612'], toCode: '1f609', toShortcode: 'wink', names: ['unamused', 'недовольный', 'надменный', 'презрение'] },
            { from: '🤨', to: '🧐', fromCodes: ['1f928'], toCode: '1f9d0', toShortcode: 'monocle', names: ['raised_eyebrow', 'бровь', 'подозрение'] },
            { from: '🙃', to: '🙂', fromCodes: ['1f643'], toCode: '1f642', toShortcode: 'slight_smile', names: ['upside_down', 'перевернутый', 'пассивная_агрессия'] },
            { from: '😬', to: '😁', fromCodes: ['1f62c'], toCode: '1f601', toShortcode: 'grin', names: ['grimacing', 'гримаса', 'кринж'] },
            { from: '🥱', to: '☕', fromCodes: ['1f971'], toCode: '2615', toShortcode: 'coffee', names: ['yawning', 'зевота', 'скучно'] },
            { from: '🫠', to: '🌞', fromCodes: ['1fae0'], toCode: '1f31e', toShortcode: 'sun_with_face', names: ['melting_face', 'тающий', 'плавлюсь'] },
            { from: '🥴', to: '😋', fromCodes: ['1f974'], toCode: '1f60b', toShortcode: 'yum', names: ['woozy_face', 'кринж', 'перекосило', 'пьяный'] },
            { from: '🤦‍♂️', to: '👏', fromCodes: ['1f926-200d-2642-fe0f', '1f926-200d-2642'], toCode: '1f44f', toShortcode: 'clap', names: ['man_facepalming', 'фейспалм_мужчина'] },
            { from: '🤦‍♀️', to: '👏', fromCodes: ['1f926-200d-2640-fe0f', '1f926-200d-2640'], toCode: '1f44f', toShortcode: 'clap', names: ['woman_facepalming', 'фейспалм_женщина'] },
            { from: '🤦', to: '👏', fromCodes: ['1f926'], toCode: '1f44f', toShortcode: 'clap', names: ['facepalm', 'фейспалм', 'рукалицо'] },
            { from: '🤷‍♂️', to: '🤝', fromCodes: ['1f937-200d-2642-fe0f', '1f937-200d-2642'], toCode: '1f91d', toShortcode: 'handshake', names: ['man_shrugging', 'пожатие_плечами_мужчина'] },
            { from: '🤷‍♀️', to: '🤝', fromCodes: ['1f937-200d-2640-fe0f', '1f937-200d-2640'], toCode: '1f91d', toShortcode: 'handshake', names: ['woman_shrugging', 'пожатие_плечами_женщина'] },
            { from: '🤷', to: '🤝', fromCodes: ['1f937'], toCode: '1f91d', toShortcode: 'handshake', names: ['shrug', 'пожатие_плечами', 'хз'] },
            { from: '🙅‍♂️', to: '🙆', fromCodes: ['1f645-200d-2642-fe0f', '1f645-200d-2642'], toCode: '1f646', toShortcode: 'ok_woman', names: ['man_gesturing_no', 'отказ_мужчина'] },
            { from: '🙅‍♀️', to: '🙆', fromCodes: ['1f645-200d-2640-fe0f', '1f645-200d-2640'], toCode: '1f646', toShortcode: 'ok_woman', names: ['woman_gesturing_no', 'отказ_женщина'] },
            { from: '🙅', to: '🙆', fromCodes: ['1f645'], toCode: '1f646', toShortcode: 'ok_woman', names: ['no_good', 'person_gesturing_no', 'отказ', 'стоп_жест'] },
            { from: '🗑️', to: '✨', fromCodes: ['1f5d1-fe0f', '1f5d1'], toCode: '2728', toShortcode: 'sparkles', names: ['wastebasket', 'мусорка', 'помойка'] },
            { from: '🗑', to: '✨', fromCodes: ['1f5d1'], toCode: '2728', toShortcode: 'sparkles', names: ['wastebasket'] },
            { from: '🚮', to: '✨', fromCodes: ['1f6ae'], toCode: '2728', toShortcode: 'sparkles', names: ['put_litter_in_its_place', 'в_мусорку', 'мусорка_знак'] },
            { from: '🧻', to: '📜', fromCodes: ['1f9fb'], toCode: '1f4dc', toShortcode: 'scroll', names: ['roll_of_paper', 'toilet_paper', 'туалетка', 'туалетная_бумага'] },
            { from: '🚽', to: '🛁', fromCodes: ['1f6bd'], toCode: '1f6c1', toShortcode: 'bath', names: ['toilet', 'унитаз', 'толчок'] },

            // 7. Despair, agony, panic, overwhelming anxiety, freezing
            { from: '😣', to: '💪', fromCodes: ['1f623'], toCode: '1f4aa', toShortcode: 'muscle', names: ['persevere', 'страдание', 'терпение'] },
            { from: '😫', to: '🥳', fromCodes: ['1f62b'], toCode: '1f973', toShortcode: 'partying_face', names: ['tired_face', 'нытье', 'усталость'] },
            { from: '😩', to: '🤪', fromCodes: ['1f629'], toCode: '1f92a', toShortcode: 'zany_face', names: ['weary', 'изнеможение'] },
            { from: '😖', to: '🙌', fromCodes: ['1f616'], toCode: '1f64c', toShortcode: 'raised_hands', names: ['confounded', 'мучение'] },
            { from: '😰', to: '😌', fromCodes: ['1f630'], toCode: '1f60c', toShortcode: 'relieved', names: ['cold_sweat', 'холодный_пот', 'тревога'] },
            { from: '😨', to: '😇', fromCodes: ['1f628'], toCode: '1f607', toShortcode: 'innocent', names: ['fearful', 'испуг'] },
            { from: '😱', to: '🤩', fromCodes: ['1f631'], toCode: '1f929', toShortcode: 'star_struck', names: ['scream', 'крик_ужаса', 'паника'] },
            { from: '😮‍💨', to: '😌', fromCodes: ['1f62e-200d-1f4a8'], toCode: '1f60c', toShortcode: 'relieved', names: ['face_exhaling', 'тяжкий_вздох'] },
            { from: '😵', to: '🤩', fromCodes: ['1f635'], toCode: '1f929', toShortcode: 'star_struck', names: ['dizzy_face', 'головокружение', 'нокаут', 'крестики_глаза'] },
            { from: '😵‍💫', to: '💫', fromCodes: ['1f635-200d-1f4ab'], toCode: '1f4ab', toShortcode: 'dizzy', names: ['face_with_spiral_eyes', 'спирали_глаза'] },
            { from: '🥶', to: '☀️', fromCodes: ['1f976'], toCode: '2600', toShortcode: 'sunny', names: ['cold_face', 'замерз', 'мороз'] },
            { from: '🥵', to: '🍦', fromCodes: ['1f975'], toCode: '1f366', toShortcode: 'icecream', names: ['hot_face', 'жара', 'перегрев'] },

            // 8. Anger, wrath, demonic hostility
            { from: '😡', to: '😸', fromCodes: ['1f621'], toCode: '1f638', toShortcode: 'grinning_cat', names: ['rage', 'злость', 'ярость', 'гнев'] },
            { from: '😠', to: '😺', fromCodes: ['1f620'], toCode: '1f63a', toShortcode: 'smiley_cat', names: ['angry', 'сердитый'] },
            { from: '🤬', to: '😇', fromCodes: ['1f92c'], toCode: '1f607', toShortcode: 'innocent', names: ['cursing_face', 'ругань', 'мат'] },
            { from: '😤', to: '💪', fromCodes: ['1f624'], toCode: '1f4aa', toShortcode: 'muscle', names: ['triumph', 'пар_из_носа', 'ярость_пар', 'бешенство'] },
            { from: '😾', to: '😻', fromCodes: ['1f63e'], toCode: '1f63b', toShortcode: 'heart_eyes_cat', names: ['pouting_cat', 'сердитый_кот'] },
            { from: '👿', to: '🤠', fromCodes: ['1f47f'], toCode: '1f920', toShortcode: 'cowboy', names: ['imp', 'злой_черт'] },
            { from: '😈', to: '😜', fromCodes: ['1f608'], toCode: '1f61c', toShortcode: 'stuck_out_tongue_winking_eye', names: ['smiling_imp', 'дьявол', 'чертенок'] },
            { from: '👺', to: '🎭', fromCodes: ['1f47a'], toCode: '1f3ad', toShortcode: 'performing_arts', names: ['japanese_goblin', 'гоблин', 'демон'] },
            { from: '👹', to: '🦁', fromCodes: ['1f479'], toCode: '1f981', toShortcode: 'lion_face', names: ['japanese_ogre', 'они', 'чудовище', 'монстр'] },

            // 9. Disgust, sickness, poop, poisons
            { from: '🤮', to: '😋', fromCodes: ['1f92e'], toCode: '1f60b', toShortcode: 'yum', names: ['vomiting', 'рвота', 'тошнота'] },
            { from: '🤢', to: '😋', fromCodes: ['1f922'], toCode: '1f60b', toShortcode: 'yum', names: ['nauseated_face', 'мутит', 'зеленый'] },
            { from: '🤧', to: '🌸', fromCodes: ['1f927'], toCode: '1f338', toShortcode: 'cherry_blossom', names: ['sneezing_face', 'чихание', 'простуда'] },
            { from: '😷', to: '😎', fromCodes: ['1f637'], toCode: '1f60e', toShortcode: 'sunglasses', names: ['mask', 'маска', 'болезнь'] },
            { from: '🤒', to: '☀️', fromCodes: ['1f912'], toCode: '2600', toShortcode: 'sunny', names: ['thermometer_face', 'температура', 'градусник'] },
            { from: '🤕', to: '💖', fromCodes: ['1f915'], toCode: '1f496', toShortcode: 'sparkling_heart', names: ['head_bandage', 'бинт', 'травма'] },
            { from: '💩', to: '🧁', fromCodes: ['1f4a9'], toCode: '1f9c1', toShortcode: 'cupcake', names: ['poop', 'shit', 'какашка', 'говно', 'дерьмо'] },
            { from: '☣️', to: '🍀', fromCodes: ['2623-fe0f', '2623'], toCode: '1f340', toShortcode: 'four_leaf_clover', names: ['biohazard', 'биохазард', 'биологическая_опасность', 'токсично'] },
            { from: '☣', to: '🍀', fromCodes: ['2623'], toCode: '1f340', toShortcode: 'four_leaf_clover', names: ['biohazard'] },
            { from: '☢️', to: '🌻', fromCodes: ['2622-fe0f', '2622'], toCode: '1f33b', toShortcode: 'sunflower', names: ['radioactive', 'радиация', 'радиоактивно'] },
            { from: '☢', to: '🌻', fromCodes: ['2622'], toCode: '1f33b', toShortcode: 'sunflower', names: ['radioactive'] },
            { from: '💉', to: '🧃', fromCodes: ['1f489'], toCode: '1f9c3', toShortcode: 'beverage_box', names: ['syringe', 'шприц', 'укол'] },
            { from: '💊', to: '🍬', fromCodes: ['1f48a'], toCode: '1f36c', toShortcode: 'candy', names: ['pill', 'таблетка', 'пилюля'] },

            // 10. Aggression, violence, weapons, broken hearts
            { from: '🖕', to: '✌️', fromCodes: ['1f595'], toCode: '270c', toShortcode: 'peace', names: ['middle_finger', 'фак', 'средний_палец'] },
            { from: '👎', to: '👍', fromCodes: ['1f44e'], toCode: '1f44d', toShortcode: 'thumbsup', names: ['thumbsdown', 'дизлайк', 'палец_вниз'] },
            { from: '👊', to: '🤝', fromCodes: ['1f44a'], toCode: '1f91d', toShortcode: 'handshake', names: ['punch', 'fist', 'удар', 'кулак'] },
            { from: '🤛', to: '🤝', fromCodes: ['1f91b'], toCode: '1f91d', toShortcode: 'handshake', names: ['left_facing_fist', 'левый_кулак'] },
            { from: '🤜', to: '🤝', fromCodes: ['1f91c'], toCode: '1f91d', toShortcode: 'handshake', names: ['right_facing_fist', 'правый_кулак'] },
            { from: '💔', to: '❤️', fromCodes: ['1f494'], toCode: '2764', toShortcode: 'heart', names: ['broken_heart', 'разбитое_сердце'] },
            { from: '🖤', to: '💖', fromCodes: ['1f5a4'], toCode: '1f496', toShortcode: 'sparkling_heart', names: ['black_heart', 'черное_сердце'] },
            { from: '🩶', to: '💖', fromCodes: ['1fa76'], toCode: '1f496', toShortcode: 'sparkling_heart', names: ['grey_heart', 'gray_heart', 'серое_сердце'] },
            { from: '💣', to: '🎆', fromCodes: ['1f4a3'], toCode: '1f386', toShortcode: 'fireworks', names: ['bomb', 'бомба'] },
            { from: '💥', to: '🎉', fromCodes: ['1f4a5'], toCode: '1f389', toShortcode: 'tada', names: ['collision', 'boom', 'взрыв', 'бабах'] },
            { from: '🔪', to: '🍰', fromCodes: ['1f52a'], toCode: '1f370', toShortcode: 'cake', names: ['hocho', 'knife', 'нож'] },
            { from: '🗡️', to: '🪄', fromCodes: ['1f5e1-fe0f', '1f5e1'], toCode: '1fa84', toShortcode: 'magic_wand', names: ['dagger', 'кинжал'] },
            { from: '🗡', to: '🪄', fromCodes: ['1f5e1'], toCode: '1fa84', toShortcode: 'magic_wand', names: ['dagger'] },
            { from: '⚔️', to: '🎸', fromCodes: ['2694-fe0f', '2694'], toCode: '1f3b8', toShortcode: 'guitar', names: ['crossed_swords', 'мечи'] },
            { from: '⚔', to: '🎸', fromCodes: ['2694'], toCode: '1f3b8', toShortcode: 'guitar', names: ['crossed_swords'] },
            { from: '🪓', to: '🌲', fromCodes: ['1fa93'], toCode: '1f332', toShortcode: 'evergreen_tree', names: ['axe', 'топор'] },
            { from: '🔫', to: '🫧', fromCodes: ['1f52b'], toCode: '1fae7', toShortcode: 'bubbles', names: ['gun', 'pistol', 'пистолет', 'пушка', 'водяной_пистолет'] },
            { from: '🏹', to: '🎯', fromCodes: ['1f3f9'], toCode: '1f3af', toShortcode: 'dart', names: ['bow_and_arrow', 'лук', 'стрела'] },
            { from: '🛡️', to: '🌟', fromCodes: ['1f6e1-fe0f', '1f6e1'], toCode: '1f31f', toShortcode: 'star2', names: ['shield', 'щит', 'броня'] },
            { from: '🛡', to: '🌟', fromCodes: ['1f6e1'], toCode: '1f31f', toShortcode: 'star2', names: ['shield'] },
            { from: '🪢', to: '🎀', fromCodes: ['1faa2'], toCode: '1f380', toShortcode: 'ribbon', names: ['knot', 'узел', 'петля'] },
            { from: '🧨', to: '🎉', fromCodes: ['1f9e8'], toCode: '1f389', toShortcode: 'tada', names: ['firecracker', 'динамит', 'петарда'] },

            // 11. Innuendo -> positive fruits
            { from: '🍆', to: '🍎', fromCodes: ['1f346'], toCode: '1f34e', toShortcode: 'apple', names: ['eggplant', 'aubergine', 'баклажан'] },
            { from: '🍑', to: '🍉', fromCodes: ['1f351'], toCode: '1f349', toShortcode: 'watermelon', names: ['peach', 'персик'] },

            // 12. Gloomy, depressing weather
            { from: '🌧️', to: '☀️', fromCodes: ['1f327-fe0f', '1f327'], toCode: '2600', toShortcode: 'sunny', names: ['cloud_rain', 'дождь', 'пасмурно'] },
            { from: '🌧', to: '☀️', fromCodes: ['1f327'], toCode: '2600', toShortcode: 'sunny', names: ['cloud_rain'] },
            { from: '⛈️', to: '🌈', fromCodes: ['26c8-fe0f', '26c8'], toCode: '1f308', toShortcode: 'rainbow', names: ['thunder_cloud_rain', 'гроза'] },
            { from: '⛈', to: '🌈', fromCodes: ['26c8'], toCode: '1f308', toShortcode: 'rainbow', names: ['thunder_cloud_rain'] },
            { from: '🌩️', to: '⚡', fromCodes: ['1f329-fe0f', '1f329'], toCode: '26a1', toShortcode: 'zap', names: ['cloud_lightning', 'молния_облако'] },
            { from: '🌩', to: '⚡', fromCodes: ['1f329'], toCode: '26a1', toShortcode: 'zap', names: ['cloud_lightning'] },
            { from: '🌫️', to: '🌤️', fromCodes: ['1f32b-fe0f', '1f32b'], toCode: '1f324', toShortcode: 'sun_behind_small_cloud', names: ['fog', 'туман'] },
            { from: '🌫', to: '🌤️', fromCodes: ['1f32b'], toCode: '1f324', toShortcode: 'sun_behind_small_cloud', names: ['fog'] },

            // 13. Negative cross marks, bans, refusal -> calm neutral marks
            { from: '❌', to: '⚪', fromCodes: ['274c'], toCode: '26aa', toShortcode: 'white_circle', names: ['x', 'cross_mark', 'крестик', 'крест', 'отмена'] },
            { from: '❎', to: '🔘', fromCodes: ['274e'], toCode: '1f518', toShortcode: 'radio_button', names: ['negative_squared_cross_mark', 'квадратный_крестик'] },
            { from: '✖️', to: '⚪', fromCodes: ['2716-fe0f', '2716'], toCode: '26aa', toShortcode: 'white_circle', names: ['heavy_multiplication_x', 'умножение'] },
            { from: '✖', to: '⚪', fromCodes: ['2716'], toCode: '26aa', toShortcode: 'white_circle', names: ['heavy_multiplication_x'] },
            { from: '🚫', to: '🔘', fromCodes: ['1f6ab'], toCode: '1f518', toShortcode: 'radio_button', names: ['no_entry_sign', 'prohibited', 'запрещено'] },
            { from: '⛔', to: '⚪', fromCodes: ['26d4'], toCode: '26aa', toShortcode: 'white_circle', names: ['no_entry', 'кирпич', 'въезд_запрещен'] },
            { from: '🛑', to: '🔘', fromCodes: ['1f6d1'], toCode: '1f518', toShortcode: 'radio_button', names: ['octagonal_sign', 'stop', 'стоп'] }
        ];
    }

    start() {
        // start() is reachable more than once -- BetterDiscord's enable toggle,
        // a plugin hot-reload, or a throw between two starts. Unwind the prior
        // lifecycle first: re-wrapping history[name] without unwinding leaves the
        // previous wrapper installed AFTER stop(), and re-nulling sweepTimer
        // orphans a timer id that stop() can no longer reach.
        if (this.observer || this.sweepTimer || this.__historyRestore) this.stop();
        this.initMaps();
        this.processTree(document.body);
        this.startObserver();
        this.updateCardDescription();
        // PERF-004 (audit/7.md, SRC-018:R016): the MutationObserver above already
        // watches the complete subtree for childList / characterData and the
        // exact relevant image/text attributes, and incrementally processes every
        // changed node. The old unconditional 2,000 ms setInterval duplicated that
        // coverage with a body-wide image query and a body-wide tooltip query on
        // an idle heartbeat -- O(current DOM size) forever, with no dirty flag and
        // no visibility gate. Removed. A bounded reconciliation is scheduled ONLY
        // when there is a reason to believe work was missed:
        //   * the tab returns to the foreground (visibilitychange), because
        //     Chromium coalesces/parks observer callbacks while hidden;
        //   * a Discord route change the observer cannot see as a single record
        //     (history pushState/replaceState), coalesced.
        // Both paths go through ONE coalesced timer with an adaptive backoff, so
        // there is never a fixed idle sweep and never more than one pending.
        this.sweepTimer = null;
        this.reconcileDelay = GoodEmoji.RECONCILE_MIN_MS;
        this.onVisibility = () => {
            if (typeof document !== 'undefined' && document.visibilityState === 'visible') {
                this.requestReconcile(0);
            }
        };
        this.onRouteChange = () => { this.requestReconcile(this.reconcileDelay); };
        try { document.addEventListener('visibilitychange', this.onVisibility); } catch (e) { }
        try {
            const wrap = (name) => {
                const orig = history[name];
                if (typeof orig !== 'function') return;
                history[name] = (...args) => {
                    const r = orig.apply(history, args);
                    this.onRouteChange();
                    return r;
                };
                this.__historyRestore = this.__historyRestore || [];
                this.__historyRestore.push([name, orig]);
            };
            wrap('pushState');
            wrap('replaceState');
        } catch (e) { }
        const strings = GoodEmoji.getStrings();
        console.log(strings.started);
    }

    // One bounded, coalesced reconciliation. Nothing schedules it while idle;
    // an unchanged document performs zero global scans between events.
    requestReconcile(delayMs) {
        if (this.sweepTimer) clearTimeout(this.sweepTimer);
        const d = Math.max(delayMs || 0, 0);
        this.sweepTimer = setTimeout(() => {
            this.sweepTimer = null;
            if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return;
            this.reconcile();
            // Adaptive backoff: a burst of route changes widens the window rather
            // than permitting a scan per event. It never becomes a heartbeat --
            // it only delays the NEXT activity-triggered scan.
            this.reconcileDelay = Math.min(this.reconcileDelay * 2, GoodEmoji.RECONCILE_MAX_MS);
        }, d);
    }

    reconcile() {
        const root = document.body;
        if (!root) return;
        const imgs = root.querySelectorAll('img.emoji, [class*="reaction"] img, img[class*="emoji"], [role="tooltip"] img, [class*="tooltip"] img');
        for (let i = 0; i < imgs.length; i++) {
            this.processImg(imgs[i]);
        }
        const tooltips = root.querySelectorAll('[role="tooltip"], [class*="tooltipContent"], [class*="tooltip-"]');
        for (let i = 0; i < tooltips.length; i++) {
            const walker = document.createTreeWalker(tooltips[i], NodeFilter.SHOW_TEXT, null, false);
            let textNode;
            while ((textNode = walker.nextNode())) {
                this.processTextNode(textNode);
            }
        }
    }

    stop() {
        if (this.sweepTimer) {
            clearTimeout(this.sweepTimer);
            this.sweepTimer = null;
        }
        if (this.observer) {
            this.observer.disconnect();
            this.observer = null;
        }
        try { document.removeEventListener('visibilitychange', this.onVisibility); } catch (e) { }
        if (this.__historyRestore) {
            // LIFO: each wrapper captured the function it replaced, so unwinding
            // in insertion order would install the newest wrapper rather than
            // the native and leave a stopped plugin mutating the DOM.
            for (let i = this.__historyRestore.length - 1; i >= 0; i--) {
                const [name, orig] = this.__historyRestore[i];
                try { history[name] = orig; } catch (e) { }
            }
            this.__historyRestore = null;
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

        const skinTones = ['\u{1F3FB}', '\u{1F3FC}', '\u{1F3FD}', '\u{1F3FE}', '\u{1F3FF}'];
        const skinToneHexes = ['1f3fb', '1f3fc', '1f3fd', '1f3fe', '1f3ff'];

        for (const item of GoodEmoji.MAPPINGS) {
            // 1. Base unicode
            this.textMap[item.from] = item.to;
            this.unicodeToItem[item.from] = item;
            chars.push(item.from);

            // 2. Unicode with variation selector \uFE0F
            if (!item.from.includes('\uFE0F')) {
                const withFe0f = item.from + '\uFE0F';
                this.textMap[withFe0f] = item.to;
                this.unicodeToItem[withFe0f] = item;
                chars.push(withFe0f);
            }

            // 3. Unicode with Fitzpatrick skin tones (e.g. 🖕🏻, 🖕🏼...)
            for (const tone of skinTones) {
                const withTone = item.from + tone;
                this.textMap[withTone] = item.to;
                this.unicodeToItem[withTone] = item;
                chars.push(withTone);

                const withFe0fTone = item.from + '\uFE0F' + tone;
                this.textMap[withFe0fTone] = item.to;
                this.unicodeToItem[withFe0fTone] = item;
                chars.push(withFe0fTone);
            }

            // 4. Hex codes (with and without skin tones)
            for (const code of item.fromCodes) {
                const c = code.toLowerCase();
                this.codeToItem[c] = item;

                for (const tHex of skinToneHexes) {
                    this.codeToItem[c + '-' + tHex] = item;
                }
            }

            // 5. Shortcodes and names. These are LOOKUP keys only (matchEmojiString
            // resolves an already-known emoji name/attribute); they are deliberately
            // NOT added to textMap/chars, which drive the regex that rewrites every
            // text node in document.body. Registering ':rat:' or ':x:' there made the
            // plugin silently rewrite the user's own authored text -- Discord never
            // expands those, so the user only sees their words mutate.
            for (const name of item.names) {
                const n = name.toLowerCase();
                this.nameToItem[n] = item;
                this.nameToItem[':' + n + ':'] = item;

                for (let i = 1; i <= 5; i++) {
                    const toneName = n + '_tone' + i;
                    this.nameToItem[toneName] = item;
                    this.nameToItem[':' + toneName + ':'] = item;
                }
                // Discord's skin-tone shortcode is ':name:skin-tone-N:' -- one
                // colon between the name and the suffix. matchEmojiString strips
                // the outer colons before the suffix, so the key carries none.
                for (let t = 1; t <= 6; t++) {
                    this.nameToItem[n + ':skin-tone-' + t] = item;
                }
            }
        }

        const uniqueChars = Array.from(new Set(chars));
        uniqueChars.sort((a, b) => b.length - a.length);
        const escaped = uniqueChars.map(s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
        this.textRegex = new RegExp(escaped.join('|'), 'gu');
    }

    matchEmojiString(str) {
        if (!str || typeof str !== 'string') return null;
        const trimmed = str.trim();
        if (!trimmed) return null;

        // 1. Direct match (covers base, variation selectors, and direct tone mappings)
        if (this.unicodeToItem[trimmed]) return this.unicodeToItem[trimmed];
        if (this.nameToItem[trimmed]) return this.nameToItem[trimmed];

        // 2. Strip Unicode skin tones & variation selectors
        const strippedUnicode = trimmed.replace(/[\u{1F3FB}-\u{1F3FF}\uFE0E\uFE0F]/gu, '');
        if (this.unicodeToItem[strippedUnicode]) return this.unicodeToItem[strippedUnicode];

        // 3. Clean shortcode: strip colons, tone suffixes
        const cleanName = trimmed
            .replace(/^:+|:+$/g, '')
            .toLowerCase()
            .replace(/[:_ -]?tone[1-5]$/i, '')
            .replace(/:skin-tone-[1-6]$/i, '')
            .replace(/[:_ -]?(?:light|medium_light|medium|medium_dark|dark)(?:_skin_tone)?$/i, '');

        if (this.nameToItem[cleanName]) return this.nameToItem[cleanName];

        return null;
    }

    matchSrc(src) {
        if (!src || typeof src !== 'string') return null;

        // Extract hex filename (e.g. 1f595-1f3fb from https://.../1f595-1f3fb.png)
        const match = src.match(/(?:^|[/_])([0-9a-fA-F]+(?:-[0-9a-fA-F]+)*)\.(?:svg|png|webp|gif)(?:[?#]|$)/i);
        if (match) {
            const rawHex = match[1].toLowerCase();
            if (this.codeToItem[rawHex]) return this.codeToItem[rawHex];

            // Strip Fitzpatrick modifier hexes (-1f3fb .. -1f3ff)
            const strippedTone = rawHex.replace(/-(?:1f3fb|1f3fc|1f3fd|1f3fe|1f3ff)\b/gi, '');
            if (this.codeToItem[strippedTone]) return this.codeToItem[strippedTone];

            // Strip variation selectors (-fe0e, -fe0f)
            const strippedFe = strippedTone.replace(/-(?:fe0e|fe0f)\b/gi, '');
            if (this.codeToItem[strippedFe]) return this.codeToItem[strippedFe];

            // Strip gender ZWJ sequences (-200d-264[02])
            const strippedGender = strippedFe.replace(/-200d-264[02]\b/gi, '');
            if (this.codeToItem[strippedGender]) return this.codeToItem[strippedGender];
        }

        // PERF-005 (audit/7.md, SRC-018:R017): bounded fallback. The old code
        // ran Object.entries(this.codeToItem) and up to three src.includes per
        // code for EVERY unmatched image -- measured 2,880,000 String.includes
        // for 1,000 ordinary unmatched URLs, plus a fresh ~960-entry array per
        // call. Matching is now proportional to URL LENGTH: tokenize only
        // complete delimited filename tokens and resolve each token (and its
        // hyphen prefixes) through the O(1) codeToItem map. The `/` or `_`
        // boundary on the left and the supported image extension plus query/
        // fragment/end boundary on the right prevent bare IDs, path children,
        // and identifiers such as `not1f62d.png` from becoming emoji.
        const runRe = /(?:^|[/_])([0-9a-fA-F]+(?:-[0-9a-fA-F]+)*)\.(?:svg|png|webp|gif)(?=[?#]|$)/ig;
        let m;
        while ((m = runRe.exec(src)) !== null) {
            let cand = m[1].toLowerCase();
            for (;;) {
                const hit = this.codeToItem[cand];
                if (hit) return hit;
                const dash = cand.lastIndexOf('-');
                if (dash < 0) break;
                cand = cand.slice(0, dash);
            }
        }

        return null;
    }

    processImg(img) {
        if (!img || !img.getAttribute) return;

        const src = img.getAttribute('src') || '';
        const alt = img.getAttribute('alt') || '';
        const aria = img.getAttribute('aria-label') || '';
        const title = img.getAttribute('title') || '';
        const dataName = img.getAttribute('data-name') || '';

        let matchedItem =
            this.matchEmojiString(alt) ||
            this.matchEmojiString(aria) ||
            this.matchEmojiString(dataName) ||
            this.matchEmojiString(title) ||
            this.matchSrc(src);

        // Check parent reaction button or button tooltip
        if (!matchedItem) {
            const parent = img.closest?.('[class*="reaction"], [role="button"]');
            if (parent) {
                const pAria = parent.getAttribute('aria-label') || '';
                matchedItem = this.matchEmojiString(pAria);
                if (!matchedItem) {
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
        }

        if (!matchedItem) return;

        const targetSrc = 'https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/svg/' + matchedItem.toCode + '.svg';
        if (img.dataset.goodEmojiReplaced === matchedItem.toCode && (img.getAttribute('src') === targetSrc || img.src === targetSrc)) {
            return;
        }

        if (img.hasAttribute('srcset')) {
            img.removeAttribute('srcset');
        }

        img.setAttribute('src', targetSrc);
        img.src = targetSrc;

        const toShortcode = ':' + (matchedItem.toShortcode || matchedItem.names[0]) + ':';

        img.setAttribute('alt', matchedItem.to);
        if (img.hasAttribute('title') || title) {
            img.setAttribute('title', toShortcode);
        }
        if (img.hasAttribute('aria-label') || aria) {
            img.setAttribute('aria-label', toShortcode);
        }
        if (img.hasAttribute('data-name') || dataName) {
            img.setAttribute('data-name', toShortcode);
        }

        img.dataset.goodEmojiReplaced = matchedItem.toCode;
        img.dataset.goodEmojiDone = 'true';

        const reactionBtn = img.closest?.('[class*="reaction"], [role="button"]');
        if (reactionBtn) {
            const pAria = reactionBtn.getAttribute('aria-label');
            if (pAria) {
                let updated = pAria;
                if (pAria.includes(matchedItem.from)) {
                    updated = updated.replaceAll(matchedItem.from, matchedItem.to);
                }
                for (const name of matchedItem.names) {
                    updated = updated.replace(new RegExp(':' + name + '(?:_tone[1-5])?:', 'gi'), toShortcode);
                }
                if (updated !== pAria) {
                    reactionBtn.setAttribute('aria-label', updated);
                }
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
        const target = document.body || document.documentElement;
        if (!target) return;
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
            attributeFilter: ['src', 'alt', 'aria-label', 'title', 'data-name']
        });
    }
};
