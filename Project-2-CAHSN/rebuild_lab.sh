#!/bin/bash
set -e
echo "=== Rebuilding Project 2 Lab Topology ==="

# 1. Clean up any existing namespaces from a previous run
sudo ip netns del host1 2>/dev/null || true
sudo ip netns del host2 2>/dev/null || true
sudo ip netns del router 2>/dev/null || true
sudo ip netns del attacker 2>/dev/null || true

# 2. Create namespaces
sudo ip netns add host1
sudo ip netns add host2
sudo ip netns add router
sudo ip netns add attacker

# 3. Create veth pairs
sudo ip link add veth1 type veth peer name veth1-r
sudo ip link add veth2 type veth peer name veth2-r
sudo ip link add veth3 type veth peer name veth3-a

# 4. Move interfaces to namespaces
sudo ip link set veth1 netns host1
sudo ip link set veth1-r netns router
sudo ip link set veth2 netns host2
sudo ip link set veth2-r netns router
sudo ip link set veth3 netns attacker
sudo ip link set veth3-a netns router

# 5. Assign IP addresses
sudo ip netns exec host1 ip addr add 10.0.1.10/24 dev veth1
sudo ip netns exec host2 ip addr add 10.0.2.10/24 dev veth2
sudo ip netns exec router ip addr add 10.0.2.1/24 dev veth2-r
sudo ip netns exec router ip addr add 10.0.1.1/24 dev veth1-r
sudo ip netns exec attacker ip addr add 10.0.1.20/24 dev veth3

# 6. Bring up interfaces (both ends of every cable)
sudo ip netns exec host1 ip link set lo up
sudo ip netns exec host2 ip link set lo up
sudo ip netns exec router ip link set lo up
sudo ip netns exec attacker ip link set lo up

sudo ip netns exec host1 ip link set veth1 up
sudo ip netns exec host2 ip link set veth2 up
sudo ip netns exec router ip link set veth2-r up
sudo ip netns exec router ip link set veth1-r up
sudo ip netns exec attacker ip link set veth3 up
sudo ip netns exec router ip link set veth3-a up

# 7. Set default routes
sudo ip netns exec host1 ip route add default via 10.0.1.1
sudo ip netns exec host2 ip route add default via 10.0.2.1
sudo ip netns exec attacker ip route add default via 10.0.1.1

# 8. Enable IP Forwarding on router
sudo ip netns exec router sysctl -w net.ipv4.ip_forward=1 > /dev/null

# 9. Create the br0 bridge inside the router namespace (Lines 479-486)
sudo ip netns exec router ip link add br0 type bridge
sudo ip netns exec router ip link set br0 up
sudo ip netns exec router ip addr del 10.0.1.1/24 dev veth1-r
sudo ip netns exec router ip addr add 10.0.1.1/24 dev br0
sudo ip netns exec router ip link set veth1-r master br0
sudo ip netns exec router ip link set veth3-a master br0
sudo ip netns exec router ip link set veth1-r up
sudo ip netns exec router ip link set veth3-a up

# 10. Rebuild the web server content on host2
sudo ip netns exec host2 bash -c 'mkdir -p /tmp/site && echo "<h1>Lab server on host2</h1>" > /tmp/site/index.html'

echo "=== Topology Rebuilt ==="

# 11. Verification tests
echo "Pinging gateway from attacker..."
sudo ip netns exec attacker ping -c 2 10.0.1.1

echo "Pinging host1 from attacker..."
sudo ip netns exec attacker ping -c 2 10.0.1.10

echo "Pinging host2 from host1..."
sudo ip netns exec host1 ping -c 2 10.0.2.10

echo "=== Setup Complete! ==="
echo "To start your web server for scans, run:"
echo "sudo ip netns exec host2 python3 -m http.server 80 --bind 10.0.2.10 --directory /tmp/site"
