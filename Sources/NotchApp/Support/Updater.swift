import AppKit
import Security

/// Обновление из релизов GitHub: спрашиваем последний релиз, качаем его dmg,
/// проверяем подпись и подменяем собственный бандл.
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case installing
        case failed(String)
    }

    struct Release {
        let version: String
        let dmg: URL
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    static let repo = "UniTeam-dev/NotchApp"
    /// Команда Developer ID, которой подписаны релизы. Обновление с другой
    /// подписью не ставим, откуда бы оно ни скачалось.
    static let teamID = "TB954423F4"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    @Published private(set) var state: State = .idle
    private var pending: Release?

    @MainActor
    func check() async {
        state = .checking
        do {
            let release = try await Self.latestRelease()
            if Self.isNewer(release.version, than: Self.currentVersion) {
                pending = release
                state = .available(version: release.version)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @MainActor
    func install() async {
        guard let release = pending else { return }
        state = .installing
        do {
            try await Self.install(release)
            Self.relaunch()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Шаги

    /// «0.10» новее «0.9»: сравниваем числа, а не строки.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    static func latestRelease() async throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let assets: [Asset]
        }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure("GitHub не ответил")
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let asset = payload.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            throw Failure("В релизе нет dmg")
        }
        let version = String(payload.tag_name.drop { $0 == "v" || $0 == "V" })
        return Release(version: version, dmg: asset.browser_download_url)
    }

    static func install(_ release: Release) async throws {
        let fm = FileManager.default
        let bundle = Bundle.main.bundleURL
        let folder = bundle.deletingLastPathComponent()
        // Запуск прямо из образа или из карантинной копии: писать некуда.
        guard bundle.pathExtension == "app", fm.isWritableFile(atPath: folder.path) else {
            throw Failure("Нет прав на запись в папку приложения — обновите вручную")
        }

        let work = fm.temporaryDirectory.appendingPathComponent("NotchApp-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let (downloaded, response) = try await URLSession.shared.download(from: release.dmg)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure("Не удалось скачать обновление")
        }
        let dmg = work.appendingPathComponent("NotchApp.dmg")
        try fm.moveItem(at: downloaded, to: dmg)

        let mount = work.appendingPathComponent("mount")
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }

        // Копия рядом с приложением: подмена атомарна только в пределах тома.
        // Подпись проверяем у копии — ставим ровно то, что проверили.
        let staged = folder.appendingPathComponent(".NotchApp-update.app")
        try? fm.removeItem(at: staged)
        try fm.copyItem(at: mount.appendingPathComponent("NotchApp.app"), to: staged)
        do {
            try verifySignature(of: staged)
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
        _ = try fm.replaceItemAt(bundle, withItemAt: staged)
    }

    /// Developer ID нашей команды и наш bundle ID — то же, что проверяет Gatekeeper,
    /// плюс привязка к команде.
    static func verifySignature(of app: URL) throws {
        let text = """
        identifier "com.notchapp.NotchApp" and anchor apple generic \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
        and certificate leaf[subject.OU] = "\(teamID)"
        """
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)

        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
        else {
            throw Failure("Подпись обновления не прошла проверку")
        }
    }

    /// Запускаем новую копию после выхода старой: `open` на живое приложение
    /// просто активировал бы его.
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure("\((path as NSString).lastPathComponent) завершился с кодом \(process.terminationStatus)")
        }
    }
}
