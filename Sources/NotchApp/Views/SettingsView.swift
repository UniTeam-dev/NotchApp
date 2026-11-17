import SwiftUI

/// Настройки: какие разделы показывать и обновление из релизов GitHub.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            sections
            Divider().overlay(Color.white.opacity(0.08))
            update
        }
        .task {
            if updater.state == .idle { await updater.check() }
        }
    }

    // MARK: - Разделы

    private var sections: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("Разделы")
            LazyVGrid(
                columns: [GridItem(.fixed(128), alignment: .leading), GridItem(.fixed(128), alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(NotchTab.allCases) { tab in
                    Toggle(isOn: Binding(
                        get: { settings.isVisible(tab) },
                        set: { settings.setVisible(tab, $0) }
                    )) {
                        Label(tab.title, systemImage: tab.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .lineLimit(1)
                            .fixedSize()
                            // Тумблеры выстраиваются по правому краю колонки.
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    // Последний включённый раздел выключить нельзя.
                    .disabled(settings.isVisible(tab) && settings.visibleTabs.count == 1)
                }
            }
        }
    }

    // MARK: - Обновление

    private var update: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("Версия \(Updater.currentVersion)")

            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(statusColor)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                switch updater.state {
                case .checking, .installing:
                    ProgressView().controlSize(.mini).tint(.white)
                case .available(let version):
                    PillButton(symbol: "arrow.down.circle", title: "Обновить до \(version)") {
                        Task { await updater.install() }
                    }
                default:
                    PillButton(symbol: "arrow.clockwise", title: "Проверить") {
                        Task { await updater.check() }
                    }
                }
                PillButton(symbol: "arrow.up.right", title: "Релизы") {
                    NSWorkspace.shared.open(Updater.releasesPage)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: String {
        switch updater.state {
        case .idle, .checking: return "Проверяю обновления…"
        case .upToDate: return "Установлена последняя версия"
        case .available(let version): return "Доступна версия \(version)"
        case .installing: return "Скачиваю и устанавливаю — приложение перезапустится"
        case .failed(let reason): return reason
        }
    }

    private var statusColor: Color {
        if case .failed = updater.state { return Color(red: 1.0, green: 0.38, blue: 0.36) }
        return Color.white.opacity(0.6)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.6))
    }
}
