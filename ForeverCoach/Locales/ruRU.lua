-- Русские строки. Загружаются только в русском клиенте; чего нет здесь — берётся из enUS.lua.
-- Названия заклинаний и предметов в аддоне не хранятся: их отдаёт клиент по ID.
local ADDON, ns = ...
if GetLocale() ~= "ruRU" then return end

local L = ns.L

-- 1 враг, 2 врага, 5 врагов, 21 враг
function ns.Plural(n, forms)
    local m10, m100 = n % 10, n % 100
    if m10 == 1 and m100 ~= 11 then return forms[1] end
    if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then return forms[2] end
    return forms[3]
end

L.BINDING_TOGGLE = "Показать или скрыть подсказки"
L.BINDING_BUILDS = "Окно «Билды»"
L.BINDING_PLAN = "Окно «Планировщик»"
L.BINDING_RECAP = "Окно «Разбор боя»"
L.BINDING_SETTINGS = "Настройки"

L.LOADED = "ForeverCoach %s загружен. /fc — настройки, /fc help — команды."
L.HELP = {
    "/fc — настройки",
    "/fc toggle — показать или скрыть подсказки",
    "/fc lock | unlock — закрепить или двигать блок подсказок",
    "/fc minimap — показать или скрыть кнопку у мини-карты",
    "/fc mode auto | leveling | group | pvp — закрепить режим",
    "/fc builds — окно билдов (Talents Forever)",
    "/fc plan — планировщик: учитель, таланты, предпросмотр уровня",
    "/fc recap — разбор боя (появится на этапе 3)",
    "/fc debug — писать в чат причину каждой подсказки",
    "/fc state — снимок игры, который видит аддон",
    "/fc perf — время обновления",
    "/fc surprises — неожиданные смены подсказки (clear — очистить)",
    "/fc reset — сбросить положение и настройки",
}
L.HINTS_SHOWN = "Подсказки показаны."
L.HINTS_HIDDEN = "Подсказки скрыты."
L.LOCKED = "Блок подсказок закреплён."
L.UNLOCKED = "Блок подсказок можно двигать мышью, затем /fc lock."
L.DEBUG_ON = "Отладка включена: причина каждой подсказки пишется в чат."
L.DEBUG_OFF = "Отладка выключена."
L.RESET_DONE = "Настройки сброшены."
L.MINIMAP_SHOWN = "Кнопка у мини-карты показана."
L.MINIMAP_HIDDEN = "Кнопка у мини-карты скрыта: /fc minimap вернёт её."
L.MODE_SET = "Режим: %s."
L.UNKNOWN_COMMAND = "Неизвестная команда. Список: /fc help."
L.NOT_YET = "Это окно появится на этапе %d (см. README)."
L.NO_CLASS_DATA = "Для твоего класса ротации пока нет: сначала чернокнижник, потом остальные."
L.DATA_OUTDATED = "Данные ротации сделаны для патча %s, а игра — %s: часть подсказок может устареть."
L.PROFILE_ACTIVE = "Профиль: %s%s"
L.PROFILE_APPROX = " (приблизительный)"
L.TF_CLOSEST = "Ближайший билд Talents Forever: #%d %s %s, совпадает %d%% твоих очков"
L.PERF = "Обновлений: %d, в среднем %.3f мс, максимум %.3f мс."
L.LUA_ERROR = "Ошибка в %s: %s"
L.BLOCKED = "Игра заблокировала действие аддона: %s. Пришли эту строку разработчику."
L.DEBUG_NONE = "подсказки нет: %s"
L.HIDDEN_SUFFIX = " (скрыто, принято %s)"
L.SURPRISE_LINE = "%s, %.0f с боя: вдруг %s, а в очереди было %s. %s"
L.SURPRISES_NONE = "Неожиданных смен подсказки пока не было."
L.SURPRISES_HEAD = "Неожиданных смен подсказки: %d, последние %d ниже. Они сохранены в WTF\\Account\\<учётная запись>\\<сервер>\\<персонаж>\\SavedVariables\\ForeverCoach.lua — пришли этот файл разработчику."
L.SURPRISES_CLEARED = "Список неожиданных смен подсказки очищен."
L.PRICE_UNKNOWN = "цена неизвестна"
L.COIN_GOLD = "з"
L.COIN_SILVER = "с"
L.COIN_COPPER = "м"

