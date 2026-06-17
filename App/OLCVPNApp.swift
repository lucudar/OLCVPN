import SwiftUI

@main
struct OLCVPNApp: App {
    @StateObject private var store = ConfigStore()
    @StateObject private var tunnel = TunnelManager()
    @StateObject private var proxy = ProxyManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(tunnel)
                .environmentObject(proxy)
                .task {
                    // Синхронизируем подробность логов с настройкой до первого log().
                    DiagLog.debugEnabled = store.settings.debugLogging
                    DiagLog.log("OLCVPN запущен")
                    await tunnel.prepare()
                }
                .onOpenURL { url in
                    // Импорт профиля по ссылке olcrtc://.
                    // НЕ проглатываем ошибку парсинга — логируем её, иначе
                    // пользователь не узнает, почему профиль не добавился.
                    DiagLog.log("Получен URL импорта: \(url.absoluteString)")
                    do {
                        let (profile, key) = try OLCUri.parse(url.absoluteString)
                        store.add(profile: profile, keyHex: key)
                        DiagLog.log("Профиль импортирован по ссылке: \(profile.name)")
                    } catch {
                        DiagLog.error("Не удалось разобрать ссылку импорта: \(error.localizedDescription)")
                    }
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            ConnectView()
                .tabItem { Label("Подключение", systemImage: "bolt.horizontal.circle") }
            ProfilesView()
                .tabItem { Label("Профили", systemImage: "list.bullet") }
            ProxyTestView()
                .tabItem { Label("Прокси", systemImage: "network") }
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}
