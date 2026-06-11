import SwiftUI
import UIKit

/// Импорт профиля: вставка ссылки olcrtc:// и (опционально) clientID.
struct ImportView: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var uri: String = ""
    @State private var clientID: String = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Ссылка olcrtc://") {
                    TextField("olcrtc://...", text: $uri, axis: .vertical)
                        .lineLimit(2...5)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        if let s = UIPasteboard.general.string { uri = s }
                    } label: {
                        Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                    }
                }

                Section("Параметры") {
                    TextField("Client ID (необязательно)", text: $clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Text("Формат: olcrtc://<carrier>?<transport>@<roomID>#<key64hex>$<имя>")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Импорт профиля")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") { add() }
                        .disabled(uri.isEmpty)
                }
            }
        }
    }

    private func add() {
        do {
            var (profile, key) = try OLCUri.parse(uri)
            // Применяем глобальные настройки по умолчанию.
            profile.dns = store.settings.defaultDNS
            profile.socksPort = store.settings.defaultSocksPort
            let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                profile.clientID = trimmed
            }
            store.add(profile: profile, keyHex: key)
            DiagLog.log("Импорт профиля: \(profile.name)")
            dismiss()
        } catch {
            errorText = Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let e = error as? OLCUri.ParseError else {
            return "Не удалось разобрать ссылку"
        }
        switch e {
        case .missingScheme:    return "Ссылка должна начинаться с olcrtc://"
        case .missingAuth:      return "Не указан carrier (jitsi/telemost/wbstream)"
        case .missingTransport: return "Не указан транспорт"
        case .missingRoom:      return "Не указан roomID (после @)"
        case .missingKey:       return "Не указан ключ (после #)"
        case .invalidKey:       return "Ключ должен быть 64 hex-символа"
        case .unknownCarrier(let c):   return "Неизвестный carrier: \(c)"
        case .unknownTransport(let t): return "Неизвестный транспорт: \(t)"
        }
    }
}
