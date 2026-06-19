import SwiftUI
import UIKit

/// Переиспользуемый просмотрщик логов в стиле Aurora Glass.
///
/// Возможности:
///   - поиск по подстроке;
///   - фильтр-чипы по категории (Все / Ошибки / Core / Приложение);
///   - авто-таил (автоскролл к последней строке при появлении новых);
///   - цветная подсветка по категории, моноширинный выделяемый текст;
///   - копировать всё (видимое) и поделиться.
///
/// Используется и в «Диагностике», и в «Прокси-режиме».
struct LogView: View {
    /// Исходные строки лога (как есть). Парсинг и фильтрация — внутри.
    let lines: [String]

    @State private var search = ""
    @State private var filter: LogLine.Filter = .all
    @State private var autoTail = true
    @State private var showShare = false
    @State private var copied = false

    private var parsed: [LogLine] { .from(text: lines.joined(separator: "\n")) }

    private var filtered: [LogLine] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return parsed.filter { line in
            guard filter.matches(line) else { return false }
            guard !q.isEmpty else { return true }
            return line.raw.lowercased().contains(q)
        }
    }

    private var visibleText: String { filtered.map(\.raw).joined(separator: "\n") }

    var body: some View {
        VStack(spacing: 12) {
            controls
            logBody
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [visibleText.isEmpty ? "(пусто)" : visibleText])
        }
    }

    // MARK: - Контролы

    private var controls: some View {
        VStack(spacing: 10) {
            // Поиск
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Поиск по логу", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .foregroundStyle(Theme.textPrimary)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))

            // Фильтры + действия
            HStack(spacing: 8) {
                ForEach(LogLine.Filter.allCases) { f in
                    let on = filter == f
                    Button { filter = f } label: {
                        Text(f.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(on ? .white : Theme.textSecondary)
                            .padding(.vertical, 6).padding(.horizontal, 12)
                            .background(on ? AnyShapeStyle(Theme.auroraSoft) : AnyShapeStyle(Color.white.opacity(0.06)),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack(spacing: 14) {
                Toggle(isOn: $autoTail) {
                    Label("Авто-таил", systemImage: "arrow.down.to.line")
                        .font(.caption.weight(.medium))
                }
                .toggleStyle(.button)
                .tint(Theme.teal)
                .foregroundStyle(autoTail ? Theme.teal : Theme.textSecondary)

                Spacer()

                Button {
                    UIPasteboard.general.string = visibleText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? "Скопировано" : "Копировать",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Theme.textSecondary)

                Button { showShare = true } label: {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Тело лога

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if filtered.isEmpty {
                        Text(search.isEmpty ? "Журнал пуст" : "Ничего не найдено")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(filtered) { row($0) }
                        Color.clear.frame(height: 1).id("BOTTOM")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(Color.black.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1))
            .onChange(of: lines.count) { _ in
                guard autoTail, !filtered.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
            }
            .onAppear {
                if autoTail, !filtered.isEmpty { proxy.scrollTo("BOTTOM", anchor: .bottom) }
            }
        }
    }

    private func row(_ line: LogLine) -> some View {
        Group {
            if line.category == .section {
                Text(line.message)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.green)
                    .padding(.top, 6)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    if let t = line.time {
                        Text(t)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    }
                    if let tag = line.tag, tag != "app", tag != "error" {
                        Text(tag)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(line.category.color)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(line.category.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(line.message)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(line.category.color)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Обёртка UIActivityViewController для экспорта/шаринга лога.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
