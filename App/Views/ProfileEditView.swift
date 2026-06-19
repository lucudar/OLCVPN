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

    private var rowBg: some View { Color.white.opacity(0.05) }

    init(profile: Profile) {
        _draft = State(initialValue: profile)
        _fpsText = State(initialValue: profile.transportParams[OLCTransportParam.vp8FPS] ?? "")
        _batchText = State(initialValue: profile.transportParams[OLCTransportParam.vp8Batch] ?? "")
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            Form {
                Section {
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
                } header: { SectionTitle(text: "Профиль", systemImage: "person.crop.circle") }
                .listRowBackground(rowBg)

                Section {
                    TextField("DNS (например 8.8.8.8:53)", text: $draft.dns)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                    Stepper("SOCKS-порт: \(draft.socksPort)", value: $draft.socksPort, in: 1024...65535)
                } header: { SectionTitle(text: "Сеть", systemImage: "network") }
                .listRowBackground(rowBg)

                Section {
                    NavigationLink {
                        WhitelistView(whitelist: $draft.whitelist)
                    } label: {
                        HStack {
                            Label { Text("Белый список") } icon: {
                                Image(systemName: "arrow.triangle.branch").foregroundStyle(Theme.teal)
                            }
                            Spacer()
                            Text(draft.whitelist.isEmpty ? "выкл" : "\(draft.whitelist.count) зап.")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } header: { SectionTitle(text: "Маршрутизация") } footer: {
                    Text("Домены и IP из белого списка идут напрямую, минуя VPN-туннель.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(rowBg)

                if draft.transport == .vp8channel {
                    Section {
                        TextField("FPS", text: $fpsText).keyboardType(.numberPad)
                        TextField("Batch size", text: $batchText).keyboardType(.numberPad)
                    } header: { SectionTitle(text: "VP8") }
                    .listRowBackground(rowBg)
                }

                Section {
                    Button {
                        Task { await runPing() }
                    } label: {
                        HStack {
                            Label { Text("Проверить связь (ping)") } icon: {
                                Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(Theme.teal)
                            }
                            Spacer()
                            if pinging { ProgressView() }
                            else if let pingResult {
                                Text(pingResult).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .disabled(pinging)
                } header: { SectionTitle(text: "Проверка связи") }
                .listRowBackground(rowBg)

                Section {
                    Button {
                        copyLink()
                    } label: {
                        Label(copied ? "Скопировано" : "Скопировать olcrtc://",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied ? Theme.statusOn : Theme.teal)
                    }
                } header: { SectionTitle(text: "Экспорт") }
                .listRowBackground(rowBg)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Редактор профиля")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { save() }.fontWeight(.semibold)
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
        } else {
            // Транспорт сменили с VP8 — выкидываем vp8-параметры, иначе они
            // утекут в olcrtc://-ссылку и конфиг чужого транспорта.
            params[OLCTransportParam.vp8FPS] = nil
            params[OLCTransportParam.vp8Batch] = nil
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
