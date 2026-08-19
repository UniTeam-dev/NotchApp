import AppKit

/// Снимок позиции. Ни один источник не двигает позицию сам — он отдаёт
/// значение на момент последнего обновления. Прогресс UI считает по формуле.
struct PositionSnapshot: Equatable {
    var value: TimeInterval
    var takenAt: Date
    var rate: Double

    static let zero = PositionSnapshot(value: 0, takenAt: .distantPast, rate: 0)

    func effective(at now: Date = Date(), duration: TimeInterval?) -> TimeInterval {
        guard rate > 0 else { return value }
        let elapsed = now.timeIntervalSince(takenAt) * rate
        let result = value + elapsed
        guard let duration, duration > 0 else { return max(result, 0) }
        return min(max(result, 0), duration)
    }
}

struct NowPlaying: Equatable {
    var title: String
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    var position: PositionSnapshot
    var isPlaying: Bool
    var bundleID: String?
    var artwork: NSImage?

    /// Человекочитаемое имя приложения-источника.
    var appName: String? {
        guard let bundleID else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    static let placeholder = NowPlaying(
        title: "Ничего не играет",
        artist: nil,
        album: nil,
        duration: nil,
        position: .zero,
        isPlaying: false,
        bundleID: nil,
        artwork: nil
    )
}
