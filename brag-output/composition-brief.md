# Hyperframes Composition Brief: NotchApp

## Objective
Короткий launch-ролик для NotchApp, 21s, русский язык.

## Output
- Composition: `brag-output/composition/`
- Render: `brag-output/brag.mp4`
- Format: landscape 1920x1080, 30fps
- Duration: 21s

## Source Material
- Project root: /Users/ilya.balandin/DevProjects/NotchApp
- Files read: README.md, AgentModels.swift, AgentSource+Style.swift, AgentsView.swift, NotchTab.swift, CommandsView.swift, NotchRootView.swift, Resources/AppIcon-1024.png
- Product name: NotchApp
- Strongest claim: «цвет = состояние агента, оттенок = IDE, яркость дышит, когда агент ждёт»
- UI to recreate: раскрытая панель, вкладка «Агенты», аура вокруг челки
- Copy verbatim: «Claude Code ждёт разрешения.», «Уже 40 минут.», «1 ждёт вас», «Цвет — состояние. Оттенок — IDE.», «Пять вкладок. Ноль Alt+Tab.», «Челка, которая знает, кто вас ждёт.»
- Имена сессий вымышленные (api-gateway, web-client, docs-site)

## Creative Direction
- Tone: default; сухой dev-юмор, тёмный премиум
- Hook: две строки на чёрном, янтарное дыхание челки
- Outro: «Челка, которая знает, кто вас ждёт.»
- Avoid: generic SaaS-язык, абстрактные заливки, редизайн

## Visual Identity
См. brag-plan.md (палитра состояний и IDE, фон #050506, панель #000, системный SF).

## Storyboard
См. brag-plan.md.

## Audio
- Music: assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3, volume 0.30, fade-out 1.5s
- Cues: bundled preset (vol-12), strong 8.74 / 10.93 / 13.11 / 17.47 / 18.56
- Audio-reactive: subtle RMS → яркость ауры (ffmpeg astats; helper hyperframes-creative не установлен)
- SFX (в assets/sfx): impactSoft_medium_000 (раскрытие), drop_001 (первая строка), mouseclick1 (клик), switch_002 (тумблер), impactBell_heavy_000 (финал)

## Hyperframes Instructions
Домен-скиллы hyperframes-* в этой среде не установлены; композиция пишется по `npx hyperframes docs` (data-attributes, gsap). Гейт: `npx hyperframes check`.
