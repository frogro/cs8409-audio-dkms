#!/usr/bin/env bash
# Apply suspend patch: GRUB flags + install xHCI s2idle hook with fallback autodetect
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

# ---- GRUB flags ----
ensure_grub_flags(){
  local grub=/etc/default/grub
  [[ -r "$grub" ]] || { warn "$grub not found, skipping GRUB changes"; return 0; }
  cp -a "$grub" "${grub}.bak.$(date +%Y%m%d-%H%M%S)"

  local need1="snd_hda_intel.dmic_detect=0"
  local need2="mem_sleep_default=s2idle"

  local line
  line="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub" || true)"
  if [[ -z "$line" ]]; then
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash $need1 $need2\"" >> "$grub"
    ok "Added GRUB_CMDLINE_LINUX_DEFAULT with required flags"
  else
    # Extract content in quotes
    local val
    val="$(echo "$line" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/\1/')"
    if [[ "$val" != *"$need1"* ]]; then val="$val $need1"; fi
    if [[ "$val" != *"$need2"* ]]; then val="$val $need2"; fi
    # Replace the line
    sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${val}\"|" "$grub"
    ok "Ensured GRUB flags present"
  fi

  if command -v update-grub >/dev/null 2>&1; then
    update-grub
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
  else
    warn "Neither update-grub nor grub-mkconfig found; please regenerate GRUB config manually"
  fi
}

# ---- Detect xHCI targets (non-PCH) ----
detect_targets(){
  if ! command -v lspci >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  local out
  out="$(lspci -Dnns | awk '/ USB controller: / && tolower($0) ~ /xhci/ {print $1}')"
  # remove PCH 00:14.0 if present
  out="$(echo "$out" | grep -v '^0000:00:14\.0$' || true)"
  echo "$out"
}

# ---- Install hook & config ----
install_hook(){
  install -D -m 0755 "$HOOK_SRC" "$HOOK_DST"
  ok "Installed hook to $HOOK_DST"

  if [[ ! -e "$CFG_DST" ]]; then
    install -D -m 0644 "$CFG_TEMPLATE" "$CFG_DST"
    # Fill auto-detected targets as a commented hint
    local t; t="$(detect_targets | tr '\n' ' ' | sed -E 's/ +$//')"
    if [[ -n "$t" ]]; then
      printf "\n# Auto-detected non-PCH xHCI on this machine (for reference):\n# TARGETS=\"%s\"\n" "$t" >> "$CFG_DST"
    fi
    ok "Created $CFG_DST (you can edit TARGETS if needed)"
  else
    info "$CFG_DST already exists; leaving as-is"
  fi
}

# ---- Ensure s2idle default immediately (optional runtime switch) ----
set_runtime_s2idle(){
  if [[ -w /sys/power/mem_sleep ]]; then
    if grep -q '\[deep\]' /sys/power/mem_sleep; then
      echo s2idle > /sys/power/mem_sleep || true
    fi
  fi
}

bold "Applying suspend patch (s2idle + xHCI hook)…"
ensure_grub_flags
install_hook
set_runtime_s2idle
ok "Suspend patch applied"
