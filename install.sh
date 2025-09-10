#!/usr/bin/env bash
# install.sh — CS8409 DKMS one‑click installer (Debian 12)
#
# Repo intent:
#  - You cloned or curl|bash'ed this repo which contains the module sources from
#    https://github.com/egorenar/snd-hda-codec-cs8409 (plus optimized Makefile + dkms.conf).
#  - This script installs build deps + headers, registers DKMS, builds for a fixed
#    target kernel (6.1.0-15-amd64), installs the module under /updates/dkms,
#    reloads the driver and optionally reboots.
#
# Notes:
#  - DKMS PACKAGE_NAME stays "snd-hda-codec-cs8409"; the *repo* can be named
#    "cs8409-dkms-wrapper". The source will be mirrored to
#    /usr/src/snd-hda-codec-cs8409-1.0+dkms/
#  - If you need a different exact kernel build target, edit KVER_TARGET below.
#
# Usage examples:
#   curl -fsSL https://raw.githubusercontent.com/<you>/cs8409-dkms-wrapper/main/install.sh | bash
#   # or after cloning:
#   sudo bash ./install.sh

set -euo pipefail
IFS=$'\n\t'

# ---------------------------
# Config
# ---------------------------
KVER_TARGET="6.1.0-15-amd64"              # explicit build target as requested
PKG_HEADERS="linux-headers-${KVER_TARGET}" # header package to install
DKMS_NAME="snd-hda-codec-cs8409"
DKMS_VER="1.0+dkms"                        # must match dkms.conf PACKAGE_VERSION
SRC_DST="/usr/src/${DKMS_NAME}-${DKMS_VER}"

# ---------------------------
# UI helpers
# ---------------------------
bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
info(){ printf "• %s\n" "$*"; }
ok(){ printf "✅ %s\n" "$*"; }
warn(){ printf "⚠️  %s\n" "$*"; }
die(){ printf '❌ %s\n' "$*" >&2; exit 1; }

need_root(){ if [[ ${EUID:-$(id -u)} -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi; }
trap 'rc=$?; [[ $rc -ne 0 ]] && printf "\n❌ Aborted (exit %d)\n" "$rc"' EXIT

# Re-exec as root if needed
need_root "$@"

bold "CS8409 DKMS installer (target: ${KVER_TARGET})"

# ---------------------------
# 1) Headers & tools
# ---------------------------
info "Updating APT and installing build deps + headers…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  build-essential dkms kmod \
  "${PKG_HEADERS}"
ok "Build deps + ${PKG_HEADERS} present."

# Sanity check for dkms.conf + Makefile in the repo root
if [[ ! -f dkms.conf ]]; then
  die "dkms.conf not found in current directory. Please run from repo root that contains module sources."
fi
if [[ ! -f Makefile ]]; then
  die "Makefile not found in current directory. Please run from repo root that contains module sources."
fi

# ---------------------------
# 2) Clean DKMS and register fresh source
# ---------------------------
info "Cleaning previous DKMS state (if any)…"
# Remove old registrations/trees (ignore errors)
dkms remove -m "${DKMS_NAME}" -v 1.0 --all || true
dkms remove -m "${DKMS_NAME}" -v "${DKMS_VER}" --all || true
rm -rf \
  "/var/lib/dkms/${DKMS_NAME}" \
  "/usr/src/${DKMS_NAME}-1.0" \
  "/usr/src/${DKMS_NAME}-${DKMS_VER}"

# Mirror the current repo (excluding .git) into /usr/src
info "Mirroring module sources to ${SRC_DST}…"
rsync -a --delete --exclude ".git" ./ "${SRC_DST}/"
ok "Source staged at ${SRC_DST}."

# ---------------------------
# 3) DKMS add/build/install for *exact* kernel ${KVER_TARGET}
# ---------------------------
info "Registering source with DKMS…"
dkms add -m "${DKMS_NAME}" -v "${DKMS_VER}"

info "Building module via DKMS for ${KVER_TARGET}…"
dkms build -m "${DKMS_NAME}" -v "${DKMS_VER}" -k "${KVER_TARGET}"

info "Installing module via DKMS for ${KVER_TARGET}…"
dkms install -m "${DKMS_NAME}" -v "${DKMS_VER}" -k "${KVER_TARGET}"

# Verify where the module landed
info "Verifying installed module path/version…"
if ! /sbin/modinfo snd-hda-codec-cs8409 2>/dev/null | egrep -q "filename|version"; then
  die "modinfo did not return data for snd-hda-codec-cs8409. Build/install likely failed."
fi
/sbin/modinfo snd-hda-codec-cs8409 | egrep 'filename|version' || true
# Expect e.g.:
#  filename: /lib/modules/6.1.0-15-amd64/updates/dkms/snd-hda-codec-cs8409.ko
#  version:  1.0+dkms
ok "DKMS module present."

# ---------------------------
# 4) Reload driver now (best-effort) and show recent logs
# ---------------------------
info "Reloading driver (best‑effort)…"
modprobe -r snd_hda_codec_cs8409 2>/dev/null || true
if modprobe snd_hda_codec_cs8409 2>/dev/null; then
  ok "Driver loaded for the *running* kernel ($(uname -r)) if compatible."
else
  warn "Could not load module into the running kernel ($(uname -r)). This is expected if it was built for ${KVER_TARGET}. A reboot into ${KVER_TARGET} will activate it."
fi

info "Last 80 dmesg lines related to HDA/CS8409:"
dmesg | egrep -i 'cs8409|cirrus|hda' | tail -n 80 || true

# ---------------------------
# 5) Offer reboot
# ---------------------------
printf "\n"
bold "Installation finished."
cat <<EOF
If your *running* kernel is not ${KVER_TARGET}, please reboot into that kernel
so the DKMS module under /updates/dkms is used. Audio will only work after the
first boot with the installed module.
EOF

read -r -p $'\nDo you want to reboot now to activate the audio driver? [y/N] ' yn || true
case "${yn:-N}" in
  y|Y)
    info "Rebooting now…"
    sleep 1
    reboot
    ;;
  *)
    ok "Reboot skipped. Remember to reboot into ${KVER_TARGET}."
    ;;
esac
