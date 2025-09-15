#!/bin/sh
# Minimal xHCI unbind hook for s2idle suspend
# - Only runs for s2idle (not for deep)
# - Targets come from /etc/default/xhci-s2idle (if present)
# - Fallback: autodetect non-PCH xHCI (exclude 0000:00:14.0)
# - Safe: If nothing is detected or ENABLE=0 -> no-op.

CFG=/etc/default/xhci-s2idle
LIST=/run/xhci-s2idle.bound

is_s2idle() {
  grep -q '\[s2idle\]' /sys/power/mem_sleep 2>/dev/null
}

autodetect_targets() {
  # 1) bevorzugt: gebundene xhci_hcd-Geräte (außer 0000:00:14.0)
  local d dev found=""
  for d in /sys/bus/pci/drivers/xhci_hcd/0000:* 2>/dev/null; do
    [ -e "$d" ] || continue
    dev=$(basename "$d")
    [ "$dev" = "0000:00:14.0" ] && continue
    found="${dev}"
    break
  done
  if [ -n "$found" ]; then
    printf '%s\n' "$found"
    return 0
  fi

  # 2) Fallback: per PCI-Class (0x0c0330 = xHCI), erneut non-PCH bevorzugen
  for d in /sys/bus/pci/devices/0000:* 2>/dev/null; do
    [ -e "$d/class" ] || continue
    [ "$(cat "$d/class" 2>/dev/null)" = "0x0c0330" ] || continue
    dev=$(basename "$d")
    [ "$dev" = "0000:00:14.0" ] && continue
    printf '%s\n' "$dev"
    return 0
  done

  # 3) Notfalls: PCH-xHCI (wenn wirklich nichts anderes existiert)
  if [ -e /sys/bus/pci/devices/0000:00:14.0 ]; then
    printf '%s\n' "0000:00:14.0"
    return 0
  fi

  # 4) Gar nichts gefunden
  return 1
}

case "$1/$2" in
  pre/*)
    is_s2idle || exit 0

    # Defaults
    ENABLE=1
    TARGETS=""
    [ -r "$CFG" ] && . "$CFG"

    [ "${ENABLE:-1}" = "0" ] && exit 0

    if [ -z "$TARGETS" ]; then
      TARGETS="$(autodetect_targets || true)"
    fi
    [ -z "$TARGETS" ] && exit 0

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
