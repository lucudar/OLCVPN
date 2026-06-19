import SwiftUI
import UIKit

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
                .tint(Theme.teal)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    init() {
        // Тёмный полупрозрачный таб-бар под стиль Aurora Glass.
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(Theme.bgDeep.opacity(0.6))
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        // Прозрачные навигационные бары, чтобы был виден aurora-фон.
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some View {
        TabView {
            ConnectView()
                .tabItem { Label("Подключение", systemImage: "bolt.horizontal.circle.fill") }
            ProfilesView()
                .tabItem { Label("Профили", systemImage: "square.stack.3d.up.fill") }
            ProxyTestView()
                .tabItem { Label("Прокси", systemImage: "network") }
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
        }
    }
}
