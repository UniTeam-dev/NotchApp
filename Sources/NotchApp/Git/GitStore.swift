import AppKit
import Combine

/// Вкладка «Git»: аккаунты gh, переключение, подписи коммитов.
///
/// Источник правды — сам gh: после каждого действия заново читаем
/// `gh auth status`, а не правим список у себя. Своё храним только одно —
/// какую подпись коммитов ставить при переключении на аккаунт
/// (`git-identities.json` в Application Support).
/// Всё состояние трогается только с главного потока.
final class GitStore: ObservableObject {
    struct Notice: Equatable {
        let text: String
        let isError: Bool
    }

    @Published private(set) var accounts: [GitAccount] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var ghMissing = false
    /// Аккаунт, над которым сейчас идёт действие.
    @Published private(set) var busyAccountID: String?
    @Published private(set) var notice: Notice?

    /// Текущая глобальная подпись из `git config --global`.
    @Published private(set) var globalIdentity: GitIdentity?
    /// Ходит ли git за паролем к gh. `nil` — ещё не знаем.
    @Published private(set) var gitUsesGh: Bool?
    /// Подписи, которые ставим при переключении. Ключ — `GitAccount.id`.
    @Published private(set) var identities: [String: GitIdentity] = [:]

    private var lastRefresh: Date?
    private var noticeWorkItem: DispatchWorkItem?

    init() {
        loadIdentities()
    }

    // MARK: - Чтение

    /// Перечитать, если данные старше нескольких секунд, — для входа на вкладку.
    func refreshIfStale() {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 8 { return }
        refresh()
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        lastRefresh = Date()

        Sh.run("gh auth status", timeout: 20) { [weak self] result in
            guard let self else { return }
            self.ghMissing = result.commandNotFound
            // Код выхода не смотрим: gh отдаёт 1, если хоть один токен протух,
            // а список аккаунтов при этом полный.
            self.accounts = result.commandNotFound ? [] : GhAuthParser.parse(result.output)
            self.hasLoaded = true
            self.isLoading = false
        }

        readGitConfig()
    }

    /// Подпись и credential helper одним вызовом, секции разделены маркером.
    private func readGitConfig() {
        let marker = "@@notch@@"
        let command = [
            "git config --global --get user.name",
            "echo \(marker)",
            "git config --global --get user.email",
            "echo \(marker)",
            "git config --global --get-all credential.https://github.com.helper",
            "git config --global --get-all credential.helper"
        ].joined(separator: "; ")

        Sh.run(command, timeout: 10) { [weak self] result in
            guard let self else { return }
            let parts = result.output
                .components(separatedBy: marker)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 3 else { return }

            let identity = GitIdentity(name: parts[0], email: parts[1])
            self.globalIdentity = identity.isEmpty ? nil : identity
            self.gitUsesGh = parts[2].contains("gh auth git-credential")
        }
    }

    // MARK: - Действия

    func activate(_ account: GitAccount) {
        guard !account.isActive, busyAccountID == nil else { return }
        busyAccountID = account.id

        let command = Sh.join(["gh", "auth", "switch", "-h", account.host, "-u", account.login])
        Sh.run(command) { [weak self] result in
            guard let self else { return }
            guard result.succeeded else {
                self.busyAccountID = nil
                self.show("Не переключился: \(result.firstLine)", isError: true)
                return
            }

            if let identity = self.identities[account.id] {
                self.applyIdentity(identity) { ok in
                    self.busyAccountID = nil
                    self.show(
                        ok ? "Активен \(account.login), подпись — \(identity.name)"
                           : "Активен \(account.login), но подпись не записалась",
                        isError: !ok
                    )
                    self.refresh()
                }
            } else {
                self.busyAccountID = nil
                self.show("Активен \(account.login)")
                self.refresh()
            }
        }
    }

    func logout(_ account: GitAccount) {
        guard busyAccountID == nil else { return }
        busyAccountID = account.id

        let command = Sh.join(["gh", "auth", "logout", "-h", account.host, "-u", account.login])
        Sh.run(command) { [weak self] result in
            guard let self else { return }
            self.busyAccountID = nil
            if result.succeeded {
                self.identities[account.id] = nil
                self.saveIdentities()
                self.show("Вышли из \(account.login)")
            } else {
                self.show("Не вышли: \(result.firstLine)", isError: true)
            }
            self.refresh()
        }
    }

    /// `gh auth setup-git`: git начинает брать токен активного аккаунта у gh.
    func setupGit() {
        Sh.run("gh auth setup-git") { [weak self] result in
            guard let self else { return }
            self.show(
                result.succeeded ? "git теперь берёт токен у gh" : "Не вышло: \(result.firstLine)",
                isError: !result.succeeded
            )
            self.readGitConfig()
        }
    }

    // MARK: - Подписи коммитов

    func setIdentity(_ identity: GitIdentity?, for account: GitAccount) {
        identities[account.id] = (identity?.isEmpty ?? true) ? nil : identity
        saveIdentities()

        // Для активного аккаунта подпись нужна прямо сейчас, а не при следующем переключении.
        if account.isActive, let identity = identities[account.id] {
            applyIdentity(identity) { [weak self] ok in
                self?.show(ok ? "Подпись обновлена" : "Подпись не записалась", isError: !ok)
            }
        }
    }

    private func applyIdentity(_ identity: GitIdentity, completion: @escaping (Bool) -> Void) {
        let command = Sh.join(["git", "config", "--global", "user.name", identity.name])
            + " && "
            + Sh.join(["git", "config", "--global", "user.email", identity.email])
        Sh.run(command, timeout: 10) { [weak self] result in
            self?.readGitConfig()
            completion(result.succeeded)
        }
    }

    /// Подсказка для редактора: имя из профиля и noreply-адрес GitHub.
    func suggestIdentity(for account: GitAccount, completion: @escaping (GitIdentity?) -> Void) {
        let command = Sh.join([
            "gh", "api", "--hostname", account.host, "users/\(account.login)",
            "--jq", #"[(.name // .login), (.id | tostring)] | join("\t")"#
        ])
        Sh.run(command, timeout: 15) { result in
            let parts = result.output.components(separatedBy: "\t")
            guard result.succeeded, parts.count == 2 else {
                completion(nil)
                return
            }
            let domain = account.host == "github.com"
                ? "users.noreply.github.com"
                : "users.noreply.\(account.host)"
            completion(GitIdentity(
                name: parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                email: "\(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))+\(account.login)@\(domain)"
            ))
        }
    }

    private func loadIdentities() {
        guard let data = try? Data(contentsOf: Paths.gitIdentities),
              let decoded = try? JSONDecoder().decode([String: GitIdentity].self, from: data)
        else { return }
        identities = decoded
    }

    private func saveIdentities() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? encoder.encode(identities).write(to: Paths.gitIdentities, options: .atomic)
    }

    // MARK: - Сообщения

    func show(_ text: String, isError: Bool = false) {
        notice = Notice(text: text, isError: isError)
        noticeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 8 : 4), execute: item)
    }

    func dismissNotice() {
        noticeWorkItem?.cancel()
        notice = nil
    }

    // MARK: - Мелочи

    func copyLogin(_ account: GitAccount) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(account.login, forType: .string)
    }

    func openProfile(_ account: GitAccount) {
        if let url = account.profileURL { NSWorkspace.shared.open(url) }
    }
}
