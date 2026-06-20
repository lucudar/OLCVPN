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

echo "==> [0/4] генерация иконки приложения (best-effort)"
# Иконка рисуется скриптом Scripts/make_icon.py (Pillow) в изолированном venv.
# Если python3/pillow недоступны — остаётся уже лежащая в репо icon-1024.png
# (не роняем сборку из-за иконки).
if command -v python3 >/dev/null 2>&1; then
  ICON_VENV="${TMPDIR:-/tmp}/olc-iconvenv"
  if python3 -m venv "$ICON_VENV" >/dev/null 2>&1 \
     && "$ICON_VENV/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1 \
     && "$ICON_VENV/bin/pip" install --quiet pillow >/dev/null 2>&1 \
     && "$ICON_VENV/bin/python" Scripts/make_icon.py; then
    echo "    → иконка сгенерирована"
  else
    echo "    → не удалось сгенерировать иконку, использую существующую icon-1024.png" >&2
  fi
else
  echo "    → python3 не найден, использую существующую icon-1024.png" >&2
fi

echo "==> [1/4] gomobile bind -> Olcrtc.xcframework"
command -v gomobile >/dev/null || {
  go install golang.org/x/mobile/cmd/gomobile@latest
  go install golang.org/x/mobile/cmd/gobind@latest
  gomobile init
}
export PATH="$PATH:$(go env GOPATH)/bin"
mkdir -p Frameworks

echo "==> [1b/4] патч olcRTC: DNS-over-TCP внутри туннеля (SOCKS5 UDP ASSOCIATE)"
# Встраиваем в исходники olcRTC поддержку UDP ASSOCIATE в локальном SOCKS5:
# DNS (порт 53) заворачивается в TCP внутри туннеля (DNS-over-TCP, RFC 7766),
# чтобы резолвинг переживал операторов, травящих plaintext UDP DNS.
python3 - "$OLCRTC_SRC" <<'PYEOF'
import os, sys

root = sys.argv[1]

