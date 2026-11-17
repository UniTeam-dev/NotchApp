import AppKit
import Combine

/// Привязанные команды и результаты их последних запусков.
///
/// Сами привязки лежат в `~/Library/Application Support/NotchApp/commands.json`.
/// Результаты живут только в памяти: после перезапуска кнопки снова чистые.
/// Всё состояние трогается только с главного потока.
final class CommandStore: ObservableObject {
    @Published private(set) var bindings: [CommandBinding] = []
    @Published private(set) var states: [UUID: CommandRunState] = [:]

    /// Сколько ждём команду, прежде чем снять её.
    static let timeout: TimeInterval = 60

    private var runners: [UUID: CommandRunner] = [:]

    // MARK: - Хранение

    func load() {
        guard let data = try? Data(contentsOf: Paths.commands) else { return }
        do {
            bindings = try JSONDecoder().decode([CommandBinding].self, from: data)
        } catch {
            Log.commands.error("не прочитал commands.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Поднять фоновые команды с автозапуском — один раз при старте приложения.
    func startAutostart() {
        for binding in bindings where binding.startsWithApp {
            run(binding)
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
            try encoder.encode(bindings).write(to: Paths.commands, options: .atomic)
        } catch {
            Log.commands.error("не сохранил commands.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Правка

    func upsert(_ binding: CommandBinding) {
        if let index = bindings.firstIndex(where: { $0.id == binding.id }) {
            // Команду поменяли — старый ответ к ней больше не относится.
            if bindings[index].command != binding.command,
               !(states[binding.id]?.isRunning ?? false) {
                states[binding.id] = nil
            }
            bindings[index] = binding
        } else {
            bindings.append(binding)
        }
        save()
    }

    func remove(id: UUID) {
        runners[id]?.cancel()
        bindings.removeAll { $0.id == id }
        states[id] = nil
        save()
    }

    // MARK: - Запуск

    func state(for id: UUID) -> CommandRunState {
        states[id] ?? .idle
    }

    /// Нажатие на кнопку: запустить, а если уже работает — остановить.
    func trigger(_ binding: CommandBinding) {
        if state(for: binding.id).isRunning {
            cancel(id: binding.id)
        } else {
            run(binding)
        }
    }

    func run(_ binding: CommandBinding) {
        let id = binding.id
        guard runners[id] == nil else { return }

        let runner = CommandRunner(binding: binding)
        runners[id] = runner
        states[id] = .running(since: Date())
        Log.commands.info("запуск «\(binding.title, privacy: .public)»")

        let timeout: TimeInterval? = binding.isBackground ? nil : Self.timeout
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runner.execute(timeout: timeout)
            DispatchQueue.main.async {
                guard let self else { return }
                self.runners[id] = nil
                // Пока команда работала, её могли удалить.
                guard self.bindings.contains(where: { $0.id == id }) else { return }
                self.states[id] = .finished(result)
            }
        }
    }

    func cancel(id: UUID) {
        runners[id]?.cancel()
    }

    func cancelAll() {
        for runner in runners.values { runner.cancel() }
    }

    func resetResult(id: UUID) {
        guard !state(for: id).isRunning else { return }
        states[id] = nil
    }

    // MARK: - Буфер обмена

    func copyOutput(id: UUID) {
        guard let output = states[id]?.result?.output, !output.isEmpty else { return }
        copy(output)
    }

    func copyCommand(_ binding: CommandBinding) {
        copy(binding.command)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