L.MODE_auto = "Авто"
L.MODE_leveling = "Прокачка"
L.MODE_group = "Группа"
L.MODE_pvp = "PvP"

L.AOE = "AoE: %d %s"
L.ENEMY_FORMS = { "враг", "врага", "врагов" }
L.READY = "готово"
L.WHY = "Почему: %s"
L.PROFILE = "Профиль: %s"
L.OUT_OF_RANGE = "Цель далеко"
L.NO_MANA = "Не хватает маны"
L.UNLOCKED_LABEL = "ForeverCoach\nтащи меня"

L.PREP_NO_PET = "Демон не призван"
L.PREP_NO_HEALTHSTONE = "Нет Камня здоровья"
L.PREP_NO_ARMOR = "Нет демонической брони"
L.PREP_FEW_SHARDS = "Мало осколков души: %d"
L.PREP_TRAINER = "У учителя ждут заклинания: %d"

L.WHY_FILLER = "наполнитель: ничего важнее сейчас нет"
L.WHY_DOT = "твоего периодического эффекта нет или он вот-вот спадёт, а цель проживёт достаточно"
L.WHY_CURSE = "на цели нет твоего проклятия"
L.WHY_PROC = "прок: следующее заклинание без времени произнесения"
L.WHY_EXECUTE_SHARD = "цель почти мертва: Похищение души даст осколок"
L.WHY_LIFE_TAP = "на следующее заклинание не хватает маны, а здоровья хватает: переведи здоровье в ману"
L.WHY_DRAIN_LIFE = "мало здоровья: лечись уроном"
L.WHY_WAND = "экономь ману: добей цель жезлом"
L.WHY_WAND_OOM = "мана кончилась: жезл"
L.WHY_HEALTHSTONE = "здоровье ниже порога: Камень здоровья"
L.WHY_POTION = "здоровье ниже порога, камня нет: выпей зелье"
L.WHY_DEATH_COIL = "здоровье ниже порога: Лик смерти лечит и обездвиживает врага"
L.WHY_SACRIFICE = "Демон Бездны умирает: принеси его в жертву ради щита"
L.WHY_HEALTH_FUNNEL = "демон умирает: подлечи его"
L.WHY_FEAR_SECOND = "на тебе второй враг: возьми его в цель и напугай"
L.WHY_HOWL = "рядом три врага и больше: напугай всех"
L.WHY_AMPLIFY = "сильный враг: усиль проклятие перед тем, как наложить"
L.WHY_AOE_RAIN = "три врага и больше: урон по площади"
L.WHY_AOE_HELLFIRE = "рядом три врага и больше: Адское пламя бьёт всех (и тебя тоже)"
L.WHY_PET_ATTACK = "демон стоит без дела"
L.WHY_PULL = "вне боя: начни с долгого заклинания"

L.SETTINGS_TITLE = "Настройки"
L.S_SECTION_LOOK = "ВНЕШНИЙ ВИД"
L.S_ICON_SIZE = "Размер главной иконки"
L.S_PX = "%d px"
L.S_ALPHA = "Прозрачность"
L.S_PERCENT = "%d%%"
L.S_NEXT = "Следующих иконок"
L.S_HIDE_OOC = "Прятать иконки вне боя"
L.S_HIGHLIGHT = "Подсвечивать кнопку на панелях"
L.S_SECTION_MODE = "РЕЖИМ"
L.S_MODE_HELP = "Авто: поле боя — PvP, подземелье или рейд — группа, всё остальное — прокачка."
L.S_SECTION_THRESHOLDS = "ПОРОГИ"
L.S_HP = "Камень здоровья, когда здоровья ниже"
L.S_PET_HP = "Канал здоровья, когда у демона ниже"
L.S_SHARDS = "Держать осколков души"
L.S_SECTION_SOUND = "ЗВУК"
L.S_SOUND_READY = "«Пора нажимать» — тихий щелчок"
L.S_SOUND_PROC = "Мгновенный прок — звонкий сигнал"
L.S_VOLUME = "Громкость"
L.S_SOUND_NOTE = "Щелчок не звучит, если кнопка уже нажата заранее."
L.S_SECTION_KEYS = "КЛАВИШИ"
L.S_KEY_TOGGLE = "Показать или скрыть подсказки"
L.S_KEY_WINDOWS = "Билды, планировщик, разбор боя"
L.S_KEY_NONE = "не назначено"
L.S_OPEN_KEYS = "Открыть назначение клавиш"
L.S_FOOTER = "Билды: |cffF2C94CTalents Forever|r (baldwinbuilds), соавтор, v%s"
L.S_RESET = "Сбросить"
L.S_DONE = "Готово"

