import SwiftUI
import UIKit

/// Просмотр и экспорт журнала диагностики.
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
                        DiagLog.clear(); reload()
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

    private func reload() { text = DiagLog.read() }
}

/// Обёртка UIActivityViewController для экспорта/шаринга.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
