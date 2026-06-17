import SwiftUI
import UIKit

/// Редактор профиля: редактирование полей, проверка связи, экспорт olcrtc://.
struct ProfileEditView: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Profile
    @State private var fpsText: String
    @State private var batchText: String
    @State private var pingResult: String?
    @State private var pinging = false
    @State private var copied = false

    init(profile: Profile) {
        _draft = State(initialValue: profile)
        _fpsText = State(initialValue: profile.transportParams[OLCTransportParam.vp8FPS] ?? "")
        _batchText = State(initialValue: profile.transportParams[OLCTransportParam.vp8Batch] ?? "")
    }

    var body: some View {
        Form {
            Section("Профиль") {
                TextField("Имя", text: $draft.name)
                Picker("Carrier", selection: $draft.carrier) {
                    ForEach(OLCCarrier.allCases) { c in Text(c.rawValue).tag(c) }
                }
                Picker("Транспорт", selection: $draft.transport) {
                    ForEach(OLCTransport.allCases) { t in Text(t.title).tag(t) }
                }
                TextField("Room ID", text: $draft.roomID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                TextField("Client ID", text: $draft.clientID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled(true)
            }

            Section("Сеть") {
                TextField("DNS (например 8.8.8.8:53)", text: $draft.dns)
                    .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                Stepper("SOCKS-порт: \(draft.socksPort)", value: $draft.socksPort, in: 1024...65535)
            }

            Section {
                NavigationLink {
                    WhitelistView(whitelist: $draft.whitelist)
                } label: {
                    HStack {
                        Label("Белый список", systemImage: "arrow.triangle.branch")
                        Spacer()
                        Text(draft.whitelist.isEmpty
                             ? "выкл"
                             : "\(draft.whitelist.count) зап.")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Маршрутизация")
            } footer: {
                Text("Домены и IP из белого списка идут напрямую, минуя VPN-туннель.")
            }

            if draft.transport == .vp8channel {
                Section("VP8") {
                    TextField("FPS", text: $fpsText).keyboardType(.numberPad)
                    TextField("Batch size", text: $batchText).keyboardType(.numberPad)
                }
            }

            Section("Проверка связи") {
                Button {
                    Task { await runPing() }
                } label: {
                    HStack {
                        Text("Проверить связь (ping)")
                        Spacer()
                        if pinging {
                            ProgressView()
                        } else if let pingResult {
                            Text(pingResult).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(pinging)
            }

            Section("Экспорт") {
                Button {
                    copyLink()
                } label: {
                    Label(copied ? "Скопировано" : "Скопировать olcrtc://",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            }
        }
        .navigationTitle("Редактор профиля")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { save() }
            }
        }
    }

    private func composed() -> Profile {
        var p = draft
        var params = p.transportParams
        let fps = fpsText.trimmingCharacters(in: .whitespaces)
        let batch = batchText.trimmingCharacters(in: .whitespaces)
        if p.transport == .vp8channel {
            params[OLCTransportParam.vp8FPS] = fps.isEmpty ? nil : fps
            params[OLCTransportParam.vp8Batch] = batch.isEmpty ? nil : batch
        }
        p.transportParams = params
        return p
    }

    private func save() {
        let p = composed()
        store.update(profile: p, keyHex: nil)
        DiagLog.log("Профиль обновлён: \(p.name)")
        dismiss()
    }

    private func runPing() async {
        let p = composed()
        guard let key = store.keyHex(for: p) else {
            pingResult = "нет ключа"
            DiagLog.error("Ping: у профиля '\(p.name)' нет ключа")
            return
        }
        pinging = true
        pingResult = nil
        DiagLog.debug("Ping старт: \(p.name) carrier=\(p.carrier.rawValue) room=\(p.roomID)")
        let ms = await PingService.ping(profile: p, keyHex: key)
        pinging = false
        if let ms {
            pingResult = "\(ms) мс"
            DiagLog.log("Ping \(p.name): \(ms) мс")
        } else {
            pingResult = "недоступно"
            DiagLog.error("Ping \(p.name): ошибка/таймаут")
        }
    }

    private func copyLink() {
        let p = composed()
        guard let key = store.keyHex(for: p) else {
            DiagLog.error("Экспорт: у профиля '\(p.name)' нет ключа — собрать olcrtc:// нельзя")
            return
        }
        UIPasteboard.general.string = OLCUri.serialize(profile: p, keyHex: key)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
