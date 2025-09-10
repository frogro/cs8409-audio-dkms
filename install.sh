#!/usr/bin/env bash
# CS8409 DKMS one-click installer (Debian 12/13)
# - Builds for running kernel by default; supports --kver / --all-installed
# - Mirrors sources (this dir) to /usr/src/snd-hda-codec-cs8409-1.0+dkms/
# - Registers with DKMS, builds, installs, and (optionally) reloads
# - Requires: build-essential, dkms, kmod, rsync, linux-headers-<kver>
# - AUTOINSTALL="yes" in dkms.conf ensures automatic rebuilds on kernel updates

set -euo pipefail
IFS=$'\n\t'

# ---------- helpers ----------
bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
info(){ printf "• %s\n" "$*"; }
ok(){ printf "[OK] %s\n" "$*"; }
warn(){ printf "[WARN] %s\n" "$*"; }
die(){ printf '[ERR] %s\n' "$*" >&2; exit 1; }

need_root(){ if [[ ${EUID:-$(id -u)} -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi; }
trap 'rc=$?; [[ $rc -ne 0 ]] && printf "\n[ERR] Aborted (exit %d)\n" "$rc"' EXIT

need_root "$@"

# ---------- config ----------
DKMS_NAME="snd-hda-codec-cs8409"
DKMS_VER="1.0+dkms"      # must match dkms.conf PACKAGE_VERSION
SRC_DST="/usr/src/${DKMS_NAME}-${DKMS_VER}"
TARGETS=()
DO_RELOAD=1

# ---------- args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kver) [[ $# -lt 2 ]] && die "--kver requires a value"; TARGETS+=("$2"); shift 2 ;;
    --all-installed) mapfile -t TARGETS < <(basename -a /lib/modules/* 2>/dev/null || true); shift ;;
    --no-reload) DO_RELOAD=0; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: sudo ./install.sh [--kver <ver>]... [--all-installed] [--no-reload]
Default: build for the running kernel
USAGE
      exit 0 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ ${#TARGETS[@]} -gt 0 ]] || TARGETS=("$(uname -r)")

bold "CS8409 DKMS installer (auto-rebuild via DKMS AUTOINSTALL=yes)"
info "Targets: ${TARGETS[*]}"

# ---------- deps ----------
export DEBIAN_FRONTEND=noninteractive
info "Installing prerequisites…"
apt-get update -y
apt-get install -y build-essential dkms kmod rsync

for kv in "${TARGETS[@]}"; do
  if apt-get install -y "linux-headers-${kv}"; then
    ok "Headers for ${kv}"
  else
    warn "No headers for ${kv}"
  fi
done

# ---------- ensure DKMS tree exists & is writable (NEW) ----------
if [[ ! -d /var/lib/dkms ]]; then
  info "Creating /var/lib/dkms …"
  install -d -m 0755 -o root -g root /var/lib/dkms
fi
if ! touch /var/lib/dkms/.writetest 2>/dev/null; then
  warn "/var/lib/dkms not writable; attempting dkms reinstall …"
  apt-get --reinstall install -y dkms
  # retry
  if ! touch /var/lib/dkms/.writetest 2>/dev/null; then
    die "/var/lib/dkms is still not writable after dkms reinstall. Check filesystem permissions/mount."
  fi
fi
rm -f /var/lib/dkms/.writetest

# ---------- sanity ----------
[[ -f dkms.conf ]] || die "dkms.conf not found in current directory. Run from repo root."
[[ -f Makefile   ]] || die "Makefile not found in current directory. Run from repo root."

# ---------- clean & stage ----------
info "Cleaning previous DKMS state…"
dkms remove -m "${DKMS_NAME}" -v 1.0 --all || true
dkms remove -m "${DKMS_NAME}" -v "${DKMS_VER}" --all || true
rm -rf "/var/lib/dkms/${DKMS_NAME}" "/usr/src/${DKMS_NAME}-1.0" "${SRC_DST}"

info "Mirroring sources to ${SRC_DST}…"
rsync -a --delete --exclude ".git" ./ "${SRC_DST}/"
ok "Source staged"

info "Registering with DKMS…"
dkms add -m "${DKMS_NAME}" -v "${DKMS_VER}"

# ---------- build/install ----------
built_any=0
for kv in "${TARGETS[@]}"; do
  info "Building for ${kv}…"
  if dkms build -m "${DKMS_NAME}" -v "${DKMS_VER}" -k "${kv}"; then
    info "Installing for ${kv}…"
    dkms install -m "${DKMS_NAME}" -v "${DKMS_VER}" -k "${kv}"
    built_any=1
  else
    warn "Build failed for ${kv}"
  fi
done
[[ $built_any -eq 1 ]] || die "No successful DKMS builds"

# ---------- verify & optional reload ----------
info "modinfo (filename/version):"
/sbin/modinfo snd-hda-codec-cs8409 2>/dev/null | egrep 'filename|version' || true

running_kv="$(uname -r)"
if printf '%s\n' "${TARGETS[@]}" | grep -qx "${running_kv}"; then
  if [[ $DO_RELOAD -eq 1 ]]; then
    info "Reloading driver on ${running_kv}…"
    modprobe -r snd_hda_codec_cs8409 2>/dev/null || true
    if modprobe snd_hda_codec_cs8409 2>/dev/null; then
      ok "Driver loaded"
    else
      warn "Load failed (reboot may be needed)"
    fi
  fi
else
  warn "Built for: ${TARGETS[*]}, running: ${running_kv}. Reboot into a built target to activate."
fi

info "Recent dmesg (HDA/CS8409):"
dmesg | egrep -i 'cs8409|cirrus|hda' | tail -n 80 || true

bold "Installation finished."
if printf '%s\n' "${TARGETS[@]}" | grep -qx "${running_kv}"; then
  read -r -p $'\nDo you want to reboot now to activate the audio driver? [y/N] ' yn || true
  case "${yn:-N}" in
    y|Y) info "Rebooting…"; sleep 1; reboot ;;
    *)   ok "Reboot skipped." ;;
  esac
else
  printf "\nIf your *running* kernel (%s) is not among the built targets, please reboot into one of: %s.\n" "$running_kv" "${TARGETS[*]}"
fi
