import SwiftUI

/// Вкладка «Терминал»: привязанные команды кнопками.
/// Нажатие — запуск, повторное нажатие во время работы — остановка.
struct CommandsView: View {
    @ObservedObject var commands: CommandStore

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 8)]

    var body: some View {
        if commands.bindings.isEmpty {
            VStack(spacing: 10) {
                EmptyHint(
                    symbol: "terminal",
                    title: "Команд пока нет",
                    subtitle: "Привяжите команду — она появится здесь кнопкой"
                )
                AddCommandPill(commands: commands)
            }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Команды")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))

                Text("\(commands.bindings.count)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.35))

                Spacer()

                AddCommandPill(commands: commands)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(commands.bindings) { binding in
                        CommandButton(
                            binding: binding,
                            state: commands.state(for: binding.id),
                            commands: commands
                        )
                    }
                }
            }
        }
    }
}

private struct AddCommandPill: View {
    let commands: CommandStore

    var body: some View {
        Button {
            CommandEditorWindowController.shared.show(store: commands)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("Привязать")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .foregroundStyle(Color.white.opacity(0.75))
        }
        .buttonStyle(.plain)
        .help("Привязать новую команду")
    }
}

struct CommandButton: View {
    let binding: CommandBinding
    let state: CommandRunState
    let commands: CommandStore

    @State private var isHovering = false

    private static let green = Color(red: 0.38, green: 0.85, blue: 0.54)
    private static let red = Color(red: 1.0, green: 0.43, blue: 0.40)
    private static let orange = Color(red: 1.0, green: 0.66, blue: 0.26)

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        Button {
            commands.trigger(binding)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    statusIcon
                        .frame(width: 12, height: 12)

                    Text(binding.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    meta
                }

                bodyText
                    .font(.system(size: 9.5, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
        .contextMenu { menu }
    }

    // MARK: - Части кнопки

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .idle:
            Image(systemName: binding.isBackground ? "infinity" : "play.fill")
                .font(.system(size: binding.isBackground ? 9 : 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.45))
        case .running where binding.isBackground:
            PulsingBackgroundDot(color: Self.green)
        case .running:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .tint(.white)
        case .finished(let result):
            Image(systemName: icon(for: result))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color(for: result))
        }
    }

    @ViewBuilder
    private var meta: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running(let since):
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(Self.elapsed(context.date.timeIntervalSince(since)))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        case .finished(let result):
            Text(Self.timeFormatter.string(from: result.finishedAt))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    @ViewBuilder
    private var bodyText: some View {
        switch state {
        case .idle:
            Text("$ " + binding.command)
                .foregroundStyle(Color.white.opacity(0.35))
        case .running:
            Text(binding.isBackground
                 ? "работает в фоне · нажмите, чтобы остановить"
                 : "выполняется… нажмите, чтобы остановить")
                .foregroundStyle(Color.white.opacity(0.45))
        case .finished(let result):
            Text(result.summary())
                .truncationMode(result.succeeded ? .head : .tail)
                .foregroundStyle(result.succeeded ? Color.white.opacity(0.85) : color(for: result).opacity(0.9))
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle: return .clear
        case .running: return binding.isBackground ? Self.green.opacity(0.35) : Color.white.opacity(0.18)
        case .finished(let result): return color(for: result).opacity(0.30)
        }
    }

    private func icon(for result: CommandResult) -> String {
        if result.succeeded { return "checkmark.circle.fill" }
        if result.timedOut || result.cancelled { return "stop.circle.fill" }
        return "xmark.octagon.fill"
    }

    private func color(for result: CommandResult) -> Color {
        if result.succeeded { return Self.green }
        // Фоновую команду останавливают штатно — это не тревога.
        if result.cancelled && binding.isBackground { return Color.white.opacity(0.55) }
        if result.timedOut || result.cancelled { return Self.orange }
        return Self.red
    }

    /// 42 с · 5:07 · 2:13:05
    static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%d:%02d", minutes, seconds) }
        return "\(seconds) с"
    }

    private var helpText: String {
        var lines = ["$ " + binding.command]
        if binding.isBackground {
            lines.append(binding.startsWithApp ? "фоновая, стартует вместе с NotchApp" : "фоновая, без таймаута")
        }
        if let dir = binding.workingDirectory { lines.append("в " + dir) }
        if let result = state.result {
            lines.append("")
            lines.append("код \(result.exitCode) · \(String(format: "%.1f", result.duration)) с")
            if !result.output.isEmpty {
                // Подсказка не для простыней — обрезаем хвостом.
                let output = result.output.count > 2000
                    ? "…" + String(result.output.suffix(2000))
                    : result.output
                lines.append(output)
            }
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var menu: some View {
        if state.isRunning {
            Button("Остановить") { commands.cancel(id: binding.id) }
        } else {
            Button("Выполнить") { commands.run(binding) }
        }

        Button("Скопировать вывод") { commands.copyOutput(id: binding.id) }
            .disabled((state.result?.output ?? "").isEmpty)
        Button("Скопировать команду") { commands.copyCommand(binding) }

        Divider()

        Button("Изменить…") {
            CommandEditorWindowController.shared.show(store: commands, editing: binding)
        }
        Button("Сбросить ответ") { commands.resetResult(id: binding.id) }
            .disabled(state.result == nil)

        Divider()

        Button("Удалить", role: .destructive) { commands.remove(id: binding.id) }
    }
}

/// Мерцающая точка «жив» для фоновой команды — спиннер тут врал бы,
/// будто команда вот-вот закончится.
private struct PulsingBackgroundDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(pulse ? 0.9 : 0.2), radius: pulse ? 4 : 1)
            .opacity(pulse ? 1 : 0.55)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
