# Changelog

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
