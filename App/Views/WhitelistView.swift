import SwiftUI

/// Редактор белого списка профиля: домены/IP/CIDR, которые идут напрямую мимо VPN.
/// Использует @Binding — изменения идут в draft ProfileEditView, сохранение при «Готово» родителя.
struct WhitelistView: View {
    @Binding var whitelist: [String]
    @State private var newEntry: String = ""

    private var rowBg: some View { Color.white.opacity(0.05) }

    var body: some View {
        ZStack {
            AuroraBackground()
            Form {
                Section {
                    HStack {
                        TextField("example.com или 10.0.0.0/8", text: $newEntry)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .submitLabel(.done)
                            .onSubmit(addEntry)
                        Button {
                            addEntry()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(trimmedNew.isEmpty ? Theme.textSecondary : Theme.teal)
                        }
                        .disabled(trimmedNew.isEmpty)
                    }
                } header: { SectionTitle(text: "Добавить запись", systemImage: "plus") } footer: {
                    Text("Поддерживаются домены (google.com), IP-адреса (1.2.3.4) и CIDR-диапазоны (192.168.0.0/16). Записи из списка идут напрямую, минуя VPN-туннель.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(rowBg)

                if !whitelist.isEmpty {
                    Section {
                        ForEach(whitelist.indices, id: \.self) { idx in
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.uturn.right")
                                    .font(.caption).foregroundStyle(Theme.green)
                                Text(whitelist[idx])
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        .onDelete { offsets in whitelist.remove(atOffsets: offsets) }
                    } header: { SectionTitle(text: "Записи (\(whitelist.count))") }
                    .listRowBackground(rowBg)
                } else {
                    Section {
                        Text("Список пуст — весь трафик идёт через VPN")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(rowBg)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Белый список")
        .navigationBarTitleDisplayMode(.inline)
    }

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
