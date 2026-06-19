import SwiftUI

/// Единый визуальный язык приложения — **Mono** (минимализм, чёрно-белый).
///
/// Тёмная почти-чёрная подложка, белый текст, тонкие серые штрихи и
/// «стеклянные» карточки. Без цветных акцентов — только оттенки серого и белый.
/// Главный декоративный элемент — вращающаяся линия по рамке круга (`RotatingRing`).
///
/// Используется всеми экранами через:
///   - `AuroraBackground()`            — нейтральная подложка под контент;
///   - `.glassCard()`                  — карточка со стеклом и тонкой рамкой;
///   - `.buttonStyle(AuroraButtonStyle())` — главная кнопка (белая заливка, чёрный текст);
///   - `RotatingRing(...)`             — анимированное кольцо-рамка;
///   - цвета `Theme.*`.
enum Theme {
    // MARK: - Палитра (монохром)

    static let bgDeep       = Color(hex: 0x0A0A0B)   // почти чёрный фон
    static let bgRaised     = Color(hex: 0x161618)   // приподнятые поверхности
    static let stroke       = Color.white.opacity(0.12)
    static let strokeStrong = Color.white.opacity(0.22)

    static let textPrimary   = Color(hex: 0xF7F7F8)
    static let textSecondary = Color(hex: 0x9A9AA0)

    // «Акценты» в монохроме — просто оттенки серого/белого.
    // Имена сохранены, чтобы не ломать существующие экраны.
    static let teal   = Color(hex: 0xFFFFFF)
    static let green  = Color(hex: 0xE6E6E8)
    static let blue   = Color(hex: 0xC2C2C8)
    static let indigo = Color(hex: 0x8E8E96)

    // Статусы (монохром: яркость = смысл)
    static let statusOn    = Color(hex: 0xFFFFFF)
    static let statusBusy  = Color(hex: 0xC2C2C8)
    static let statusOff   = Color(hex: 0x55555C)
    static let statusError = Color(hex: 0xEDEDEF)

    // MARK: - Градиенты (монохромные)

    /// Основной градиент (для колец, кнопок, акцентов) — белый → серый.
    static let aurora = LinearGradient(
        colors: [Color.white, Color(hex: 0x9A9AA0)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let auroraSoft = LinearGradient(
        colors: [Color.white.opacity(0.92), Color(hex: 0x9A9AA0).opacity(0.92)],
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

// MARK: - Подложка

/// Минималистичная подложка: почти-чёрный фон с едва заметным белым свечением.
/// Нейтральна к layout, поэтому контент никогда не уезжает за края.
///
/// ВАЖНО (сохранено из фикса 1.0.1): свечение оборачиваем в `GeometryReader`,
/// фиксируем внутренний `ZStack` строго по размеру экрана и обрезаем (`.clipped()`),
/// чтобы крупные размытые круги не растягивали корневой `ZStack` экрана.
struct AuroraBackground: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.bgDeep

                glow(opacity: 0.06, size: 460)
                    .offset(x: animate ? -60 : -100, y: animate ? -240 : -280)
                glow(opacity: 0.04, size: 520)
                    .offset(x: animate ? 120 : 90, y: animate ? 280 : 320)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }

    private func glow(opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Color.white.opacity(opacity), Color.white.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: 60)
    }
}

// MARK: - Анимированное кольцо-рамка (вращающаяся линия)

/// Тонкая статичная рамка-круг с бегущей по ней светлой дугой —
/// главный декоративный элемент минималистичного дизайна.
///
/// АНИМАЦИЯ (исправлено в 1.2.0): вращение драйвится через `TimelineView(.animation)`,
/// а не через `withAnimation(...).repeatForever(...)`. Раньше repeatForever-анимация
/// «срывалась» / дёргалась: любой ре-рендер родителя (смена статуса, implicit-анимации
/// рядом) и возврат из фона перезапускали/останавливали её. `TimelineView` идёт по
/// собственным часам и не зависит от внешних изменений состояния — движение плавное.
///
/// - Parameters:
///   - size: диаметр кольца;
///   - lineWidth: толщина линии;
///   - active: `true` — дуга вращается, `false` — стоит на месте (часы на паузе);
///   - progress: длина бегущей дуги (доля окружности, 0…1);
///   - duration: период полного оборота, сек.
struct RotatingRing: View {
    var size: CGFloat = 200
    var lineWidth: CGFloat = 3
    var active: Bool = true
    var progress: CGFloat = 0.25
    var duration: Double = 2.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !active)) { context in
            let angle = rotation(at: context.date)
            ZStack {
                // Статичная рамка
                Circle()
                    .stroke(Theme.stroke, lineWidth: lineWidth)

                // Бегущая дуга (хвост гаснет → ведущая точка яркая)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [Color.white.opacity(0), Color.white]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(Double(progress) * 360)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }

    /// Угол поворота от текущего времени (непрерывный, без рывков на переходе 360→ 0).
    private func rotation(at date: Date) -> Double {
        guard active, duration > 0 else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        let fraction = t.truncatingRemainder(dividingBy: duration) / duration
        return fraction * 360
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
    /// Оборачивает содержимое в минималистичную стеклянную карточку.
    func glassCard(padding: CGFloat = 16, radius: CGFloat = Theme.radius) -> some View {
        modifier(GlassCard(padding: padding, radius: radius))
    }
}

// MARK: - Кнопка

/// Главная кнопка: белая заливка, чёрный текст, мягкая тень, отклик на нажатие.
struct AuroraButtonStyle: ButtonStyle {
    var fill: AnyShapeStyle = AnyShapeStyle(Color.white)
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: configuration.isPressed ? 4 : 12, y: 6)
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
/// В монохроме параметр `color` сохранён для совместимости, но визуально
/// используется единый бело-серый стиль.
struct PillLabel: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text).font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
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
                    .foregroundStyle(Theme.textSecondary)
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
    /// В монохроме — оттенки серого/белого вместо цветных акцентов.
    var tint: Color {
        switch self {
        case .jitsi:    return Theme.textPrimary
        case .telemost: return Theme.blue
        case .wbstream: return Theme.indigo
        }
    }
}
