import Foundation

/// Отправка команд плееру через приватный MediaRemote.
///
/// Ключевой факт: с macOS 15.4 **чтение** системного Now Playing закрыто для
/// сторонних процессов — `MRMediaRemoteGetNowPlayingInfo` отдаёт пустоту.
/// А **отправка команд** работает in-process и никуда не делась. Гейт стоит не
/// на entitlement, который можно получить: `mediaremoted` пускает клиентов,
/// чей bundle ID начинается на `com.apple.`.
///
/// Поэтому метаданные читаем через `media-control` (см. `MediaControlBridge`),
/// а командуем отсюда.
final class MediaRemoteBridge {
    enum Command: Int32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias SendCommandFunction = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias SetElapsedTimeFunction = @convention(c) (Double) -> Void

    private var sendCommandFn: SendCommandFunction?
    private var setElapsedTimeFn: SetElapsedTimeFunction?

    var isAvailable: Bool { sendCommandFn != nil }

    init() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL) else {
            Log.music.error("MediaRemote.framework не открылся")
            return
        }

        if let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            sendCommandFn = unsafeBitCast(pointer, to: SendCommandFunction.self)
        }
        if let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString) {
            setElapsedTimeFn = unsafeBitCast(pointer, to: SetElapsedTimeFunction.self)
        }
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        guard let sendCommandFn else { return false }
        return sendCommandFn(command.rawValue, nil)
    }

    func seek(to seconds: TimeInterval) {
        setElapsedTimeFn?(seconds)
    }
}
