# reverse-port-forwarding-tun2socks-demo

This README file is written by AI and heavily checked by me to ensure detail correctness.

## Problem Statement

Imagine a container that cannot make outbound Internet connections but can only accept inbound TCP connections to a single port. How can it obtain full TCP and UDP Internet access without modifying its applications?

This repository uses:

    reverse TCP tunnel
    SOCKS5 proxy
    UDP gateway
    tun2socks

resulting in transparent Internet access for applications running inside the isolated container.

## Architecture

The demo consists of two containers:

* **hasinet** — has direct Internet connectivity.
* **noinet** — connected only to an isolated Docker network and can only accept incoming connections to a single port (in this case 7565, but you can change it).

A reverse TCP tunnel is established from `hasinet` to `noinet`. The tunnel is then used to transport SOCKS5 traffic, allowing `noinet` to route all TCP and UDP traffic through `hasinet`.

```text
                                   Internet
                                       ▲
                                       │
                             outbound TCP/UDP
                                       │
                                       │
┌────────────────────────────────────────────────────────────────────────────┐
│                         hasinet container                                  │
│                                                                            │
│  TCP outbound connections    UDP outbound connections                      │
│         ▲                          ▲                                       │
│         │                          │                                       │
│  microsocks:1080       -- ▶  badvpn-udpgw:7300                             │
│         ▲                                                                  │
│         │                                                                  │
│  reverse_tcp_forwarding                                                    │
│       mode=CLIENT                                                          │
│         │                                                                  │
└─────────┼──────────────────────────────────────────────────────────────────┘
          │
          │ only permitted connection
          │ TCP/7565 from hasinet to noinet
          │ initiated by CLIENT
          ▼
┌─────────┼──────────────────────────────────────────────────────────────────┐
│         │                                                                  │
│         │                    noinet container                              │
│  (listening at 7565)                                                       │
│  reverse_tcp_forwarding                                                    │
│       mode=SERVER                                                          │
│  (listening at 1080)                                                       │
│         ▲                                                                  │
│         │                                                                  │
│         │ connects to 127.0.0.1:1080 to forward TCP                        │
│         │ connects to 127.0.0.1:7300 through 127.0.0.1:1080 to forward UDP │
│         │                                                                  │
│  badvpn-tun2socks                                                          │
│         ▲                                                                  │
│         │                                                                  │
│      TUN device                                                            │
│         ▲                                                                  │
│         │                                                                  │
│    Applications                                                            │
└─────────┴──────────────────────────────────────────────────────────────────┘
```

The only allowed connection between the containers is:

```text
hasinet → noinet : TCP/7565
```

Everything else is built on top of that single TCP connection. If you instead have only incoming `ssh` connections allowed, You can use `ssh -L` flag to forward this port (see FAQ below).

## Features

* Demonstrates reverse TCP port forwarding.
* Transparently (VPN-styled) routes TCP and UDP, even for the applications that do not support using socks proxy.
* Demonstrates turning the `tun2socks` ON and OFF and again ON.
* Requires only a single outbound TCP connection from the Internet-connected side.
* Useful if you can connect to the container but not from it.
* Does not require per-app proxy configuration or setting proxy in environment vars.

## Components

### microsocks

Provides a SOCKS5 proxy on the Internet-connected host.

```text
127.0.0.1:1080
```

### badvpn-udpgw

Provides UDP transport over SOCKS.

```text
127.0.0.1:7300
```

This port is not forwarded via reverse_tcp_forwarding, because tun2socks would reach it through socks proxy.

### reverse_tcp_forwarding

Creates a reverse port-forwarding tunnel.

In this demo:

* `hasinet` runs `reverse_tcp_forwarding` in **client** mode. It connects to `noinet` container and to `microsocks` proxy server.
* `noinet` runs `reverse_tcp_forwarding` in **server** mode. It accepts connections from `hasinet` container and from `tun2socks` service.

The `reverse_tcp_forwarding` forwards:

```text
noinet:1080 → hasinet:1080
```

where `hasinet:1080` is provided by `microsocks`.

