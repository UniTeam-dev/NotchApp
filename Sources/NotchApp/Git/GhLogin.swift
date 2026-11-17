import AppKit
import SwiftUI

/// Вход в новый аккаунт gh: через браузер (device flow) или по токену.
///
/// Браузерный вход: запускаем `gh auth login --web` без терминала. Когда stdin
/// не TTY, gh не ждёт Enter, а сразу печатает одноразовый код и адрес
/// страницы и дальше сам опрашивает GitHub. Код ловим из вывода, копируем в
/// буфер и открываем страницу — пользователю остаётся вставить и подтвердить.
final class GhLoginModel: ObservableObject {
    enum Method: String, CaseIterable, Identifiable {
        case browser = "Через браузер"
        case token = "По токену"
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case idle
        case waitingForCode
        case waitingForBrowser(code: String, url: URL)
        case working
        case done(login: String?)
        case failed(String)
    }

    @Published var method: Method = .browser
    @Published var host = "github.com"
    @Published var token = ""
    @Published private(set) var phase: Phase = .idle

    var onFinished: (() -> Void)?

    private var process: Process?
    private var output = ""
    private let codeRegex = try? NSRegularExpression(pattern: #"code:\s*([A-Z0-9]{4}-[A-Z0-9]{4})"#)
    private let urlRegex = try? NSRegularExpression(pattern: #"https://\S+/login/device"#)
    private let loginRegex = try? NSRegularExpression(pattern: #"Logged in as (\S+)"#)

    var isBusy: Bool {
        switch phase {
        case .waitingForCode, .waitingForBrowser, .working: return true
        default: return false
        }
    }

    private var cleanHost: String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "github.com" : trimmed
    }

    // MARK: - Браузер

    func startBrowserLogin() {
        cancel()
        output = ""
        phase = .waitingForCode

        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandRunner.shell)
        process.arguments = ["-lc", Sh.join(["gh", "auth", "login", "-h", cleanHost, "-p", "https", "-w"])]
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        // Браузер откроем сами — вместе с кодом в буфере.
        env["GH_BROWSER"] = "true"
        env["BROWSER"] = "true"
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: chunk, as: UTF8.self)
            DispatchQueue.main.async { self?.consume(text) }
        }

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            let reason = finished.terminationReason
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.finish(status: status, killed: reason == .uncaughtSignal)
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            phase = .failed("Не удалось запустить gh: \(error.localizedDescription)")
        }
    }

    private func consume(_ text: String) {
        output += text
        guard case .waitingForCode = phase,
              let code = firstGroup(codeRegex, in: output) else { return }

        let url = firstMatch(urlRegex, in: output).flatMap(URL.init(string:))
            ?? URL(string: "https://\(cleanHost)/login/device")!
        phase = .waitingForBrowser(code: code, url: url)
        copyCodeAndOpen()
    }

    func copyCodeAndOpen() {
        guard case .waitingForBrowser(let code, let url) = phase else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        NSWorkspace.shared.open(url)
    }

    // MARK: - Токен

    func startTokenLogin() {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        cancel()
        phase = .working

        Sh.run(
            Sh.join(["gh", "auth", "login", "-h", cleanHost, "--with-token"]),
            input: Data((token + "\n").utf8),
            timeout: 30
        ) { [weak self] result in
            guard let self else { return }
            self.token = ""
            if result.succeeded {
                self.phase = .done(login: nil)
                self.onFinished?()
            } else {
                self.phase = .failed(result.firstLine)
            }
        }
    }

    // MARK: - Общее

    func cancel() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        if isBusy { phase = .idle }
    }

    func reset() {
        cancel()
        phase = .idle
        token = ""
    }

    private func finish(status: Int32, killed: Bool) {
        process = nil
        // Отменили сами — фаза уже сброшена.
        guard isBusy else { return }

        if status == 0 {
            phase = .done(login: firstGroup(loginRegex, in: output))
            onFinished?()
        } else if killed {
            phase = .idle
        } else {
            let line = output
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last { !$0.isEmpty }
            phase = .failed(line ?? "gh завершился с кодом \(status)")
        }
    }

    private func firstGroup(_ regex: NSRegularExpression?, in text: String) -> String? {
        guard let regex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func firstMatch(_ regex: NSRegularExpression?, in text: String) -> String? {
        guard let regex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }
}

// MARK: - Окна

/// Служебные окна вкладки «Git». Отдельные окна по той же причине, что и
/// редактор команд: панель не становится key, а без этого не набрать текст.
@MainActor
final class GitWindows: NSObject, NSWindowDelegate {
    static let shared = GitWindows()

    private var loginWindow: NSWindow?
    private var identityWindow: NSWindow?
    private let loginModel = GhLoginModel()

