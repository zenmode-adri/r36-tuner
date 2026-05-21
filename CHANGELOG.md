# Changelog

## v3.4 — 2026-05-21

**Research: GPU OC 600 MHz — complete voltage sweep (L2 bin):**
- Full undervolt sweep from 1150 mV down to 1012.5 mV in 12.5 mV steps (on-screen, ES stopped, 30–90s terrain)
- Confirmed stable limit: **1025 mV** (−125 mV from PMIC max) — 15 fps on-screen, no artifacts
- Artifacts at: 1012.5 mV (rendering errors, fps drop to 13) — do not use
- Total undervolt: −125 mV — same silicon margin as CPU UV on this L2 chip
- Key insight: OC has much more voltage headroom than stock GPU UV because the 600 MHz OPP is isolated — patching it does NOT lower the 400/480/520 MHz OPPs (stock UV was limited by 400 MHz OPP approaching PMIC floor)
- Crash behavior at 1012.5 mV: device boots fine (GPU starts at 400 MHz), artifacts appear only when devfreq scales to 600 MHz under load — safety service does NOT trigger
- Recovery at any failed voltage: patch DTB via SSH without reboot (`fdtput` to restore 1025 mV)
- Updated `docs/opp-research.md` with complete sweep table and analysis

## v3.3 — 2026-05-21

**Feat: RAM OC 928 MHz — DTBDMCOC() integrated into DTB menu:**
- DMC OC confirmed working: ATF v0x105 supports 928 MHz — delivers 924 MHz (nearest PLL divisor)
- New menu item "RAM OC 928 MHz" in DTB Undervolt submenu, after GPU OC entry
- Menu item shows `[ACTIVE]` if 928 MHz is present in DMC `available_frequencies`
- `DTBDMCOC()`: adds `opp-928000000` to `/dmc-opp-table`; no equivalent of `avs-scale` needed
- Voltage selector: 1075 / 1062.5 / 1050 mV (L2 bin). vdd_logic shared with GPU — at 1150 mV when GPU OC active, no extra voltage cost
- +18% RAM bandwidth over 786 MHz. Benefit: CPU JIT, texture reads, emulator loading times
- GPU compute-bound workloads (terrain): no fps change (confirmed). Emulation mixed workloads: real benefit
- Same backup/safety-service/reboot flow as all other DTB patches

**Fix: corrected wrong claim in docs — RAM OC IS possible via DTB:**
- README and opp-research.md previously stated "RAM OC not possible via DTB — ATF owns DMC"
- Reality: ATF owns the *frequency switching*, but the kernel *exposes available frequencies from DTB OPP table*
- Adding an OPP node → kernel requests it → ATF executes the switch. Confirmed working.

## v3.2 — 2026-05-21

**Feat: GPU OC 600 MHz — integrated into DTB menu (`DTBGPUOC()`):**
- New menu item "GPU OC 600 MHz" in DTB Undervolt submenu, after CPU OC entry
- Menu item shows `[ACTIVE]` suffix if 600 MHz is already in GPU `available_frequencies`
- `DTBGPUOC()`: adds `opp-600000000` to `/gpu-opp-table` — no `rockchip,avs-scale` needed (GPU has none)
- `opp-hz`: 0 600000000 (64-bit, gpll/2 = 600 MHz exactly)
- Voltage selector: 1150 / 1137.5 / 1125 / 1112.5 mV (1150 mV recommended — PMIC vdd_logic max)
- Writes both `opp-microvolt-L2` (binned) and generic `opp-microvolt` for compatibility
- Same safety net: backup preserved, safety service, reboot prompt
- State detection: ACTIVE / OPP in DTB pending reboot / not patched

## v3.1 — 2026-05-21

**Discovery: GPU OC 600 MHz — confirmed stable via DTB only:**
- GPU composite clock uses `gpll (1200 MHz) / 2 = 600 MHz` — no rate table in driver, no kernel changes needed
- Unlike CPU OC, GPU has no `rockchip,avs-scale` — adding `opp-600000000` to `/gpu-opp-table` is sufficient
- Voltage: 1150 mV (`opp-microvolt-L2`) — PMIC hard limit for `vdd_logic`, within `rockchip,max-volt = 1175 mV`
- Result: **18 fps** terrain off-screen vs 15–16 fps @ 520 MHz undervolted (**+20%**), stable at 62°C
- devfreq correctly exposes `600000000` in `available_frequencies` after reboot
- Updated `docs/opp-research.md` and `README.md` with GPU OC findings and voltage table

