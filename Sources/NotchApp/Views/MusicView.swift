import SwiftUI

struct MusicView: View {
    @ObservedObject var music: MusicModel

    var body: some View {
        if !music.mediaControlInstalled {
            EmptyHint(
                symbol: "exclamationmark.triangle",
                title: "Нет media-control",
                subtitle: "brew install media-control — без него метаданные системе недоступны"
            )
        } else if music.nowPlaying.title == NowPlaying.placeholder.title {
            EmptyHint(symbol: "waveform", title: "Ничего не играет")
        } else {
            player
        }
    }

    private var player: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 6) {
                titles
                progress
                controls
            }
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))

            if let image = music.nowPlaying.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .frame(width: 68, height: 68)
        .onTapGesture { music.revealPlayer() }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(music.nowPlaying.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)

            Text(subtitleText)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    private var subtitleText: String {
        let parts = [music.nowPlaying.artist, music.nowPlaying.appName].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    // MARK: - Прогресс

    private var progress: some View {
        let duration = music.nowPlaying.duration ?? 0
        let position = music.effectivePosition
        let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0

        return VStack(spacing: 3) {
            GeometryReader { geometry in
                let width = geometry.size.width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3)

                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: width * fraction, height: 3)
                }
                .frame(height: 10)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            guard duration > 0, width > 0 else { return }
                            let ratio = min(max(value.location.x / width, 0), 1)
                            music.seek(to: ratio * duration)
                        }
                )
            }
            .frame(height: 10)

            HStack {
                Text(Self.time(position))
                Spacer()
                Text(Self.time(duration))
            }
            .font(.system(size: 8).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    private static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Кнопки

    private var controls: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "backward.fill", help: "Предыдущий", action: music.previous)
            IconButton(
                symbol: music.nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                help: "Играть или пауза",
                size: 12,
                action: music.toggle
            )
            IconButton(symbol: "forward.fill", help: "Следующий", action: music.next)
            Spacer()
        }
    }
}
