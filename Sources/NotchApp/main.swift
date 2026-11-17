import AppKit

// Точка входа. Обычный NSApplication, а не SwiftUI App: панель — это NSPanel
// с ручной геометрией, сцены SwiftUI тут только мешали бы.
//
// Код верхнего уровня в main.swift не изолирован на главный актор, а
// NSApplicationDelegate в SDK помечен @MainActor. Мы физически на главном
// потоке, поэтому заявляем это явно вместо того, чтобы уводить старт в async.

/// Делегат держим в глобальной переменной: NSApplication.delegate — weak-ссылка.
let appDelegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.delegate = appDelegate
    // .accessory — нет иконки в Dock и нет меню приложения, только статус-бар.
    application.setActivationPolicy(.accessory)
    application.run()
}