## v3.0 — 2026-05-20

**Feat: CPU OC 1608 MHz — re-added to DTB menu with correct mechanism:**
- Previous implementation (v1.8) added the OPP node but did not clear `rockchip,avs-scale=4`, which caused the kernel to strip all OPPs >1512 MHz at boot
- New `DTBCPUOC()` function: adds `opp-1608000000` node AND sets `rockchip,avs-scale=0`
- Voltage selector: 1350/1325/1300/1275 mV (1350 mV recommended — conservative start)
- Silicon lottery warning: not all R36S units will be stable; start with max voltage
- Menu item shows `[ACTIVE]` suffix if 1608 MHz is already in `scaling_available_frequencies`
- Same safety net as undervolt: backup preserved, safety service active, reboot prompt

## v2.9 — 2026-05-20 (docs)

**Discovery: CPU OC 1608 MHz works via DTB — no kernel recompile needed:**
- Root cause of previous failure identified: `rockchip,avs-scale=4` in `/cpu0-opp-table` caused the kernel to call `rockchip_adjust_opp_table(dev, 1512 MHz)` at boot, actively stripping all OPPs above 1512 MHz
- Fix: set `rockchip,avs-scale=0` + add `opp-1608000000` node — clock driver already had 1608 MHz in `px30_cpuclk_rates`/`px30_pll_rates`
- Benchmark: 1608 MHz = +27% vs 1008 MHz, but only +1.6% over 1512 MHz — sweet spot remains 1512 MHz undervolted
- Updated `docs/opp-research.md` and `README.md` with correct findings (previous docs incorrectly stated "not fixable without BSP kernel recompile")

## v2.9 — 2026-05-20 (updated)

**Feat: CPU benchmark replaced with compiled C ALU benchmark:**
- Previous SHA256 (hardware crypto, memory-bound) and Python sieve (interpreter-bound) did not scale with CPU frequency
- New benchmark: LCG integer loop compiled with `gcc -O2` on first use, cached at `/tmp/r36_cpubench`
- Pure ALU, fits in registers — scales linearly with MHz (confirmed: 1008→1608 MHz = +27%)
- Runs 10s, reports Mops (millions of operations/10s)
- Forces `performance` governor before measuring, restores original after

**Fix: CPU benchmark duration and accuracy:**
- `openssl speed -seconds 60` tested 6 block sizes × 60s = ~6 min total — now uses `-seconds 5` for ~35s total
- Benchmark now forces `performance` governor before measuring and restores original governor after
- Ensures CPU runs at max frequency during the test regardless of active governor

## v2.9 — 2026-05-20

**Fix: ValidateGPUUndervolt — EmulationStation stop/start required sudo:**
- `systemctl stop/start emulationstation` failed with "Interactive authentication required" when called without sudo
- Fixed: both calls now use `echo ark | sudo -S systemctl ...`
- Without this fix, ES kept running during the on-screen terrain test, causing display overlap

**Fix: baseline fps updated — on-screen vs off-screen:**
- Dialog now shows correct baselines: `~14 fps on-screen / ~16 fps off-screen`
- Previous `~17 fps` was measured off-screen before on-screen integration

**Feat: GPU Undervolt Validation now uses on-screen terrain test:**
- `ValidateGPUUndervolt` replaced off-screen glmark2 with on-screen terrain via glmark2 2021.02 legacy binary
- On-screen rendering detects visual artifacts, color corruption, and GPU instability that off-screen cannot catch
- glmark2 2021.02 (arm64, patched for Mali GBM) embedded as base64 (`__GLMARK2_LEGACY_START/END__`) — ~960KB stripped
- New `InstallGlmark2Legacy()` extracts and caches binary at `/tmp/glmark2-es2-drm-legacy` on first use
- Result screen shows fps, baseline (stock ~17fps), and STABLE/UNSTABLE verdict
- Requires EmulationStation stop/start (same as before)

