#!/usr/bin/env bash
# Apply suspend patch: GRUB flags + install xHCI s2idle hook with fallback autodetect
# - Ensures GRUB flags: snd-intel-dspcfg.dsp_driver=1 mem_sleep_default=s2idle
# - Installs hook from repo (hooks/98-xhci-s2idle-unbind.sh) or inline fallback (identisch)
# - Writes /etc/default/xhci-s2idle with robust autodetected TARGETS (so dass es "passt")
# - Hook selbst behält seine Autodetektion als Fallback bei (Logik unverändert)

set -euo pipefail
IFS=$'\n\t'

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
info(){ printf "• %s\n" "$*"; }
ok(){ printf "[OK] %s\n" "$*"; }
warn(){ printf "[WARN] %s\n" "$*"; }
die(){ printf '[ERR] %s\n' "$*" >&2; exit 1; }

need_root(){ if [[ ${EUID:-$(id -u)} -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi; }
need_root "$@"

GRUB_DEF="/etc/default/grub"
GRUB_FLAGS=("snd-intel-dspcfg.dsp_driver=1" "mem_sleep_default=s2idle")

HOOK_DST="/usr/lib/systemd/system-sleep/98-xhci-s2idle-unbind.sh"
HOOK_SRC_REL="hooks/98-xhci-s2idle-unbind.sh"
CONF_PATH="/etc/default/xhci-s2idle"

install -d -m 0755 -o root -g root "$(dirname "$HOOK_DST")" /etc/default

ensure_grub_flags() {
  [[ -f "$GRUB_DEF" ]] || die "$GRUB_DEF not found"

  local cur line new f
  line="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_DEF" || true)"
  if [[ -n "$line" ]]; then
    cur="${line#GRUB_CMDLINE_LINUX_DEFAULT=\"}"
    cur="${cur%\"}"
  else
    cur=""
    echo 'GRUB_CMDLINE_LINUX_DEFAULT=""' >> "$GRUB_DEF"
  fi

  new="$cur"
  for f in "${GRUB_FLAGS[@]}"; do
    if ! grep -Eq "(^|[[:space:]])${f//\//\\/}([[:space:]]|\$)" <<<"$new"; then
      new="$new $f"
    fi
  done
  new="${new#" "}"

  if [[ "$new" != "$cur" ]]; then
    sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${new}\"|" "$GRUB_DEF"
    ok "GRUB flags ensured: ${GRUB_FLAGS[*]}"
    info "Updating GRUB…"
    if command -v update-grub >/dev/null 2>&1; then
      update-grub >/dev/null
    else
      grub-mkconfig -o /boot/grub/grub.cfg >/dev/null
    fi
  else
    ok "GRUB already contains required flags"
  fi
}

hook_fallback_body() {
cat <<'HOOK'
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
  for d in /sys/bus/pci/devices/0000:* 2>/dev/null; do
    [ -e "$d/class" ] || continue
    [ "$(cat "$d/class" 2>/dev/null)" = "0x0c0330" ] || continue
    dev=$(basename "$d")
    [ "$dev" = "0000:00:14.0" ] && continue
    printf '%s\n' "$dev"
    return 0
  done
  if [ -e /sys/bus/pci/devices/0000:00:14.0 ]; then
    printf '%s\n' "0000:00:14.0"
    return 0
  fi
  return 1
}

case "$1/$2" in
  pre/*)
    is_s2idle || exit 0
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
HOOK
}

install_hook() {
  if [[ -f "$HOOK_SRC_REL" ]]; then
    install -m 0755 -o root -g root "$HOOK_SRC_REL" "$HOOK_DST"
  else
    local tmp; tmp="$(mktemp)"
    hook_fallback_body > "$tmp"
    install -m 0755 -o root -g root "$tmp" "$HOOK_DST"
    rm -f "$tmp"
  fi
  ok "Installed hook to $HOOK_DST"
}

detect_targets_for_conf() {
  # identisch zur Logik im Hook, aber wir dürfen mehrere Kandidaten evaluieren
  local d dev
  # 1) gebundene xhci (non-PCH bevorzugt)
  for d in /sys/bus/pci/drivers/xhci_hcd/0000:* 2>/dev/null; do
    [ -e "$d" ] || continue
    dev=$(basename "$d")
    [ "$dev" = "0000:00:14.0" ] && continue
    printf '%s\n' "$dev"
    return 0
  done
  # 2) PCI-Class Fallback (non-PCH bevorzugt)
  for d in /sys/bus/pci/devices/0000:* 2>/dev/null; do
    [ -e "$d/class" ] || continue
    [ "$(cat "$d/class" 2>/dev/null)" = "0x0c0330" ] || continue
    dev=$(basename "$d")
    [ "$dev" = "0000:00:14.0" ] && continue
    printf '%s\n' "$dev"
    return 0
  done
  # 3) PCH als letzter Ausweg
  if [[ -e /sys/bus/pci/devices/0000:00:14.0 ]]; then
    printf '%s\n' "0000:00:14.0"
    return 0
  fi
  return 1
}

write_conf() {
  local tgt="$1" tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<EOF
# xhci-s2idle config
# ENABLE=1 -> aktiv; ENABLE=0 -> ausgeschaltet (Hook macht no-op)
# TARGETS: Space-separated PCI IDs von xHCI-Controllern, die bei s2idle unbind/bind bekommen sollen.
# Wenn leer, nimmt der Hook seine eigene Fallback-Autodetektion (non-PCH bevorzugt).
ENABLE=1
TARGETS="${tgt}"
EOF
  install -m 0644 -o root -g root "$tmp" "$CONF_PATH"
  rm -f "$tmp"
  ok "Created ${CONF_PATH} (edit ENABLE/TARGETS if needed)"
}

bold "Applying suspend patch (s2idle + xHCI hook)…"
ensure_grub_flags
install_hook
tgt="$(detect_targets_for_conf || true)"
write_conf "${tgt}"
ok "Suspend patch applied"
