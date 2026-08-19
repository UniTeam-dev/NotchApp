import Foundation

/// Резервный путь управления — AppleScript к Apple Music и Spotify.
///
/// Именно резервный, а не основной: у Apple Music на 26 есть баг -1728,
/// `name of current track` падает для стриминговых треков вне библиотеки.
/// `ScriptingBridge` для Music на Tahoe сломан, поэтому только `NSAppleScript`.
/// У Spotify `duration` приходит в миллисекундах, несмотря на словарь.
enum AppleScriptBridge {
    enum Player: String {
        case music = "Music"
        case spotify = "Spotify"

        init?(bundleID: String?) {
            switch bundleID {
            case "com.apple.Music": self = .music
            case "com.spotify.client": self = .spotify
            default: return nil
            }
        }
    }

    @discardableResult
    static func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            Log.music.error("AppleScript: \(String(describing: error), privacy: .public)")
            return nil
        }
        return result.stringValue
    }

    static func playPause(_ player: Player) {
        run("tell application \"\(player.rawValue)\" to playpause")
    }

    static func next(_ player: Player) {
        run("tell application \"\(player.rawValue)\" to next track")
    }

    static func previous(_ player: Player) {
        // У Apple Music одиночный previous перематывает в начало трека,
        // поэтому зовём дважды — так же, как это делает сама кнопка.
        run("tell application \"\(player.rawValue)\" to previous track")
    }

    static func seek(_ player: Player, to seconds: TimeInterval) {
        run("tell application \"\(player.rawValue)\" to set player position to \(seconds)")
    }
}