udp_dns = r'''package client

import (
    "context"
    "encoding/binary"
    "fmt"
    "io"
    "net"
    "time"

    "github.com/openlibrecommunity/olcrtc/internal/logger"
    "github.com/xtaci/smux"
)

// handleConn replaces handleSocks5 as the per-connection entry point. It adds
// SOCKS5 UDP ASSOCIATE handling (used by hev-socks5-tunnel for DNS) on top of
// the existing TCP CONNECT tunnelling.
func (c *Client) handleConn(ctx context.Context, conn net.Conn) {
    defer func() { _ = conn.Close() }()

    if err := c.socks5Handshake(conn); err != nil {
        return
    }

    targetAddr, targetPort, cmd, err := c.socks5RequestEx(conn)
    if err != nil {
        return
    }

    if cmd == 3 {
        c.handleUDPAssociate(ctx, conn)
        return
    }

    sess, err := c.waitForSession(ctx, 60*time.Second)
    if err != nil {
        _, _ = conn.Write(replyHostUnreachable())
        return
    }
    c.tunnel(conn, sess, targetAddr, targetPort)
}

// socks5RequestEx parses a SOCKS5 request and also returns the command byte so
// the caller can dispatch UDP ASSOCIATE. It otherwise mirrors socks5Request.
func (c *Client) socks5RequestEx(conn net.Conn) (string, int, byte, error) {
    header := make([]byte, 4)
    if _, err := io.ReadFull(conn, header); err != nil {
        return "", 0, 0, fmt.Errorf("read socks5 request: %w", err)
    }
    cmd := header[1]
    addr, err := c.readSocks5Addr(conn, header[3])
    if err != nil {
        return "", 0, 0, err
    }
    portBuf := make([]byte, 2)
    if _, err := io.ReadFull(conn, portBuf); err != nil {
        return "", 0, 0, fmt.Errorf("read socks5 port: %w", err)
    }
    port := int(binary.BigEndian.Uint16(portBuf))
    return addr, port, cmd, nil
}

// handleUDPAssociate implements SOCKS5 UDP ASSOCIATE (RFC 1928). Only DNS
// (port 53) is relayed; each query is tunnelled as DNS-over-TCP (RFC 7766) so
// resolution survives carriers that poison plaintext UDP DNS.
func (c *Client) handleUDPAssociate(ctx context.Context, conn net.Conn) {
    relay, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
    if err != nil {
        logger.Warnf("udp associate: listen relay: %v", err)
        _, _ = conn.Write(replyHostUnreachable())
        return
    }
    defer func() { _ = relay.Close() }()

    bnd, ok := relay.LocalAddr().(*net.UDPAddr)
    if !ok {
        _, _ = conn.Write(replyHostUnreachable())
        return
    }
    reply := []byte{5, 0, 0, 1, 127, 0, 0, 1, byte(bnd.Port >> 8), byte(bnd.Port & 0xff)}
    if _, err := conn.Write(reply); err != nil {
        return
    }
    logger.Infof("udp associate up, relay=127.0.0.1:%d", bnd.Port)

    go func() {
        buf := make([]byte, 256)
        for {
            if _, err := conn.Read(buf); err != nil {
                _ = relay.Close()
                return
            }
        }
    }()
    go func() {
        <-ctx.Done()
        _ = relay.Close()
    }()

    rbuf := make([]byte, 64*1024)
    for {
        n, src, err := relay.ReadFromUDP(rbuf)
        if err != nil {
            return
        }
        pkt := make([]byte, n)
        copy(pkt, rbuf[:n])
        go c.handleUDPDatagram(ctx, relay, src, pkt)
    }
}

// handleUDPDatagram decodes one SOCKS5 UDP datagram, resolves DNS through the
// TCP tunnel and writes the reply back to the sender.
func (c *Client) handleUDPDatagram(ctx context.Context, relay *net.UDPConn, src *net.UDPAddr, pkt []byte) {
    if len(pkt) < 4 || pkt[2] != 0 {
        return
    }
    idx := 4
    var dstAddr string
    switch pkt[3] {
    case 1:
        if len(pkt) < idx+4 {
            return
        }
        dstAddr = net.IP(pkt[idx : idx+4]).String()
        idx += 4
    case 3:
        if len(pkt) < idx+1 {
            return
        }
        dlen := int(pkt[idx])
        idx++
        if len(pkt) < idx+dlen {
            return
        }
        dstAddr = string(pkt[idx : idx+dlen])
        idx += dlen
    case 4:
        if len(pkt) < idx+16 {
            return
        }
        dstAddr = net.IP(pkt[idx : idx+16]).String()
        idx += 16
    default:
        return
    }
    if len(pkt) < idx+2 {
        return
    }
    dstPort := int(binary.BigEndian.Uint16(pkt[idx : idx+2]))
    idx += 2
    header := pkt[:idx]
    payload := pkt[idx:]

    if dstPort != 53 {
        return
    }

    resp, err := c.dnsOverTCP(ctx, dstAddr, dstPort, payload)
    if err != nil {
        logger.Warnf("udp dns %s:%d failed: %v", dstAddr, dstPort, err)
        return
    }

    out := make([]byte, 0, len(header)+len(resp))
    out = append(out, header...)
    out = append(out, resp...)
    _, _ = relay.WriteToUDP(out, src)
}

// dnsOverTCP forwards a DNS query through the tunnel using DNS-over-TCP framing
// (2-byte length prefix, RFC 7766) and returns the raw DNS response.
func (c *Client) dnsOverTCP(ctx context.Context, addr string, port int, query []byte) ([]byte, error) {
    sess, err := c.waitForSession(ctx, 10*time.Second)
    if err != nil {
        return nil, err
    }
    stream, err := sess.OpenStream()
    if err != nil {
        return nil, fmt.Errorf("open dns stream: %w", err)
    }
    defer func() { _ = stream.Close() }()

    if err := c.sendConnectRequest(stream, addr, port); err != nil {
        return nil, fmt.Errorf("dns connect: %w", err)
    }

    framed := make([]byte, 2+len(query))
    binary.BigEndian.PutUint16(framed[:2], uint16(len(query)))
    copy(framed[2:], query)

    _ = stream.SetWriteDeadline(time.Now().Add(10 * time.Second))
    if _, err := stream.Write(framed); err != nil {
        return nil, fmt.Errorf("dns write: %w", err)
    }
    _ = stream.SetWriteDeadline(time.Time{})

    _ = stream.SetReadDeadline(time.Now().Add(10 * time.Second))
    lenBuf := make([]byte, 2)
    if _, err := io.ReadFull(stream, lenBuf); err != nil {
        return nil, fmt.Errorf("dns read len: %w", err)
    }
    resp := make([]byte, int(binary.BigEndian.Uint16(lenBuf)))
    if _, err := io.ReadFull(stream, resp); err != nil {
        return nil, fmt.Errorf("dns read body: %w", err)
    }
    _ = stream.SetReadDeadline(time.Time{})
    return resp, nil
}

// waitForSession blocks until a smux session is fully established or timeout.
func (c *Client) waitForSession(ctx context.Context, timeout time.Duration) (*smux.Session, error) {
    readyCtx, cancel := context.WithTimeout(ctx, timeout)
    defer cancel()
    for {
        c.sessMu.RLock()
        sess := c.session
        sid := c.sessionID
        c.sessMu.RUnlock()
        if sess != nil && !sess.IsClosed() && sid != "" {
            return sess, nil
        }
        select {
        case <-readyCtx.Done():
            return nil, fmt.Errorf("session not ready")
        case <-c.readyChannel():
        }
    }
}
'''

udp_path = os.path.join(root, "internal", "client", "udp_dns.go")
with open(udp_path, "w") as f:
    f.write(udp_dns)
print("    wrote " + udp_path)

cli_path = os.path.join(root, "internal", "client", "client.go")
with open(cli_path) as f:
    src = f.read()

needle = "c.handleSocks5(ctx, conn)"
if needle not in src:
    sys.exit("FATAL: dispatch needle not found in client.go — патч не применён")
src = src.replace(needle, "c.handleConn(ctx, conn)", 1)
with open(cli_path, "w") as f:
    f.write(src)
print("    patched dispatch in " + cli_path)
PYEOF

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
