# CS8409 Audio DKMS (Debian/Ubuntu on Intel Macs)

This repository provides a **DKMS-based audio enablement** for Intel Macs (iMac, MacBook, Mac mini, iMac Pro, Mac Pro) that use **Cirrus Logic CS8409** HDA audio with a **CS42L42** companion codec — the common setup on many **T2‑era Macs (2018–2020)** running **Linux (Debian/Ubuntu)**.
On these machines, users frequently hit **“no sound”** because the Linux kernel may lack **model‑specific initialization** and **resume quirks** out of the box. This project bundles **kernel‑compatible driver sources** and installs them via **DKMS**, plus an optional **resume workaround**, to make audio **work reliably** across kernel updates and sleep/wake cycles.

- **Why this repo?** It is a **consolidation and forward‑evolution** of existing **community solutions** for CS8409/CS42L42 on T2 Macs. It **integrates** community driver work and adds small glue fixes, wrapped as a **DKMS module** so that audio **keeps working after kernel updates** — and includes a **suspend/resume fix** for the notorious “no audio after suspend” issue.
- **What you get**
  - **Sound out of the box** on supported Macs (speakers/headphones, HDA controls).
  - **DKMS auto‑rebuild** across kernel upgrades (solves “no sound after kernel update”).
  - Optional **resume fix** (“no sound after suspend”) via a minimal **systemd sleep hook** and recommended runtime settings for T2 hardware.
  - A clean uninstall path.

> This repository ships **no proprietary firmware**. It provides **open driver sources** for the HDA codec path and integrates them via **DKMS**. It also applies optional configuration to improve **suspend/resume** on T2‑era Macs.

---

## Supported hardware (examples)

Intel Macs with **CS8409 + CS42L42** audio path, typically:
- **iMac 2019/2020** (`iMac19,1`, `iMac20,1`, `iMac20,2`)
- **MacBook Pro 2018–2020** (`MacBookPro15,x`, `MacBookPro16,x`)
- **Mac mini 2018** (`Macmini8,1`)
- **iMac Pro** (`iMacPro1,1`)

> The installer auto‑detects supported hardware. If a similar model isn’t recognized, the module may refuse to load or create incomplete nodes — please open an issue with `dmesg` and `alsactl info` output.

---

## What the installer actually does

1. **Sanity checks & prerequisites**
   - Ensures **root**, verifies required tools and **kernel headers** are present.
   - Detects a compatible Mac model and running kernel.

2. **Build & install via DKMS**
   - Registers the module (e.g. `snd-hda-codec-cs8409`) with **DKMS**.
   - Builds against your current headers and **installs** it for **all installed kernels**.
   - Ensures automatic **rebuild on future kernel updates**.

3. **Apply runtime settings for T2 stability**
   - Writes **recommended kernel parameters** for T2 audio:  
     `snd_hda_intel.dmic_detect=0 mem_sleep_default=s2idle`
   - Offers to install a **minimal systemd sleep hook** (xHCI / s2idle workaround) to avoid **“no sound after suspend”** on affected models. If accepted, the installer places:  
     - the helper script: `/usr/lib/systemd/system-sleep/98-xhci-s2idle-unbind.sh`  
     - the configuration file: `/etc/default/xhci-s2idle.default`
   - Reloads the HDA stack and prints a short report (`aplay -l`, relevant `dmesg`).

4. **Uninstall helpers**
   - Includes a removal path to **unregister** the DKMS package and **revert optional settings**, i.e. **removing the installed sleep hook and its config**.

---

## Highlights (what makes this repo special)

- **No sound after kernel update?** Solved by **DKMS**: the module auto‑rebuilds whenever the kernel is updated.
- **No sound after suspend/resume?** Mitigated by a **tested s2idle + xHCI sleep hook** (optional) and runtime settings tailored for T2 Macs.
- **Community integration**: a **curated, forward‑compatible** packaging of community driver improvements with maintenance glue for current kernels.

---

## Requirements

- **Debian 12/13** or **Ubuntu 22.04/24.04** (or newer)
- **Kernel headers** for your running kernel (e.g. `linux-headers-$(uname -r)`)
- Tools: `git`, `build-essential` (or `base-devel` equivalent), `dkms`, `kmod`, `rsync`, `patch`, `pciutils`, `alsa-utils`, `pavucontrol`, `pulseaudio-utils`

Install helpers (Debian/Ubuntu):
```bash
sudo apt update
sudo apt install -y git build-essential dkms kmod rsync patch pciutils alsa-utils                     pavucontrol pulseaudio-utils                     linux-headers-$(uname -r)
```

