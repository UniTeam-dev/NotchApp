import Foundation

enum HookInstallError: LocalizedError {
    case unreadableConfig(String)
    case scriptWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableConfig(let path):
            return "Не удалось разобрать \(path). Файл не тронут — проверьте его руками."
        case .scriptWriteFailed(let path):
            return "Не удалось записать скрипт \(path)."
        }
    }
}

/// Установка хуков в чужие конфиги.
///
/// Правила, от которых нельзя отступать:
/// - конфиги мержатся, а не перезаписываются;
/// - рядом кладётся `.notchapp-backup`;
/// - нераспознанный JSON — это ошибка и повод остановиться, а не повод начать
///   с пустого файла.
enum HookInstaller {

    // MARK: - Скрипт

    /// Скрипт всегда выходит с кодом 0 и молчит в stdout/stderr: код 2 блокирует
    /// действие агента, непустой stdout парсится как структурированное решение.
    /// Монитор не имеет права ломать работу агента.
    private static let scriptBody = """
    #!/bin/sh
    # NotchApp: складывает payload хука в инбокс и никогда не мешает агенту.
    # $1 — инструмент (claude|cursor), $2 — необязательное имя события.

    TOOL="${1:-claude}"
    INBOX="$HOME/Library/Application Support/NotchApp/inbox"

    mkdir -p "$INBOX" 2>/dev/null || exit 0

    # Временный файл создаётся в том же каталоге, иначе mv пойдёт через
    # копирование и перестанет быть атомарным.
    TMP=$(mktemp "$INBOX/.notch.XXXXXXXX" 2>/dev/null) || exit 0

    cat > "$TMP" 2>/dev/null
    mv -f "$TMP" "$INBOX/$(date +%s)-$$.$TOOL.json" 2>/dev/null

    exit 0
    """

    static func installScript() throws {
        try? FileManager.default.createDirectory(at: Paths.scriptHome, withIntermediateDirectories: true)
        do {
            try scriptBody.write(to: Paths.hookScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: Paths.hookScript.path
            )
        } catch {
            throw HookInstallError.scriptWriteFailed(Paths.hookScript.path)
        }
    }

    // MARK: - Статус

    static func status() -> HookStatus {
        HookStatus(
            claude: configMentionsScript(at: Paths.claudeSettings),
            cursor: configMentionsScript(at: Paths.cursorHooks)
        )
    }

    private static func configMentionsScript(at url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains(Paths.hookScript.path)
    }

    // MARK: - Установка

    static func installAll() throws {
        try installScript()
        try installClaude()
        try installCursor()
    }

    private static let claudeEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Notification",
        "Stop",
        "SessionEnd"
    ]

    /// У Cursor нет события «агент начал работу», поэтому берём всё, что
    /// сигнализирует активность. Без `beforeSubmitPrompt` и файловых событий
    /// чат, который не запускает команды, виден только в момент `stop` —
    /// то есть уже завершённым.
    private static let cursorEvents = [
        "beforeSubmitPrompt",
        "beforeShellExecution",
        "beforeMCPExecution",
        "beforeReadFile",
        "afterFileEdit",
        "afterShellExecution",
        "afterMCPExecution",
        "stop"
    ]

    private static func installClaude() throws {
        var root = try readObject(at: Paths.claudeSettings)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\(Paths.hookScript.path) claude"

        for event in claudeEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            guard !entries.contains(where: { entryContains(command: command, in: $0) }) else { continue }
            entries.append(["hooks": [["type": "command", "command": command]]])
            hooks[event] = entries
        }

        root["hooks"] = hooks
        try write(root, to: Paths.claudeSettings)
    }

    private static func installCursor() throws {
        var root = try readObject(at: Paths.cursorHooks)
        if root["version"] == nil { root["version"] = 1 }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\(Paths.hookScript.path) cursor"

        for event in cursorEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            guard !entries.contains(where: { ($0["command"] as? String) == command }) else { continue }
            entries.append(["command": command])
            hooks[event] = entries
        }

        root["hooks"] = hooks
        try write(root, to: Paths.cursorHooks)
    }

    private static func entryContains(command: String, in entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else {
            return (entry["command"] as? String) == command
        }
        return inner.contains { ($0["command"] as? String) == command }
    }

    // MARK: - Чтение и запись

    private static func readObject(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url) else {
            throw HookInstallError.unreadableConfig(url.path)
        }
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Именно ошибка, а не «начнём с чистого листа»: в этом файле лежат
            // чужие настройки, и терять их мы не имеем права.
            throw HookInstallError.unreadableConfig(url.path)
        }
        return object
    }

    private static func write(_ object: [String: Any], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("notchapp-backup")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
        }

        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }
}
