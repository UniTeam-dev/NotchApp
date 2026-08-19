import AppKit

// Точка входа. Обычный NSApplication, а не SwiftUI App: панель — это NSPanel
// с ручной геометрией, сцены SwiftUI тут только мешали бы.
let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
// .accessory — нет иконки в Dock и нет меню приложения, только статус-бар.
application.setActivationPolicy(.accessory)
application.run()
