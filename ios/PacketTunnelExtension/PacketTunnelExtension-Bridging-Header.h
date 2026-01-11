//
//  PacketTunnelExtension-Bridging-Header.h
//  PacketTunnelExtension
//
//  Bridge header for importing C functions from libclashcore and
//  hev-socks5-tunnel
//

#ifndef PacketTunnelExtension_Bridging_Header_h
#define PacketTunnelExtension_Bridging_Header_h

#include <stddef.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <sys/socket.h>

// ============ Clash Core functions ============
extern char *ClashStart(char *homeDir, char *configContent);
extern char *ClashStartWithFD(char *homeDir, char *configContent, int fd);
extern char *ClashStop(void);
extern char *ClashSetMode(char *mode);
extern char *ClashGetMode(void);
extern int ClashIsRunning(void);
extern char *ClashGetVersion(void);

// ============ Go Tun2socks functions (fallback) ============
extern char *Tun2socksStart(char *socksHost, int socksPort, int mtu);
extern int Tun2socksInputPacket(char *data, int length);
extern int Tun2socksReadPacket(char *buffer, int bufferSize);
extern char *Tun2socksStop(void);
extern int Tun2socksIsRunning(void);

// ============ HevSocks5Tunnel functions (C implementation) ============
// These work properly in iOS Network Extension (unlike Go's net.Dial)
extern int hev_socks5_tunnel_main(const char *config_path, int tun_fd);
extern int hev_socks5_tunnel_main_from_file(const char *config_path,
                                            int tun_fd);
extern int hev_socks5_tunnel_main_from_str(const unsigned char *config_str,
                                           unsigned int config_len, int tun_fd);
extern void hev_socks5_tunnel_quit(void);
extern void hev_socks5_tunnel_stats(size_t *tx_packets, size_t *tx_bytes,
                                    size_t *rx_packets, size_t *rx_bytes);

// ============ Type definitions for TUN fd discovery ============
typedef uint8_t u_int8_t;
typedef uint16_t u_int16_t;
typedef uint32_t u_int32_t;
typedef uint64_t u_int64_t;
typedef unsigned char u_char;

// Control socket info for utun interface discovery
#define CTLIOCGINFO 0xc0644e03UL

struct ctl_info {
  u_int32_t ctl_id;
  char ctl_name[96];
};

struct sockaddr_ctl {
  u_char sc_len;
  u_char sc_family;
  u_int16_t ss_sysaddr;
  u_int32_t sc_id;
  u_int32_t sc_unit;
  u_int32_t sc_reserved[5];
};

#endif /* PacketTunnelExtension_Bridging_Header_h */
