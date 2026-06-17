import SwiftUI
import UIKit

/// Просмотр и экспорт журнала диагностики.
///
/// Собирает два источника:
///   1) DiagLog (лог приложения + расширения через App Group, если доступен);
///   2) лог расширения живьём по IPC (работает ДАЖЕ без App Group), пока туннель подключён.
struct DiagnosticsView: View {
    @EnvironmentObject var tunnel: TunnelManager
    @State private var text: String = ""
    @State private var showShare = false
    @State private var loading = false
    /// Храним текущую перезагрузку, чтобы отменять её при повторном onAppear
    /// (иначе плодятся параллельные Task, гоняющие друг друга за text/loading).
    @State private var reloadTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Журнал пуст" : text)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("Диагностика")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { reload() } label: { Label("Обновить", systemImage: "arrow.clockwise") }
                    Button { showShare = true } label: { Label("Экспорт", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        DiagLog.clear()
                        UserDefaults.standard.removeObject(forKey: TunnelManager.extLogKey)
                        Task { _ = await tunnel.sendCommand("clearlog") ; reload() }
                    } label: { Label("Очистить", systemImage: "trash") }
                } label: {
                    Image(systemName: loading ? "ellipsis" : "ellipsis.circle")
                }
            }
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [text.isEmpty ? "(пусто)" : text])
        }
    }

    private func reload() {
        // Отменяем предыдущую перезагрузку, если она ещё бежит — onAppear
        // может срабатывать часто (переходы по табам), и без отменки
        // накапливались бы параллельные Task.
        reloadTask?.cancel()
        reloadTask = Task { await reloadAsync() }
    }

    @MainActor
    private func reloadAsync() async {
        // Если эту перезагрузку уже отменили (пришёл новый onAppear) — выходим,
        // не затирая text/loading более свежей задачей.
        if Task.isCancelled { return }
        loading = true
        defer { loading = false }
        // Живой IPC-запрос лога расширения (работает, пока сессия connecting/connected).
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
        text = parts.joined(separator: "\n\n")
    }
}

/// Обёртка UIActivityViewController для экспорта/шаринга.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
