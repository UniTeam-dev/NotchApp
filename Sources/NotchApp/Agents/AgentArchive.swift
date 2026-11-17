import Foundation

/// Непросмотренные «готово» переживают перезапуск приложения.
///
/// Без этого обещание «сессия висит, пока в неё не зайдут» рвётся на первом же
/// перезапуске NotchApp — а он бывает чаще, чем кажется: пересборка,
/// обновление, перезагрузка. Файл маленький и намеренно необязательный: любая
/// ошибка чтения означает «начинаем с пустого списка», ронять из-за неё нечего.
enum AgentArchive {
    private static var url: URL {
        Paths.support.appendingPathComponent("pending-done.json")
    }

    /// Дольше недели держать бессмысленно: это уже не сигнал, а мусор.
    private static let lifetime: TimeInterval = 7 * 24 * 3600
    private static let limit = 30

    static func save(_ sessions: [AgentSession]) {
        let payload = Array(sessions.prefix(limit))

        guard !payload.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(payload) else { return }
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> [AgentSession] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let stored = try? decoder.decode([AgentSession].self, from: data) else {
            Log.agents.error("архив готовых сессий не разобрался — начинаю с пустого")
            return []
        }

        let now = Date()
        return stored.compactMap { session in
            guard session.awaitsVisit, now.timeIntervalSince(session.updatedAt) < lifetime else {
                return nil
            }
            // PID из прошлого запуска — ложный след: система давно выдала этот
            // номер кому-то другому, и переход поднял бы чужое приложение.
            var restored = session
            restored.pid = nil
            return restored
        }
    }
}
