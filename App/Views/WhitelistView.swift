import SwiftUI

/// Редактор белого списка профиля: домены/IP/CIDR, которые идут напрямую мимо VPN.
/// Использует @Binding — изменения идут в draft ProfileEditView, сохранение при «Готово» родителя.
struct WhitelistView: View {
    @Binding var whitelist: [String]
    @State private var newEntry: String = ""

    var body: some View {
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
                    }
                    .disabled(trimmedNew.isEmpty)
                }
            } header: {
                Text("Добавить запись")
            } footer: {
                Text("Поддерживаются домены (google.com), IP-адреса (1.2.3.4) и CIDR-диапазоны (192.168.0.0/16). Записи из списка идут напрямую, минуя VPN-туннель.")
            }

            if !whitelist.isEmpty {
                Section("Записи (\(whitelist.count))") {
                    ForEach(whitelist.indices, id: \.self) { idx in
                        Text(whitelist[idx])
                            .font(.system(.body, design: .monospaced))
                    }
                    .onDelete { offsets in
                        whitelist.remove(atOffsets: offsets)
                    }
                }
            } else {
                Section {
                    Text("Список пуст — весь трафик идёт через VPN")
                        .foregroundStyle(.secondary)
                }
            }
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
