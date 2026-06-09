# OLCVPN (iOS)

iOS VPN-клиент поверх ядра **olcRTC** (Go). Приложение поднимает системный VPN через
`NEPacketTunnelProvider`, а трафик заворачивает в локальный SOCKS5, который поднимает olcRTC.

```
iOS apps -> NEPacketTunnelProvider (TUN) -> hev-socks5-tunnel -> 127.0.0.1:10808 (olcRTC SOCKS5) -> WebRTC -> srv -> internet
```

## Сборка одной командой (на macOS)

Нужны: Xcode, Go 1.26+, git, Homebrew.

```bash
chmod +x build.sh
./build.sh /путь/к/olcrtc-master
open OLCVPN.xcodeproj
```

`build.sh` делает всё тяжёлое автоматически:
1. `gomobile bind -target=ios,iossimulator -o Frameworks/Olcrtc.xcframework ./mobile`
2. клонирует и собирает `hev-socks5-tunnel` в статическую библиотеку (Vendor/hev/)
3. `xcodegen generate` — генерирует `OLCVPN.xcodeproj`

После этого в Xcode: поставь свой **Team ID / bundle id**, подпиши своим сертификатом
и запусти на реальном iPhone (в симуляторе VPN-туннель не работает).

> Важно: gomobile префиксует экспорты именем фреймворка. Открой
> `Frameworks/Olcrtc.xcframework/.../Headers/Olcrtc.objc.h` и если префикс не `Olcrtc`,
> поправь ОДНО место — `OLCTunnel/OLCCore.swift`.

## Что уже готово в коде (без заглушек)

- Полный SwiftUI-UI: подключение, профили, импорт, настройки.
- `TunnelManager` поверх `NETunnelProviderManager` (создание профиля, connect/disconnect, статус).
- `PacketTunnelProvider`: старт ядра olcRTC + сетевые настройки туннеля.
- `Tun2Socks`: **полная** интеграция hev-socks5-tunnel — YAML-конфиг, получение utun fd,
  запуск в фоновом потоке, остановка.
- `OLCCore`: тонкая обёртка над gomobile-символами (одно место для правки).
- `OLCUri`: парсер `olcrtc://` + unit-тесты.
- App Group + Keychain для обмена конфигом app <-> extension.
- entitlements, Info.plist, bridging header, `project.yml`, `build.sh`.

## Почему бинарники не в архиве

Скомпилированный `Olcrtc.xcframework` и `libhev-socks5-tunnel.a` — это iOS-бинарники,
которые собираются ТОЛЬКО на macOS с Xcode (cross-compile под arm64-apple-ios).
Их нельзя собрать на Linux. Поэтому их собирает `build.sh` на твоём Mac.

## Параметры olcRTC

- carrier: `jitsi` | `telemost` | `wbstream`
- roomID / clientID / keyHex (64 hex)
- transport: `vp8channel` (по умолчанию) | `datachannel`

## Риски

- **Память NE (~50 МБ).** Go-рантайм + WebRTC + tun2socks. При проблемах бери `datachannel`.
- **App Store** почти наверняка отклонит это — для личной установки по сертификату это ок.
