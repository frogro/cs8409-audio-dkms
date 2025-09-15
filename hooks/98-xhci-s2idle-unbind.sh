#!/bin/sh
# Minimal xHCI unbind hook for s2idle suspend
# - Only runs for s2idle (not for deep)
# - Targets come from /etc/default/xhci-s2idle (if present)
# - Fallback: autodetect non-PCH xHCI (exclude 0000:00:14.0)
# Safe: If nothing is detected or ENABLE=0 -> no-op.

CFG=/etc/default/xhci-s2idle
LIST=/run/xhci-s2idle.bound

is_s2idle() { grep -q '\[s2idle\]' /sys/power/mem_sleep 2>/dev/null; }
detect_targets() { 
  # lspci -Dnns shows BDF like 0000:08:00.0 at col1
  # Filter USB controller with xHCI, exclude PCH 00:14.0
  lspci -Dnns | awk '/ USB controller: / && tolower($0) ~ /xhci/ {print $1}' | grep -v '^0000:00:14\.0$' || true
}

ENABLE=1
TARGETS=""
[ -r "$CFG" ] && . "$CFG"

[ "$ENABLE" = "1" ] || exit 0
[ -n "$TARGETS" ] || TARGETS="$(detect_targets)"
[ -n "$TARGETS" ] || exit 0

case "$1/$2" in
  pre/*)
    is_s2idle || exit 0
    : > "$LIST"
    for dev in $TARGETS; do
      [ -e "/sys/bus/pci/devices/$dev/driver" ] || continue
      echo "$dev" >> "$LIST"
      echo "$dev" > /sys/bus/pci/drivers/xhci_hcd/unbind
    done
    ;;
  post/*)
    is_s2idle || exit 0
    [ -r "$LIST" ] || exit 0
    while read -r dev; do
      [ -e "/sys/bus/pci/devices/$dev" ] || continue
      echo "$dev" > /sys/bus/pci/drivers/xhci_hcd/bind
    done < "$LIST"
    rm -f "$LIST"
    ;;
esac
