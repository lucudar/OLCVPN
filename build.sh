#!/usr/bin/env bash
# Автоматическая подготовка проекта НА macOS (нужны Xcode, Go 1.26+, git, brew).
# Запуск:  ./build.sh /путь/к/olcrtc-master
set -euo pipefail

OLCRTC_SRC="${1:-}"
if [[ -z "$OLCRTC_SRC" || ! -d "$OLCRTC_SRC/mobile" ]]; then
  echo "usage: ./build.sh /path/to/olcrtc-master  (должна быть папка mobile/)" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> [1/4] gomobile bind -> Olcrtc.xcframework"
command -v gomobile >/dev/null || {
  go install golang.org/x/mobile/cmd/gomobile@latest
  go install golang.org/x/mobile/cmd/gobind@latest
  gomobile init
}
export PATH="$PATH:$(go env GOPATH)/bin"
mkdir -p Frameworks
( cd "$OLCRTC_SRC" && gomobile bind -target=ios,iossimulator \
    -o "$ROOT/Frameworks/Olcrtc.xcframework" ./mobile )
echo "    → сверь префикс символов в Frameworks/Olcrtc.xcframework/.../Headers/Olcrtc.objc.h с OLCCore.swift"

echo "==> [2/4] сборка hev-socks5-tunnel (static lib)"
mkdir -p Vendor
if [[ ! -d Vendor/hev-socks5-tunnel ]]; then
  git clone --recursive https://github.com/heiher/hev-socks5-tunnel Vendor/hev-socks5-tunnel
fi
( cd Vendor/hev-socks5-tunnel && make clean >/dev/null 2>&1 || true
  # Сборка под iOS arm64 (устройство). Для симулятора собери отдельно.
  make CC="$(xcrun --sdk iphoneos -f clang)" \
       CFLAGS="-arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=16.0" \
       static )
mkdir -p "$ROOT/Vendor/hev/lib" "$ROOT/Vendor/hev/include"

# hev-socks5-tunnel зависит от подмодулей hev-task-system, lwip и yaml,
# которые собираются в отдельные .a (third-part/*/bin/*.a).
# Линкеру нужны все эти символы, поэтому объединяем ВСЕ статические
# библиотеки в один архив libhev-socks5-tunnel.a.
HEV_LIBS=$(find Vendor/hev-socks5-tunnel -name '*.a')
echo "    → объединяю статические библиотеки в один архив:"
echo "$HEV_LIBS" | sed 's/^/        /'
libtool -static -o "$ROOT/Vendor/hev/lib/libhev-socks5-tunnel.a" $HEV_LIBS

# Заголовки hev-socks5-tunnel
cp Vendor/hev-socks5-tunnel/include/*.h "$ROOT/Vendor/hev/include/" 2>/dev/null || true

echo "==> [3/4] xcodegen generate"
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

echo "==> [4/4] готово"
echo "Открой OLCVPN.xcodeproj, поставь свой DEVELOPER_TEAM/bundle id, подпиши и запусти на iPhone."