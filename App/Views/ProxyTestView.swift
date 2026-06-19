import SwiftUI

/// Экран прокси-режима: запускает ядро в приложении и показывает результат
/// проверки связи + полный лог (один процесс, App Group не нужен).
struct ProxyTestView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var proxy: ProxyManager

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                VStack(alignment: .leading, spacing: 14) {
                    profileHeader

                    HStack(spacing: 10) {
                        Circle().fill(proxy.running ? Theme.statusOn : Theme.statusOff)
                            .frame(width: 10, height: 10)
                        Text(proxy.status)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(proxy.running ? Theme.statusOn : Theme.textSecondary)
                        Spacer()
                    }
                    .glassCard(padding: 13)

                    if let tr = proxy.testResult {
                        Text(tr)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(padding: 13)
                    }

                    if let err = proxy.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Theme.statusError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(padding: 12)
                    }

                    HStack(spacing: 10) {
                        Button {
                            if proxy.running { proxy.stop() } else { startProxy() }
                        } label: {
                            HStack(spacing: 8) {
                                if proxy.busy { ProgressView().tint(.white) }
                                Image(systemName: proxy.running ? "stop.fill" : "play.fill")
                                Text(proxy.running ? "Остановить" : "Запустить ядро")
                            }
                        }
                        .buttonStyle(AuroraButtonStyle(
                            fill: proxy.running ? AnyShapeStyle(Theme.statusGradient(Theme.statusError))
                                                : AnyShapeStyle(Theme.aurora),
                            tint: proxy.running ? Theme.statusError : Theme.teal))
                        .disabled(store.activeProfile == nil || proxy.busy)

                        if proxy.running {
                            Button { proxy.runTest() } label: {
                                Label("Тест", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .buttonStyle(GlassButtonStyle())
                        }
                    }

                    if !proxy.log.isEmpty {
                        SectionTitle(text: "Лог ядра", systemImage: "terminal")
                            .padding(.top, 2)
                        LogView(lines: proxy.log)
                    } else {
                        Spacer()
                    }
                }
                .padding(16)
            }
            .navigationTitle("Прокси-режим")
        }
    }

    @ViewBuilder
    private var profileHeader: some View {
        if let p = store.activeProfile {
            HStack(spacing: 12) {
                Image(systemName: p.carrier.glyph).font(.title3)
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
            .glassCard(padding: 13)
        } else {
            Text("Нет активного профиля")
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(padding: 13)
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
