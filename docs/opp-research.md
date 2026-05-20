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
| **600** | **1150 mV** | **1150** | **1150** | **1150**     | **1150** |

> Constraint: vdd_logic min=950 mV, max=1150 mV. Rail is **shared** between GPU and all SoC logic — undervolt margin is much tighter than CPU.  
> `rockchip,max-volt = 1175000 µV` — OPP framework enforces this ceiling on all entries.  
> 600 MHz row: added via OC patch (see GPU OC section below). 1150 mV is the PMIC hard limit.

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
| Condition           | terrain fps | Notes                        |
|---------------------|-------------|------------------------------|
| Stock (520 MHz)     | ~17         | baseline                     |
| GPU −12.5 mV UV     | 14–16       | stable, undervolted          |
| GPU OC 600 MHz      | **18**      | +20% vs UV baseline, stable  |

---

## GPU OC — 600 MHz (confirmed working)

**600 MHz is achievable via DTB only — no kernel recompile needed.**

### Clock driver analysis

No GPU rate table exists in `drivers/clk/rockchip/clk-px30.c`. The GPU uses a composite
clock (`clk_gpu_src`) with parent `gpll` (1200 MHz) and an integer divider:

```
gpll (1200 MHz) / 2 = 600 MHz  ✓
```

Unlike the CPU (which needed `rockchip,avs-scale=0` to unblock higher OPPs), the GPU OPP
table has no such restriction. The only limit is what OPP nodes exist in the DTB.

Confirmed by writing `600000000` to `/sys/kernel/debug/clk/clk_gpu/clk_rate` — the clock
driver accepted it immediately, confirming hardware capability.

### DTB change required

Add one node to `/gpu-opp-table`:

```
fdtput -c  /boot/rk3326-r36s-linux.dtb /gpu-opp-table/opp-600000000
fdtput -t u /boot/rk3326-r36s-linux.dtb /gpu-opp-table/opp-600000000 opp-hz 0 600000000
fdtput -t u /boot/rk3326-r36s-linux.dtb /gpu-opp-table/opp-600000000 opp-microvolt 1150000
fdtput -t u /boot/rk3326-r36s-linux.dtb /gpu-opp-table/opp-600000000 opp-microvolt-L2 1150000
```

Voltage used: **1150 mV** — PMIC hard limit for `vdd_logic`. Within `rockchip,max-volt = 1175 mV`.

After reboot, `available_frequencies` shows `600000000 520000000 480000000 400000000` and
devfreq correctly manages the new OPP with proper voltage.

### Benchmark results (L2 bin, off-screen)

| Condition           | Freq    | Voltage  | terrain fps |
|---------------------|---------|----------|-------------|
| Undervolted (stock) | 520 MHz | 1087.5 mV | 15–16     |
| GPU OC              | 600 MHz | 1150 mV  | **18**      |

**+20% FPS**. Stable at 62°C. No crash over 20s terrain run.

### Voltage reduction headroom

1150 mV is conservative (PMIC max). Untested lower voltages for 600 MHz:

| Target | Margin vs UV 520 MHz baseline |
|--------|-------------------------------|
| 1137.5 mV | +50 mV over undervolted 520 MHz |
| 1125 mV   | +37.5 mV |
| 1112.5 mV | +25 mV |

The `-12.5 mV` was the undervolt limit at 520 MHz — vdd_logic has very tight margins.
Start high (1150 mV) and reduce cautiously. If kernel crashes before `basic.target`,
manual SD card recovery is required (safety service cannot act).

---

## CPU OC — 1608 MHz (confirmed working)

**1608 MHz is achievable via DTB only — no kernel recompile needed.**

Earlier testing showed the kernel ignoring the 1608 MHz OPP. Root cause was `rockchip,avs-scale=4` in `/cpu0-opp-table`, not the clock driver.

### Mechanism: AVS (Adaptive Voltage Scaling)

`rockchip,avs=1` + `rockchip,avs-scale=4` in the DTB causes the kernel to call
`rockchip_adjust_opp_table(dev, scale_to_rate(4))` = `rockchip_adjust_opp_table(dev, 1512 MHz)`,
which **actively removes all OPPs above 1512 MHz** from the table at boot.

Fix: set `rockchip,avs-scale=0`. The condition `opp_scale(0) < avs_scale(0)` = FALSE → no OPPs removed.

The PX30 clock driver (`drivers/clk/rockchip/clk-px30.c`) already contains 1608 MHz in both
`px30_cpuclk_rates` and `px30_pll_rates` (RK3326 = PX30 same SoC, same driver).

### DTB changes required

1. Add OPP node to `/cpu0-opp-table`:
   ```
   opp-1608000000 { opp-hz = /bits/ 64 <1608000000>; opp-microvolt-L2 = <1350000 1350000 1350000>; }
   ```
