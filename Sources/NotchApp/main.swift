import AppKit

// Точка входа. Обычный NSApplication, а не SwiftUI App: панель — это NSPanel
// с ручной геометрией, сцены SwiftUI тут только мешали бы.
//
// Код верхнего уровня в main.swift не изолирован на главный актор, а
// NSApplicationDelegate в SDK помечен @MainActor. Мы физически на главном
// потоке, поэтому заявляем это явно вместо того, чтобы уводить старт в async.

// `NotchApp --self-update` — обновиться из релизов GitHub без интерфейса
// и без перезапуска: для скриптов и для проверки самого механизма.
if CommandLine.arguments.contains("--self-update") {
    Task {
        do {
            let release = try await Updater.latestRelease()
            guard Updater.isNewer(release.version, than: Updater.currentVersion) else {
                print("актуальная версия: \(Updater.currentVersion)")
                exit(0)
            }
            try await Updater.install(release)
            print("обновлено: \(Updater.currentVersion) -> \(release.version)")
            exit(0)
        } catch {
            print("ошибка: \(error.localizedDescription)")
            exit(1)
        }
    }
    dispatchMain()
}

/// Делегат держим в глобальной переменной: NSApplication.delegate — weak-ссылка.
let appDelegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.delegate = appDelegate
    // .accessory — нет иконки в Dock и нет меню приложения, только статус-бар.
    application.setActivationPolicy(.accessory)
    application.run()
}
