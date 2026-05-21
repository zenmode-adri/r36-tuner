# R36 Tuner

Real-time CPU / GPU / DMC / Voltage tuning tool for R36S and compatible devices running [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36) (RK3326 SoC).

## Features

- CPU max / min frequency selection
- CPU governor selector (performance / schedutil / ondemand / conservative / powersave)
- GPU max frequency selection
- DMC / RAM max frequency selection
- **DTB undervolt** — permanent voltage reduction via OPP table patch in the Device Tree Binary. The DTB contains multiple voltage tables (bins L0–L3): the kernel measures chip leakage at boot (PVTM) and selects the appropriate bin for your unit. The tuner reads dmesg to detect which bin is active and patches only that table. Offsets from -100 mV to +50 mV. Reboot required.
- **CPU OC to 1608 MHz** — unlocks 1608 MHz by patching `rockchip,avs-scale` in the DTB (no kernel recompile needed). The PX30/RK3326 clock driver already contains 1608 MHz; it was being suppressed by the AVS mechanism at runtime.
- **GPU OC to 600 MHz** — adds a 600 MHz OPP to the GPU OPP table in the DTB. The GPU composite clock uses GPLL/2 = 600 MHz exactly; no clock driver changes needed.
- **RAM OC to 928 MHz** — adds a 928 MHz OPP to the DMC OPP table. ATF v0x105 supports the frequency and delivers 924 MHz (nearest PLL divisor). +11% read bandwidth over stock 786 MHz (measured, CPU pinned, 5-run average).
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

Copy `R36 Tuner.sh` to `/opt/system/` on your device:

```bash
scp "R36 Tuner.sh" ark@<device-ip>:/opt/system/
ssh ark@<device-ip> "chmod +x '/opt/system/R36 Tuner.sh'"
```

Then launch it from the dArkOSRE system menu.

## DTB Undervolt

The RK3326 OPP framework owns all voltage regulators — runtime sysfs writes are reverted during frequency transitions. The only permanent undervolt is patching the voltage table in the Device Tree Binary.

This device uses Rockchip OPP binning (`pvtm-volt-sel`). At boot, the kernel selects a voltage bin based on chip leakage measurement. Most R36S units land on **L2**. The tuner detects the active bin from `dmesg` and patches the correct property (`opp-microvolt-L2`).

Tested results on L2 bin (our test unit — your bin may differ, check dmesg):

| Component | Stock L2 @ max freq | Stable limit | Result |
|-----------|---------------------|--------------|--------|
| CPU (vdd_arm) | 1300 mV @ 1512 MHz | **−125 mV → 1175 mV** | ✅ Long-term stable |
| GPU (vdd_logic) | 1100 mV @ 520 MHz | **−12.5 mV → 1087.5 mV** | ✅ Stable (vdd_logic shared with SoC logic — tight margin) |
| RAM/DMC (vdd_logic) | — | not recommended | ⚠️ Shares vdd_logic with GPU — benefit marginal, risk high |

