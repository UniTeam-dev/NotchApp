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

    @State private var breathe = false

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
        .opacity((breathe ? 0.85 : 0.42) * (glow.intense ? 1.0 : 0.55))
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
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

/// Что видно, когда панель свёрнута, а агент чего-то ждёт: слева иконка IDE,
/// справа счётчик и пульсирующая точка состояния.
///
/// Оба элемента прижаты к краям, мимо центральной камеры.
struct ClosedIndicator: View {
    let glow: NotchGlow
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: glow.source.mark)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(glow.tint)

            Spacer()

            HStack(spacing: 5) {
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(glow.intense ? glow.color : Color.white.opacity(0.55))
                }
                PulsingDot(color: glow.color, animated: glow.intense)
                    .frame(width: 7, height: 7)
                    .shadow(color: glow.color.opacity(0.8), radius: 4)
            }
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
