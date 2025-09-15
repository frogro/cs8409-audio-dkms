# CS8409 Audio DKMS (Debian/Ubuntu on Intel Macs)

This repository provides a **DKMS-based audio enablement** for Intel Macs (iMac, MacBook, Mac mini, iMac Pro, Mac Pro) that use **Cirrus Logic CS8409** HDA audio with a **CS42L42** companion codec — the common setup on many **T2‑era Macs (2018–2020)** running **Linux (Debian/Ubuntu)**.  
On these machines, users frequently hit **“no sound”** because the Linux kernel may lack **model‑specific initialization** and **resume quirks** out of the box. This project bundles **kernel‑compatible driver sources/patches** and installs them via **DKMS**, plus optional **resume workarounds**, to make audio **work reliably** across kernel updates and sleep/wake cycles.

- **Why this repo?** It is a **consolidation and forward‑evolution** of community efforts around CS8409/CS42L42 on T2 Macs. It **integrates and adapts** community driver code and small fixes, wrapped as a **DKMS module** so that audio **keeps working after kernel updates**, and adds a **suspend/resume fix** for the notorious “no audio after suspend” issue.
- **What you get**
  - **Sound out of the box** on supported Macs (speakers/headphones, HDA controls).
  - **DKMS auto‑rebuild** across kernel upgrades (solves “no sound after kernel update”).
  - Optional **resume fix** (“no sound after suspend”), using a minimal **systemd sleep hook** and recommended kernel parameters for s2idle on T2 hardware.
  - A clean uninstall path.

> This repository ships **no proprietary firmware**. It provides **source code and patches** for the HDA codec driver path and integrates them via **DKMS**. It also installs optional configuration to improve **suspend/resume** behavior on T2‑era Macs.

---

## Supported hardware (examples)

Intel Macs with **CS8409 + CS42L42** audio path, typically:
- **iMac 2019/2020** (`iMac19,1`, `iMac20,1`, `iMac20,2`)
- **MacBook Pro 2018–2020** (`MacBookPro15,x`, `MacBookPro16,x`)
- **Mac mini 2018** (`Macmini8,1`)
- **iMac Pro** (`iMacPro1,1`)

> The installer auto‑detects supported hardware. You can still proceed on similar machines; unsupported models will refuse to load or have missing nodes, in which case please open an issue with `dmesg` and `alsactl info` output.

---

## What the installer actually does

1. **Sanity checks & prerequisites**
   - Verifies **root** and that required tools and **kernel headers** are installed.
   - Detects a compatible Mac model and kernel version.

2. **Build & install via DKMS**
   - Registers the module (e.g. `snd-hda-codec-cs8409`) with **DKMS**.
   - Builds against your current kernel headers and **installs** it for **all installed kernels**.
   - Ensures automatic **rebuild on future kernel updates**.

3. **Enable runtime configuration**
   - Applies recommended **kernel parameters** for T2 audio stability (see below).
   - Optionally installs a **minimal systemd sleep hook** to avoid xHCI issues in `s2idle` and ensure audio comes back after suspend.

4. **Driver (re)load and verification**
   - Reloads HDA modules (`snd_hda_intel`, `snd_hda_codec_cs8409`, etc.).
   - Prints a short report (`aplay -l`, `dmesg | egrep -i 'cs8409|cs42l42|hda'`).

---

## Highlights (what makes this repo special)

- **No sound after kernel update?** Solved by **DKMS**: module auto‑rebuilds with every kernel install.
- **No sound after suspend/resume?** Mitigated by **s2idle + xHCI unbind/rebind hook** (optional) and recommended kernel parameters.
- **Better than piecing patches together**: this is a **curated, forward‑compatible** packaging of community improvements, with small integration fixes to keep it working on current kernels.

---

## Requirements

- **Debian 12/13** or **Ubuntu 22.04/24.04** (or newer)
- **Kernel headers** installed for your running kernel (e.g. `linux-headers-$(uname -r)`)
- Tools: `git`, `build-essential` (or `base-devel` equivalent), `dkms`, `kmod`, `rsync`, `patch`, `pciutils`, `alsa-utils`

Install helpers (Debian/Ubuntu):
```bash
sudo apt update
sudo apt install -y git build-essential dkms kmod rsync patch pciutils alsa-utils \
                    linux-headers-$(uname -r)
```

> **Secure Boot (Ubuntu/Debian)**: If Secure Boot is **enabled**, unsigned DKMS modules **won’t load**. Either **disable Secure Boot** in firmware, **or** enroll a **Machine Owner Key (MOK)** and sign the DKMS module. Ubuntu will typically prompt you to set a MOK password during dkms installation when Secure Boot is on.

---

## Quick start

```bash
git clone https://github.com/frogro/cs8409-audio-dkms
cd cs8409-audio-dkms
chmod +x install.sh
sudo ./install.sh
```

After installation, you should see devices under `aplay -l`. If audio is still muted, open **alsamixer** and check the output path.

---

## Recommended kernel parameters (T2 Macs)

