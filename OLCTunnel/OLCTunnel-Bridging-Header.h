#ifndef OLCTunnel_Bridging_Header_h
#define OLCTunnel_Bridging_Header_h

#include <stdint.h>

// hev-socks5-tunnel C API.
// Прототипы из hev-socks5-tunnel.h (вендорится build.sh в Vendor/hev/).

/**
 * Запускает туннель из YAML-конфига в памяти. Блокирующий.
 * @param config_str указатель на YAML.
 * @param config_len длина конфига.
 * @param tun_fd файловый дескриптор utun.
 * @return 0 при штатном завершении.
 */
int hev_socks5_tunnel_main_from_str(const uint8_t *config_str,
                                    unsigned int config_len,
                                    int tun_fd);

/** Останавливает работающий туннель. */
void hev_socks5_tunnel_quit(void);

#endif /* OLCTunnel_Bridging_Header_h */
