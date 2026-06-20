import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var tunnel: TunnelManager

    @State private var dns: String = ""
    @State private var portText: String = ""
    @State private var debug: Bool = true
    @State private var autoReconnect: Bool = true
    @State private var alwaysOn: Bool = false
    @State private var pingText: String?
    @State private var pinging = false

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
                        Toggle("Авто-переподключение", isOn: $autoReconnect).toggleStyle(MonoToggleStyle())
                        Toggle("Всегда включён (Kill Switch)", isOn: $alwaysOn).toggleStyle(MonoToggleStyle())
                    } header: { sectionHeader("Сеть и подключение") } footer: {
                        Text("Авто-переподключение само поднимает туннель при обрыве (до 5 попыток). «Всегда включён» держит VPN активным через системный On-Demand и перехватывает трафик до подключения — отключается только вручную здесь или кнопкой на главном экране.")
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(rowBg)

                    Section {
                        TextField("DNS по умолчанию", text: $dns)
                            .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                        TextField("SOCKS-порт по умолчанию", text: $portText)
                            .keyboardType(.numberPad)
                        Toggle("Подробные логи", isOn: $debug).toggleStyle(MonoToggleStyle())
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
                        Button {
                            runPing()
                        } label: {
                            Label { Text(pinging ? "Проверяю…" : "Тест соединения") } icon: {
                                Image(systemName: "wave.3.right").foregroundStyle(Theme.teal)
                            }
                        }
                        .disabled(pinging || store.activeProfile == nil)
                        if let pingText {
                            statusRow("Результат теста", pingText, color: Theme.textSecondary)
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
            .onChange(of: autoReconnect) { _ in saveSettings() }
            .onChange(of: alwaysOn) { v in
                saveSettings()
                tunnel.setOnDemand(v)
            }
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
        autoReconnect = store.settings.autoReconnect
        alwaysOn = store.settings.alwaysOn
    }

    private func saveSettings() {
        var s = store.settings
        s.defaultDNS = dns.trimmingCharacters(in: .whitespaces)
        if let port = Int(portText), port > 0 { s.defaultSocksPort = port }
        s.debugLogging = debug
        s.autoReconnect = autoReconnect
        s.alwaysOn = alwaysOn
        guard s != store.settings else { return }
        store.updateSettings(s)
    }

    private func runPing() {
        guard let p = store.activeProfile, let key = store.keyHex(for: p) else {
            pingText = "Нет активного профиля"
            return
        }
        pinging = true
        pingText = nil
        Task {
            let ms = await PingService.ping(profile: p, keyHex: key)
            await MainActor.run {
                pinging = false
                if let ms { pingText = "\(ms) мс" } else { pingText = "Недоступно" }
            }
        }
    }
}
