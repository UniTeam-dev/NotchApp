import AppKit
import ServiceManagement

/// Автозапуск при входе в систему.
///
/// Через `SMAppService`, а не через старую связку `SMLoginItemSetEnabled` с
/// отдельным хелпером внутри бандла: с macOS 13 система умеет регистрировать
/// само приложение, и лишний таргет не нужен.
///
/// Две особенности, которые видит пользователь:
/// - регистрация привязана к **месту и подписи** бандла. Перенесли приложение
///   в другую папку или пересобрали с другой идентичностью — запись протухла,
///   надо включить заново;
/// - система может потребовать подтверждения. Тогда статус будет
///   `requiresApproval`, и переключатель сам по себе ничего не даст — нужно
///   разрешить в «Системных настройках».
enum LaunchAtLogin {

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var needsApproval: Bool {
        status == .requiresApproval
    }

    /// Возвращает ошибку, а не бросает: вызывающий код — это пункт меню,
    /// которому нечего делать с исключением.
    @discardableResult
    static func set(_ enabled: Bool) -> Error? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            Log.notch.error("автозапуск: \(error.localizedDescription, privacy: .public)")
            return error
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
