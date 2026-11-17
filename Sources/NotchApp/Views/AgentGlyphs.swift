import SwiftUI

// MARK: - Аура

/// Рассеянное свечение позади панели. Цвет — состояние, оттенок — IDE.
///
/// Живёт за пределами `clipShape`, поэтому мягко выходит за края панели:
/// ради этого `NotchController` добавляет запас вокруг контента.
struct NotchAura: View {
    let glow: NotchGlow
    let isOpen: Bool
    let size: CGSize

    /// «Дыхание» — только для того, что ждёт человека прямо сейчас.
    @State private var breathe = false
    /// Вспышка на смену состояния: свечение приходит ярким и за несколько
    /// секунд оседает до своей постоянной яркости. Без этого переход
    /// «работает → готово» на периферии зрения просто не виден.
    @State private var settled = true

    private var opacity: Double {
        let base = glow.intense ? (breathe ? 0.9 : 0.45) : 0.62
        return min(1, base * glow.strength * (settled ? 1 : 1.7))
    }

    var body: some View {
        NotchShape(
            topRadius: isOpen ? 11 : 6,
            bottomRadius: isOpen ? 30 : 16
        )
        .fill(
            LinearGradient(
                colors: [glow.color, glow.tint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .frame(
            width: size.width + (isOpen ? 10 : 6),
            height: size.height + 12
        )
        .blur(radius: isOpen ? 28 : 16)
        .opacity(opacity)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
            flare()
        }
        .onChange(of: glow) { _, _ in
            flare()
        }
    }

    private func flare() {
        settled = false
        withAnimation(.easeOut(duration: 4.5)) {
            settled = true
        }
    }
}

// MARK: - Пульсирующая точка состояния

/// Точка цвета состояния. Для «требует внимания» — пульсирует.
struct PulsingDot: View {
    let color: Color
    let animated: Bool
    var ring: Color = Color(red: 0.03, green: 0.03, blue: 0.04)

    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .overlay { Circle().strokeBorder(ring, lineWidth: 1.5) }
            .scaleEffect(on ? 1.28 : 1)
            .opacity(on ? 0.6 : 1)
            .onAppear {
                guard animated else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

// MARK: - Индикатор в закрытой челке

/// Что видно, когда панель свёрнута, а по агентам есть что сказать.
///
/// Центр отдан аппаратному вырезу — под ним ничего не рисуем, там ничего не
/// видно. Иконка IDE уходит в левое крыло, счётчик и значок состояния —
/// в правое. Значок именно формой, а не только цветом: в крыле шириной 40 pt
/// зелёная точка и жёлтая точка на глаз почти одинаковы.
struct ClosedIndicator: View {
    let glow: NotchGlow
    let count: Int
    /// Ширина физического выреза.
    let notchWidth: CGFloat
    /// Ширина полосы сбоку от выреза.
    let wing: CGFloat

    private var countColor: Color {
        glow.state == .working ? Color.white.opacity(0.55) : glow.color
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: glow.source.mark)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(glow.tint)
                .shadow(color: glow.tint.opacity(0.6), radius: 4)
                .frame(width: wing)

            // Мёртвая зона под вырезом.
            Color.clear.frame(width: notchWidth)

            HStack(spacing: 4) {
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(countColor)
                }

                if glow.state == .working {
                    PulsingDot(color: glow.color, animated: false)
                        .frame(width: 7, height: 7)
                        .shadow(color: glow.color.opacity(0.8), radius: 4)
                } else {
                    Image(systemName: glow.mark)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(glow.color)
                        .shadow(color: glow.color.opacity(0.8), radius: 4)
                        .symbolEffect(.pulse, isActive: glow.intense)
                }
            }
            .frame(width: wing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
