# CS8409 Audio DKMS (Debian/Ubuntu on Intel Macs)

This repository provides a **DKMS-based audio enablement** for Intel Macs (iMac, MacBook, Mac mini, iMac Pro, Mac Pro) that use **Cirrus Logic CS8409** HDA audio with a **CS42L42** companion codec — the common setup on many **T2‑era Macs (2018–2020)** running **Linux (Debian/Ubuntu)**.
On these machines, users frequently hit **“no sound”** because the Linux kernel may lack **model‑specific initialization** and **resume quirks** out of the box. This project bundles **kernel‑compatible driver sources** and installs them via **DKMS**, plus an optional **resume workaround**, to make audio **work reliably** across kernel updates and sleep/wake cycles.

- **Why this repo?** It is a **consolidation and forward‑evolution** of existing **community solutions** for CS8409/CS42L42 on T2 Macs. It **integrates** community driver work and adds small glue fixes, wrapped as a **DKMS module** so that audio **keeps working after kernel updates** — and includes a **suspend/resume fix** for the notorious “no audio after suspend” issue.
- **What you get**
  - **Sound out of the box** on supported Macs (speakers/headphones, HDA controls).
  - **DKMS auto‑rebuild** across kernel upgrades (solves “no sound after kernel update”).
  - **Suspend/resume fix** (“no sound after suspend”), via a minimal **systemd sleep hook** and recommended runtime settings for T2 hardware.
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
   - Detects the **running kernel** (and any installed kernels) to determine **DKMS build targets**.  
     **Note:** This repo does **not** check or update your kernel (unlike the Wi‑Fi wrapper).

2. **Build & install via DKMS**
   - Registers the module (e.g. `snd-hda-codec-cs8409`) with **DKMS**.
   - Builds against your current headers and **installs** it for **all installed kernels** (or specific targets you select via flags below).
   - Ensures automatic **rebuild on future kernel updates**.

3. **Apply runtime settings for T2 stability**
   - Writes **recommended kernel parameters** for T2 audio:  
     `snd-intel-dspcfg.dsp_driver=1 mem_sleep_default=s2idle`
   - By default, installs a **minimal systemd sleep hook** (xHCI / s2idle workaround) to avoid “no sound after suspend” on affected models.
If you run with `--no-suspend-patch`, the installer keeps **`snd-intel-dspcfg.dsp_driver=1`** for audio but skips the **`mem_sleep_default=s2idle`** flag and **does not** install the hook.

Installs (when enabled):
- helper script: `/usr/lib/systemd/system-sleep/98-xhci-s2idle-unbind.sh` (or `/lib/systemd/system-sleep/…` on non-usrmerge)
- config file: `/etc/default/xhci-s2idle`