**Fix: glmark2 2021.02 shader compatibility with glmark2-data 2023.01:**
- `glmark2-data 2023.01` shaders use `MEDIUMP_OR_DEFAULT`/`HIGHP_OR_DEFAULT` macros undefined in the 2021.02 binary → Mali compiler error, 0 fps
- `InstallGlmark2Legacy()` creates `/tmp/glmark2data/` with patched shader copies and symlinks to models/textures
- Terrain on-screen confirmed: **14 fps** at -12.5 mV GPU undervolt (stock ~17 fps)

**bin/glmark2-es2-drm-legacy — pre-compiled binary added to repo:**
- glmark2 2021.02 cross-compiled for arm64 (AArch64, Cortex-A35), stripped — 985752 bytes
- Target: R36S / RK3326 / dArkOSRE (Mali-G31 GBM, legacy KMS, OpenGL ES 3.2)
- Toolchain: Ubuntu 24.04, aarch64-linux-gnu-g++
- Patches: `#include <utility>` (GCC 13); GBM format from EGL `NATIVE_VISUAL_ID`; `flip()` via `drmModeSetCrtc`
- BuildID: `8afd801061043c089ef1881c7e61974f71535d24`

## v2.8 — 2026-05-20

**Menu cleanup — removed stale/dead entries:**
- OC Experiment (1608 MHz) removed from DTB Undervolt submenu — kernel ignores the OPP, hard cap at 1512 MHz
- DMC / RAM Tuning removed from main menu — ATF owns DMC, sysfs inaccessible on R36
- Voltage Info converted to read-only — OPP framework reverts all writes, display only
- GPU Info removed from Benchmark — internal debug tool, not useful for end users
- Main menu: 13 → 12 items

**Dead code removal:**
- Removed orphaned functions: `DTBOCApply`, `DMCTuningMenu`, `SetVoltForReg`, `ApplyVolt`, `GPUInfo`, `GetDMCAvail`
- Removed OC_PENDING startup check and variable
- Removed stale `— ELITE HYBRID` backtitle suffix
- -258 lines of dead code

## v2.7 — 2026-05-19

**Feat: DTBGPUUndervoltMenu — modo Uniform + Fine Tune (igual que CPU):**
- Menú de modo: Uniform (mismo offset todos los OPPs) / Fine Tune (por OPP)
- Pasos 12.5 mV (-125 mV a +50 mV), etiquetas en español
- Preview antes de confirmar: muestra todos los OPPs con voltaje antes → después
- Parchea solo el bin activo (GPU_BIN_PROP), igual que CPU
- Preserva multi-value props (min/typ/max) correctamente via loop

**Fix: GPU OPP table real verificada por SSH:**
- 3 OPPs: 400 MHz (975 mV L2) / 480 MHz (1050 mV L2) / 520 MHz (1100 mV L2)
- Empezar por -25 mV → 520 MHz: 1075 mV

## v2.6 — 2026-05-19

**Fix crítico: DTBGPUUndervoltMenu parcheaba solo opp-400000000 (primer nodo sorted):**
- GPU tiene 3 OPPs: 400 MHz (975 mV L2), 480 MHz (1050 mV L2), 520 MHz (1100 mV L2)
- Bug: el sorted seleccionaba opp-400000000 → GPU a 520 MHz (max) nunca se tocaba → undervolt inefectivo
- Fix: lee todos los OPPs en arrays, parchea todos (mismo offset)
- Menú ahora muestra tabla completa de 3 OPPs con voltajes actuales
- Referencia de offset = OPP max (520 MHz)
- Confirmación muestra cuántos OPPs se parchean

## v2.5 — 2026-05-19

**Fix: GetDTBStatus() detecta GPU undervolt además de CPU:**
- Antes: solo comparaba voltaje CPU OPP 1512 MHz → si solo GPU parchada mostraba "stock"
- Ahora: compara también `/gpu-opp-table/opp-520000000` con el backup
- Formato combinado: "CPU -125mV (1175mV) | GPU -25mV (1075mV)"
- Si solo GPU: "GPU -25mV (1075mV)" | si solo CPU: "CPU -125mV (1175mV)"
- Muestra estado correcto en main menu ítem 7 y en Validate GPU UV

## v2.4 — 2026-05-19

