import AppKit
import ApplicationServices

/// Тонкая обёртка над Accessibility API.
///
/// Всё здесь возвращает `nil`/`false` вместо ошибок: без выданного доступа
/// каждый вызов законно проваливается, и это не повод шуметь.
enum AX {
    /// Роли, по которым можно кликнуть. Нажимать на что попало нельзя:
    /// мы ходим по чужому интерфейсу.
    /// Строки задаём литералами, а не константами AX: часть из них в SDK
    /// отсутствует, а имена ролей стабильны уже много лет.
    static let actionableRoles: Set<String> = ["AXRow", "AXCell", "AXButton", "AXLink"]

    /// Роли контейнеров-списков. Внутри такого и живёт список сессий, и только
    /// внутри него можно кому-то жать: совпадение в тулбаре или в тексте
    /// сообщения — это чужая кнопка, а не строка чата.
    static let containerRoles: Set<String> = ["AXOutline", "AXList", "AXTable"]

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ответ чужого приложения может не прийти вовсе — например, пока оно
    /// показывает модальное окно. Без своего таймаута обход дерева повиснет
    /// на системном, а он щедрый.
    static func setTimeout(_ element: AXUIElement, seconds: Float) {
        _ = AXUIElementSetMessagingTimeout(element, seconds)
    }

    /// Показать системный диалог выдачи доступа.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: - Чтение

    static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func role(_ element: AXUIElement) -> String {
        string(element, kAXRoleAttribute) ?? ""
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func windows(of application: AXUIElement) -> [AXUIElement] {
        value(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    static func parent(of element: AXUIElement) -> AXUIElement? {
        guard let raw = value(element, kAXParentAttribute) else { return nil }
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    /// Весь видимый текст элемента одной строкой — по нему и опознаём сессию.
    static func label(_ element: AXUIElement) -> String {
        var parts: [String] = []
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            guard let text = string(element, attribute), !text.isEmpty else { continue }
            parts.append(text)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Действия

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func raise(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Electron и всё на Chromium строят дерево AX только по явной просьбе.
    /// Без этого у приложения видны одни окна и ни одной строки внутри них.
    static func enableElectronAccessibility(_ application: AXUIElement) {
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// Ближайший предок (включая сам элемент), по которому можно кликнуть:
    /// текст в списке обычно лежит внутри строки, а нажимается строка.
    static func actionable(from element: AXUIElement, levels: Int = 4) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0...levels {
            guard let candidate = current else { return nil }
            if actionableRoles.contains(role(candidate)) { return candidate }
            current = parent(of: candidate)
        }
        return nil
    }

    // MARK: - Обход

    /// Поиск в ширину: ближние к корню совпадения важнее дальних.
    static func firstMatch(
        in root: AXUIElement,
        maxDepth: Int = 24,
        limit: Int = 6000,
        where predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var head = 0
        var visited = 0

        while head < queue.count {
            let node = queue[head]
            head += 1
            visited += 1
            if visited > limit { break }

            if node.depth > 0, predicate(node.element) { return node.element }
            if node.depth >= maxDepth { continue }

            for child in children(of: node.element) {
                queue.append((child, node.depth + 1))
            }
        }
        return nil
    }

    /// Текстовый снимок дерева — чтобы один раз посмотреть, как чужой
    /// интерфейс устроен на самом деле, вместо угадывания.
    static func dump(_ root: AXUIElement, maxDepth: Int = 14, limit: Int = 1500) -> String {
        var lines: [String] = []
        var visited = 0

        func walk(_ element: AXUIElement, _ depth: Int) {
            guard visited < limit else { return }
            visited += 1

            let indent = String(repeating: "  ", count: depth)
            var text = label(element)
            if text.count > 120 { text = String(text.prefix(120)) + "…" }
            let identifier = string(element, "AXIdentifier").map { " #\($0)" } ?? ""
            lines.append("\(indent)\(role(element))\(identifier)\(text.isEmpty ? "" : "  \(text)")")

            guard depth < maxDepth else { return }
            for child in children(of: element) {
                walk(child, depth + 1)
            }
        }

        walk(root, 0)
        if visited >= limit { lines.append("… обрезано на \(limit) элементах") }
        return lines.joined(separator: "\n")
    }
}
