#!/usr/bin/env bash
# apply-suspend-patch.sh
# Richtet s2idle-Workaround + GRUB-Args ein:
#  - erkennt Nicht-PCH-xHCI (alles außer 0000:00:14.0)
#  - schreibt /etc/default/xhci-s2idle (TARGETS)
#  - installiert minimalen Hook /etc/systemd/system-sleep/98-xhci-s2idle-unbind.sh
#  - ergänzt GRUB um: snd_hda_intel.dmic_detect=0 mem_sleep_default=s2idle

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Bitte als root ausführen (sudo)"; exit 1; }

CFG=/etc/default/xhci-s2idle
HOOK=/etc/systemd/system-sleep/98-xhci-s2idle-unbind.sh

detect_targets() {
  # Liste aktuell an xhci_hcd gebundener Geräte, excl. PCH (00:14.0)
  local devs t
  [ -d /sys/bus/pci/drivers/xhci_hcd ] || return 0
  devs=$(ls -1 /sys/bus/pci/drivers/xhci_hcd 2>/dev/null | grep -E '^0000:' || true)
  for t in $devs; do
    [ "$t" = "0000:00:14.0" ] && continue
    echo "$t"
  done
}

ensure_grub_arg() {
  local key="$1" val="$2" file="/etc/default/grub"
  grep -qE '^\s*GRUB_CMDLINE_LINUX_DEFAULT=' "$file" || \
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> "$file"
  grep -qE "(^|\s)${key}(=|$)" "$file" || \
    sed -i "s/^\s*GRUB_CMDLINE_LINUX_DEFAULT=\"/&${key}=${val} /" "$file"
}

write_cfg() {
  local targets="$1"
  install -Dm644 /dev/stdin "$CFG" <<EOF
# xHCI-Controller, die bei s2idle vor dem Suspend unbound und danach wieder bound werden.
# Automatisch erkannt (Nicht-PCH). Manuell anpassbar.
TARGETS="${targets}"
EOF
  echo "[OK] Config: $CFG (TARGETS=${targets})"
}

install_hook() {
  install -Dm755 /dev/stdin "$HOOK" <<'EOF'
#!/bin/sh
# 98-xhci-s2idle-unbind.sh — minimaler Unbind/Bind nur bei s2idle
CFG=/etc/default/xhci-s2idle
LIST=/run/xhci-s2idle.bound
is_s2idle() { grep -q '\[s2idle\]' /sys/power/mem_sleep 2>/dev/null; }

TARGETS=""
[ -r "$CFG" ] && . "$CFG"

case "$1/$2" in
  pre/*)
    is_s2idle || exit 0
    : > "$LIST"
    for dev in $TARGETS; do
      [ -e "/sys/bus/pci/devices/$dev/driver" ] || continue
      echo "xhci-unbind $dev" | logger -t xhci-s2idle
      echo "$dev" >> "$LIST"
      echo "$dev" > /sys/bus/pci/drivers/xhci_hcd/unbind
    done
    ;;
  post/*)
    is_s2idle || exit 0
    [ -r "$LIST" ] || exit 0
    while read -r dev; do
      [ -e "/sys/bus/pci/devices/$dev" ] || continue
      echo "xhci-bind $dev" | logger -t xhci-s2idle
      echo "$dev" > /sys/bus/pci/drivers/xhci_hcd/bind
    done < "$LIST"
    rm -f "$LIST"
    ;;
esac
EOF
  echo "[OK] Hook: $HOOK"
}

# 1) xHCI-Ziele erkennen
targets="$(detect_targets || true)"
if [ -z "$targets" ]; then
  echo "[HINW] Kein Nicht-PCH-xHCI erkannt. Hook bleibt aktiv, TARGETS leer → no-op."
fi

# 2) Config + Hook schreiben
write_cfg "$targets"
install_hook

# 3) GRUB-Args ergänzen
ensure_grub_arg "snd_hda_intel.dmic_detect" "0"
ensure_grub_arg "mem_sleep_default" "s2idle"
if command -v update-grub >/dev/null 2>&1; then
  update-grub >/dev/null || true
else
  grub-mkconfig -o /boot/grub/grub.cfg >/dev/null || true
fi
echo "[OK] GRUB-Parameter gesetzt (dmic_detect=0, mem_sleep_default=s2idle)"

cat <<MSG

Fertig:
- Hook aktiv (nur bei s2idle): $HOOK
- Konfig anpassbar:            $CFG
- GRUB ergänzt:                snd_hda_intel.dmic_detect=0 mem_sleep_default=s2idle

Bitte neu starten und s2idle zweimal testen.
MSG
