## install.sh
rm -rf \
"/var/lib/dkms/${DKMS_NAME}" \
"/usr/src/${DKMS_NAME}-1.0" \
"${SRC_DST}"


info "Mirroring sources to ${SRC_DST}…"
rsync -a --delete --exclude ".git" ./ "${SRC_DST}/"
ok "Source staged at ${SRC_DST}."


info "Registering with DKMS…"
dkms add -m "${DKMS_NAME}" -v "${DKMS_VER}"


# ---------------------------
# 3) Build/install for each target kernel
# ---------------------------
built_any=0
for kv in "${TARGETS[@]}"; do
info "Building for ${kv}…"
if dkms build -m "${DKMS_NAME}" -v "${DKMS_VER}" -k "${kv}"; then
info "Installing for ${kv}…"
dkms install -m "${DKMS_NAME}" -v "${DKMS_VER}" -k "${kv}"
built_any=1
else
warn "Build failed for ${kv}."
fi
done


[[ $built_any -eq 1 ]] || die "No successful DKMS builds. Check headers and logs."


# ---------------------------
# 4) Verify + optional reload on the running kernel
# ---------------------------
info "modinfo (filename/version):"
/sbin/modinfo snd-hda-codec-cs8409 | egrep 'filename|version' || true


running_kv="$(uname -r)"
if printf '%s
' "${TARGETS[@]}" | grep -qx "${running_kv}"; then
if [[ $DO_RELOAD -eq 1 ]]; then
info "Reloading driver for running kernel (${running_kv})…"
modprobe -r snd_hda_codec_cs8409 2>/dev/null || true
if modprobe snd_hda_codec_cs8409 2>/dev/null; then
ok "Driver loaded for ${running_kv}."
else
warn "Module installed but not loaded for ${running_kv}. A reboot may be required."
fi
fi
else
warn "Built for ${TARGETS[*]} but current kernel is ${running_kv}. Reboot into a built target to activate."
fi


info "Recent dmesg lines (HDA/CS8409):"
dmesg | egrep -i 'cs8409|cirrus|hda' | tail -n 80 || true


bold "Installation finished."
# Offer reboot only if the running kernel was one of the targets and reload failed
if printf '%s
' "${TARGETS[@]}" | grep -qx "${running_kv}"; then
read -r -p $'
Do you want to reboot now to activate the audio driver? [y/N] ' yn || true
case "${yn:-N}" in
y|Y) info "Rebooting now…"; sleep 1; reboot ;;
*) ok "Reboot skipped. If audio is still missing, reboot later." ;;
esac
else
printf "
"
printf "If your *running* kernel (%s) is not among the built targets, please reboot into one of: %s.
" "$running_kv" "${TARGETS[*]}"
fi
```