L.MINIMAP_TIP_LEFT = "Левая кнопка: настройки"
L.MINIMAP_TIP_RIGHT = "Правая кнопка: показать или скрыть подсказки"
L.MINIMAP_TIP_DRAG = "Перетащить: сдвинуть кнопку"

-- Числа: 4 884
L.THOUSANDS = " "

L.TREE_Affliction = "Колдовство"
L.TREE_Demonology = "Демонология"
L.TREE_Destruction = "Разрушение"

L.QUEST_voidwalker = "Демон Бездны"
L.QUEST_succubus = "Суккуб"
L.QUEST_felhunter = "Охотник Скверны"
L.QUEST_felsteed = "Конь Скверны"

L.NOTE_drain_life = "лечит тебя за счёт врага"
L.NOTE_health_funnel = "лечит демона"
L.NOTE_life_tap = "здоровье в ману"
L.NOTE_fear = "выводит врага из боя на время"
L.NOTE_drain_soul = "осколок души с умирающего врага"
L.NOTE_corruption = "урон со временем, мгновенно"
L.NOTE_curse_of_agony = "проклятие: урон со временем"
L.NOTE_curse_of_weakness = "проклятие: враг бьёт слабее"
L.NOTE_immolate = "огонь и горение"
L.NOTE_siphon_life = "урон со временем, лечит тебя"
L.NOTE_rain_of_fire = "урон по площади"
L.NOTE_hellfire = "урон вокруг себя, ранит и тебя"
L.NOTE_death_coil = "лечит тебя и пугает врага"
L.NOTE_howl_of_terror = "пугает врагов вокруг"
L.NOTE_shadowburn = "мгновенный добивающий удар"
L.NOTE_conflagrate = "сжигает Жертвенный огонь ради урона"
L.NOTE_incinerate = "удар огнём, сильнее по горящей цели"
L.NOTE_searing_pain = "быстрый удар огнём"
L.NOTE_soul_fire = "сильный удар огнём за осколок души"
L.NOTE_create_healthstone = "камень, который лечит"
L.NOTE_demon_armor = "броня и восстановление здоровья"
L.NOTE_amplify_curse = "следующее проклятие сильнее"
L.NOTE_curse_of_doom = "огромный урон через минуту"

L.BUILDS_TITLE = "Билды"
L.B_TAB_all = "Все"
L.B_TAB_leveling = "Прокачка"
L.B_TAB_group = "PvE"
L.B_TAB_pvp = "PvP"
L.B_PASTE = "Вставить ссылку"
L.B_SUBTITLE = "Популярные билды из Talents Forever — обновляются каждый день"
L.B_SUBTITLE_ASOF = "Популярные билды из Talents Forever — обновляются каждый день (данные от %s)"
L.B_YOURS = "Твой"
L.B_CHOSEN = "Выбран"
L.B_LINK = "ссылка"
L.B_STATS = "Сохранили %s, открыли %s, %s похожих билдов"
L.B_STATS_LINK = "Билд по ссылке"
L.B_ROTATION = "РОТАЦИЯ ПОД ЭТОТ БИЛД"
L.B_ON_PROC = "%s\nпо проку"
L.B_COMPARE = "СРАВНЕНИЕ С ТВОИМИ ТАЛАНТАМИ"
L.B_ALL_MATCH = { "Вложенное %d очко совпадает с билдом", "Все %d вложенных очка совпадают с билдом",
                  "Все %d вложенных очков совпадают с билдом" }
