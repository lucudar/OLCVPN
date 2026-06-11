import SwiftUI

/// Экран настроек: состояние, редактор активного профиля, глобальные настройки, диагностика.
struct SettingsView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var tunnel: TunnelManager

    @State private var dns: String = ""
    @State private var portText: String = ""
    @State private var debug: Bool = true

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
                    LabeledContent("Профиль", value: store.activeProfile?.name ?? "не выбран")
                }

                if let p = store.activeProfile {
                    Section("Активный профиль") {
                        NavigationLink {
                            ProfileEditView(profile: p)
                        } label: {
                            LabeledContent("Редактировать", value: p.name)
                        }
                        LabeledContent("Транспорт", value: p.transport.title)
                        LabeledContent("DNS", value: p.dns)
                        LabeledContent("SOCKS-порт", value: String(p.socksPort))
                    }
                }

                Section {
                    TextField("DNS по умолчанию", text: $dns)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                    TextField("SOCKS-порт по умолчанию", text: $portText)
                        .keyboardType(.numberPad)
                    Toggle("Подробные логи", isOn: $debug)
                } header: {
                    Text("Настройки по умолчанию")
                } footer: {
                    Text("DNS и порт применяются к новым импортированным профилям. Логи влияют на ядро при следующем подключении.")
                }

                Section("Диагностика") {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Журнал диагностики", systemImage: "doc.text.magnifyingglass")
                    }
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: appVersion)
                    LabeledContent("Ядро", value: "olcRTC + hev-socks5-tunnel")
                }
            }
            .navigationTitle("Настройки")
            .onAppear(perform: loadSettings)
            .onChange(of: dns) { _ in saveSettings() }
            .onChange(of: portText) { _ in saveSettings() }
            .onChange(of: debug) { _ in saveSettings() }
        }
    }

    private func loadSettings() {
        dns = store.settings.defaultDNS
        portText = String(store.settings.defaultSocksPort)
        debug = store.settings.debugLogging
    }

    private func saveSettings() {
        var s = store.settings
        s.defaultDNS = dns.trimmingCharacters(in: .whitespaces)
        if let port = Int(portText), port > 0 { s.defaultSocksPort = port }
        s.debugLogging = debug
        guard s != store.settings else { return }
        store.updateSettings(s)
    }
}
