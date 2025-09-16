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

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
CFG_DIR="/etc/default"
CFG_FILE="${CFG_DIR}/xhci-s2idle"
choose_sleep_dir() {
  for d in /usr/lib/systemd/system-sleep /lib/systemd/system-sleep; do
    # prefer existing dir; otherwise try to create it
    if [ -d "$d" ] || mkdir -p "$d" 2>/dev/null; then
      echo "$d"
      return 0
    fi
  done
  # fallback – should exist on essentially all modern usrmerge systems
  echo "/usr/lib/systemd/system-sleep"
}

HOOK_DIR="$(choose_sleep_dir)"
HOOK_DST="${HOOK_DIR}/98-xhci-s2idle-unbind.sh"
HOOK_SRC="${SCRIPT_DIR}/hooks/98-xhci-s2idle-unbind.sh"
FALLBACK_SRC="${SCRIPT_DIR}/tools/98-xhci-s2idle-unbind.fallback.sh"

ensure_grub_flags() {
  local f="/etc/default/grub"
  [[ -r "$f" ]] || die "$f not readable"
  # read current line (inside quotes)
  local cur; cur="$(sed -nE 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)".*/\1/p' "$f")"
  # flags we need (dmic_detect ist veraltet → dsp_driver=1)
  local need=("snd-intel-dspcfg.dsp_driver=1" "mem_sleep_default=s2idle")
  local new="$cur"
  for fl in "${need[@]}"; do
    if [[ "$new" != *"$fl"* ]]; then
      new="$new $fl"
    fi
  done
  # trim
  new="$(echo "$new" | xargs)"
  if [[ "$new" != "$cur" ]]; then
    info "GRUB flags ensuring…"
    sed -i -E 's|^GRUB_CMDLINE_LINUX_DEFAULT=".*"|GRUB_CMDLINE_LINUX_DEFAULT="'"$new"'"|' "$f"
    ok "GRUB flags set: $new"
    if command -v update-grub >/dev/null 2>&1; then
      update-grub
    else
      grub-mkconfig -o /boot/grub/grub.cfg
    fi
  else
    ok "GRUB flags already present: $cur"
  fi
}

list_xhci() {
  # Listet alle xHCI-Geräte (Klasse 0x0c0330) als PCI-BDF
  local d c
  for d in /sys/bus/pci/devices/*; do
    [[ -r "$d/class" ]] || continue
    c="$(cat "$d/class")"
    [[ "$c" == "0x0c0330" ]] || continue
    basename "$d"
  done
}

detect_targets() {
  # bevorzugt non-PCH (≠ 0000:00:14.0); sonst PCH, sonst leer
  local all nonpch pch="0000:00:14.0" out=""
  mapfile -t all < <(list_xhci || true)
  if [[ ${#all[@]} -eq 0 ]]; then
    echo ""
    return 0
  fi
  mapfile -t nonpch < <(printf '%s\n' "${all[@]}" | grep -v -E '^0000:00:14\.0$' || true)
  if [[ ${#nonpch[@]} -gt 0 ]]; then
    out="$(printf '%s ' "${nonpch[@]}" | xargs)"
  elif [[ -e "/sys/bus/pci/devices/$pch" ]]; then
    out="$pch"
  fi
  echo "$out"
}

install_hook() {
  install -d -m 0755 -o root -g root "$(dirname "$HOOK_DST")"
  if [[ -r "$HOOK_SRC" ]]; then
    info "Installing hook from repo: $HOOK_SRC"
    install -m 0755 -o root -g root "$HOOK_SRC" "$HOOK_DST"
  else
    warn "Repo hook not found, using embedded fallback"
    # Schreibe eine geprüfte Fallback-Version (identisch zur Repo-Version)
    cat > "$HOOK_DST" <<'SH'
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
SH
    chmod 0755 "$HOOK_DST"
  fi
  ok "Installed hook to $HOOK_DST"
}

write_cfg() {
  local targets="$1"
  install -d -m 0755 -o root -g root "$CFG_DIR"
  cat > "$CFG_FILE" <<EOF
# Config for 98-xhci-s2idle-unbind.sh
# ENABLE: 1=active, 0=disabled
ENABLE=1
# TARGETS: space-separated PCI BDFs; leave empty to auto-detect
TARGETS="${targets}"
# Examples:
# TARGETS="0000:00:14.0"
# TARGETS="0000:00:14.0 0000:08:00.0"
EOF
  chmod 0644 "$CFG_FILE"
  ok "Created ${CFG_FILE} (edit TARGETS if needed)"
}

### main
bold "Applying suspend patch (s2idle + xHCI hook)…"
ensure_grub_flags
install_hook

tgt="$(detect_targets || true)"
if [[ -z "$tgt" ]]; then
  warn "Could not detect an xHCI controller automatically; leaving TARGETS empty (hook will fallback at runtime)."
else
  info "Auto-detected xHCI TARGETS: $tgt"
fi
write_cfg "$tgt"
ok "Suspend patch applied"
