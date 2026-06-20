import NetworkExtension

/// Основной класс расширения VPN-туннеля.
class PacketTunnelProvider: NEPacketTunnelProvider {
    private var tun2socks: Tun2Socks?

    /// В Network Extension действует жёсткий лимит памяти (~50 MB). Тяжёлые
    /// видео-транспорты olcRTC (vp8/sei/video) тянут кодеки и легко его пробивают,
    /// что приводит к убийству расширения системой. Поэтому в туннеле принудительно
    /// используем лёгкий `datachannel`. (Эксперименты с тяжёлыми транспортами —
    /// только вне extension.)
    private static let heavyTransports: Set<String> = ["vp8channel", "videochannel", "seichannel"]

    private static func memorySafeTransport(_ t: String) -> String {
        heavyTransports.contains(t.lowercased()