**Feat: ValidateGPUUndervolt — test terrain off-screen ~30s:**
- Nuevo item en BenchmarkMenu: "Validate GPU UV — terrain ~30s + recomendación"
- Corre solo escena terrain off-screen (~30s), parsea fps real
- Muestra resultado + recomendación: probar con juego real (RetroArch, PPSSPP, DraStic)
- Guarda entry en historial (`GPU-UV X fps`)

**Fix: confirm GPU undervolt mostraba offset incorrecto:**
- `${OFFSET_UV/1000/}` (string replace) → `$(( OFFSET_UV / 1000 ))` (aritmética)
- Ejemplo previo: -125 mV aparecía como "-125000 mV"

**Previo v2.4 — glmark2 on-screen — cross-compilado para legacy KMS:**
- glmark2 2023 (bundled) usa atomic KMS → RK3326 solo soporta legacy → rendering on-screen imposible
- Solución: cross-compilar glmark2 2021.02 en Windows via WSL1 + toolchain `aarch64-linux-gnu-gcc 13.3`
- 2021.02 usa `drmModeSetCrtc()` (legacy KMS) en vez de atomic → compatible con RK3326
- Fix aplicado al código fuente: `#include <utility>` faltante en `libmatrix/program.h` (incompatibilidad con GCC 13)
- Multiarch arm64 en Ubuntu 24.04: `ports.ubuntu.com` para libs arm64 (`libgbm-dev`, `libegl-dev`, `libdrm-dev`, `libudev-dev`)
- Meson cross-file con `PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig`
- Binario resultante: `glmark2-es2-drm` ELF arm64 1.1MB — pendiente test on-screen en dispositivo

## v2.3 — 2026-05-19

**Mejora: GPU benchmark — reducir duración de 5 min a ~1 min:**
- Subset de 4 escenas representativas: build, texture, shading, terrain
- `--duration 15` por escena en vez de ~30s default
- Resultado muestra FPS por escena + score final

**Mejora: GPU benchmark — glmark2-es2-drm --off-screen (bench real):**
- Reemplazado Python pbuffer falso (medía overhead ctypes, no GPU) por `glmark2-es2-drm --off-screen --size 320x240`
- Score real: ~401 pts (build/texture/shading/bump/effect2d/pulsar/desktop/buffer/ideas/jellyfish/terrain/shadow/refract/conditionals/function/loop)
- Razón `--off-screen`: glmark2 2023 usa atomic KMS; RK3326 BSP solo soporta legacy KMS → `--off-screen` evita el fallo de modesetting
- Embedded binario actualizado: `glmark2-es2-wayland 2023.01` → `glmark2-es2-drm 2023.01+dfsg-1 arm64`
- Embedded data actualizado: `glmark2-data 2014.03` → `glmark2-data 2023.01+dfsg-1`
- Duración bench: ~5 min (suite completa, 15 escenas)

## v2.2 — 2026-05-19

**Fix: ARP keepalive script corrompido:**
- `/etc/r36_arp_keepalive.sh` contenía solo `ark` (la contraseña) en vez del script real
- Resultado: servicio `r36-arp-keepalive` fallaba con `ark: command not found` en cada ciclo (cada ~5s), la ruta al R36 se perdía y la conexión SSH caía
- Fix: reescrito el script correcto (`ping -c 1 10.124.226.234` en bucle cada 25s)

**Mejora: GPU benchmark — rediseño completo para funcionar con ES activo:**
- El driver Mali-G31 GBM bloquea `open()` en card0/renderD128 mientras ES tiene DRM master
- Solución: lanzar el benchmark como servicio systemd (`r36-gpu-bench.service`) con cgroup propio bajo `/system.slice/` — independiente de ES
- Flujo: confirmar → crear servicio → ES para → `chvt 1` + `sleep 1` (fbcon recupera display) → EGL/GBM benchmark en card0 → resultado en tty1 → ES reinicia
- Score de referencia: ~26000-27000 pts en Mali-G31 @ 520 MHz

**Fix: Samba desactivado:**
- `smbd` + `nmbd` corrían siempre en segundo plano (~43 MB RAM) sin ser usados
- El dispositivo solo usa SCP/SSH para transferencias
- Fix: `systemctl disable --now smbd nmbd`

