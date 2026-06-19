import SwiftUI

/// Единый визуальный язык приложения — стиль **Aurora Glass**.
///
/// Глубоко-синий фон, мягкое aurora-свечение (teal → green → blue), фрост-стекло
/// (`.ultraThinMaterial`) для карточек, градиентные кнопки. Тёмная тема.
///
/// Используется всеми экранами через:
///   - `AuroraBackground()`            — подложка под контент;
///   - `.glassCard()`                  — стеклянная карточка;
///   - `.buttonStyle(AuroraButtonStyle())` — главная кнопка;
///   - цвета `Color.aurora*` / `Theme.*`.
enum Theme {
    // MARK: - Палитра

    static let bgDeep      = Color(hex: 0x070B16)   // почти чёрно-синий фон
    static let bgRaised    = Color(hex: 0x0E1426)   // приподнятые поверхности
    static let stroke      = Color.white.opacity(0.10)
    static let strokeStrong = Color.white.opacity(0.18)

    static let textPrimary   = Color(hex: 0xF2F5FF)
    static let textSecondary = Color(hex: 0x9AA6C2)

    // Aurora-акценты
    static let teal   = Color(hex: 0x2DD4BF)
    static let green  = Color(hex: 0x34D399)
    static let blue   = Color(hex: 0x3B82F6)
    static let indigo = Color(hex: 0x6366F1)

    // Статусы
    static let statusOn    = green
    static let statusBusy  = Color(hex: 0xF6B73C)
    static let statusOff   = Color(hex: 0x64708C)
    static let statusError = Color(hex: 0xFF5C6C)

    // MARK: - Градиенты

    /// Основной aurora-градиент (для колец, кнопок, акцентов).
    static let aurora = LinearGradient(
        colors: [teal, green, blue],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let auroraSoft = LinearGradient(
        colors: [teal.opacity(0.85), blue.opacity(0.85)],
        startPoint: .leading, endPoint: .trailing)

    static func statusGradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.95), color.opacity(0.55)],
                       startPoint: .top, endPoint: .bottom)
    }

    // Радиусы / отступы
    static let radius: CGFloat = 18
    static let radiusSmall: CGFloat = 12
    static let hPadding: CGFloat = 16
}

// MARK: - Color hex helper

extension Color {
    /// Цвет из 0xRRGGBB.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Анимированный aurora-фон

/// Подложка под весь контент: тёмный фон + медленно дрейфующие цветные «пятна»
/// (radial gradients), создающие эффект полярного сияния.
///
/// ВАЖНО: фон ДОЛЖЕН быть нейтральным к layout. Раньше «пятна» задавались
/// фиксированными размерами 460–520pt, а так как `.offset` и `.ignoresSafeArea()`
/// прозрачны для системы компоновки, каждый круг сообщал родителю свой полный
/// размер. Из-за этого внутренний `ZStack` фона (и, как следствие, корневой
/// `ZStack` каждого экрана) становился ~520pt шириной — шире экрана — и контент
/// обрезался с обеих сторон.
///
/// Решение: оборачиваем «пятна» в `GeometryReader`, фиксируем внутренний `ZStack`
/// строго по размеру экрана и обрезаем (`.clipped()`). Теперь фон занимает ровно
/// доступную область и никогда не растягивает контент за пределы экрана.
struct AuroraBackground: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.bgDeep

                blob(Theme.teal,   size: 460)
                    .offset(x: animate ? -120 : -160, y: animate ? -220 : -260)
                blob(Theme.blue,   size: 520)
                    .offset(x: animate ? 150 : 120, y: animate ? -120 : -60)
                blob(Theme.indigo, size: 480)
                    .offset(x: animate ? -90 : -40, y: animate ? 260 : 320)
                blob(Theme.green,  size: 380)
                    .offset(x: animate ? 160 : 200, y: animate ? 260 : 300)
            }
            // Жёстко фиксируем размер по экрану, чтобы крупные «пятна»
            // не влияли на компоновку, и обрезаем всё, что выходит за края.
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.55), color.opacity(0.0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: 60)
    }
}

// MARK: - Стеклянная карточка

struct GlassCard: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = Theme.radius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
    }
}

extension View {
    /// Оборачивает содержимое в стеклянную карточку Aurora Glass.
    func glassCard(padding: CGFloat = 16, radius: CGFloat = Theme.radius) -> some View {
        modifier(GlassCard(padding: padding, radius: radius))
    }
}

// MARK: - Кнопка

/// Главная кнопка: заливка градиентом, мягкая тень, отклик на нажатие.
struct AuroraButtonStyle: ButtonStyle {
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.aurora)
    var tint: Color = Theme.teal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: tint.opacity(0.45), radius: configuration.isPressed ? 6 : 16, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Вторичная кнопка (контурная, на стекле).
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 12).padding(.horizontal, 18)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Чип / pill

/// Маленькая «таблетка» с подписью (carrier · transport и т.п.).
struct PillLabel: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = Theme.teal

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text).font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1))
    }
}

// MARK: - Заголовок секции

struct SectionTitle: View {
    let text: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage).font(.subheadline)
                    .foregroundStyle(Theme.teal)
            }
            Text(text.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
        }
    }
}

// MARK: - Глиф провайдера (carrier)

extension OLCCarrier {
    var glyph: String {
        switch self {
        case .jitsi:    return "video.fill"
        case .telemost: return "phone.bubble.fill"
        case .wbstream: return "dot.radiowaves.left.and.right"
        }
    }
    var tint: Color {
        switch self {
        case .jitsi:    return Theme.teal
        case .telemost: return Theme.indigo
        case .wbstream: return Theme.green
        }
    }
}
