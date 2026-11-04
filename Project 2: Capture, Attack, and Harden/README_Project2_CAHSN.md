# Project 2 – Capture, Analyze, and Harden a Small Network (CAHSN)

A hands-on networking lab where a small virtual network is built from scratch using Linux network namespaces. The project covers traffic capture, ARP spoofing/MITM simulation, and firewall hardening with `nftables`.

---

## Table of Contents

1. [Lab Topology](#lab-topology)
2. [Setup](#setup)
3. [Traffic Capture](#traffic-capture)
4. [Nmap Scanning](#nmap-scanning)
5. [Attacker Setup & ARP Poisoning](#attacker-setup--arp-poisoning)
6. [MITM Attack](#mitm-attack)
7. [Firewall Hardening with nftables](#firewall-hardening-with-nftables)
8. [Test Results](#test-results)

---

## Lab Topology

```
 10.0.1.0/24                          10.0.2.0/24
 ┌──────────┐    veth1 ── veth1-r    ┌──────────┐    veth2 ── veth2-r    ┌──────────┐
 │  host1   │◄──────────────────────►│  router  │◄──────────────────────►│  host2   │
 │10.0.1.10 │                        │ (fwd on) │                        │10.0.2.10 │
 └──────────┘                        └──────────┘                        └──────────┘
                                           ▲
                                           │ veth3 ── veth3-a + br0
                                           │
                                    ┌──────────────┐
                                    │   attacker   │
                                    │  10.0.1.20   │
                                    └──────────────┘
```

Three components: **router**, **host1**, **host2** (and later **attacker**), all in separate Linux network namespaces connected via virtual ethernet (veth) pairs.

---

## Setup

### 1. Create Namespaces

```bash
sudo ip netns add router
sudo ip netns add host1
sudo ip netns add host2
```

### 2. Create veth Pairs

```bash
sudo ip link add veth1 type veth peer name veth1-r
sudo ip link add veth2 type veth peer name veth2-r
```

### 3. Connect Hosts to Router

```bash
sudo ip link set veth1 netns host1
sudo ip link set veth1-r netns router
sudo ip link set veth2 netns host2
sudo ip link set veth2-r netns router
```

### 4. Assign IP Addresses

```bash
sudo ip netns exec host1   ip addr add 10.0.1.10/24 dev veth1
sudo ip netns exec router  ip addr add 10.0.1.1/24  dev veth1-r
sudo ip netns exec host2   ip addr add 10.0.2.10/24 dev veth2
sudo ip netns exec router  ip addr add 10.0.2.1/24  dev veth2-r
```

### 5. Bring Interfaces Up

```bash
sudo ip netns exec host1  ip link set veth1   up
sudo ip netns exec router ip link set veth1-r up
sudo ip netns exec host2  ip link set veth2   up
sudo ip netns exec router ip link set veth2-r up
```

Verify: `sudo ip netns exec <namespace> ip a` — interface should show `UP` with its IP.

### 6. Enable IP Forwarding on Router

```bash
sudo ip netns exec router sysctl -w net.ipv4.ip_forward=1
# Expected: net.ipv4.ip_forward = 1
```

### 7. Verify Connectivity

```bash
# Ping host2 from host1 (cross-subnet)
sudo ip netns exec host1 ping -c 3 10.0.2.10

# Reverse direction
sudo ip netns exec host2 ping -c 3 10.0.1.10
```

### ARP & Routes

```bash
sudo ip netns exec host1 arp -a
# ? (10.0.1.1) at 56:61:ab:f8:14:5e [ether] on veth1

sudo ip netns exec host2 arp -a
# ? (10.0.2.1) at 76:47:8f:ee:1d:12 [ether] on veth2
```

---

## Traffic Capture

### Capture from Router's veth1-r Side

**Terminal 1 — start capture:**
```bash
sudo ip netns exec router tcpdump -i veth1-r -w lab.pcap -v
```

**Terminal 2 — generate traffic:**
```bash
sudo ip netns exec host1 ping -c 8 10.0.2.10
```

Stop capture with `Ctrl+C`, then open: `wireshark lab.pcap`

### Capture from veth2-r Side

```bash
sudo ip netns exec router tcpdump -i veth2-r -w lab2.pcap -v
```

### Comparing lab.pcap vs lab2.pcap

| | lab.pcap (veth1-r) | lab2.pcap (veth2-r) |
|--|--|--|
| ARP source MAC | veth1-r MAC | veth2-r MAC |
| ARP target IP | host1 subnet | host2 subnet |

**Key insight:** ARP is per-subnet and per-hop. The router initiates a fresh ARP on each interface it forwards onto — exactly the expected behavior.

---

## Nmap Scanning

### Start a Web Server on host2

**Terminal 1:**
```bash
sudo ip netns exec host2 python3 -m http.server 80
# Verify: 10.0.1.10 - - [05/Oct/2026 15:05:58] "GET / HTTP/1.1" 200 -
```

### Run Nmap from host1

```bash
# 1. Host discovery (ping sweep)
sudo ip netns exec host1 nmap -sn 10.0.2.0/24

# 2. SYN scan on ports 1-1000
sudo ip netns exec host1 nmap -sS -p 1-1000 10.0.2.10
# Result: 80/tcp open  http

# 3. Service/version detection on port 80
sudo ip netns exec host1 nmap -sV -p 80 10.0.2.10
# Result: 80/tcp open  http  SimpleHTTPServer 0.6 (Python 3.12.3)
```

### Notable Wireshark Finding (> 4000 frames)

A **TCP RST** was observed after a completed handshake (SYN=1, ACK=1). This is expected behavior: `nmap -sV` connects, grabs the service banner, and sends `RST` to tear down the connection — it doesn't need a full session.

---

## Attacker Setup & ARP Poisoning

### Add Attacker Namespace

```bash
sudo ip netns add attacker
sudo ip link add veth3 type veth peer name veth3-a
sudo ip link set veth3-a netns attacker
sudo ip netns exec attacker ip addr add 10.0.1.20/24 dev veth3-a
sudo ip netns exec attacker ip link set veth3-a up
```

### Create Bridge on Router (to connect attacker to host1 subnet)

```bash
sudo ip netns exec router ip link add br0 type bridge
sudo ip netns exec router ip link set veth1-r master br0
sudo ip netns exec router ip link set veth3   master br0
sudo ip netns exec router ip link set br0 up
```

> **Why a bridge?** The router hadn't learned the attacker's MAC. Adding `br0` makes the attacker part of the `10.0.1.0/24` segment and inherits the bridge MAC as the new gateway MAC.

### Verify Attacker Reachability

```bash
sudo ip netns exec host1 ping -c 3 10.0.1.20
```

### Run ARP Poisoning (4 Terminals)

| Terminal | Command | Purpose |
|----------|---------|---------|
| 1 | `python3 -m http.server 80` (on host2) | Web server target |
| 2 | `tcpdump -i veth3-a -w attack.pcap` (on attacker) | Capture traffic |
| 3 | `arpspoof -i veth3-a -t 10.0.1.10 10.0.1.1` (on attacker) | Poison ARP cache |
| 4 | Watch ARP table on host1 | Observe MAC change |

**Proof it worked:**

- **Terminal 2:** 53 packets recorded.
- **Terminal 3:** `arp reply 10.0.1.1 is-at 4a:6e:5d:23:5:32` (attacker's MAC).
- **Terminal 4:** host1's ARP cache now shows the attacker's MAC for the gateway IP.

---

## MITM Attack

Enable forwarding on the attacker so traffic flows through (instead of just breaking the network):

```bash
# Terminal 1: Enable forwarding on attacker
sudo ip netns exec attacker sysctl -w net.ipv4.ip_forward=1

# Terminal 2: Start sniffer on attacker
sudo ip netns exec attacker tcpdump -i veth3-a -A

# Terminal 3: Re-run ARP poison
sudo ip netns exec attacker arpspoof -i veth3-a -t 10.0.1.10 10.0.1.1

# Terminal 4: Generate traffic from host1
sudo ip netns exec host1 curl http://10.0.2.10
```

**Result:** Terminal 2 shows the raw HTTP GET request and HTML response in **plaintext** flowing through the attacker — a successful MITM.

---

## Firewall Hardening with nftables

### Firewall Options Considered

| Tool | Type | Notes |
|------|------|-------|
| **nftables** | Low-level (modern) | Built into the kernel; replaces iptables infrastructure; handles IPv4+IPv6; faster, less CPU |
| iptables | Low-level (legacy) | Translates to nftables rules via `iptables-nft` on modern Ubuntu |
| ufw | High-level frontend | Ubuntu default; human-readable rules; wraps nftables/iptables |
| firewalld | High-level frontend | Red Hat's alternative; zone-based; dynamic rule management |

**Chosen:** `nftables` — most efficient for this simple scenario.

### Create Table and Chain

```bash
sudo ip netns exec router nft add table ip filter

sudo ip netns exec router nft add chain ip filter FORWARD \
  '{ type filter hook forward priority 0; policy accept; }'
```

### Add Rules

```bash
# Rule 1: Allow established/related return traffic (stateful)
sudo ip netns exec router nft add rule ip filter FORWARD \
  ct state established,related counter accept

# Rule 2: Allow HTTP (TCP port 80) to host2
sudo ip netns exec router nft add rule ip filter FORWARD \
  ip daddr 10.0.2.10 tcp dport 80 counter accept

# Rule 3: Default deny to host2
sudo ip netns exec router nft add rule ip filter FORWARD \
  ip daddr 10.0.2.10 counter drop
```

### Verify Rules

```bash
sudo ip netns exec router nft list tables
sudo ip netns exec router nft list ruleset
```

Expected output (with counters after testing):

```
table ip filter {
    chain FORWARD {
        type filter hook forward priority filter; policy accept;
        ct state established,related counter packets 12 bytes 918 accept
        ip daddr 10.0.2.10 tcp dport 80 counter packets 1 bytes 60 accept
        ip daddr 10.0.2.10 counter packets 2 bytes 168 drop
    }
}
```

---

## Test Results

| Test | Expected | Result |
|------|----------|--------|
| **A** — HTTP from host1 to host2 (`curl http://10.0.2.10`) | ✅ Success (Rule 2 + 1) | ✅ Pass |
| **B** — Ping host2 from host1 (`ping 10.0.2.10`) | ❌ Fail (Rule 3 drops ICMP) | ✅ Pass — 100% packet loss |
| **C** — Packet counters | Counters increment per rule | ✅ Pass — counters visible after adding `counter` keyword to rules |

> **Note:** The `counter` keyword must be explicitly added to each nftables rule to display hit counts. Without it, `nft list ruleset` omits the counter field.
