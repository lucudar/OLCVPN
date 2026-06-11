import SwiftUI

/// Экран настроек: сведения о приложении и активном профиле.
struct SettingsView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var tunnel: TunnelManager

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Состояние") {
                    LabeledContent("VPN", value: tunnel.statusText)
                    if let p = store.activeProfile {
                        LabeledContent("Профиль", value: p.name)
                    } else {
                        LabeledContent("Профиль", value: "не выбран")
                    }
                }

                if let p = store.activeProfile {
                    Section("Активный профиль") {
                        LabeledContent("Carrier", value: p.carrier.rawValue)
                        LabeledContent("Транспорт", value: p.transport.title)
                        LabeledContent("Room ID", value: p.roomID)
                        if !p.clientID.isEmpty {
                            LabeledContent("Client ID", value: p.clientID)
                        }
                        LabeledContent("DNS", value: p.dns)
                        LabeledContent("SOCKS-порт", value: String(p.socksPort))
                    }
                }

                Section("Сеть") {
                    LabeledContent("DNS по умолчанию", value: OLC.defaultDNS)
                    LabeledContent("SOCKS-порт ядра", value: String(OLC.socksPort))
                    LabeledContent("Адрес туннеля", value: OLC.tunnelIP)
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: appVersion)
                    LabeledContent("Ядро", value: "olcRTC + hev-socks5-tunnel")
                }
            }
            .navigationTitle("Настройки")
        }
    }
}