> **DMC OC is separate from DMC undervolt** — see [RAM OC — 928 MHz](#ram-oc--928-mhz) below.

### CPU voltage table — all bins (mV)

Source: official [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36) DTB · Rail: `vdd_arm` · **Bold = our tested bin (L2)**

| MHz  | default | L0   | L1   | **L2** | L3   |
|------|---------|------|------|--------|------|
| 1008 | 1175    | 1175 | 1125 | **1125** | 1050 |
| 1200 | 1300    | 1300 | 1275 | **1250** | 1200 |
| 1248 | 1350    | 1350 | 1300 | **1275** | 1225 |
| 1296 | 1350    | 1350 | 1350 | **1300** | 1250 |
| 1512 | 1350    | 1350 | 1350 | **1300** | 1250 |

### GPU voltage table — all bins (mV)

Source: official [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36) DTB · Rail: `vdd_logic` (shared with SoC logic) · **Bold = our tested bin (L2)**

| MHz | default | L0   | L1   | **L2**  | L3   |
|-----|---------|------|------|---------|------|
| 400 | 1050    | 1050 | 1025 | **975** | 950  |
| 480 | 1125    | 1125 | 1100 | **1050** | 1000 |
| 520 | 1150    | 1150 | 1150 | **1100** | 1050 |

### DMC (RAM controller) voltage table — all bins (mV)

Rail: `vdd_logic` (shared with GPU and SoC logic) · Node: `/dmc-opp-table` · **Bold = tested unit (L2)**

| MHz | L0   | L1   | **L2**   | L3   |
|-----|------|------|----------|------|
| 528 | 975  | 975  | **950**  | 950  |
| 666 | 1050 | 1000 | **975**  | 950  |
| 786 | 1100 | 1050 | **1025** | 1000 |
| **928** | — | — | **1075** | — |

> DMC shares `vdd_logic` with the GPU — the PMIC always sets the rail to the highest voltage demanded by any consumer. Patching DMC voltages lower has marginal effect and risks DDR instability (random crashes, data corruption).
>
> RAM OC via DTB **is possible** — see [RAM OC — 928 MHz](#ram-oc--928-mhz).

For full research notes and benchmark data, see [docs/opp-research.md](docs/opp-research.md).

## GPU OC — 600 MHz

The GPU composite clock uses `gpll (1200 MHz) / 2 = 600 MHz` exactly. No GPU rate table exists in the driver — the only limit was the OPP table. Adding a `opp-600000000` node is sufficient.

**Voltage:** 1150 mV — the PMIC hard limit for `vdd_logic` (shared rail). Within `rockchip,max-volt = 1175 mV`.

**Benchmark results (L2 bin, off-screen terrain):**

| Condition       | Freq    | Voltage  | terrain fps |
|-----------------|---------|----------|-------------|
| UV baseline     | 520 MHz | 1087.5 mV | 15–16      |
| GPU OC          | 600 MHz | 1150 mV  | **18 fps**  |

**+20% FPS**, stable at 62°C. devfreq manages the new OPP correctly after reboot.

> `vdd_logic` is shared between GPU and all SoC logic. The undervolt limit at 520 MHz was −12.5 mV — the rail has very tight margins. Start at 1150 mV and reduce cautiously. If the kernel crashes before `basic.target`, manual SD card recovery is required.

## CPU OC — 1608 MHz

The RK3326 clock driver already contains 1608 MHz in `px30_cpuclk_rates` and `px30_pll_rates`. It was suppressed at runtime by `rockchip,avs-scale=4` in the DTB, which caused the kernel to actively strip OPPs above 1512 MHz from the table during boot.

**Fix (DTB only, no kernel recompile):**
1. Add `opp-1608000000` node to `/cpu0-opp-table` with desired voltage.
2. Set `rockchip,avs-scale` from `4` to `0` — disables the AVS OPP stripping.

**Benchmark results (ALU, LCG C, 10s):**

| MHz  | Mops | vs 1008 MHz |
|------|------|-------------|
| 1008 | 1500 | 100%        |
| 1296 | 1920 | +28%        |
| 1512 | 1870 | +25%        |
| 1608 | 1900 | +27%        |

Practical gain of 1608 over 1512 MHz: **+1.6%**. The sweet spot remains **1512 MHz @ 1175 mV** (undervolted). GPU-bound workloads show no difference at any CPU frequency.

A backup of the original DTB is created automatically before patching. The backup is used by both the safety service and the manual restore option in the menu.

## RAM OC — 928 MHz

ATF (ARM Trusted Firmware) v0x105 controls DDR frequency switching via SMC calls, but the kernel DMC devfreq driver determines *which frequencies to expose* from the DTB OPP table. Adding an OPP node to `/dmc-opp-table` causes the kernel to request that frequency from ATF, which executes the switch if it has timing support for it.

**Confirmed working on this device:** ATF v0x105 accepts 928 MHz and delivers **924 MHz** (nearest PLL divisor). Verified stable — system survives sustained GPU + DMC load at 924 MHz.

**Voltage:** 1075 mV for L2 bin (conservative). `vdd_logic` is shared with GPU — when GPU OC is active at 1150 mV, there is zero extra voltage cost for DMC OC.

**DTB change required:**

```bash
fdtput -c  /boot/rk3326-r36s-linux.dtb /dmc-opp-table/opp-928000000
fdtput -t u /boot/rk3326-r36s-linux.dtb /dmc-opp-table/opp-928000000 opp-hz 0 928000000
fdtput -t u /boot/rk3326-r36s-linux.dtb /dmc-opp-table/opp-928000000 opp-microvolt-L2 1075000
fdtput -t u /boot/rk3326-r36s-linux.dtb /dmc-opp-table/opp-928000000 opp-microvolt 1100000
```

After reboot, `available_frequencies` shows `528000000 666000000 786000000 928000000`. The `dmc_ondemand` governor scales up to 924 MHz under memory pressure.

**Benchmark results:**

Memory bandwidth (128 MB dd read via `/dev/shm`, CPU pinned to 1512 MHz, 5 runs averaged, L2 bin):

| DMC freq | Read MB/s |
|----------|----------|
| 786 MHz (stock max) | 966 |
| **924 MHz (OC)**    | **1076** |

Read bandwidth: **+11%** over stock 786 MHz. CPU frequency (1512 vs 1608 MHz) has no measurable effect on RAM bandwidth (<1% difference).

GPU terrain fps shows no change (18 fps at all DMC freqs) because Mali-G31 at 600 MHz is compute-bound, not bandwidth-bound. Benefits are real in mixed CPU+GPU workloads: emulator JIT, texture streaming, ROM loading, save states.

> **UMA note:** Mali-G31 has no dedicated VRAM — it reads textures directly from system RAM. Faster RAM = faster texture sampling, though the effect is workload-dependent.

### Higher frequencies — tested and results

Frequencies above 928 MHz were tested by adding OPP nodes to the DTB. ATF v0x105 accepted both but with different results:

| Requested | ATF delivers | Result | Read MB/s |
|-----------|-------------|--------|----------|
| 928 MHz | **924 MHz** | Stable | 1076 |
| 1000 MHz | **996 MHz** | Stable but slower | 1012 |
| 1056 MHz | **1056 MHz** | Kernel panic under sustained load | — |

**996 MHz is slower than 924 MHz** — ATF has timing tables for 996 MHz but they are more conservative than those for 924 MHz, resulting in lower effective bandwidth despite higher frequency.

**1056 MHz crashes** under sustained memory-intensive workloads. `vdd_logic` is already at the PMIC hard limit (1150 mV) — no headroom to stabilize it with higher voltage.

**Why we cannot push further:** LPDDR4 timing tables are embedded in Rockchip's closed DDR init binary (`px30_ddr_333MHz_v2.11.bin` in `rkbin`). Modifying them requires Rockchip's internal DDR training tools, which are not publicly available. The ATF BL31 source (available at [ARM-software/arm-trusted-firmware](https://github.com/ARM-software/arm-trusted-firmware)) does not contain the DDR timing data.

**924 MHz (from 928 MHz OPP) is the confirmed stable ceiling** for this hardware.

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
> Always start with conservative values (−25 mV CPU, −12.5 mV GPU) and verify stability before going further.

## Credits

UI scripting framework (TTY setup, `dialog`, `gptokeyb` integration, systemd service pattern) adapted from [ZRam Manager](https://github.com/southoz/dArkOSRE-R36) by [southoz](https://github.com/southoz).

Built for and tested on [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36).

## License

[MIT](LICENSE)
