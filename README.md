# R36 Tuner

> **⚠️ Early Access — Experimental**
> This project is under active development and not yet feature-complete. Expect rough edges, missing options, and breaking changes between versions. Not recommended for daily use until a stable release is tagged.

Real-time CPU / GPU / DMC / Voltage tuning tool for R36S and compatible devices running [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36) (RK3326 SoC).

## Features

- CPU max / min frequency selection
- CPU governor selector (performance / schedutil / ondemand / conservative / powersave) — persisted at boot
- GPU max frequency selection
- DMC / RAM max frequency selection
- Voltage undervolting (vdd_logic / vcc_ddr) with OPP-aware write
- Real-time monitor (temp, freq, voltage) with overheat warning at ≥80°C
- Benchmarks: CPU (sha256 + gzip), RAM (128MB r/w), GPU (glmark2) — individually or all in sequence
- Save profile → applies at every boot via systemd service
- Fail-safe: panic flag detects boot hangs and auto-disables the profile
- Startup warning if last boot profile caused a hang
- View saved profile from the main menu

## Known Limitations

**CPU voltage undervolt (`vdd_arm`) does not work** on stock dArkOSRE kernel.

The RK3326 OPP framework owns the `vdd_arm` regulator and reverts any manual voltage write during cpufreq transitions. A permanent undervolt requires patching the Device Tree (DTB) to modify the OPP voltage table — this is not yet implemented.

> 🔧 **Work in progress:** DTB-based CPU undervolt is planned for a future release.

## Requirements

- Device: R36S or compatible clone (RK3326 / RK3326S SoC)
- OS: [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36) by southoz
- Tools present in dArkOSRE: `dialog`, `gptokeyb`, `systemd`

## Installation

Copy `R36 Tuner v2.0.sh` to `/opt/system/` on your device:

```bash
scp "R36 Tuner v2.0.sh" ark@<device-ip>:/opt/system/
ssh ark@<device-ip> "chmod +x '/opt/system/R36 Tuner v2.0.sh'"
```

Then launch it from the dArkOSRE system menu.

## Disclaimer

> **USE AT YOUR OWN RISK.**
>
> This tool writes directly to kernel sysfs interfaces to modify CPU, GPU, RAM frequencies and voltages at runtime. Incorrect settings — especially voltage undervolting — can cause **system instability, data corruption, or permanent hardware damage**.
>
> The authors take **no responsibility** for bricked devices, corrupted SD cards, data loss, or any other damage resulting from the use of this software. The fail-safe mechanism reduces risk but does not eliminate it.
>
> Always start with conservative values and test stability before saving a profile.

## Credits

UI scripting framework (TTY setup, `dialog`, `gptokeyb` integration, systemd service pattern) adapted from [ZRam Manager](https://github.com/southoz/dArkOSRE-R36) by [southoz](https://github.com/southoz).

Built for and tested on [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36).

## License

[MIT](LICENSE)
