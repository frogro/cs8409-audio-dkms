#!/usr/bin/env bash
# Apply suspend patch: set GRUB flags + install xHCI s2idle hook (with autodetect hint)
set -euo pipefail
IFS=$'\n\t'

need_root(){ if [[ ${EUID:-$(id -u)} -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi; }
need_root "$@"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="${REPO_DIR}/hooks/98-xhci-s2idle-unbind.sh"
HOOK_DST="/usr/lib/systemd/system-sleep/98-xhci-s2idle-unbind.sh"
CFG_DST="/etc/default/xhci-s2idle"
CFG_TEMPLATE="${REPO_DIR}/etc/xhci-s2idle.default"

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
info(){ printf "• %s\n" "$*"; }
ok(){ printf "[OK] %s\n" "$*"; }
warn(){ printf "[WARN] %s\n" "$*"; }

# ---- GRUB flags (modern) ----
ensure_grub_flags(){
  local grub=/etc/default/grub
  [[ -r "$grub" ]] || { warn "$grub not found, skipping GRUB changes"; return 0; }
  cp -a "$grub" "${grub}.bak.$(date +%Y%m%d-%H%M%S)"

  # modern flag replaces legacy dmic_detect
  local want_dsp="snd-intel-dspcfg.dsp_driver=1"
  local want_s2i="mem_sleep_default=s2idle"

  # remove any legacy dmic_detect=... everywhere in file
  sed -i -E 's/\bsnd_hda_intel\.dmic_detect=[0-9]\b//g' "$grub"
  # cleanup double spaces that may result
  sed -i -E 's/  +/ /g' "$grub"

  # ensure in GRUB_CMDLINE_LINUX_DEFAULT
  if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub"; then
    # extract, add if missing
    local val
    val="$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' "$grub")"
    [[ "$val" == *"$want_dsp"* ]] || val="$val $want_dsp"
    [[ "$val" == *"$want_s2i"* ]] || val="$val $want_s2i"
    val="$(echo "$val" | sed -E 's/^ +| +$//g' )"
    sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${val}\"|" "$grub"
  else
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash $want_dsp $want_s2i\"" >> "$grub"
  fi
  ok "GRUB flags ensured: $want_dsp $want_s2i"

  if command -v update-grub >/dev/null 2>&1; then
    update-grub
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
  else
    warn "Neither update-grub nor grub-mkconfig found; regenerate GRUB config manually"
  fi
}

# ---- Detect non-PCH xHCI (for info hint in /etc/default/xhci-s2idle) ----
detect_targets(){
  command -v lspci >/dev/null 2>&1 || { echo ""; return 0; }
  # list all xHCI USB controllers, then drop PCH 0000:00:14.0
  local out
  out="$(lspci -Dnn | awk 'tolower($0) ~ /usb controller/ && tolower($0) ~ /xhci/ {print $1}')"
  echo "$out" | grep -v '^0000:00:14\.0$' || true
}

# ---- Install hook & config ----
install_hook(){
  install -D -m 0755 "$HOOK_SRC" "$HOOK_DST"
  ok "Installed hook to $HOOK_DST"

  if [[ ! -e "$CFG_DST" ]]; then
    install -D -m 0644 "$CFG_TEMPLATE" "$CFG_DST"
    local t; t="$(detect_targets | tr '\n' ' ' | sed -E 's/ +$//')"
    if [[ -n "$t" ]]; then
      printf "\n# Auto-detected non-PCH xHCI on this machine (for reference):\n# TARGETS=\"%s\"\n" "$t" >> "$CFG_DST"
    fi
    ok "Created $CFG_DST (edit TARGETS if needed)"
  else
    info "$CFG_DST already exists; leaving as-is"
  fi
}

# ---- Make s2idle active immediately (optional) ----
set_runtime_s2idle(){
  if [[ -w /sys/power/mem_sleep ]] && grep -q '\[deep\]' /sys/power/mem_sleep; then
    echo s2idle > /sys/power/mem_sleep || true
  fi
}

bold "Applying suspend patch (s2idle + xHCI hook)…"
ensure_grub_flags
install_hook
set_runtime_s2idle
ok "Suspend patch applied"
