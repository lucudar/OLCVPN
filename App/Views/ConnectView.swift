import SwiftUI
import NetworkExtension

struct ConnectView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var tunnel: TunnelManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                statusCircle
                Text(tunnel.statusText)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if let p = store.activeProfile {
                    VStack(spacing: 4) {
                        Text(p.name).font(.title3).bold()
                        Text("\(p.carrier.rawValue) · \(p.transport.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Нет активного профиля").foregroundStyle(.secondary)
                }

                Spacer()
                connectButton
                if let err = tunnel.lastError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationTitle("OLCVPN")
        }
    }

    private var statusCircle: some View {
        Circle()
            .fill(tunnel.isConnected ? Color.green : Color.gray.opacity(0.3))
            .frame(width: 120, height: 120)
            .overlay(Image(systemName: tunnel.isConnected ? "lock.fill" : "lock.open")
                .font(.system(size: 44)).foregroundStyle(.white))
            .shadow(radius: tunnel.isConnected ? 12 : 0)
            .animation(.easeInOut, value: tunnel.isConnected)
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
            Text(tunnel.isConnected ? "Отключиться" : "Подключиться")
                .font(.headline).frame(maxWidth: .infinity).padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(tunnel.isConnected ? .red : .accentColor)
        .disabled(store.activeProfile == nil || tunnel.isBusy)
    }
}
