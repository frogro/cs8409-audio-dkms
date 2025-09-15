#!/bin/sh
# Minimal xHCI unbind hook for s2idle suspend
# - Runs only for s2idle
# - Reads /etc/default/xhci-s2idle (ENABLE, TARGETS)
# - Fallback autodetect if config missing/empty

CFG=/etc/default/xhci-s2idle
LIST=/run/xhci-s2idle.bound

is_s2idle() { grep -q '\[s2idle\]' /sys/power/mem_sleep 2>/dev/null; }

list_xhci() {
  # Print PCI BDFs of xHCI (class 0x0c0330)
  for d in /sys/bus/pci/devices/*; do
    [ -r "$d/class" ] || continue
    c=$(cat "$d/class")
    [ "$c" = "0x0c0330" ] || continue
    b=$(basename "$d")
    echo "$b"
  done
}

fallback_targets() {
  # prefer non-PCH (≠ 0000:00:14.0), else PCH, else empty
  PCH=0000:00:14.0
  nonpch="$(list_xhci | grep -v -E '^0000:00:14\.0$' || true)"
  if [ -n "$nonpch" ]; then
    echo "$nonpch"
  elif [ -e "/sys/bus/pci/devices/$PCH" ]; then
    echo "$PCH"
  else
    echo ""
  fi
}

load_cfg() {
  ENABLE=1
  TARGETS=""
  [ -r "$CFG" ] && . "$CFG"
  # If TARGETS empty or invalid, recompute
  if [ -z "$TARGETS" ]; then
    TARGETS="$(fallback_targets)"
  fi
}

case "$1/$2" in
  pre/*)
    is_s2idle || exit 0
    load_cfg
    [ "${ENABLE:-1}" = "1" ] || exit 0
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
