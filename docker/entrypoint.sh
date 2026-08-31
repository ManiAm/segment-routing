#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# 1. Kernel tunables — enable IPv6 forwarding and SRv6 (seg6)
# ---------------------------------------------------------------------------
sysctl -w net.ipv6.conf.all.forwarding=1          > /dev/null
sysctl -w net.ipv6.conf.default.forwarding=1       > /dev/null
sysctl -w net.ipv6.conf.all.seg6_enabled=1         2>/dev/null || true
sysctl -w net.ipv6.conf.default.seg6_enabled=1     2>/dev/null || true
for f in /sys/class/net/*; do
    sysctl -w "net.ipv6.conf.$(basename "$f").seg6_enabled=1" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# 2. Detect interface-to-subnet mapping
#
#    Docker Compose does not guarantee the order in which interfaces are
#    named (eth0, eth1, …).  We look up the interface that carries each
#    known subnet so the IS-IS configuration matches reality.
# ---------------------------------------------------------------------------
iface_for_subnet() {
    ip -o -6 addr show | grep "$1" | awk '{print $2}' | head -1
}

# ---------------------------------------------------------------------------
# 3. Build the FRR configuration file
#
#    We generate frr.conf dynamically because:
#      a) interface names are unpredictable (see above)
#      b) FRR's config-file parser drops the segment-routing global block
#         and everything after it, so we configure that via vtysh instead.
# ---------------------------------------------------------------------------
HOSTNAME=$(hostname)
cp /etc/frr/hosts/daemons /etc/frr/daemons

write_iface() {
    local iface="$1" desc="$2" metric="$3"
    cat >> /etc/frr/frr.conf <<EOF
!
interface ${iface}
 description ${desc}
 ipv6 router isis SRv6LAB
EOF
    [ -n "$metric" ] && echo " isis metric ${metric}" >> /etc/frr/frr.conf || true
}

case "$HOSTNAME" in
    H1)
        LOCATOR_PREFIX="fcbb:bb00:1::/48"
        NET="49.0001.0000.0000.0001.00"
        LO_ADDR="fc00::1/128"
        IFACES=("$(iface_for_subnet fd00:12::)" "Link to H2" ""
                "$(iface_for_subnet fd00:13::)" "Link to H3" "20")
        ;;
    H2)
        LOCATOR_PREFIX="fcbb:bb00:2::/48"
        NET="49.0001.0000.0000.0002.00"
        LO_ADDR="fc00::2/128"
        IFACES=("$(iface_for_subnet fd00:12::)" "Link to H1" ""
                "$(iface_for_subnet fd00:24::)" "Link to H4" "")
        ;;
    H3)
        LOCATOR_PREFIX="fcbb:bb00:3::/48"
        NET="49.0001.0000.0000.0003.00"
        LO_ADDR="fc00::3/128"
        IFACES=("$(iface_for_subnet fd00:13::)" "Link to H1" "20"
                "$(iface_for_subnet fd00:34::)" "Link to H4" "")
        ;;
    H4)
        LOCATOR_PREFIX="fcbb:bb00:4::/48"
        NET="49.0001.0000.0000.0004.00"
        LO_ADDR="fc00::4/128"
        IFACES=("$(iface_for_subnet fd00:24::)" "Link to H2" ""
                "$(iface_for_subnet fd00:34::)" "Link to H3" "")
        ;;
esac

cat > /etc/frr/frr.conf <<EOF
frr defaults traditional
hostname ${HOSTNAME}
!
interface lo
 ipv6 address ${LO_ADDR}
 ipv6 router isis SRv6LAB
 isis passive
EOF

write_iface "${IFACES[0]}" "${IFACES[1]}" "${IFACES[2]}"
write_iface "${IFACES[3]}" "${IFACES[4]}" "${IFACES[5]}"

cat >> /etc/frr/frr.conf <<EOF
!
router isis SRv6LAB
 net ${NET}
 is-type level-1
 topology ipv6-unicast
 segment-routing srv6
  locator MAIN
 !
!
EOF

chown -R frr:frr /etc/frr

# ---------------------------------------------------------------------------
# 4. Start FRR
# ---------------------------------------------------------------------------
/usr/lib/frr/frrinit.sh start

# ---------------------------------------------------------------------------
# 5. Configure the SRv6 locator via vtysh
#    (The segment-routing global block must be applied after FRR starts
#     because FRR's config-file parser does not handle it reliably.)
# ---------------------------------------------------------------------------
sleep 1
vtysh -c "configure terminal" \
      -c "segment-routing" \
      -c "srv6" \
      -c "locators" \
      -c "locator MAIN" \
      -c "prefix ${LOCATOR_PREFIX}" \
      -c "end"

exec tail -f /dev/null