* It is better than `ssh -R` flag because the flag is known for keeping port marked as "used" for a few minutes after the connection is lost, preventing quickly restoring the broken connection (see FAQ below).

### badvpn-tun2socks

Creates a virtual network interface and forwards all traffic through the SOCKS proxy.

It accepts two host-port pairs:
* `127.0.0.1:1080` for socks proxy, which is forwarded via `reverse_port_forwarding`
* `127.0.0.1:7300` for `badvpn-udpgw`, which it would try to reach through socks proxy.

The demo configures:

```text
TUN interface: badvpntun
Gateway:       10.240.128.2
Subnet:        10.240.128.0/30
```

Default routes are redirected into the TUN interface:

```text
0.0.0.0/1
128.0.0.0/1
```

allowing all outbound traffic to pass through the SOCKS tunnel. (see FAQ why we split 0.0.0.0/0 in halves).

## Building and running

```bash
./restart_containers.sh
```

The startup sequence performs several checks automatically.

### Verify that `hasinet` has Internet access

```bash
ping 1.1.1.1
```

### Verify that `noinet` initially has no Internet access

```bash
ping 1.1.1.1
```

This check is expected to fail.

### Start the tunnel

The compose file launches:

* reverse tunnel server/client
* SOCKS5 proxy
* UDP gateway
* tun2socks

### Verify TCP connectivity

The demo queries:

```bash
curl https://ipinfo.io
```

from inside `noinet`.

Successful output proves that traffic is leaving through `hasinet`.

### Verify UDP connectivity

The demo uses HTTP/3:

```bash
curl --http3-only https://ozon.ru
```

HTTP/3 requires UDP (QUIC), so a successful request verifies:

```text
Application
  ↓
tun2socks
  ↓
SOCKS5
  ↓
badvpn-udpgw
  ↓
Reverse TCP tunnel
  ↓
Internet
```

## Tunnel Restart Test

The demo intentionally:

1. Stops `badvpn-tun2socks`.
2. Removes TUN routes.
3. Verifies loss of connectivity.
4. Recreates the TUN interface.
5. Restarts `badvpn-tun2socks`.
6. Verifies connectivity again.

This demonstrates that the tun2socks service can be stopped and restarted when needed.

## Networks

### internet

Regular Docker bridge network with Internet access.

Attached only to:

```text
hasinet
```

### internal

Docker internal network:

```yaml
internal: true
```

Attached to:

```text
hasinet
noinet
```

Subnet:

```text
172.31.51.0/24
```

Addresses:

```text
hasinet  172.31.51.2
noinet   172.31.51.3
```

Because the network is marked as internal, `noinet` cannot reach the Internet directly.

## Required Docker Capabilities

The demo requires:

```yaml
cap_add:
  - NET_ADMIN
  - SYS_MODULE
devices:
  - /dev/net/tun:/dev/net/tun
security_opt:
  - seccomp:unconfined
```

These are needed for:

* creating TUN interfaces
* modifying routes
* running `tun2socks`

## Use Cases

This pattern can be useful when:

* a machine has no direct Internet access
* only a single inbound TCP connection is permitted
* a SOCKS proxy must be exposed through a reverse tunnel
* TCP and UDP traffic need to be transported through restrictive firewalls
* containerized environments require transparent proxying

## Notes

* ICMP (`ping`) is not supported through `badvpn-tun2socks`.
* UDP support is provided through `badvpn-udpgw`.
* HTTP/3 is used as the UDP validation mechanism.
* The restart loops in the compose file are intended for demonstration purposes. For production deployments, a proper service manager such as `systemd`, `s6`, or Docker restart policies should be used.
* This demo uses `--resolve` flag of curl because for unknown reason DNS is not working, despite UDP being available. In production setup you should be able to fix it by configuring system-wide DNS server.

## FAQ

* How to use it? Can I use it by just cloning and running it?

    Not really. This is configuration demo, not a tool that can be used as is. You can setup your own containers or vms according to commands in docker compose, replacing while loops with systemd services and changing ips and ports according to your own network topology. Cloning and starting would result in running tests of this demo, not in internet access for your isolated container.

