import AppKit
import Combine

/// Что играет и чем этим управлять.
///
/// Разделение источников намеренное:
/// - метаданные и прогресс приходят из `media-control`;
/// - команды уходят через `MRMediaRemoteSendCommand`;
/// - если MediaRemote недоступен, а плеер знакомый — резерв через AppleScript.
final class MusicModel: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying = .placeholder
    /// Тик для перерисовки прогресса. Сам прогресс считается по снимку позиции.
    @Published private(set) var tick = Date()
    @Published private(set) var mediaControlInstalled = MediaControlBridge.isAvailable

    private let stream = MediaControlBridge()
    private let remote = MediaRemoteBridge()
    private var ticker: Timer?
    private var lastTrackKey: String?

    var effectivePosition: TimeInterval {
        nowPlaying.position.effective(at: tick, duration: nowPlaying.duration)
    }

    // MARK: - Жизненный цикл

    func start() {
        mediaControlInstalled = MediaControlBridge.isAvailable

        stream.onSnapshot = { [weak self] payload in
            self?.apply(payload)
        }
        stream.start()

        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.nowPlaying.isPlaying else { return }
            self.tick = Date()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func stop() {
        stream.stop()
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Разбор снимка

    private func apply(_ payload: [String: Any]) {
        let title = string(payload, "title") ?? ""
        guard !title.isEmpty else {
            nowPlaying = .placeholder
            lastTrackKey = nil
            return
        }

        let artist = string(payload, "artist")
        let album = string(payload, "album")
        let bundleID = string(payload, "bundleIdentifier") ?? string(payload, "bundleID")
        let duration = number(payload, "duration")
        let elapsed = number(payload, "elapsedTime") ?? number(payload, "position") ?? 0
        let playing = (payload["playing"] as? Bool) ?? (payload["isPlaying"] as? Bool) ?? false

        // Метка времени снимка: если источник её дал — берём её, иначе «сейчас».
        let takenAt: Date
        if let timestamp = number(payload, "timestamp"), timestamp > 1_000_000_000 {
            takenAt = Date(timeIntervalSince1970: timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp)
        } else {
            takenAt = Date()
        }

        let trackKey = [title, artist ?? "", album ?? ""].joined(separator: "|")
        let artworkChanged = trackKey != lastTrackKey

        var updated = NowPlaying(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: PositionSnapshot(value: elapsed, takenAt: takenAt, rate: playing ? 1 : 0),
            isPlaying: playing,
            bundleID: bundleID,
            artwork: artworkChanged ? nil : nowPlaying.artwork
        )

        if !artworkChanged { updated.artwork = nowPlaying.artwork }
        nowPlaying = updated
        tick = Date()

        if artworkChanged {
            lastTrackKey = trackKey
            stream.fetchArtwork { [weak self] data in
                guard let self, let data, let image = NSImage(data: data) else { return }
                guard self.lastTrackKey == trackKey else { return }
                self.nowPlaying.artwork = image
            }
        }
    }

    private func string(_ payload: [String: Any], _ key: String) -> String? {
        guard let value = payload[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    private func number(_ payload: [String: Any], _ key: String) -> Double? {
        if let value = payload[key] as? Double { return value }
        if let value = payload[key] as? Int { return Double(value) }
        if let value = payload[key] as? NSNumber { return value.doubleValue }
        return nil
    }

    // MARK: - Управление

    func toggle() {
        if remote.send(.togglePlayPause) { return }
        if let player = AppleScriptBridge.Player(bundleID: nowPlaying.bundleID) {
            AppleScriptBridge.playPause(player)
        }
    }

    func next() {
        if remote.send(.nextTrack) { return }
        if let player = AppleScriptBridge.Player(bundleID: nowPlaying.bundleID) {
            AppleScriptBridge.next(player)
        }
    }

    func previous() {
        if remote.send(.previousTrack) { return }
        if let player = AppleScriptBridge.Player(bundleID: nowPlaying.bundleID) {
            AppleScriptBridge.previous(player)
        }
    }

    func seek(to seconds: TimeInterval) {
        guard remote.isAvailable else {
            if let player = AppleScriptBridge.Player(bundleID: nowPlaying.bundleID) {
                AppleScriptBridge.seek(player, to: seconds)
            }
            return
        }
        remote.seek(to: seconds)
        nowPlaying.position = PositionSnapshot(
            value: seconds,
            takenAt: Date(),
            rate: nowPlaying.isPlaying ? 1 : 0
        )
        tick = Date()
    }

    /// Открыть приложение-источник.
    func revealPlayer() {
        guard let bundleID = nowPlaying.bundleID else { return }
        Shell.open(["-b", bundleID])
    }
}