L.B_NO_POINTS = "Очков талантов пока нет"
L.B_SOME_MATCH = "С билдом совпадают %d из %d очков"
L.B_NEXT_AT = "Следующее очко на %d ур.: %s"
L.B_NEXT_NOW = "Свободное очко — сейчас: %s"
L.B_DONE = "Билд собран полностью"
L.B_SPEC = "Спек %d"
L.B_SPEC2_LOCKED = "Спек 2 (с %d ур.)"
L.B_CHOOSE = "Выбрать билд"
L.B_UNCHOOSE = "Отменить выбор"
L.B_FOOTER = "Билды: |cffF2C94CTalents Forever|r (baldwinbuilds), соавтор, CC BY 4.0"
L.B_NO_TF = "Билды берутся из аддона Talents Forever (TalentsForeverBook). Установи его — и здесь появятся популярные билды."
L.B_EMPTY_TAB = "В этом списке пока нет билдов."
L.B_PASTE_HINT = "Вставь ссылку или код Talents Forever и нажми Enter"
L.B_BAD_LINK = "Это не похоже на ссылку или код Talents Forever."
L.B_AUTO = "Билд не выбран: ротация идёт по твоим талантам."
L.B_CHOSEN_MSG = "Спек %d: выбран билд %s %s."
L.B_UNCHOSEN_MSG = "Спек %d: билд не выбран, ротация идёт по твоим талантам."

L.PLANNER_TITLE = "Планировщик"
L.P_LEVEL = "%d уровень"
L.P_TRAINER_WAITS = { "У учителя ждёт %d заклинание", "У учителя ждут %d заклинания", "У учителя ждут %d заклинаний" }
L.P_TRAINER_NONE = "У учителя пока ничего нового"
L.P_TRAINER_NEXT = "следующее — на %d ур."
L.P_TRAINER_UNKNOWN = "зайди к учителю класса — аддон запомнит, где он"
L.P_NEEDS = "ЧТО НУЖНО ДЛЯ РОТАЦИИ БИЛДА"
L.P_NEEDS_NONE = "Всё выучено и стоит на панелях."
L.P_MORE = "и ещё %d"
L.P_RANK = ", ранг %d"
L.P_ST_trainer = "У учителя"
L.P_ST_talent = "Талант"
L.P_ST_nobar = "Нет на панели"
L.P_ST_level = "%d ур."
L.P_ST_quest = "Квест, %d ур."
L.P_SUB_TALENT_NOW = { "Свободно %d очко таланта", "Свободно %d очка таланта", "Свободно %d очков таланта" }
L.P_SUB_TALENT_AT = "Очко таланта на %d ур."
L.P_SUB_TALENT_SPELL = "Даёт талант билда"
L.P_SUB_NOBAR = "Выучен, но не стоит на панели"
L.P_SUB_LEVEL = { "Откроется через %d уровень", "Откроется через %d уровня", "Откроется через %d уровней" }
L.P_SUB_QUEST = "Классовый квест, начало у учителя"
L.P_PREVIEW = "ПРЕДПРОСМОТР УРОВНЯ"
L.P_NEW_AT = "Новое на %d ур."
L.P_NOTHING_NEW = "На этом уровне ничего нового"
L.P_RANKS_MORE = { "%d новый ранг", "%d новых ранга", "%d новых рангов" }
L.P_ROTATION_AT = "Ротация на %d ур."
L.P_QUESTS = "КЛАССОВЫЕ КВЕСТЫ"
L.P_QUEST_DONE = "выполнен"

L.MINIMAP_TIP_SHIFT = "Shift+клик: билды"
L.MINIMAP_TIP_CTRL = "Ctrl+клик: планировщик"
