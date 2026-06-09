import SwiftUI

@main
struct OLCVPNApp: App {
    @StateObject private var store = ConfigStore()
    @StateObject private var tunnel = TunnelManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(tunnel)
                .task { await tunnel.prepare() }
                .onOpenURL { url in
                    // Импорт профиля по ссылке olcrtc://
                    if let (profile, key) = try? OLCUri.parse(url.absoluteString) {
                        store.add(profile: profile, keyHex: key)
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
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}