    func showLogin(store: GitStore) {
        loginModel.reset()
        loginModel.onFinished = { [weak store] in store?.refresh() }

        let view = GhLoginView(model: loginModel, onClose: { [weak self] in self?.closeLogin() })
        let window = loginWindow ?? makeWindow()
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "Новый аккаунт GitHub"
        present(window)
        loginWindow = window
    }

    func showIdentity(store: GitStore, account: GitAccount) {
        let view = GitIdentityEditorView(
            account: account,
            initial: store.identities[account.id],
            suggest: { [weak store] completion in
                store?.suggestIdentity(for: account, completion: completion)
            },
            onSave: { [weak self, weak store] identity in
                store?.setIdentity(identity, for: account)
                self?.identityWindow?.orderOut(nil)
            },
            onCancel: { [weak self] in self?.identityWindow?.orderOut(nil) }
        )
        let window = identityWindow ?? makeWindow()
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "Подпись коммитов · \(account.login)"
        present(window)
        identityWindow = window
    }

    private func closeLogin() {
        loginModel.cancel()
        loginWindow?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === loginWindow {
            loginModel.cancel()
        }
    }

    private func present(_ window: NSWindow) {
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
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

// MARK: - Вход

struct GhLoginView: View {
    @ObservedObject var model: GhLoginModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $model.method) {
                ForEach(GhLoginModel.Method.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.isBusy)

            VStack(alignment: .leading, spacing: 4) {
                Text("Хост")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("github.com", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .disabled(model.isBusy)
            }

            switch model.method {
            case .browser: browserSection
            case .token: tokenSection
            }

            status

            HStack {
                Spacer()
                Button(model.isBusy ? "Отменить" : "Закрыть", action: onClose)
                    .keyboardShortcut(.cancelAction)
                primaryButton
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder
    private var browserSection: some View {
        if case .waitingForBrowser(let code, _) = model.phase {
            VStack(alignment: .leading, spacing: 8) {
                Text("Код уже в буфере обмена, страница GitHub открыта — вставьте код и подтвердите вход.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(code)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Скопировать и открыть ещё раз", action: model.copyCodeAndOpen)
                }
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Жду подтверждения на GitHub…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Получите одноразовый код, подтвердите его на GitHub в браузере — и аккаунт появится на вкладке. Войти в аккаунт, отличный от открытого в браузере, можно в приватном окне.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Personal access token")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            SecureField("ghp_… или github_pat_…", text: $model.token)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isBusy)
            Text("Нужны права repo, read:org и gist. Токен уходит прямо в gh и сохраняется в связке ключей, приложение его не хранит.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .waitingForCode, .working:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Секунду…").font(.caption).foregroundStyle(.secondary)
            }
        case .done(let login):
            Label(login.map { "Готово: \($0) добавлен и стал активным" } ?? "Готово: аккаунт добавлен",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if case .done = model.phase {
            Button("Готово", action: onClose)
                .keyboardShortcut(.defaultAction)
        } else {
            switch model.method {
            case .browser:
                Button("Получить код", action: model.startBrowserLogin)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy)
            case .token:
                Button("Войти", action: model.startTokenLogin)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || model.token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Подпись коммитов

struct GitIdentityEditorView: View {
    let account: GitAccount
    let suggest: (@escaping (GitIdentity?) -> Void) -> Void
    let onSave: (GitIdentity?) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var email: String
    @State private var isSuggesting = false
    @State private var suggestFailed = false

    init(
        account: GitAccount,
        initial: GitIdentity?,
        suggest: @escaping (@escaping (GitIdentity?) -> Void) -> Void,
        onSave: @escaping (GitIdentity?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.account = account
        self.suggest = suggest
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: initial?.name ?? "")
        _email = State(initialValue: initial?.email ?? "")
    }

    private var identity: GitIdentity {
        GitIdentity(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("При переключении на \(account.login) эта подпись запишется в git config --global.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            field("user.name") {
                TextField("Имя Фамилия", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
            field("user.email") {
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            HStack(spacing: 8) {
                Button("Подставить из GitHub", action: fill)
                    .disabled(isSuggesting)
                if isSuggesting { ProgressView().controlSize(.small) }
                if suggestFailed {
                    Text("GitHub не ответил").font(.caption).foregroundStyle(.red)
                }
            }
            Text("Имя из профиля и приватный noreply-адрес — коммиты будут привязаны к аккаунту, а настоящая почта не утечёт.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Убрать подпись", role: .destructive) { onSave(nil) }
                Spacer()
                Button("Отмена", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить") { onSave(identity) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(identity.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 420)
    }

    private func fill() {
        isSuggesting = true
        suggestFailed = false
        suggest { suggestion in
            isSuggesting = false
            guard let suggestion else {
                suggestFailed = true
                return
            }
            name = suggestion.name
            email = suggestion.email
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
