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
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .contentTransition(.opacity)
                                .animation(.easeInOut(duration: 0.3), value: subtitle)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)

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
                                .fixedSize(horizontal: false, vertical: true)
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
                    .padding(.horizontal, Theme.hPadding)
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
        if tunnel.isBusy { return "Устанавливаю соединение через WebRTC… можно отменить" }
        return store.activeProfile == nil ? "Добавь профиль во вкладке «Профили»" : "Готов к подключению"
    }

    @ViewBuilder
    private var profileCard: some View {
        if let p = store.activeProfile {
            HStack(spacing: 12) {
                Image(systemName: p.carrier.glyph)
                    .font(.title3)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1))
                VStack(alignment: .leading, spacing: 5) {
                    Text(p.name).font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        PillLabel(text: p.carrier.rawValue)
                        PillLabel(text: p.transport.title)
                    }
                }
                Spacer(minLength: 4)
            }
            .glassCard()
            .id(p.id)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            HStack {
                Image(systemName: "tray").foregroundStyle(Theme.textSecondary)
                Text("Нет активного профиля")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .glassCard()
        }
    }

    private var connectButton: some View {
        Button {
            // Подключено или идёт подключение — кнопка отключает/отменяет.
            if tunnel.isConnected || tunnel.isBusy {
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
                if tunnel.isBusy { ProgressView().tint(.black) }
                Image(systemName: buttonIcon)
                Text(buttonTitle)
            }
        }
        .buttonStyle(AuroraButtonStyle())
        .disabled(store.activeProfile == nil)
        .opacity(store.activeProfile == nil ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.2), value: tunnel.isConnected)
        .animation(.easeInOut(duration: 0.2), value: tunnel.isBusy)
    }

    private var buttonIcon: String {
        if tunnel.isBusy { return "xmark" }
        return tunnel.isConnected ? "power" : "bolt.fill"
    }

    private var buttonTitle: String {
        if tunnel.isBusy { return "Отменить" }
        return tunnel.isConnected ? "Отключиться" : "Подключиться"
    }
}

// MARK: - Минималистичный орб подключения

private struct ConnectionOrb: View {
    let connected: Bool
    let busy: Bool

    private var ringActive: Bool { connected || busy }

    var body: some View {
        ZStack {
            // Едва заметное свечение
            Circle()
                .fill(Color.white.opacity(connected ? 0.07 : 0.03))
                .frame(width: 230, height: 230)
                .blur(radius: 40)

            // Вращающаяся линия по рамке
            RotatingRing(size: 196,
                         lineWidth: 3,
                         active: ringActive,
                         progress: busy ? 0.16 : 0.28,
                         duration: busy ? 1.1 : 3.0)
                .opacity(ringActive ? 1 : 0.5)

            // Центральный диск
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 150, height: 150)
                .overlay(Circle().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: connected ? 22 : 10)

            Image(systemName: connected ? "lock.fill" : "lock.open")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(connected ? Theme.textPrimary : Theme.textSecondary)
                .contentTransition(.opacity)
        }
        .frame(height: 240)
    }
}
