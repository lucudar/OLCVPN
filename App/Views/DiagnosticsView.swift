import SwiftUI
import UIKit

/// Просмотр и экспорт журнала диагностики.
///
/// Собирает два источника:
///   1) DiagLog (лог приложения + расширения через App Group, если доступен);
///   2) лог расширения, забранный по IPC и сохранённый в UserDefaults.standard
///      (работает ДАЖЕ без App Group).
struct DiagnosticsView: View {
    @State private var text: String = ""
    @State private var showShare = false

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
                        reload()
                    } label: { Label("Очистить", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [text.isEmpty ? "(пусто)" : text])
        }
    }

    private func reload() {
        var parts: [String] = []
        let app = DiagLog.read()
        if !app.isEmpty {
            parts.append("=== ПРИЛОЖЕНИЕ / App Group ===\n" + app)
        }
        if let ext = UserDefaults.standard.string(forKey: TunnelManager.extLogKey), !ext.isEmpty {
            parts.append("=== РАСШИРЕНИЕ (IPC) ===\n" + ext)
        }
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
