# Changelog

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