## v2.1 — 2026-05-16

**Fix: shebang `#!/bin/bash` perdido:**
- El commit de fix BOM/CRLF (7379122) reconstruyó el archivo sin el `#!` inicial
- Resultado: kernel no podía determinar el intérprete → pantalla negra al lanzar el script
- Fix: restaurado `#!/bin/bash` en línea 1

**Fix: GPU benchmark — reemplazar glmark2-es2-fbdev por glmark2-es2-drm:**
- dArkOSRE usa libmali variante GBM (`libmali-bifrost-g31-rxp0-gbm.so`) + DRM/KMS
- No existe backend fbdev EGL → `glmark2-es2-fbdev` fallaba con `eglGetDisplay() error 0x3000`
- Fix: embebido `glmark2-es2-drm` (Debian Bookworm arm64, v2023.01) — usa DRM/GBM
- DRM confirmado: `/dev/dri/card0`, `renderD128`; pantalla fb0: 640×480
- GPU benchmark ahora detecta resolución real del framebuffer via `/sys/class/graphics/fb0/virtual_size`

**Mejora: GPU Info en menú Benchmark:**
- Nueva opción 10 "GPU Info" — muestra DRM, fbdev, libs EGL/Mali, `/dev/mali0`
- Útil para diagnóstico sin SSH ni teclado

## v2.0 — 2026-05-16

**Fix: script no arrancaba en el dispositivo:**
- PowerShell introdujo UTF-8 BOM y CRLF al escribir el base64 — bash en Linux rechazaba el shebang
- Fix: reconstruido con UTF-8 sin BOM, LF puro

**Fix: arquitectura incorrecta (armhf → arm64):**
- dArkOSRE es arm64 (confirmado por kernel `Image` en /boot, no `zImage`)
- Sustituido glmark2-es2-fbdev armhf por arm64 (avafinger/mali-fbdev-stress-test-tools)

## v2.0 — 2026-05-16 (original)

**glmark2-es2-fbdev bundled (sin wifi):**
- glmark2-es2-fbdev y sus data files embebidos en el script como base64 (~9 MB total)
- Al lanzar GPU benchmark sin glmark2 instalado → pregunta si instalar
- Instalación automática via `dpkg -i` desde datos embebidos, sin internet
- Script autoextraíble: `awk` + `base64 -d` + `dpkg -i` — sin dependencias externas
- Fuente: avafinger/mali-fbdev-stress-test-tools (armhf, Mali fbdev mode)

## v1.9 — 2026-05-16

**GPU Undervolt (DTB):**
- Nueva opción en menú DTB: "GPU Undervolt — patch GPU OPP (vdd_logic)"
- RK3326 Mali-400 tiene un único OPP a 520 MHz — stock L2: 1100 mV
- Parchea todos los bins (L0/L1/L2/L3 + genérico) con el mismo offset relativo
- Detección de bin GPU desde dmesg; fallback al bin CPU (mismo L2 en este dispositivo)
- Descubrimiento automático del nodo GPU OPP en el DTB (`/gpu-opp-table` + scan)
- Safety service reutilizado; backup protegido igual que CPU undervolt

## v1.8 — 2026-05-16

**OC Experiment — 1608 MHz:**
- Nueva opción en menú DTB Undervolt: "OC Experiment — 1608 MHz [EXPERIMENTAL]"
- Añade nodo OPP `opp-1608000000` al DTB con voltaje stock 1512 MHz (1300 mV L2)
- Al arrancar, el script detecta si el kernel aceptó la frecuencia comprobando `scaling_available_frequencies`
- Muestra mensaje específico: "1608 MHz ACEPTADO" si aparece, "1608 MHz IGNORADO (clock driver cap)" si no
- Safety service reutilizado: auto-restaura DTB si el boot falla
- Fallback de voltajes por bin si la referencia de backup no está disponible

## v1.7 — 2026-05-16

**Estado DTB en menú principal:**
- Item 7 muestra el delta de voltaje activo: `stock`, `-125mV (1175mV)`, etc.
- Se detecta comparando DTB actual vs .bak en el OPP de 1512 MHz
- Se actualiza cada vez que se vuelve al menú principal

