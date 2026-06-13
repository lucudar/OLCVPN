import SwiftUI

/// Экран прокси-режима: запускает ядро в приложении и показывает результат
/// проверки связи + полный лог (один процесс, App Group не нужен).
struct ProxyTestView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var proxy: ProxyManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let p = store.activeProfile {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.title3).bold()
                            Text("\(p.carrier.rawValue) · \(p.transport.rawValue) · \(p.roomID)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Нет активного профиля").foregroundStyle(.secondary)
                    }

                    Text(proxy.status)
                        .font(.headline)
                        .foregroundStyle(proxy.running ? Color.green : Color.secondary)

                    if let tr = proxy.testResult {
                        Text(tr)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let err = proxy.lastError {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }

                    HStack {
                        Button(proxy.running ? "Остановить" : "Запустить ядро (прокси)") {
                            if proxy.running { proxy.stop() } else { startProxy() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(proxy.running ? .red : .accentColor)
                        .disabled(store.activeProfile == nil || proxy.busy)

                        if proxy.running {
                            Button("Тест связи") { proxy.runTest() }
                                .buttonStyle(.bordered)
                        }
                    }

                    if !proxy.log.isEmpty {
                        Text("Лог").font(.headline)
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(proxy.log.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.85))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle("Прокси-режим")
        }
    }

    private func startProxy() {
        guard let p = store.activeProfile, let key = store.keyHex(for: p) else {
            proxy.lastError = "Выбери профиль и проверь ключ"
            return
        }
        proxy.start(profile: p, keyHex: key, debug: store.settings.debugLogging)
    }
}
