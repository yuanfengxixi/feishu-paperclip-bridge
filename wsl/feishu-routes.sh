#!/bin/bash
# Install at: /usr/local/sbin/feishu-routes.sh  (chmod +x, owned by root)
# Triggered by /etc/wsl.conf [boot] command on every WSL start.
#
# Purpose: route Feishu API CIDRs through the real network adapter (eth0),
# bypassing the Clash/FlClash TUN adapter (which would route them overseas
# and break with EOF / ERR_CONNECTION_CLOSED).
#
# Why these CIDRs: discovered by resolving open.feishu.cn,
# msg-frontier.feishu.cn, open-callback-ws.feishu.cn,
# lark-msg-frontier.feishu.cn via the LAN gateway DNS (192.168.0.1).
# Re-resolve and update if Feishu rotates IP ranges.
#
# Gateway IP (192.168.0.1) and interface (eth0) are typical for WSL2 on a
# home network. Adjust if yours differs.

sleep 5  # let WSL networking finish initializing

GATEWAY="${GATEWAY:-192.168.0.1}"
IFACE="${IFACE:-eth0}"

for cidr in 111.1.166.0/24 112.13.108.0/24 223.95.56.0/24 39.173.165.0/24; do
    ip route del "$cidr" 2>/dev/null || true
    ip route add "$cidr" via "$GATEWAY" dev "$IFACE" 2>/dev/null || true
done
