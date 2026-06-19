import SwiftUI

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
            ZStack {
                AuroraBackground()
                Form {
                    Section {
                        statusRow("VPN", tunnel.statusText,
                                  color: tunnel.isConnected ? Theme.statusOn : Theme.textSecondary)
                        statusRow("Профиль", store.activeProfile?.name ?? "не выбран", color: Theme.textPrimary)
                    } header: { sectionHeader("Состояние") }
                    .listRowBackground(rowBg)

                    if let p = store.activeProfile {
                        Section {
                            NavigationLink {
                                ProfileEditView(profile: p)
                            } label: {
                                Label { Text("Редактировать «\(p.name)»") } icon: {
                                    Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.teal)
                                }
                            }
                            statusRow("Транспорт", p.transport.title, color: Theme.textSecondary)
                            statusRow("DNS", p.dns, color: Theme.textSecondary)
                            statusRow("SOCKS-порт", String(p.socksPort), color: Theme.textSecondary)
                        } header: { sectionHeader("Активный профиль") }
                        .listRowBackground(rowBg)
                    }

                    Section {
                        TextField("DNS по умолчанию", text: $dns)
                            .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                        TextField("SOCKS-порт по умолчанию", text: $portText)
                            .keyboardType(.numberPad)
                        Toggle("Подробные логи", isOn: $debug).tint(Theme.teal)
                    } header: { sectionHeader("Настройки по умолчанию") } footer: {
                        Text("DNS и порт применяются к новым импортированным профилям. Логи влияют на ядро при следующем подключении.")
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(rowBg)

                    Section {
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            Label { Text("Журнал диагностики") } icon: {
                                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(Theme.teal)
                            }
                        }
                    } header: { sectionHeader("Диагностика") }
                    .listRowBackground(rowBg)

                    Section {
                        statusRow("Версия", appVersion, color: Theme.textSecondary)
                        statusRow("Ядро", "olcRTC + hev-socks5-tunnel", color: Theme.textSecondary)
                    } header: { sectionHeader("О приложении") }
                    .listRowBackground(rowBg)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Настройки")
            .onAppear(perform: loadSettings)
            .onChange(of: dns) { _ in saveSettings() }
            .onChange(of: portText) { _ in saveSettings() }
            .onChange(of: debug) { _ in saveSettings() }
        }
    }

    private var rowBg: some View { Color.white.opacity(0.05) }

    private func sectionHeader(_ t: String) -> some View {
        SectionTitle(text: t)
    }

    private func statusRow(_ title: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
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