* Do i need to have `docker` to connect my isolated container to the internet?

    No.

    Here `docker` and `docker compose` are used as an environment to test the solution. They help creating isolated container, usual container and a network between them. If you have isolated system, you do not need `docker` to execute these commands on the isolated system itself.

* Why use `reverse_tcp_forwarding` when we can use `ssh -R`?

    ssh -R is perfectly adequate for many deployments. However, after an unexpected disconnect, sshd may keep the reverse-forwarded port allocated until it detects the session timeout. During that period, reconnect attempts can fail because the port is still considered in use. It would cause downtime for a few minutes.

    reverse_tcp_forwarding uses a preemptive strategy to reuse port when it accepts the new connection, allowing the tunnel to be re-established without waiting for SSH session cleanup.

* What if I cannot expose port 7565 but I can SSH into the isolated container?

    You can forward this port via `ssh -L` flag. It does not have the problem mentioned above. Do not forget that the ssh connection might get lost and use some infinite retry logic, like bash while loop or systemd service.

* What if my application does not support SOCKS proxies?

   The proxy is used only by tun2socks to connect to the internet. Applications never interact with the SOCKS proxy directly. `tun2socks` routes traffic through the proxy at the network layer using a TUN interface. Applications simply use the normal system routing table and do not need proxy support or proxy configuration.

* Why is a TUN device required?

    The SOCKS proxy only accepts TCP connections. Applications normally send packets through the kernel routing stack rather than through SOCKS.

    tun2socks creates a virtual network interface (TUN device), receives IP packets from the kernel, and forwards them through the SOCKS tunnel. This allows existing applications to work without modification.

* Does this work with UDP?

    Yes.

    UDP packets are transported through SOCKS using badvpn-udpgw. The demo validates this by successfully performing an HTTP/3 request, which requires UDP (QUIC).

* Does this work with ICMP (ping)?

    No.

    badvpn-tun2socks supports TCP and UDP traffic but does not forward ICMP packets. As a result, ping will fail even when Internet access is working correctly.

* Why are there two default routes (0.0.0.0/1 and 128.0.0.0/1)?

    Replacing the default route directly can break connectivity to services required to maintain the tunnel itself.

    Splitting the Internet into: 0.0.0.0/1 and 128.0.0.0/1 actually still covers whole range (0.0.0.0/0) but the system would choose it as more specific (having longer prefix)

* Can I use another SOCKS server?

    Yes.

    Any SOCKS5 server that works with badvpn-tun2socks should work. microsocks is used because it is lightweight and easy to deploy.

* Can multiple applications use the tunnel simultaneously?

    Yes.

    Once the TUN interface is active, all applications using the system routing table can share the same tunnel concurrently

* Why not run a VPN such as WireGuard or OpenVPN?

    `WireGuard` and `OpenVPN` require UDP connection. This demo shows the situation when only TCP between containers is allowed.

    `OpenVPN` has TCP mode, but this mode is extremely slow due to its TCP-over-TCP problem. You can actually use it alongside this solution if you want to support ICMP while having fast TCP, but it requires much more complex configuration of routing TCP and UDP packets to one TUN, and others to another TUN.

    `ShadowSocks` is fast and works over TCP, but still does not have linux cli-only client with TUN support, which is required for transparent routing.

* What happens if the tunnel disconnects?

    Existing connections will be interrupted. New connections would be refused while socks proxy is not available. `tun2socks` process will not stop working unless manually disabled. When socks proxy becomes available again, `tun2socks` would start using it automatically without any user action, which makes the tunnel seamless.

* Is traffic encrypted?

    Not by reverse_tcp_forwarding or socks protocol itself.

    If encryption is required, run the TCP stream through SSH, TLS, or another encrypted transport before exposing it to untrusted networks.

* Can the isolated side reach services on the Internet-connected side?

    Yes.

    Any service reachable through the SOCKS proxy can be accessed, including services hosted on hasinet itself, provided routing and firewall rules allow it.

