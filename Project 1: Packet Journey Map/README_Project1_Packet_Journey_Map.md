# Project 1 – Packet Journey Map

A hands-on walkthrough of how a single HTTPS request travels from browser to server, covering every protocol layer involved — DNS, ARP, TCP, TLS, and HTTP — plus live traffic capture and analysis with Wireshark.

---

## Table of Contents

1. [Protocol & Port Reference](#protocol--port-reference)
2. [The Full Packet Journey](#the-full-packet-journey)
3. [Hands-On Capture (Linux CLI)](#hands-on-capture-linux-cli)
4. [Wireshark Analysis](#wireshark-analysis)
5. [Step-by-Step Flow](#step-by-step-flow)
6. [Security Notes](#security-notes)

---

## Protocol & Port Reference

### Core Protocols

| Protocol | Layer | Purpose |
|----------|-------|---------|
| Ethernet | Layer 2 | Framing |
| ARP | Layer 2/3 | IP → MAC resolution |
| IP | Layer 3 | Logical addressing & routing |
| ICMP | Layer 3 | Ping, traceroute, errors |
| TCP | Layer 4 | Connection-oriented, reliable, 3-way handshake |
| UDP | Layer 4 | Connectionless, fast, no guarantee |
| DNS | Layer 7 | Names → IPs |
| DHCP | Layer 7 | Automatic IP configuration |
| HTTP/HTTPS | Layer 7 | Web traffic |
| TLS | Layer 7 | Encryption, integrity, authentication |
| QUIC | Layer 7 | UDP-based transport for HTTP/3 |

### Ports to Memorize

| Port | Protocol |
|------|----------|
| 22 | SSH |
| 53 | DNS |
| 67/68 | DHCP |
| 80 | HTTP |
| 123 | NTP |
| 443 | HTTPS / QUIC |
| 3389 | RDP |

### Also Useful

`25` SMTP · `110` POP3 · `143` IMAP · `161` SNMP · `389` LDAP · `445` SMB · `3306` MySQL · `5432` PostgreSQL

### TCP Handshake & Teardown

- **3-way handshake:** `SYN → SYN-ACK → ACK`
- **Teardown:** `FIN/ACK → ACK → FIN/ACK → ACK` (or `RST`)

---

## The Full Packet Journey

When you type `https://example.com` in a browser, the following sequence happens:

1. **DNS** – The browser looks up the IP address for `example.com`.
2. **ARP** – If the destination is local (or to reach the gateway), the IP is resolved to a MAC address.
3. **TCP** – A reliable, connection-oriented channel is opened via the 3-way handshake.
4. **TLS** – An encrypted session is established; both sides exchange cryptographic keys so no one can intercept the data.
5. **HTTP** – The application data travels through the secure, established channel; the server replies with the webpage content.

---

## Hands-On Capture (Linux CLI)

Commands used to explore the network stack directly:

```bash
# Show network interface configuration
ip a

# Show routing table
ip route

# Show ARP cache (IP → MAC mappings)
arp -a

# Perform a DNS lookup
dig example.com

# Trace the route to a host (shows each hop)
traceroute example.com

# List active TCP/UDP listening ports with process info
ss -tulnp

# Verbose HTTP/HTTPS request (shows full connection flow)
curl -v https://example.com
```

### What Each Command Shows

| Command | Output |
|---------|--------|
| `ip a` | Network interfaces (loopback `lo`, `eth0`, etc.) with IPs and states |
| `ip route` | Routing table — where packets are sent for each destination |
| `arp -a` | ARP cache: recently contacted hosts and their MAC addresses |
| `dig example.com` | DNS lookup result: A record IP, response time, server used |
| `traceroute example.com` | Each hop the packet takes (7 hops to `example.com` in this capture) |
| `ss -tulnp` | All active TCP/UDP listening sockets with PIDs and process names |
| `curl -v https://example.com` | Full TLS handshake, HTTP headers, and response body details |

---

## Wireshark Analysis

**90 frames captured** from local device traffic.

### Key Findings

| Question | Answer |
|----------|--------|
| IP returned by DNS for `example.com` | `172.66.147.243` and `104.20.23.154` |
| Source (ephemeral) port of TCP SYN to port 443 | `43702` |
| TLS version offered by Client Hello | TLS 1.2 |
| TLS version selected by server | TLSv1.3 |
| SNI in Client Hello | `example.com` |
| Destination MAC in the SYN packet | `Microsoft_8f:c1:c8 (00:15:5d:8f:c1:c8)` — the **gateway** |
| ARP packets present? | Yes — `"Who has <gateway IP>? Tell <your IP>"` |
| TCP handshake packets | 3 (SYN, SYN-ACK, ACK) |
| Plaintext HTTP in capture? | Yes — frames 64 & 67 (captured using `curl -v http://example.com` to compare protocols) |

---

## Step-by-Step Flow

```
1.  Browser: type https://example.com
2.  DNS query  → UDP/53 → response: A record = <IP>
3.  ARP: who has <gateway>?  reply → <gateway MAC>
4.  TCP SYN     → <server IP>:443  (src port <ephemeral>)
5.  TCP SYN-ACK ← server
6.  TCP ACK     → server
7.  TLS ClientHello  → SNI=example.com, versions=<...>
8.  TLS ServerHello  → chosen version=<...>, cipher=<...>
9.  Certificate exchange → validate chain
10. TLS Finished (both sides)
11. HTTP GET /  (encrypted)
12. HTTP 200 OK (encrypted)
13. Assets fetched, page renders
14. TCP FIN/ACK teardown (or keep-alive reuse)
```

---

## Security Notes

| Protocol | Vulnerability | Mitigation |
|----------|--------------|------------|
| DNS | Unencrypted by default — spoofable | DNSSEC, DNS-over-HTTPS (DoH), DNS-over-TLS (DoT) |
| ARP | Unauthenticated — MITM possible | Dynamic ARP Inspection, static ARP entries, 802.1X |
| TLS | MITM possible if certificates aren't validated | Validate cert chain, enforce HSTS |
| HTTP | Plaintext — readable on the wire | Use HTTPS + HSTS |
