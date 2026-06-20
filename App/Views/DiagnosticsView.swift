import SwiftUI
import Combine

struct DiagnosticsView: View {
    @EnvironmentObject var tunnel: TunnelManager
    @State private var lines: [String] = []
    @State private var loading = false
    @State private var autoRefresh = false
    @State private var reloadTask: Task<Void, Never>?

    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 12) {
                if autoRefresh {
                    Label("Авто-обновление включено", systemImage: "dot.radiowaves.up.forward")
                        .font(.caption).foregroundStyle(Theme.teal)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                LogView(lines: lines)
            }
            .padding(.horizontal, Theme.hPadding)
            .padding(.vertical, 8)
        }
        .navigationTitle("Диагностика")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { reload() } label: { Label("Обновить", systemImage: "arrow.clockwise") }
                    Toggle(isOn: $autoRefresh) {
                        Label("Авто-обновление", systemImage: "timer")
                    }
                    ShareLink(item: lines.joined(separator: "\n")) {
                        Label("Поделиться логом", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        DiagLog.clear()
                        UserDefaults.standard.removeObject(forKey: TunnelManager.extLogKey)
                        Task { _ = await tunnel.sendCommand("clearlog"); reload() }
                    } label: { Label("Очистить", systemImage: "trash") }
                } label: {
                    Image(systemName: loading ? "ellipsis" : "ellipsis.circle")
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(ticker) { _ in if autoRefresh { reload() } }
    }

    private func reload() {
        reloadTask?.cancel()
        reloadTask = Task { await reloadAsync() }
    }

    @MainActor
    private func reloadAsync() async {
        if Task.isCancelled { return }
        loading = true
        defer { loading = false }
        let live = await tunnel.fetchExtensionLog()
        if Task.isCancelled { return }
        if !live.isEmpty {
            UserDefaults.standard.set(live, forKey: TunnelManager.extLogKey)
        }
        var parts: [String] = []
        let app = DiagLog.read()
        if !app.isEmpty {
            parts.append("=== ПРИЛОЖЕНИЕ / App Group ===\n" + app)
        }
        if let ext = UserDefaults.standard.string(forKey: TunnelManager.extLogKey), !ext.isEmpty {
            parts.append("=== РАСШИРЕНИЕ (IPC) ===\n" + ext)
        }
        if Task.isCancelled { return }
        lines = parts.joined(separator: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
