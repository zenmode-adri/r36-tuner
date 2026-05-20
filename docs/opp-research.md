# RK3326 OPP Voltage Research — R36S / dArkOSRE

Device: R36S · SoC: Rockchip RK3326 · PMIC: RK805  
OS: dArkOSRE-R36 by southoz · Chip bin: **L2** (pvtm-volt-sel=2, leakage=13)

---

## How OPP Binning Works

The Rockchip BSP kernel measures chip leakage (PVTM) at boot and picks a voltage bin:
`L0` (worst silicon) → `L1` → `L2` → `L3` (best silicon / lowest voltage needs).

The active bin is logged in dmesg:
```
dmesg | grep "opp-binning.*using OPP prop name"
```

**Patching `opp-microvolt` has zero effect.** The kernel uses `opp-microvolt-L2` (or whichever bin applies). Must patch the correct `opp-microvolt-L<N>` property.

---

## CPU OPP Table — `/cpu0-opp-table`

Rail: `vdd_arm` (DCDC_REG2) · DTB node format: `opp-<hz>` · Values: `[min, typ, max]` (3× u32 big-endian)

| MHz   | opp-microvolt | L0     | L1     | **L2** (active) | L3     |
|-------|---------------|--------|--------|-----------------|--------|
| 1008  | 1175 mV       | 1175   | 1125   | **1125**        | 1050   |
| 1200  | 1300 mV       | 1300   | 1275   | **1250**        | 1200   |
| 1248  | 1350 mV       | 1350   | 1300   | **1275**        | 1225   |
| 1296  | 1350 mV       | 1350   | 1350   | **1300**        | 1250   |
| 1512  | 1350 mV       | 1350   | 1350   | **1300**        | 1250   |

> Values from official [dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36) DTB.  
> `max` col in [min, typ, max] tuple is the voltage ceiling; kernel uses `min`/`typ`.  
> Constraint: vdd_arm min=950 mV, max=1350 mV.

### CPU Undervolt Test Results (L2 bin)

| Offset  | L2 @ 1296/1512 MHz | Result                         |
|---------|--------------------|--------------------------------|
| 0 mV    | 1300 mV (stock)    | Stable (baseline)              |
| −25 mV  | 1275 mV            | ✅ Stable                      |
| −125 mV | 1175 mV            | ✅ Stable — confirmed long-term |
| −137.5 mV | 1162.5 mV        | ❌ Freeze at "starting ui"     |
| −150 mV | 1150 mV            | ❌ Black screen (kernel crash) |

**Confirmed stable limit: −125 mV → 1125 mV** at 1296/1512 MHz.

Safety service (`r36-dtb-safety`) catches freeze/hang cases (before=basic.target).  
If kernel crashes before basic.target → safety service cannot act → manual SD recovery needed.

---

## GPU OPP Table — `/gpu-opp-table`

GPU: Mali-G31 (Bifrost) · Rail: `vdd_logic` (DCDC_REG1, **shared with SoC logic**)  
DTB node format: `opp-<hz>` · Values: single u32 big-endian (not 3-tuple like CPU)

| MHz   | opp-microvolt | L0     | L1     | **L2** (active) | L3     |
|-------|---------------|--------|--------|-----------------|--------|
| 400   | 1050 mV       | 1050   | 1025   | **975**         | 950    |
| 480   | 1125 mV       | 1125   | 1100   | **1050**        | 1000   |
| 520   | 1150 mV       | 1150   | 1150   | **1100**        | 1050   |

> Constraint: vdd_logic min=950 mV, max=1150 mV. Rail is **shared** between GPU and all SoC logic — undervolt margin is much tighter than CPU.

### GPU Undervolt Test Results (L2 bin)

| Offset   | L2 @ 520 MHz | Result                                |
|----------|--------------|---------------------------------------|
| 0 mV     | 1100 mV      | Stable (baseline)                     |
| −12.5 mV | 1087.5 mV    | ✅ Stable — glmark2 terrain 14fps     |
| −25 mV   | 1075 mV      | ❌ Kernel crash before basic.target   |

**Confirmed stable limit: −12.5 mV → 1087.5 mV** (all 3 OPPs patched uniformly).  
Baseline glmark2 terrain score (stock, no ES): ~17fps off-screen. Undervolted: **14fps** (no crash).

Safety service **cannot** recover GPU undervolt crashes (kernel dies too early).  
Always keep `/boot/rk3326-r36s-linux.dtb.bak` — restoring from SD is the only recovery.

---

## GPU Benchmark Reference

Binary: `glmark2-es2-drm` (2021.02, cross-compiled arm64, custom GBM patches)  
Command for stability test (no EmulationStation):
```bash
systemctl stop emulationstation
/tmp/glmark2-es2-drm-legacy --data-path /tmp/glmark2data --size 320x240 -b terrain:duration=30
systemctl start emulationstation
```

Key scores (off-screen, ES stopped):
| Condition      | terrain fps | Notes               |
|----------------|-------------|---------------------|
| Stock          | ~17         | baseline            |
| GPU −12.5 mV   | 14          | stable, no crash    |

---

## OC Experiment

- 1608 MHz OPP added to `/cpu0-opp-table` → kernel ignores it. Clock driver hard cap at 1512 MHz. Not fixable without BSP kernel recompile.
- GPU OC not tested. `vdd_logic` max=1150 mV leaves ~50 mV above L0 520 MHz (1150 mV) — no headroom.

---

## RAM / DMC

### DMC OPP table — all bins (mV)

Node: `/dmc-opp-table` · Rail: `vdd_logic` (shared with GPU and SoC logic)

| MHz | L0   | L1   | **L2** | L3   |
|-----|------|------|--------|------|
| 528 | 975  | 975  | **950**  | 950  |
| 666 | 1050 | 1000 | **975**  | 950  |
| 786 | 1100 | 1050 | **1025** | 1000 |

### DMC Undervolt — not worth it

The DMC shares `vdd_logic` with the GPU. The PMIC sets the rail voltage to the maximum demanded by any consumer at a given moment. When the GPU runs at 520 MHz (demanding 1087.5 mV with our patch), the DMC receives that same voltage regardless of its own OPP. Patching DMC L2 voltages lower would only save power in the narrow window where GPU is at low freq and DMC is at high freq — marginal benefit. Risk: DDR memory instability → random crashes and data corruption.

### RAM OC — not possible via DTB

DMC frequency is controlled by **ATF (ARM Trusted Firmware)**, not the kernel. Confirmed from dmesg:
```
rockchip-dmc dmc: current ATF version 0x105
```
The kernel devfreq interface for DMC has no accessible `available_frequencies` — ATF owns DDR frequency transitions via SMC calls. Overclocking RAM would require modifying the ATF binary in the bootloader, for which dArkOSRE provides no source. Not feasible.

---

## DTB File Info

```
/boot/rk3326-r36s-linux.dtb        (active — patch target)
/boot/rk3326-r36s-linux.dtb.bak    (original stock — never overwrite)
```

Read a property:
```bash
fdtget -t u /boot/rk3326-r36s-linux.dtb /gpu-opp-table/opp-520000000 opp-microvolt-L2
```

Write a property:
```bash
fdtput -t u /boot/rk3326-r36s-linux.dtb /gpu-opp-table/opp-520000000 opp-microvolt-L2 <value_uv>
```

Verify kernel-loaded value (after reboot):
```bash
python3 -c "import struct; d=open('/proc/device-tree/gpu-opp-table/opp-520000000/opp-microvolt-L2','rb').read(); print(struct.unpack('>I',d[:4])[0])"
```