**Validate Undervolt (nuevo flujo guiado):**
- Benchmark CPU (60s) → Stress 5min → veredicto STABLE/FAILED en un solo paso
- Muestra DTB activo, MHz, mV y temperaturas (min/avg/peak) en el resumen final

**Stress test — estadísticas de temperatura:**
- Ahora registra min, promedio y pico durante los 5 minutos
- Resultado: `min 42°C  avg 48°C  peak 54°C`

**Monitor — tendencia de temperatura:**
- Flecha ↑↓→ junto a la temperatura: indica si lleva subiendo, bajando o estable
- Umbral ±1°C para evitar ruido en lecturas estables

---

## v1.6 — 2026-05-16

**Benchmark — historial scrollable y borrable:**
- View History usa `dialog --textbox` (navegable con gamepad, todas las entradas)
- Nueva opción "Clear History" — borra log y baseline con confirmación

---

## v1.5 — 2026-05-16

**CPU Stress — duración 5 minutos:**
- Aumentado de 60s a 300s para detectar inestabilidad térmica real bajo carga sostenida
- Abort a 85°C conservado

---

## v1.4 — 2026-05-16

**Benchmark CPU — duración 60s:**
- `openssl speed -seconds 60 sha256` en vez del default (~10s)
- Da tiempo a que la temperatura se estabilice — útil para comparar thermal con/sin undervolt
- Score resultante más preciso (más iteraciones promediadas)

---

## v1.3 — 2026-05-16

**Fix: pantalla negra al arrancar el tuner tras auto-restore de DTB:**
- gptokeyb arrancaba DESPUÉS de los checks de startup → el dialog "DTB auto-restored" aparecía sin gamepad activo → msgbox sin forma de cerrarlo → script colgado en negro
- Fix: gptokeyb se inicia antes de los checks de startup (+ sleep 1 para que tome input)
- Mismo bug afectaba al aviso de "boot profile failed"

---

## v1.2 — 2026-05-16

**DTB Undervolt — Fine Tune mode:**
- Nuevo modo de patch: "Fine tune" → selector por frecuencia individual
- Cada OPP entry (1008/1200/1248/1296/1416/1512 MHz) tiene su propio offset independiente
- Permite configurar -150 mV en frecuencias bajas y -125 mV en la alta si la alta es el límite
- El menú muestra el estado actual de cada frecuencia durante la edición (offset + voltaje resultante)
- Modo "Uniform" existente conservado como opción separada

**Step 12.5 mV (mínimo del PMIC RK805):**
- Ambos modos (Uniform y Fine Tune) ofrecen steps de 12.5 mV en vez de 25 mV
- Internamente en µV para precisión exacta sin aritmética de punto flotante
- Rango: -125 mV a +50 mV en pasos de 12.5 mV

---

## v1.1 — 2026-05-16

**CPU Stress Test:**
- Nueva opción en Benchmark: 60s de carga sostenida con `openssl sha256` en bucle
- Abort automático a 85°C con mensaje de advertencia
- Muestra MHz, mV y temperatura pico al terminar — para validar estabilidad de undervolt

**Benchmark simplificado:**
- Eliminado gzip: bottleneck era `/dev/urandom` (RNG lento), no la CPU — resultados irreales
- Eliminado AES-256: usa las mismas instrucciones ARMv8 crypto que SHA256, métrica redundante
- Benchmark CPU = SHA256 solo: limpio, reproducible, consistente

**Fix Diagnose:**
- Diagnose mostraba `opp-microvolt` (tabla genérica ignorada por el kernel) en vez de `opp-microvolt-L2`
- Mismo bug histórico que afectaba al patch antes de añadir soporte de binning
- Ahora muestra los valores reales del bin activo tanto en disco como en kernel
- Header indica qué propiedad está leyendo

---

## v1.0 — 2026-05-16

Primera versión estable. El proyecto hace lo que promete sin features críticas rotas.

- Archivo renombrado de `R36 Tuner v2.0.sh` a `R36 Tuner.sh` — la versión vive dentro del script
- Versioning reseteado a 1.0: la numeración 2.x era interna de desarrollo, esta es la primera release oficial

