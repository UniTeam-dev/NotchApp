# Brag Plan: NotchApp

## What is this app?
Панель macOS, раскрывающаяся из челки: сессии Claude Code и Cursor, музыка, полка файлов, Git-аккаунты, команды. Подсветка «Аура» показывает состояние агента цветом.

## The angle
Знакомая боль разработчика: агент час назад остановился и ждёт разрешения, а ты в другом окне. NotchApp превращает челку в светофор для агентов. Юмор сухой, из ситуации, без гиперболы.

## Hook (0–4.4s)
Чёрный экран, челка, янтарное дыхание по бокам. Строка 1: «Claude Code ждёт разрешения.» Строка 2: «Уже 40 минут.»

## Key moments
- Челка раскрывается: вкладка «Агенты», бейдж «1 ждёт вас», три строки сессий по одной (api-gateway, web-client, docs-site — вымышленные имена).
- Курсор кликает по строке с янтарной точкой — окно поднимается (симулированный клик).
- Аура: цвет = состояние (синий работает → янтарный ждёт разрешения → зелёный готово), оттенок = IDE (коралл Claude, лёд Cursor).
- Пять вкладок по очереди подсвечиваются; на Git щёлкает тумблер аккаунта, на «Терминале» кнопка команды.

## Outro / punchline
Иконка приложения, «NotchApp», «Челка, которая знает, кто вас ждёт.»

## User flow worth showing
Агент останавливается на запросе → челка светится янтарным → раскрыть, увидеть сессию → клик, окно агента на переднем плане.

## Tone
- Preset: default
- Creative direction: сухой dev-юмор, тёмный премиальный продуктовый ролик
- Interpretation: спокойный темп, крупная типографика, юмор только в двух хук-строках; дальше продукт говорит сам.

## Format: landscape — 1920x1080
## Duration: 21s

## Visual identity (from the project)
- Background: #050506 (иконка: #08080C)
- Panel: #000000, кромка rgba(255,255,255,.08)
- Text: белый, вторичный rgba(255,255,255,.6)
- Состояния: working #5C9EFF, waitingPermission #FF9E33, waitingInput #FFD647, done #59D480, error #FF615C
- Оттенки IDE: Claude #E08A5E, Cursor #CFD9E3
- Шрифт: системный SF (в приложении `.system`), кириллица

## Share caption
NotchApp: челка Mac, которая светится, когда Claude Code или Cursor ждут вас. Цвет — состояние, оттенок — IDE.

## Audio direction
- Role: sparse professional accents
- Music: happy-beats vol-12 (≈110 BPM), спокойный чистый бит
- Music treatment: старт с 0, громкость 0.30, фейд-аут последние 1.5s
- Music cue guidance: bundled preset. Strong cues 8.74, 10.93, 13.11, 17.47, 18.56. Сетка битов 0.56 / 1.09 / 1.64 / 2.19 / 2.73 / 3.27 / 3.82 / 4.39 / 4.91 / 6.00 / 6.56 / 7.09…
- Audio-reactive treatment: subtle; RMS музыки чуть дышит яркостью ауры. Без эквалайзеров и волн.
- SFX posture: sparse, motion-matched
- Audio-coupled moments: раскрытие панели, клик по строке, щелчок тумблера, финальный акцент
- Restraint rule: без SFX на каждом появлении текста

## Storyboard

### Scene 1 — Hook — 4.4s
Чёрный экран с меню-баром и челкой. Янтарное дыхание по бокам. 0.5s: «Claude Code ждёт разрешения.» (hold ≥1.6s). 2.3s: «Уже 40 минут.» (hold до 4.2s).
Sequential/interaction: две строки друг за другом
Audio intent: тихое напряжение
Audio-coupled idea: none
Transition mood: clean, челка раскрывается на бите 4.39 → Scene 2

### Scene 2 — Reveal + click — 4.6s (4.4–9.0)
Панель раскрывается, «Агенты», бейдж «1 ждёт вас». Строки по одной: api-gateway · Claude Code · ждёт разрешения; web-client · Cursor · работает; docs-site · Claude Code · готово. Курсор кликает по первой, строка вспыхивает, подпись «Окно агента — на переднем плане».
Sequential/interaction: yes — три строки по одной, затем клик (строки — UI, после появления держатся ≥2s)
Audio intent: открытие, мягкий удар; клик
Audio-coupled idea: card-drop на первой строке, mouse click
Transition mood: clean → Scene 3

### Scene 3 — Aura — 4.1s (9.0–13.1)
Крупно челка с аурой. Заголовок: «Цвет — состояние. Оттенок — IDE.» Аура меняется: синий «работает» (9.29) → янтарный «ждёт разрешения» (10.93, strong) → зелёный «готово» (12.02). Внизу две капсулы оттенков: Claude (коралл), Cursor (лёд).
Sequential/interaction: yes — три состояния, каждое держится ≥1.0s
Audio intent: чистая ясность
Audio-coupled idea: accent на янтарном
Transition mood: soft → Scene 4

### Scene 4 — Five tabs — 4.4s (13.1–17.5)
Полоса вкладок: Музыка, Полка, Агенты, Git, Терминал. Подсвечиваются по очереди (акценты, не текст). Контент под ней меняется; на Git щёлкает тумблер аккаунта, на «Терминале» кнопка команды с ✓. Заголовок: «Пять вкладок. Ноль Alt+Tab.»
Sequential/interaction: yes — вкладки по битам 13.64→15.84, тумблер, кнопка
Audio intent: ритмичный, лёгкий
Audio-coupled idea: switch на Git
Transition mood: clean → Scene 5

### Scene 5 — Outro — 3.5s (17.5–21.0)
Иконка, «NotchApp», «Челка, которая знает, кто вас ждёт.» Hold ≥2s. Музыка затихает.
Sequential/interaction: none
Audio intent: тёплая точка
Audio-coupled idea: bell на 18.56 (strong cue)
Transition mood: end

**Music mood:** спокойный, чистый, dev-tool премиум
**Audio summary:** тихий бит, три акцента (раскрытие, клик, финал) и один щелчок тумблера.
