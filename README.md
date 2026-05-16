# R36 Tuner

Real-time CPU / GPU / DMC / Voltage tuning tool for R36S and compatible devices running [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36) (RK3326 SoC).

## Features

- CPU max / min frequency selection
- CPU governor selector (performance / schedutil / ondemand / conservative / powersave)
- GPU max frequency selection
- DMC / RAM max frequency selection
- **DTB undervolt** — permanent voltage reduction via OPP table patch in the Device Tree Binary. Patches the active OPP bin (`opp-microvolt-L2` on most R36S units). Offsets from -100 mV to +50 mV. Reboot required.
- **DTB safety net** — two systemd services protect against bad undervolts: an early-boot service detects if the previous boot hung after a DTB patch and automatically restores the original DTB backup before the system reaches userspace.
- Real-time monitor (temp, freq, voltage) with overheat warning at ≥80°C
- Benchmarks: CPU (sha256 + gzip), RAM (128MB r/w), GPU (glmark2) — individually or all in sequence. Score history with baseline comparison.
- Save profile → applies at every boot via systemd service
- Fail-safe: panic flag detects boot hangs and auto-disables the profile
- Startup warning if last boot profile caused a hang or if DTB was auto-restored

## Requirements

- Device: R36S or compatible clone (RK3326 / RK3326S SoC)
- OS: [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36) by southoz
- Tools present in dArkOSRE: `dialog`, `gptokeyb`, `systemd`
- For DTB undervolt: `device-tree-compiler` (`fdtget`/`fdtput`) — the script offers to install it automatically

## Installation

Copy `R36 Tuner v2.0.sh` to `/opt/system/` on your device:

```bash
scp "R36 Tuner v2.0.sh" ark@<device-ip>:/opt/system/
ssh ark@<device-ip> "chmod +x '/opt/system/R36 Tuner v2.0.sh'"
```

Then launch it from the dArkOSRE system menu.

## DTB Undervolt

The RK3326 OPP framework owns all voltage regulators — runtime sysfs writes are reverted during frequency transitions. The only permanent undervolt is patching the voltage table in the Device Tree Binary.

This device uses Rockchip OPP binning (`pvtm-volt-sel`). At boot, the kernel selects a voltage bin based on chip leakage measurement. Most R36S units land on **L2**. The tuner detects the active bin from `dmesg` and patches the correct property (`opp-microvolt-L2`).

Tested result: `-25 mV` offset gives **1275 mV** at 1296/1512 MHz (stock L2: 1300 mV).

A backup of the original DTB is created automatically before patching. The backup is used by both the safety service and the manual restore option in the menu.

## Emergency Recovery — Device Won't Boot

If a DTB undervolt is too aggressive, the kernel may fail to boot entirely. The automatic safety service cannot help in this case (it runs in userspace). To recover manually:

1. **Power off** the R36S.
2. **Remove the system SD card** (the one with dArkOSRE — typically the internal/main slot).
3. **Plug the SD card into a PC** using a card reader.
4. On Windows, look for a **FAT32 partition** — that is `/boot`. Open it.
   - If Windows only shows one partition, use [DiskGenius](https://www.diskgenius.com/) (free) to browse all partitions on the card.
5. Inside the boot partition, you will find:
   - `rk3326-r36s-linux.dtb` — the patched file (bad)
   - `rk3326-r36s-linux.dtb.bak` — the original backup (good)
6. **Copy `rk3326-r36s-linux.dtb.bak` over `rk3326-r36s-linux.dtb`** (overwrite).
7. Also **delete `.r36_dtb_patch_booting`** if it exists in that partition (cleans up the safety flag).
8. **Eject** the SD card safely, reinsert into the R36S, and boot.

> The `.bak` file is created at the moment of patching and always reflects the state before the first patch. It is never overwritten by subsequent patch operations.

## Disclaimer

> **USE AT YOUR OWN RISK.**
>
> This tool writes directly to kernel sysfs interfaces and patches the Device Tree Binary to modify CPU, GPU, RAM frequencies and voltages. Incorrect settings — especially voltage undervolting — can cause **system instability, data corruption, or permanent hardware damage**.
>
> The authors take **no responsibility** for bricked devices, corrupted SD cards, data loss, or any other damage resulting from the use of this software. The fail-safe mechanisms reduce risk but do not eliminate it.
>
> Always start with conservative values (-25 mV) and verify stability before going further.

## Credits

UI scripting framework (TTY setup, `dialog`, `gptokeyb` integration, systemd service pattern) adapted from [ZRam Manager](https://github.com/southoz/dArkOSRE-R36) by [southoz](https://github.com/southoz).

Built for and tested on [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36).

## License

[MIT](LICENSE)
