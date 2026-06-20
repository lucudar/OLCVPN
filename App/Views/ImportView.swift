import SwiftUI
import UIKit

struct ImportView: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var uri: String = ""
    @State private var clientID: String = ""
    @State private var errorText: String?
    @State private var showingScanner = false

    private var rowBg: some View { Color.white.opacity(0.05) }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                Form {
                    Section {
                        TextField("olcrtc://...", text: $uri, axis: .vertical)
                            .lineLimit(2...5)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.system(.body, design: .monospaced))
                        Button {
                            if let s = UIPasteboard.general.string { uri = s }
                        } label: {
                            Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                                .foregroundStyle(Theme.teal)
                        }
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Сканировать QR", systemImage: "qrcode.viewfinder")
                                .foregroundStyle(Theme.teal)
                        }
                    } header: { SectionTitle(text: "Ссылка olcrtc://", systemImage: "link") }
                    .listRowBackground(rowBg)

                    Section {
                        TextField("Client ID (необязательно)", text: $clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    } header: { SectionTitle(text: "Параметры") }
                    .listRowBackground(rowBg)

                    if let errorText {
                        Section {
                            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.statusError)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .listRowBackground(rowBg)
                    }

                    Section {
                        Text("Формат:\nolcrtc://<carrier>?<transport>@<roomID>#<key64hex>$<имя>")
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(rowBg)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Импорт профиля")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") { add() }
                        .disabled(uri.isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingScanner) {
                NavigationStack {
                    QRScannerView { value in
                        uri = value
                        showingScanner = false
                    } onError: { msg in
                        errorText = msg
                        showingScanner = false
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Сканирование QR")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") { showingScanner = false }
                        }
                    }
                }
            }
        }
    }

    private func add() {
        do {
            var (profile, key) = try OLCUri.parse(uri)
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