> **Secure Boot (Debian/Ubuntu)**: If Secure Boot is **enabled**, unsigned DKMS modules **won’t load**. Either **disable Secure Boot** in firmware, **or** enroll a **Machine Owner Key (MOK)** and sign the DKMS module (Ubuntu typically prompts for MOK enrollment during dkms builds).

---

## Quick start

```bash
git clone https://github.com/frogro/cs8409-audio-dkms
cd cs8409-audio-dkms
chmod +x install.sh
sudo ./install.sh
```

After installation, you should see devices under `aplay -l`. If audio is muted, open **alsamixer** or **pavucontrol** and check the output path.

---

## Command‑line options (as implemented by this repo)

```
sudo ./install.sh [--yes] [--install-sleep-hook|--no-sleep-hook] [--dry-run] [--uninstall] [--verbose]
```

- `--yes`, `-y` — assume “yes” to prompts (non‑interactive).
- `--install-sleep-hook` / `--no-sleep-hook` — explicitly enable/disable the **xHCI s2idle** hook (otherwise you’ll be prompted interactively).
- `--dry-run` — simulate actions without changing the system.
- `--uninstall` — remove the DKMS module and revert optional settings (incl. the sleep hook and its config).
- `--verbose` — show more build/log output.

> Note: The installer **always** writes the recommended kernel parameters for T2 audio support.

---

## Uninstall / Revert

```bash
# Discover the module as registered by DKMS
dkms status | grep -i cs8409 || true

# Example (adjust -m/-v to match your system):
sudo dkms remove -m snd-hda-codec-cs8409 -v 1.0 --all

# Unload/reload HDA stack (or just reboot)
sudo modprobe -r snd_hda_codec_cs8409 snd_hda_codec snd_hda_intel || true
sudo modprobe snd_hda_intel && sudo modprobe snd_hda_codec && sudo modprobe snd_hda_codec_cs8409

# Remove optional sleep hook + config (if installed)
sudo rm -f /usr/lib/systemd/system-sleep/98-xhci-s2idle-unbind.sh
sudo rm -f /etc/default/xhci-s2idle.default
```

---

## Troubleshooting

- **No devices in `aplay -l`**
  - Make sure headers match your kernel: `dpkg -l | grep linux-headers` vs `uname -r`.
  - Check module: `lsmod | egrep 'cs8409|snd_hda_intel'`.
  - Look for errors: `dmesg | egrep -i 'cs8409|cs42l42|hda|firmware' | tail -n 200`.

- **No sound after suspend**
  - Ensure the **xHCI s2idle** hook is enabled and the system uses `s2idle` (the installer can set this up).
  - Reboot after enabling.

- **Module builds but does not load (Secure Boot)**
  - Sign the module via **MOK** or temporarily disable Secure Boot.

- **Regression after kernel upgrade**
  - Verify DKMS rebuilt: `dkms status`. Re‑run `sudo ./install.sh` if needed.

When reporting issues, include:
```
uname -r
lsmod | egrep 'cs8409|snd_hda_intel'
dmesg | egrep -i 'cs8409|cs42l42|hda|xHCI|suspend' | tail -n 200
aplay -l
sudo alsactl info
```

---

## Sources integrated / Credits

This project **builds on and integrates** work from:
- The **Linux kernel ALSA HDA** subsystem (including `snd-hda-codec-cs8409` and related Cirrus codec pieces).
- Community driver work by **egorenar** and contributors: <https://github.com/egorenar/snd-hda-codec-cs8409> (adapted/integrated here).
  _If you’d like explicit attribution for a specific change, open an issue/PR with the source URL and preferred credit line._

---

## Security and integrity

This repo provides **open source code** only. It does **not** include proprietary firmware. Sources are compiled locally against your headers via **DKMS**.

---

## License

This repository contains components under **two licenses**:
- **Kernel‑adjacent code** (driver code and any sources that compile into a kernel module, typically under `src/`): **GPL‑2.0‑only** (Linux kernel compatibility and GPL‑only symbols).
- **Build/packaging scripts and docs** (e.g. `install.sh` and this README): **MIT License**.

See [`LICENSE`](./LICENSE) for the full texts and which paths each license applies to.

---

## Contributing

Issues and PRs are welcome. Please include logs (see **Troubleshooting**) and your distro/kernel details. Contributions should keep **DKMS compatibility** and **resume reliability** in mind.
