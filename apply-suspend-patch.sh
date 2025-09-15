#!/usr/bin/env bash
set -euo pipefail

need_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Re-running with sudo..." >&2
    exec sudo --preserve-env=PATH "$0" "$@"
  fi
}
need_root "$@"

echo "[apply-suspend-patch] Start"

# 2.1 GRUB-Erweiterung (idempotent) via /etc/default/grub.d Drop-in
GRUB_D_DIR=/etc/default/grub.d
GRUB_SNIPPET=$GRUB_D_DIR/99-cs8409-audio.conf
mkdir -p "$GRUB_D_DIR"

if [ ! -s "$GRUB_SNIPPET" ]; then
  cat >"$GRUB_SNIPPET" <<'EOF'
# Added by cs8409 installer: force s2idle & disable DMIC probe on HDA-Intel
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT snd_hda_intel.dmic_detect=0 mem_sleep_default=s2idle"
EOF
  echo "[apply-suspend-patch] wrote $GRUB_SNIPPET"
else
  echo "[apply-suspend-patch] $GRUB_SNIPPET exists (ok)"
fi

# 2.2 Minimalen xHCI-Hook installieren
HOOK=/usr/lib/systemd/system-sleep/98-xhci-s2idle-unbind.sh
install -D -m 0755 -T "$(dirname "$0")/system-sleep-98-xhci-s2idle-unbind.sh" "$HOOK" 2>/dev/null || {
  # Fallback: aus eingebettetem Here-Doc (falls Script lokal aufgerufen)
  cat >"$HOOK" <<'EOF'
#!/bin/sh
CFG=/etc/default/xhci-s2idle
LIST=/run/xhci-s2idle.bound
is_s2idle(){ grep -q '\[s2idle\]' /sys/power/mem_sleep 2>/dev/null; }
TARGETS="0000:08:00.0"
[ -r "$CFG" ] && . "$CFG"
case "$1/$2" in
  pre/*) is_s2idle || exit 0; : > "$LIST"; for dev in $TARGETS; do
           [ -e "/sys/bus/pci/devices/$dev/driver" ] || continue
           echo "$dev" >> "$LIST"
           echo "$dev" > /sys/bus/pci/drivers/xhci_hcd/unbind
         done ;;
  post/*) is_s2idle || exit 0; [ -r "$LIST" ] || exit 0
          while read -r dev; do
            [ -e "/sys/bus/pci/devices/$dev" ] || continue
            echo "$dev" > /sys/bus/pci/drivers/xhci_hcd/bind
          done < "$LIST"
          rm -f "$LIST" ;;
esac
EOF
  chmod +x "$HOOK"
}
echo "[apply-suspend-patch] hook at $HOOK"

# 2.3 /etc/default/xhci-s2idle automatisch befüllen (Nicht-PCH-xHCI)
CFG=/etc/default/xhci-s2idle
PCH="0000:00:14.0"
found=""
if [ -d /sys/bus/pci/drivers/xhci_hcd ]; then
  while IFS= read -r -d '' link; do
    slot=$(basename "$link")
    [ "$slot" = "$PCH" ] && continue
    found+=" $slot"
  done < <(find /sys/bus/pci/drivers/xhci_hcd -maxdepth 1 -type l -print0 | sort -z)
fi

mkdir -p "$(dirname "$CFG")"
if [ -n "$found" ]; then
  echo "TARGETS=\"${found# }\"" > "$CFG"
  echo "[apply-suspend-patch] config $CFG -> TARGETS=${found# }"
else
  # Kein Zusatz-xHCI gefunden – Standard 08:00.0 als Kommentar + Hinweis
  cat >"$CFG" <<'EOF'
# No non-PCH xHCI auto-detected. If your suspend/resume fails on s2idle,
# set your controller(s) here, e.g.:
# TARGETS="0000:08:00.0"
EOF
  echo "[apply-suspend-patch] no extra xHCI found; wrote commented template to $CFG"
fi

# 2.4 GRUB neu schreiben
if command -v update-grub >/dev/null 2>&1; then
  update-grub
else
  grub-mkconfig -o /boot/grub/grub.cfg
fi
echo "[apply-suspend-patch] done"
