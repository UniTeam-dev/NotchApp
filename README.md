# NotchApp

Панель, раскрывающаяся при наведении на челку. Три вкладки: музыка, файловая
полка, состояние сессий Claude Code и Cursor. macOS 15+, проверяется на 26 Tahoe.

Подсветка «Аура» встроена в представление: **цвет = состояние** агента,
**оттенок = IDE**, **яркость дышит**, когда агент ждёт участия человека.

## Сборка

```bash
./scripts/make-cert.sh     # один раз: постоянная code identity
./scripts/build.sh         # сборка + бандл + подпись -> dist/NotchApp.app
open dist/NotchApp.app
```

`make-cert.sh` не косметика. macOS привязывает выданные разрешения к code
identity; у ad-hoc подписи стабильной identity нет, поэтому без сертификата
Automation и Accessibility будут слетать после каждой пересборки. Стабильного
bundle ID для этого недостаточно. Сертификат создаётся один раз — не
пересоздавайте его без нужды, смена Common Name обнулит выданные разрешения.

Если что-то не собирается:

```bash
swift build -c release 2>&1 | tee /tmp/notchapp-build.log
grep -E "error:" /tmp/notchapp-build.log | sort -u
```

## Что нужно поставить рядом

- **`media-control`** — `brew install media-control`. Без него не будет
  метаданных Now Playing. Причина в `Sources/NotchApp/Music/MediaControlBridge.swift`:
  с macOS 15.4 чтение системного Now Playing закрыто для сторонних процессов,
  а `media-control` читает MediaRemote внутри платформенного бинаря Apple.
- **`claude`** в PATH — для опроса живых сессий. Без него остаются только хуки.
- **Хуки** ставятся кнопкой на вкладке «Агенты». Конфиги мержатся, не
  перезаписываются, рядом кладётся `.notchapp-backup`.

## Раскладка

```
Sources/NotchApp/
  main.swift                точка входа: NSApplication, политика .accessory
  AppDelegate.swift         сборка зависимостей
  StatusItemController.swift  меню-бар как запасной путь открытия

  Notch/                    оконный слой
    NotchPanel              NSPanel: borderless, nonactivating, mainMenu+3
    NotchHostingView        hitTest отсекает запас под свечение
    NotchController         геометрия, ховер, drag-to-open
    NotchShape              силуэт челки, оба радиуса анимируемые
    NotchViewModel          что видит SwiftUI
    MouseMonitor            глобальный + локальный монитор, троттлинг 20 Гц
    DragDetector            предраскрытие по changeCount драг-пастборда
    NSScreen+Notch          anchorRect, hasNotch, поиск экрана
    NotchTab

  Views/
    NotchRootView           аура позади панели, индикатор в закрытой челке
    AgentGlyphs             NotchAura, PulsingDot, ClosedIndicator
    AgentsView              строки сессий: иконка IDE, пульс, гало, hover-стрелка
    MusicView, ShelfView, ShelfDropCatcher

  Music/
    MusicModel              снимок позиции + экстраполяция
    MediaControlBridge      NDJSON-поток media-control
    MediaRemoteBridge       MRMediaRemoteSendCommand через CFBundle
    AppleScriptBridge       резерв для Apple Music и Spotify
    NowPlaying

  Shelf/                    копия файла живёт в Application Support
  Agents/
    AgentModels             состояния — контракт, общий с клиентом win/linux
    AgentStore              хуки + опрос, приоритет у хука моложе 2 с
    AgentInbox              атомарный IPC через inbox/
    ClaudeAgentsProbe       claude agents --json --all
    HookInstaller           мерж чужих конфигов, скрипт всегда exit 0
    SessionActivator        подъём терминала по дереву процессов
  Support/                  пути, логи, запуск CLI
```

## Решения, которые выглядят странно и такими не являются

- **Панель фиксированного размера.** Вся анимация внутри SwiftUI. Смешивать
  `NSAnimationContext` со SwiftUI-пружинами нельзя — разные тайминги дают джанк.
- **`ignoresMouseEvents = true`, пока панель закрыта.** Это не оптимизация:
  высокоуровневое окно, перехватывающее мышь в зоне автовыезда меню-бара,
  залипает в полноэкранном режиме.
- **Троттлинг только на непрерывные события.** Если под него попадёт
  `.leftMouseUp`, конец драга теряется и панель залипает открытой.
- **Окно шире панели на 46 pt.** Это запас, в который вытекает свечение ауры.
  `NotchHostingView.hitTest` не даёт этому запасу ловить мышь.
- **`hitTest` приёмника файлов возвращает nil.** Он не перехватывает клики, но
  остаётся целью драга: адресация драга идёт по зарегистрированным типам.
- **Прижимаемся к `screen.frame.maxY`, не к `visibleFrame`.** Второй уже вычел
  меню-бар. Высота челки берётся из `safeAreaInsets.top`:
  `NSStatusBar.system.thickness` на Tahoe всё ещё возвращает 24 вместо ~31.
- **Скрипт хука всегда выходит с кодом 0 и молчит.** Код 2 блокирует действие
  агента, непустой stdout парсится как структурированное решение. Монитор не
  имеет права ломать работу агента.

## Что осталось

1. Собрать и разобрать ошибки компиляции — код писался без возможности собрать.
2. Проверить индикатор в закрытой челке на реальном вырезе; при перекрытии
   подправить боковые отступы в `ClosedIndicator`.
3. Вытаскивание карточки с полки сделано через `.onDrag`. Если окажется, что на
   nonactivating-панели оно капризничает — переписать на `beginDraggingSession`
   с ручным порогом 3 pt.
4. Выбор источника, когда играют сразу несколько: сейчас берём системный
   Now Playing как есть. Точный путь — CoreAudio
   `kAudioProcessPropertyIsRunningOutput`, он публичный и без разрешений.
5. Хуки Cursor описаны по документации и не перепроверялись — сверить.

Обоснования решений целиком: `claude/architecture.md` в проекте.