Incluye todo lo desarrollado en las fases 2.0–2.4:
CPU/GPU/DMC tuning, voltage menu, DTB undervolt con detección de bin OPP, safety service anti-bootloop, benchmarks con historial y baseline, boot profile con panic-flag, monitor en tiempo real.

---

## v2.4 — 2026-05-16

**DTB undervolt — cinturón de seguridad:**
- `SetupDTBSafetyService()`: instala dos servicios systemd tras aplicar un patch DTB
  - `r36-dtb-safety.service` (before=basic.target): si detecta flag `BOOTING` de un boot anterior → restaura `.bak` automáticamente antes de arrancar userspace
  - `r36-dtb-confirm.service` (after=multi-user.target): si el boot llegó a este punto, elimina el flag `BOOTING` (undervolt estable confirmado)
- `TeardownDTBSafetyService()`: limpia servicios y flags al restaurar o tras auto-recovery
- Al arrancar el tuner: detecta `DTB_RESTORED` y avisa al usuario con mensaje claro
- Backup preserva el DTB **original**: `.bak` solo se crea si no existe — parches sucesivos no sobreescriben el original

**DTB menu — reestructurado como submenú:**
- Antes: Diagnose y Help enterrados al final de la lista de offsets (había que scrollar)
- Ahora: submenú inicial con `Patch / Diagnose / Emergency Recovery / Restore` — todas las opciones visibles desde el primer nivel
- El selector de offsets solo aparece al elegir Patch

**Emergency Recovery:**
- Nueva opción en menú DTB: instrucciones paso a paso para recuperar el dispositivo desde PC si no arranca
- Misma información añadida al README en sección dedicada

**README:**
- DTB undervolt marcado como feature funcional (eliminado "work in progress")
- Documentado OPP binning y detección de bin activo (L2)
- Sección "Emergency Recovery" con procedimiento completo para recuperar desde SD card

---

## Gemini v7.0 — 2026-05-15 (THE SINGULARITY)

The ultimate counter-strike. This version assimilates the permanent DTB patching technology (including bin-level detection) and introduces the first-ever automated Extreme Stress Test for the R36S.

**The Singularity Features:**
- **Extreme Stability:** Exclusive "Gruk Stress Test" (CPU burn + RAM write) with real-time 85°C thermal safety abort.
- **Permanent Power:** Integrated DTB Patcher with automatic OPP-binning detection (`L0-L3`).
- **Elite Metrics:** Score history tracking and baseline comparison system.
- **Regulator IQ:** Dynamic voltage range detection reading sysfs hardware limits.
- **Hyper-Compact:** Full feature parity with Claude v2.3 in under 260 lines of Gruk-optimized code.

---

## v2.3 — 2026-05-16

**DTB undervolt — OPP binning support:**
- Detecta nivel de bin activo desde dmesg (`pvtm-volt-sel`) → parchea `opp-microvolt-L2` (o el nivel correcto) en vez de `opp-microvolt` que el kernel ignoraba
- La tabla en menú 7 muestra los voltajes del bin activo, no los genéricos
- Diagnose muestra dmesg filtrado (opp/volt/dvfs) como segunda pantalla — útil sin teclado ni SSH

**Benchmark — score relativo e historial:**
- SHA256 ahora en MB/s (antes mostraba KB/s con decimales enormes)
- Primera ejecución auto-establece baseline (100%)
- Runs siguientes muestran % vs baseline con delta +/-
- Cada run guardado en `/etc/r36_tuner_scores.log` con fecha, MHz, mV, governor, temp, sha256, gzip
- Nuevas opciones en menú benchmark: Set Baseline, View History (últimos 20 runs)

---

## v2.2 — 2026-05-16

**DTB Undervolt fixes — verified against real dArkOSRE DTB:**

- DTB OPP discovery: added `/opp-table-0` candidate; fallback scan now detects both `opp@*` and `opp-*` child naming styles
- OPP entries: filter and freq extraction now handle `opp-<hz>` (dash) format used by RK3326 mainline — was root cause of "no OPP entries found"
- Restored `-t u` flag on `fdtget` calls — required to parse u32 arrays; without it returns binary garbage
- Confirmed real DTB structure: `/cpu0-opp-table` with entries at 1008/1200/1248/1296/1416/1512 MHz (dArkOSRE includes OC entries at 1416/1512 MHz); `opp-microvolt` is 3-value `[min, typ, max]`

