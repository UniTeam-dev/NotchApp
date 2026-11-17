import SwiftUI

/// Вкладка «Git»: аккаунты GitHub CLI с переключением тумблером.
struct GitView: View {
    @ObservedObject var git: GitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content
            footer
        }
        .onAppear { git.refreshIfStale() }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 8) {
            Text("GitHub")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))

            if !git.accounts.isEmpty {
                Text("\(git.accounts.count)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.35))
            }

            if git.gitUsesGh == false && !git.accounts.isEmpty {
                Button(action: git.setupGit) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                        Text("git берёт пароль не у gh · настроить")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(GitPalette.orange.opacity(0.18)))
                    .foregroundStyle(GitPalette.orange)
                }
                .buttonStyle(.plain)
                .help("Выполнить gh auth setup-git: git начнёт брать токен активного аккаунта")
            }

            Spacer()

            if git.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            }

            IconButton(symbol: "arrow.clockwise", help: "Обновить", size: 10, action: git.refresh)

            PillButton(symbol: "plus", title: "Аккаунт") {
                GitWindows.shared.showLogin(store: git)
            }
        }
    }

    // MARK: - Тело

    @ViewBuilder
    private var content: some View {
        if git.ghMissing {
            EmptyHint(
                symbol: "exclamationmark.triangle",
                title: "Не нашёл gh",
                subtitle: "Поставьте GitHub CLI: brew install gh"
            )
        } else if git.accounts.isEmpty {
            if git.hasLoaded {
                VStack(spacing: 8) {
                    EmptyHint(
                        symbol: "person.crop.circle.badge.plus",
                        title: "Аккаунтов нет",
                        subtitle: "Войдите в GitHub — аккаунт появится здесь"
                    )
                    PillButton(symbol: "plus", title: "Добавить аккаунт") {
                        GitWindows.shared.showLogin(store: git)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(git.accounts) { account in
                        GitAccountRow(account: account, git: git)
                    }
                }
            }
        }
    }

    // MARK: - Подвал

    @ViewBuilder
    private var footer: some View {
        if let notice = git.notice {
            HStack(spacing: 5) {
                Image(systemName: notice.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .font(.system(size: 9))
                Text(notice.text)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(notice.isError ? GitPalette.red : GitPalette.green)
            .onTapGesture { git.dismissNotice() }
            .transition(.opacity)
        } else if let identity = git.globalIdentity {
            HStack(spacing: 5) {
                Image(systemName: "signature")
                    .font(.system(size: 9))
                Text("Коммиты подписываются как \(identity.display)")
                    .font(.system(size: 9.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(Color.white.opacity(0.35))
        }
    }
}

// MARK: - Строка аккаунта

struct GitAccountRow: View {
    let account: GitAccount
    @ObservedObject var git: GitStore

    @State private var isHovering = false
    @State private var confirmLogout = false

    private var isBusy: Bool { git.busyAccountID == account.id }
    private var identity: GitIdentity? { git.identities[account.id] }

    var body: some View {
        HStack(spacing: 9) {
            GitAvatar(account: account)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(account.login)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(account.isValid ? 0.92 : 0.5))
                        .lineLimit(1)

                    if account.host != "github.com" {
                        GitTag(text: account.host, color: Color.white.opacity(0.5))
                    }
                    if account.isActive {
                        GitTag(text: "активен", color: GitPalette.green)
                    }
                    if !account.isValid {
                        GitTag(text: "токен недействителен", color: GitPalette.red)
                    }
                }

                subtitle
            }

            Spacer(minLength: 6)

            if confirmLogout {
                logoutConfirmation
            } else if isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
                    .frame(width: 32)
            } else {
                Toggle("", isOn: Binding(
                    get: { account.isActive },
                    set: { on in if on { git.activate(account) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(GitPalette.green)
                .disabled(!account.isValid || git.busyAccountID != nil || account.isActive)
                .help(account.isActive ? "Этот аккаунт уже активен" : "Сделать активным")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(account.isActive ? 0.09 : (isHovering ? 0.07 : 0.04)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(account.isActive ? GitPalette.green.opacity(0.28) : .clear, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .contextMenu { menu }
        .animation(.easeOut(duration: 0.15), value: account.isActive)
    }

    @ViewBuilder
    private var subtitle: some View {
        if let identity {
            Text(identity.display)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Подпись коммитов для этого аккаунта")
        } else if !account.scopes.isEmpty {
            Text(account.scopes.joined(separator: " · "))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.32))
                .lineLimit(1)
                .truncationMode(.tail)
                .help("Права токена")
        } else if let storage = account.storage {
            Text(storage)
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.32))
        }
    }

    private var logoutConfirmation: some View {
        HStack(spacing: 4) {
            Text("Выйти?")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
            SmallButton(title: "Да", color: GitPalette.red) {
                confirmLogout = false
                git.logout(account)
            }
            SmallButton(title: "Нет", color: Color.white.opacity(0.6)) {
                confirmLogout = false
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        if !account.isActive && account.isValid {
            Button("Сделать активным") { git.activate(account) }
        }
        Button("Подпись коммитов…") {
            GitWindows.shared.showIdentity(store: git, account: account)
        }
        Divider()
        Button("Скопировать логин") { git.copyLogin(account) }
        Button("Открыть профиль") { git.openProfile(account) }
        Divider()
        Button("Выйти из аккаунта…", role: .destructive) { confirmLogout = true }
    }
}

// MARK: - Мелкие элементы

enum GitPalette {
    static let green = Color(red: 0.38, green: 0.85, blue: 0.54)
    static let red = Color(red: 1.0, green: 0.43, blue: 0.40)
    static let orange = Color(red: 1.0, green: 0.66, blue: 0.26)
}

struct GitAvatar: View {
    let account: GitAccount

    var body: some View {
        AsyncImage(url: account.avatarURL) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Text(String(account.login.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(account.isActive ? GitPalette.green.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .saturation(account.isValid ? 1 : 0)
    }
}

private struct GitTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private struct SmallButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.18)))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

/// Капсула «плюс + подпись» — та же, что на вкладке «Терминал».
struct PillButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .foregroundStyle(Color.white.opacity(0.75))
        }
        .buttonStyle(.plain)
    }
}