2. Change `rockchip,avs-scale` from `4` to `0` in `/cpu0-opp-table`.

Voltage used: 1350 mV (same as 1512 MHz stock L2 — conservative). Could probably be undervolted further.

### Benchmark results — ALU (LCG C, 10s)

| MHz  | Mops | vs 1008 MHz |
|------|------|-------------|
| 1008 | 1500 | 100%        |
| 1200 | 1730 | +15%        |
| 1248 | 1780 | +19%        |
| 1296 | 1920 | +28%        |
| 1512 | 1870 | +25%        |
| 1608 | 1900 | +27%        |

**Sweet spot: 1512 MHz @ 1175 mV (undervolted).** 1608 MHz gives only +1.6% over 1512 MHz at stock voltage.
GPU benchmark (terrain) is identical at all CPU frequencies — GPU-limited, not CPU-limited.

### GPU OC

Not tested. `vdd_logic` (shared rail) has an absolute max of 1150 mV — the L0 520 MHz OPP
already uses 1150 mV, leaving zero headroom to add a higher-frequency OPP at a safe voltage.
Possible only if GPU can clock higher at current voltage (1100 mV L2), which is unknown.

---

## RAM / DMC

### DMC OPP table — all bins (mV)

Node: `/dmc-opp-table` · Rail: `vdd_logic` (shared with GPU and SoC logic)  
`rockchip,max-volt = 1150000` · ATF version: `0x105` · Bin active: **L2**

| MHz | L0   | L1   | **L2**   | L3   |
|-----|------|------|----------|------|
| 528 | 975  | 975  | **950**  | 950  |
| 666 | 1050 | 1000 | **975**  | 950  |
| 786 | 1100 | 1050 | **1025** | 1000 |
| **928** | — | — | **1075** | — |

> 928 MHz row added via OC patch (see DMC OC section below).  
> OPP node values: `opp-microvolt-L2 = 1075000`, `opp-microvolt = 1100000`.  
> ATF delivers **924 MHz** (nearest PLL divisor to the requested 928 MHz).

### DMC Undervolt — not worth it

The DMC shares `vdd_logic` with the GPU. The PMIC sets the rail to the maximum demanded by any consumer. When GPU OC is active at 1150 mV, DMC receives that same voltage regardless of its own OPP entry. Patching DMC L2 voltages lower has no effect on the rail — marginal power benefit at best, risk of DDR instability at worst.

### DMC OC — 928 MHz (confirmed working)

**Previous documentation incorrectly stated "RAM OC not possible via DTB."**

The correct model: ATF owns the *frequency switching* (register writes, DDR training). The kernel DMC devfreq driver determines *which frequencies to expose* from the DTB OPP table. Adding an OPP node causes the kernel to request that frequency via ATF SMC call.

**ATF v0x105 has timing support for 928 MHz LPDDR4.** Confirmed:

1. Added `opp-928000000` node to `/dmc-opp-table`
2. After reboot: `available_frequencies` = `528000000 666000000 786000000 928000000`
3. Set `governor = performance` → `cur_freq = 924000000` — system stable, no hang
4. Ran glmark2 terrain under sustained DMC 924 MHz + GPU 600 MHz — stable, no crash

**DTB changes:**

```bash
fdtput -c  /boot/rk3326-r36s-linux.dtb /dmc-opp-table/opp-928000000
fdtput -t u /boot/rk3326-r36s-linux.dtb /dmc-opp-table/opp-928000000 opp-hz 0 928000000
fdtput -t u /boot/rk3326-r36s-linux.dtb /dmc-opp-table/opp-928000000 opp-microvolt-L2 1075000
fdtput -t u /boot/rk3326-r36s-linux.dtb /dmc-opp-table/opp-928000000 opp-microvolt 1100000
```

**Benchmark results (terrain off-screen, GPU OC 600 MHz active):**

| Condition | DMC freq | terrain fps | Conclusion |
|-----------|----------|-------------|------------|
| GPU OC only | 786 MHz | 18 | baseline |
| GPU OC + DMC OC | 924 MHz | 18 | terrain = compute-bound |

terrain shows no change because Mali-G31 at 600 MHz is ALU-saturated. Expected benefits in real workloads:
- **Emulation JIT**: CPU reads guest code + emulator state from RAM constantly → real speedup
- **Texture sampling (UMA)**: Mali-G31 reads textures from system RAM each frame → more bandwidth available
- **Loading times**: ROM decompression, save states, asset streaming → pure bandwidth
- **Sustained performance**: CPU + GPU competing for same bus → more headroom for both

**Voltage note:** When GPU OC is active (vdd_logic = 1150 mV), DMC OC at 1075 mV adds zero voltage cost — the rail is already at its PMIC max. Both OCs can coexist on the same rail without conflict.

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