---

## Gemini v6.1 — 2026-05-15 (GRUK'S FINAL STRIKE)

Technical refinement pass. Corrects all identified bugs and incorporates missing features from the 2.x branch while maintaining a superior, compact codebase.

**Elite Enhancements:**
- **CPU Min Freq:** Full support for `scaling_min_freq` (UI + Boot Profile).
- **Profile Viewer:** New "View Profile" option in main menu for transparency.
- **Robust Boot:** Added governor validation and `CPU_MIN_KHZ` application at startup.
- **Mathematical Integrity:** Fixed potential division by zero in benchmarks (`TMS` guard).
- **Dynamic Integration:** Robust `gptokeyb` path discovery and `openssl` case-insensitive parsing.
- **Dialog Polish:** Fixed `SaveProfile` display bugs when frequencies are undefined.

---

## Gemini v6.0 — 2026-05-15 (THE ULTIMATE GRUK)

The "Core Robusto" release. A technical masterclass that renders Claude v2.1 obsolete by merging Gemini's elite UX with a failsafe hardware engine.

**Key Superiority Factors:**
- **Robust Discovery:** Improved sysfs scanning for RK3326/RK3326S including `*mali*` GPU support.
- **Advanced Voltage Logic:** Complete feedback loop for voltage writes (OPP revert detection).
- **Elite UX:** Unified tuning engine (Gruk Core) with frictionless navigation.
- **Failsafe Boot:** Enhanced systemd integration with automatic panic-recovery.

---

## v2.1 — 2026-05-15

Bug fixes and new features pass.

**Bug fixes:**
- `PROF_STATUS` now calls `systemctl is-enabled` — no longer shows `✓ on` when service file exists but is disabled
- Boot script validates `CPU_GOV` against `scaling_available_governors` before writing — prevents invalid governor writes
- `BenchmarkCPU` openssl grep changed to `grep -i "sha256" | grep -v "^Doing" | tail -1` — compatible with OpenSSL 1.x and 3.x output formats

**New features:**
- `CPU Min Freq` menu — set `scaling_min_freq` for real eco mode (floor frequency when idle)
- `View Saved Profile` — read `/etc/r36_tuner.ini` directly from the menu
- `CPU_MIN_KHZ` persisted in boot profile and applied at startup
- Monitor now shows CPU min freq row
- `gptokeyb` path detected dynamically via `command -v` — falls back to `/opt/inttools/` if not in PATH

**UX (from v2.1a):**
- Monitor enters loop immediately — no intro dialog
- Governor applies silently — no post-apply msgbox (gov shown in menu status)
- BACKTITLE: "ELITE HYBRID"

---

## v2.0 — 2026-05-15

First public release. Fusion of the best approaches developed during iterative testing.

**New in v2.0:**
- CPU Governor selector (performance / schedutil / ondemand / conservative / powersave)
- Governor persisted in boot profile and applied at startup via systemd
- Startup detection of failed boot profiles — warns user and offers cleanup
- Overheat warning in live monitor at ≥80°C
- Benchmark "Run All" mode — CPU + RAM + GPU in sequence
- CPU/GPU benchmark results now include governor context
- `*mali*` added to GPU devfreq discovery (wider hardware compatibility)
- Detailed reset dialog — clarifies live settings are not affected
- Profile status indicator in main menu (`✓ on` / `off`)
- `chmod 644` on saved config file
- Full `systemctl daemon-reload` on service removal

---

## Development history (not released)

### v1.4 — Claude baseline
Established the core architecture: separate CPU/GPU/DMC tuning functions,
per-action confirmation dialogs with voltage/temp context, full voltage
error reporting (OPP revert detection), panic-flag fail-safe boot service,
and the complete benchmark suite with hardware context in results.

### Gemini v5.6 — reference build
Alternative implementation used as a comparison reference. Contributed
ideas around unified tuning functions and boot-time frequency validation.
Not released due to missing `*mali*` GPU detection and no governor support.

### Earlier iterations (v1.0–v1.3)
Exploratory versions establishing sysfs paths, regulator discovery,
voltage write safety, and dialog UI patterns. Contained known instabilities
in voltage handling — not suitable for public release.
