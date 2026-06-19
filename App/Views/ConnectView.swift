import SwiftUI
import NetworkExtension

struct ConnectView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var tunnel: TunnelManager

    @State private var cardAppeared = false
    @State private var orbScale: CGFloat = 0.85

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        Spacer(minLength: 0)

                        ConnectionOrb(connected: tunnel.isConnected, busy: tunnel.isBusy)
                            .scaleEffect(orbScale)
                            .onAppear {
                                withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                                    orbScale = 1
                                }
                            }

                        VStack(spacing: 6) {
                            Text(tunnel.statusText)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(statusColor)
                                .contentTransition(.opacity)
                                .animation(.easeInOut(duration: 0.3), value: tunnel.statusText)
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .contentTransition(.opacity)
                                .animation(.easeInOut(duration: 0.3), value: subtitle)
                        }

                        profileCard
                            .opacity(cardAppeared ? 1 : 0)
                            .offset(y: cardAppeared ? 0 : 20)
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                                    cardAppeared = true
                                }
                            }

                        if let err = tunnel.lastError {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(Theme.statusError)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard(padding: 12)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        connectButton
                            .padding(.top, 4)

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
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
            .id(p.id)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
                withAnimation(.easeInOut(duration: 0.3)) {
                    tunnel.disconnect()
                }
            } else {
                guard let cfg = store.activeTunnelConfig() else {
                    tunnel.lastError = "Выбери профиль и проверь ключ"
                    return
                }
                store.publishActiveToTunnel()
                withAnimation(.easeInOut(duration: 0.3)) {
                    tunnel.connect(providerConfig: cfg)
                }
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
        .animation(.easeInOut(duration: 0.2), value: tunnel.isConnected)
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
    @State private var ringPulse = false

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

            // Второе кольцо-пульс (при подключении)
            if connected || busy {
                Circle()
                    .stroke(color.opacity(ringPulse ? 0.0 : 0.35), lineWidth: 2)
                    .frame(width: 200, height: 200)
                    .scaleEffect(ringPulse ? 1.3 : 1.0)
                    .opacity(ringPulse ? 0 : 1)
            }

            // Вращающееся градиент-кольцо
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
                .contentTransition(.opacity)
        }
        .frame(height: 240)
        .onAppear { startAnimations() }
        .onChange(of: busy) { _ in startAnimations() }
        .onChange(of: connected) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                // Trigger re-render of color/glow
            }
            startAnimations()
        }
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            pulse = true
        }
        withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
            ringPulse = true
        }
        if busy {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                spin = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                spin = 0
            }
        }
    }
}
