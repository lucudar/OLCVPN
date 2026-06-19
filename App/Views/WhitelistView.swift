import SwiftUI

/// Редактор белого списка профиля: домены/IP/CIDR, которые идут напрямую мимо VPN.
/// Использует @Binding — изменения идут в draft ProfileEditView, сохранение при «Готово» родителя.
struct WhitelistView: View {
    @Binding var whitelist: [String]
    @State private var newEntry: String = ""

    var body: some View {
        ZStack {
            AuroraBackground()

            List {
                Section {
                    HStack(spacing: 10) {
                        TextField("example.com или 10.0.0.0/8", text: $newEntry)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .submitLabel(.done)
                            .onSubmit(addEntry)
                            .foregroundStyle(Theme.textPrimary)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                addEntry()
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(trimmedNew.isEmpty ? Theme.textSecondary : Theme.teal)
                        }
                        .disabled(trimmedNew.isEmpty)
                    }
                } header: {
                    SectionTitle(text: "Добавить запись", systemImage: "plus")
                } footer: {
                    Text("Домены, IP-адреса и CIDR-диапазоны. Записи из списка идут напрямую, минуя VPN-туннель.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(rowBg)

                if !whitelist.isEmpty {
                    Section {
                        ForEach(whitelist.indices, id: \.self) { idx in
                            HStack {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.caption)
                                    .foregroundStyle(Theme.teal.opacity(0.7))
                                Text(whitelist[idx])
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                            }
                        }
                        .onDelete { offsets in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                whitelist.remove(atOffsets: offsets)
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    } header: {
                        SectionTitle(text: "Записи (\(whitelist.count))")
                    }
                    .listRowBackground(rowBg)
                } else {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield")
                                .font(.title3)
                                .foregroundStyle(Theme.textSecondary)
                            VStack(alignment: .leading) {
                                Text("Список пуст")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Весь трафик идёт через VPN")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(rowBg)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: whitelist)
        }
        .navigationTitle("Белый список")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rowBg: some View { Color.white.opacity(0.05) }

    private var trimmedNew: String {
        newEntry.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func addEntry() {
        let entry = trimmedNew
        guard !entry.isEmpty else { return }
        guard !whitelist.contains(entry) else {
            newEntry = ""
            return
        }
        whitelist.append(entry)
        newEntry = ""
    }
}
