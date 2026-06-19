import SwiftUI
import NetworkExtension

struct ConnectView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var tunnel: TunnelManager

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                VStack(spacing: 26) {
                    Spacer(minLength: 8)

                    ConnectionOrb(connected: tunnel.isConnected, busy: tunnel.isBusy)

                    VStack(spacing: 6) {
                        Text(tunnel.statusText)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(statusColor)
                            .contentTransition(.opacity)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    profileCard

                    Spacer()

                    if let err = tunnel.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.statusError)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(padding: 12)
                    }

                    connectButton
                }
                .padding(20)
            }
            .navigationTitle("OLCVPN")
        }
    }

    private var statusColor: Color {
        if tunnel.isConnected { return Theme.statusOn }
        if tunnel.isBusy { return Theme.statusBusy }
        return Theme.textSecondary
    }

    private var subtitle: String {
        if tunnel.isConnected { return "Трафик идёт через защищённый туннель" }
        if tunnel.isBusy { return "Устанавливаю соединение через WebRTC…" }
        return store.activeProfile == nil ? "Добавь профиль во вкладке «Профили»" : "Готов к подключению"
    }

    @ViewBuilder
    private var profileCard: some View {
        if let p = store.activeProfile {
            HStack(spacing: 12) {
                Image(systemName: p.carrier.glyph)
                    .font(.title3)
                    .foregroundStyle(p.carrier.tint)
                    .frame(width: 40, height: 40)
                    .background(p.carrier.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(p.name).font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        PillLabel(text: p.carrier.rawValue, color: p.carrier.tint)
                        PillLabel(text: p.transport.title, color: Theme.blue)
                    }
                }
                Spacer()
            }
            .glassCard()
        } else {
            HStack {
                Image(systemName: "tray").foregroundStyle(Theme.textSecondary)
                Text("Нет активного профиля").foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .glassCard()
        }
    }

    private var connectButton: some View {
        Button {
            if tunnel.isConnected {
                tunnel.disconnect()
            } else {
                guard let cfg = store.activeTunnelConfig() else {
                    tunnel.lastError = "Выбери профиль и проверь ключ"
                    return
                }
                // Резерв: дублируем в App Group (если доступен); основной путь — providerConfiguration.
                store.publishActiveToTunnel()
                tunnel.connect(providerConfig: cfg)
            }
        } label: {
            HStack(spacing: 8) {
                if tunnel.isBusy { ProgressView().tint(.white) }
                Image(systemName: tunnel.isConnected ? "power" : "bolt.fill")
                Text(buttonTitle)
            }
        }
        .buttonStyle(AuroraButtonStyle(
            fill: tunnel.isConnected ? AnyShapeStyle(Theme.statusGradient(Theme.statusError))
                                     : AnyShapeStyle(Theme.aurora),
            tint: tunnel.isConnected ? Theme.statusError : Theme.teal))
        .disabled(store.activeProfile == nil || tunnel.isBusy)
        .opacity(store.activeProfile == nil ? 0.5 : 1)
    }

    private var buttonTitle: String {
        if tunnel.isBusy { return "Подождите…" }
        return tunnel.isConnected ? "Отключиться" : "Подключиться"
    }
}

// MARK: - Анимированный орб подключения

private struct ConnectionOrb: View {
    let connected: Bool
    let busy: Bool

    @State private var pulse = false
    @State private var spin = 0.0

    private var color: Color {
        if connected { return Theme.statusOn }
        if busy { return Theme.statusBusy }
        return Theme.statusOff
    }

    var body: some View {
        ZStack {
            // Внешнее свечение
            Circle()
                .fill(color.opacity(connected ? 0.30 : 0.12))
                .frame(width: 230, height: 230)
                .blur(radius: 40)
                .scaleEffect(pulse ? 1.08 : 0.94)

            // Вращающееся градиент-кольцо (заметно при подключении)
            Circle()
                .trim(from: 0, to: busy ? 0.7 : 1)
                .stroke(connected || busy ? AnyShapeStyle(Theme.aurora)
                                          : AnyShapeStyle(color.opacity(0.35)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 188, height: 188)
                .rotationEffect(.degrees(busy ? spin : 0))

            // Стеклянная сердцевина
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 150, height: 150)
                .overlay(Circle().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                .shadow(color: color.opacity(0.5), radius: connected ? 24 : 8)

            Image(systemName: connected ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 50, weight: .medium))
                .foregroundStyle(connected ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(color))
        }
        .frame(height: 240)
        .onAppear { startAnimations() }
        .onChange(of: busy) { _ in startAnimations() }
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            pulse = true
        }
        if busy {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                spin = 360
            }
        } else {
            spin = 0
        }
    }
}
