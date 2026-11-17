import AppKit
import SwiftUI

/// Окно добавления и правки команды.
///
/// Отдельное окно, а не форма в самой панели: панель намеренно не становится
/// key (иначе отбирает фокус у рабочего приложения), а без key-окна
/// текст не набрать.
@MainActor
final class CommandEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = CommandEditorWindowController()

    private var window: NSWindow?

    func show(store: CommandStore, editing binding: CommandBinding? = nil) {
        let isNew = binding == nil
        let initial = binding ?? CommandBinding(title: "", command: "")

        let view = CommandEditorView(
            initial: initial,
            isNew: isNew,
            onSave: { [weak self, weak store] updated in
                store?.upsert(updated)
                self?.close()
            },
            onDelete: isNew ? nil : { [weak self, weak store] in
                store?.remove(id: initial.id)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )

        let window = self.window ?? makeWindow()
        window.contentViewController = NSHostingController(rootView: view)
        window.title = isNew ? "Новая команда" : "Команда «\(initial.title)»"
        window.center()

        // Приложение живёт без Dock-иконки, поэтому активируем его руками —
        // иначе окно появится, но фокус клавиатуры останется где был.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        return window
    }
}

struct CommandEditorView: View {
    @State private var draft: CommandBinding
    let isNew: Bool
    let onSave: (CommandBinding) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    init(
        initial: CommandBinding,
        isNew: Bool,
        onSave: @escaping (CommandBinding) -> Void,
        onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: initial)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    private var directory: Binding<String> {
        Binding(
            get: { draft.workingDirectory ?? "" },
            set: { draft.workingDirectory = $0.isEmpty ? nil : $0 }
        )
    }

    private var normalized: CommandBinding {
        var result = draft
        result.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.command = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = draft.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        result.workingDirectory = dir.isEmpty ? nil : dir
        return result
    }

    private var canSave: Bool {
        !normalized.title.isEmpty && !normalized.command.isEmpty
    }

    private var backgroundToggle: Binding<Bool> {
        Binding(
            get: { draft.isBackground },
            set: { on in
                draft.background = on ? true : nil
                if !on { draft.autostart = nil }
            }
        )
    }

    private var autostartToggle: Binding<Bool> {
        Binding(
            get: { draft.autostart ?? false },
            set: { draft.autostart = $0 ? true : nil }
        )
    }

    private var hintText: String {
        let base = "Выполняется в логин-шелле (\(shellName))."
        if draft.isBackground {
            return base + " Фоновая команда живёт, пока её не остановят повторным нажатием или пока не закроется NotchApp."
        }
        return base + " Таймаут — \(Int(CommandStore.timeout)) с. В кнопке — последние строки вывода, полный вывод — в подсказке и в контекстном меню."
    }

    private var shellName: String {
        (CommandRunner.shell as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled("Описание — подпись кнопки") {
                TextField("Например: IP в локальной сети", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
            }

            labeled("Команда") {
                TextField("ipconfig getifaddr en0", text: $draft.command, axis: .vertical)
                    .lineLimit(2...6)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    // Автозамена кавычек и тире ломает команды.
                    .autocorrectionDisabled()
            }

            labeled("Каталог запуска") {
                HStack(spacing: 6) {
                    TextField("~ (домашний)", text: directory)
                        .textFieldStyle(.roundedBorder)
                    Button("Выбрать…", action: pickDirectory)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Работает в фоне — без таймаута", isOn: backgroundToggle)
                Toggle("Запускать вместе с NotchApp", isOn: autostartToggle)
                    .disabled(!draft.isBackground)
                    .padding(.leading, 20)
            }
            .toggleStyle(.checkbox)

            Text(hintText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let onDelete {
                    Button("Удалить", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Отмена", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Добавить" : "Сохранить") { onSave(normalized) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        if let current = CommandRunner.directory(for: normalized) {
            panel.directoryURL = current
        }
        if panel.runModal() == .OK, let url = panel.url {
            draft.workingDirectory = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}