Add these to your GRUB default (Debian/Ubuntu alike) to improve stability on T2 hardware:
```
snd_hda_intel.dmic_detect=0 mem_sleep_default=s2idle
```
Steps:
```bash
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash snd_hda_intel.dmic_detect=0 mem_sleep_default=s2idle"/' /etc/default/grub
sudo update-grub
```

> `dmic_detect=0` avoids conflicts with the T2 digital mic path, and `s2idle` improves suspend/resume behavior on these Macs.

---

## Suspend/resume fix (optional)

The installer can place a minimal **systemd sleep hook** (e.g. `/usr/lib/systemd/system-sleep/98-xhci-s2idle-unbind.sh`) that works around xHCI interaction with `s2idle`. This avoids **“no sound after second suspend”** patterns on some models.

To enable/disable the hook manually:
```bash
# enable (install or symlink the helper into system-sleep)
sudo cp extras/98-xhci-s2idle-unbind.sh /usr/lib/systemd/system-sleep/
sudo chmod +x /usr/lib/systemd/system-sleep/98-xhci-s2idle-unbind.sh

# disable
sudo rm -f /usr/lib/systemd/system-sleep/98-xhci-s2idle-unbind.sh
```

> If your distro uses a different sleep directory (rare), adjust accordingly (e.g. `/lib/systemd/system-sleep`).

---

## Ubuntu specifics

- **22.04 LTS (HWE)**: if you need a newer kernel, install **HWE**:
  ```bash
  sudo apt update
  sudo apt install -y linux-generic-hwe-22.04
  ```
- **Secure Boot**: if enabled, sign the DKMS module via MOK (Ubuntu’s dkms tooling will assist) or disable Secure Boot.
- **GRUB params & hook**: identical to Debian. Run the GRUB commands above; the sleep hook path is the same on Ubuntu.

---

## Uninstall / Revert

```bash
# Figure out the module name and version used by DKMS
dkms status | grep -i cs8409 || true

# Example (adjust -m/-v to your output):
sudo dkms remove -m snd-hda-codec-cs8409 -v 1.0 --all

# Unload and reload HDA stack (or reboot):
sudo modprobe -r snd_hda_codec_cs8409 snd_hda_codec snd_hda_intel || true
sudo modprobe snd_hda_intel && sudo modprobe snd_hda_codec && sudo modprobe snd_hda_codec_cs8409
```

Also revert optional configuration:
```bash
# Remove sleep hook if present
sudo rm -f /usr/lib/systemd/system-sleep/98-xhci-s2idle-unbind.sh

# (Optional) Revert GRUB params and run update-grub again
```

---

## Troubleshooting

- **No devices in `aplay -l`**
  - Ensure headers match your running kernel: `dpkg -l | grep linux-headers` and `uname -r`.
  - Check module is loaded: `lsmod | egrep 'cs8409|snd_hda_intel'`.
  - Look for errors: `dmesg | egrep -i 'cs8409|cs42l42|hda|firmware' | tail -n 80`.

- **No sound after suspend**
  - Ensure GRUB params include `mem_sleep_default=s2idle`.
  - Enable the **xHCI s2idle hook** (see above) and reboot once.

- **Module builds but does not load (Ubuntu)**
  - Likely **Secure Boot**: sign the module via **MOK** or disable Secure Boot.

- **Regression after kernel upgrade**
  - Run the installer again (`sudo ./install.sh`) so DKMS re‑syncs, or check `dkms status` for errors.

When reporting issues, include:
```
uname -r
lsmod | egrep 'cs8409|snd_hda_intel'
dmesg | egrep -i 'cs8409|cs42l42|hda|xHCI|suspend' | tail -n 120
aplay -l
sudo alsactl info
cat /etc/default/grub | grep GRUB_CMDLINE_LINUX_DEFAULT
```

---

## Sources integrated / Credits

This project builds upon and integrates work from:
- The **Linux kernel ALSA HDA** subsystem, including **`snd-hda-codec-cs8409`** and related Cirrus codec support.
- Multiple **community patches** and snippets improving initialization and suspend/resume on T2 Macs (CS8409 + CS42L42 path).
- Packaging and scripts authored here to make the above easy to install and maintain via **DKMS**.

> If you recognize specific patches you authored and would like explicit attribution, please open an issue/PR with the preferred credit line and source URL. We’re happy to add it.

---

## Security and integrity

This repo provides **open source code and patches** only. It does **not** include proprietary firmware. Source is compiled locally against your headers via **DKMS**.

---

## License

This repository contains components under **two licenses**:
- **Kernel‑adjacent code** (driver code, patches, anything under `src/` and `patches/`): **GPL‑2.0‑only** (to remain compatible with the Linux kernel and GPL‑only symbol usage).
- **Build/packaging scripts and docs** (e.g. `install.sh`, helper scripts in `extras/`, and this README): **MIT License**.

See the combined [`LICENSE`](./LICENSE) file for full texts and which paths each license applies to.

---

## Contributing

Issues and PRs are welcome. Please include logs (see **Troubleshooting**) and your distro/kernel details. Contributions should keep **DKMS compatibility** and **resume reliability** in mind.
