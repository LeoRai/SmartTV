# Этап 0: разведка

От этого этапа зависит, на что движок может опираться в бою. Этап закрыт, когда есть три вещи:

- [ ] список «доступно / скрыто в бою» по отчёту `ForeverCoach_Probe`;
- [x] выбран способ получения билдов: прямо в игре из аддона Talents Forever (разрешение автора получено, раздел 2);
- [ ] принято решение по коду Hekili (сейчас: не берём, лицензия MIT);
- [x] понятно, с чем сверяться в Hekili Forever: у него есть редактируемые списки приоритетов (раздел 3).

## 1. Прогнать аддон разведки

Чернокнижником (или любым классом: аддон разведки работает для всех) с включёнными `ForeverCoach_Probe` и `ForeverCoach`:

1. **Мир.** Возьми моба в цель, повесь на него 2–3 своих дебаффа, подерись 15–20 секунд с призванным демоном. Повтори с двумя мобами сразу. Включи вражеские индикаторы здоровья (клавиша V).
2. **Подземелье.** Один-два боя в группе.
3. **Поле боя — отложено до этапа 5 (PvP).** Очереди на поля боя сейчас почти не собираются. Этапам 1–4 поле боя не нужно: им хватает мира и подземелий. `ForeverCoach_Probe` сам запишет ситуацию `battleground/combat`, как только попадёшь на поле боя, поэтому держи его включённым или поставь заново к этапу 5. Дуэль поле боя не заменяет: ограничения Midnight зависят от карты, а дуэль идёт в открытом мире. Но дуэль покажет, что видно о цели-игроке, поэтому её стоит провести, если будет возможность.
4. **Учитель.** Открой окно учителя своего класса: цены и уровни запишутся сами.
5. **Уровень и квест.** Если по пути взят уровень или сдан классовый квест, это тоже запишется само.
6. `/fcprobe dump` вне боя: книга заклинаний, таланты, способности демона.
7. `/fcprobe report`, затем Ctrl+A и Ctrl+C. Пришли текст и файл `WTF\Account\<аккаунт>\SavedVariables\ForeverCoach_Probe.lua`.

Заодно с включённым `ForeverCoach`:

- `/fc debug` в бою: в чате видно, что выбрано и почему. Значения со `*` скрыты игрой.
- `/fc state` вне боя и в бою: что видит аддон.
- `/fc perf` после пары боёв: среднее время обновления должно быть меньше 1 мс.
- Ошибки Lua (если будут) — скриншот или текст.

### Что смотрим в отчёте

| Проверка | Если в бою `secret` или `nil` | Что уже сделано в аддоне |
|---|---|---|
| `player.health`, `target.health` | нельзя посчитать порог защиты и время до смерти | допущения 100% и «цель живёт долго» |
| `player.mana` | нельзя посчитать «мало маны» | `player.oom` по `IsSpellUsable` |
| `aura.target.mine.*` | не видно своих дебаффов | свои таймеры от кастов |
| `aura.player.*` | не видно проков | подсветка заклинания клиентом, свои таймеры |
| `spell.cooldown.*`, `gcd.*` | не видно откатов | свои таймеры |
| `player.cast.spellID` | не видно текущего каста | события `UNIT_SPELLCAST_*` |
| событие `UNIT_SPELLCAST_SUCCEEDED` | **свои таймеры не работают** | решаем по результату |
| `nameplate.*` | нельзя посчитать врагов рядом | допущение «один враг» |
| `assisted.nextSpell` | — | если доступно: встроенный помощник Blizzard для сверки |
| регистрация `COMBAT_LOG_EVENT_UNFILTERED` | журнал боя закрыт (ожидаемо) | разбор боя строится на своих событиях |

## 2. Письмо автору Talents Forever

