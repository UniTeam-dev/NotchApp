# NotchApp — разработка

Сборка из исходников, устройство кода и неочевидные решения. Описание для пользователя — в [README](../README.md).

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
    CommandsView            кнопки команд: описание, статус, хвост вывода
    GitView                 аккаунты gh: аватар, тумблер, подпись, выход
    SettingsView            тумблеры разделов и обновление

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
  Commands/                 вкладка «Терминал»
    CommandBinding          привязка: описание, команда, каталог; итог запуска
    CommandRunner           $SHELL -lc, stdout+stderr, таймаут, остановка
    CommandStore            commands.json в Application Support, состояния
    CommandEditor           отдельное key-окно для привязки и правки
  Git/                      вкладка «Git»
    GitAccount              модель и разбор текстового `gh auth status`
    GitStore                switch/logout/setup-git, подписи коммитов
    GhLogin                 вход через device flow или токен, окна
    Sh                      короткие вызовы через логин-шелл
  Support/                  пути, логи, запуск CLI
    AppSettings             скрытые разделы панели, UserDefaults
    Updater                 последний релиз GitHub -> dmg -> проверка подписи -> подмена бандла
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

- **Форма привязки команды — отдельное окно.** Панель не становится key, иначе
  отбирает фокус у рабочего приложения; а без key-окна текст не набрать.
- **Команда идёт через `$SHELL -lc`.** Приложение из Finder получает куцый PATH;
  логин-шелл соберёт его из профиля. Алиасы из `.zshrc` при этом не видны —
  нужен полный путь или функция в `.zprofile`. Таймаут 60 с (у команд с
  флажком «в фоне» его нет, по желанию они стартуют вместе с приложением),
  при остановке сначала гасим детей процесса через `pkill -P`. Цвета погашены
  (`TERM=dumb`, `NO_COLOR=1`), в кнопке — последние три строки вывода.

- **`gh auth status` читается как текст.** `--json` есть не во всех версиях gh.
  Код выхода игнорируем: gh отдаёт 1, если протух хоть один токен.
- **Вход через браузер без терминала.** Когда stdin не TTY, `gh auth login -w`
  не ждёт Enter, а сразу печатает код и адрес. Код ловим из вывода, кладём в
  буфер и открываем страницу сами.
- **Подпись коммитов хранится у нас, а не в gh.** При переключении аккаунта
  она пишется в `git config --global`; предлагаем noreply-адрес из профиля.

- **Обновление ставит только релизы с подписью Developer ID команды `TB954423F4`.**
  Проверяется копия, которая будет установлена, а не файл в образе. Версия берётся
  из тега релиза (`v0.2` -> `0.2`) и сравнивается с `CFBundleShortVersionString`,
  поэтому перед релизом версию в `Resources/Info.plist` нужно поднять, а тег назвать
  так же. Локальная сборка с подписью «NotchApp Dev» после обновления станет
  релизной — выданные ей разрешения придётся выдать заново.
- **`NotchApp --self-update`** делает то же без интерфейса и без перезапуска.
- **Релиз: `./scripts/make-dmg.sh`.** Скрипт переподписывает копию приложения
  Developer ID, подписывает образ, отправляет его на нотаризацию и прикрепляет
  тикет. Нужен профиль notarytool в связке ключей, один раз:
  `xcrun notarytool store-credentials notchapp --team-id TB954423F4`
  (Apple ID и пароль приложения). Без профиля скрипт завершится ошибкой, а
  собранный образ останется ненотаризованным.

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