Кому: baldwinbuilds (страница [Talents Forever на CurseForge](https://www.curseforge.com/wow/addons/talents-forever), сайт [talentsforever.com](https://talentsforever.com/popular)).

> **Subject: ForeverCoach — using Talents Forever builds, with credit**
>
> Hi! I'm building ForeverCoach, a free, open-source rotation helper for WoW Forever (it only suggests the next ability; the player presses everything). I'd like Talents Forever to be its only source of builds, and to credit you as a co-author: in the in-game "Builds" window ("Builds: Talents Forever"), on the CurseForge page, in the description and in the AUTHORS file.
>
> Three questions:
>
> 1. **License.** ZBuilds mentions that your data is CC BY 4.0. Is it fine for ForeverCoach to ship popular builds (talent string, point order by level, popularity, date) with attribution? Is there anything you'd rather we didn't use?
> 2. **In-game access.** Could Talents Forever expose its builds to other addons (a global table, a small API, or a SavedVariables layout we could read when both addons are installed)? Builds would then always be fresh, and we'd point players to install Talents Forever.
> 3. **Offline export.** If not, is there a format you'd like us to use (JSON endpoint, export file) for a weekly offline script? Addons can't reach the internet, so the script would build a data file shipped with each ForeverCoach update.
>
> Also: what is the format of your build strings and links, so players can paste them into ForeverCoach manually?
>
> Thanks — the code is MIT on GitHub, and I'm happy to link back however you prefer.

От ответа зависел способ подключения из ТЗ: 1) прямо в игре → 2) выгрузка вне игры (`tools/build_data.py`) → 3) ручная вставка ссылки (работает всегда).

**Ответ автора (получен):**

- ForeverCoach может читать билды **напрямую из аддона Talents Forever**, когда оба установлены. Выбран способ 1, билды всегда свежие. Выгрузка вне игры (`tools/build_data.py`) не нужна.
- Автор просит указать его **соавтором в описании аддона**. Сделано: описание в `ForeverCoach.toc` (видно в списке аддонов), `AUTHORS.md`, README. На CurseForge — при публикации, в окне «Билды» — на этапе 2.
- Для этапа 2 нужно знать, где Talents Forever держит билды в игре: имя папки аддона, глобальная таблица или функции, формат строки билда. Ручная вставка ссылки остаётся запасным путём.

## 3. Hekili Forever

[Hekili Forever](https://www.curseforge.com/wow/addons/hekili-forever) (defzach, GPLv3) — эталон для сверки подсказок, его код не берём.

**Ответ на вопрос этапа 0.** В Hekili Forever уже есть редактируемые списки приоритетов — «Action Packs». По описанию на CurseForge это списки действий в стиле SimulationCraft со строками под правила Forever, ими можно делиться. Отсюда:

- сверка идёт на двух уровнях: подсказки в бою (оба аддона включены, причину расхождения видно в `/fc debug`) и сами приоритеты — их список против нашего профиля, строка за строкой;
- списки Hekili — только для сравнения. Перенос их строк в `Data/Profiles` — это использование частей Hekili, и тогда весь ForeverCoach переходит на GPLv3. Профили ForeverCoach пишутся самостоятельно;
- уточнить в игре или в их Discord/GitHub: как Action Packs экспортируются и есть ли уже пак для чернокнижника. По описанию сейчас в фокусе друид и воин, бета до 30 уровня.

Решение по коду: движок, язык условий и профили написаны с нуля, лицензия MIT. Если позже понадобится их код или списки, решение о GPLv3 записывается здесь.

## 4. По итогам

Заполняется после отчёта:

| Данные | В мире, в бою | В подземелье, в бою | На поле боя (этап 5) | Решение |
|---|---|---|---|---|
| здоровье свое / цели | | | | |
| мана | | | | |
| свои дебаффы на цели | | | | |
| проки на себе | | | | |
| откаты и ГКД | | | | |
| свои касты (события) | | | | |
| враги рядом | | | | |

Данные из выгрузки (ID заклинаний и рангов, таланты Forever, цены учителя, ID классовых квестов) переносятся в `Data/Spells/Warlock.lua` и `Data/Quests.lua`. После этого `verified = true`.
