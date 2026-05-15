# Changelog

## v2.1 — 2026-05-15

UX polish pass — taking Gemini v5.6's best frictionless patterns into the clean v2.0 architecture.

**Changes:**
- Monitor enters loop immediately — no intro dialog
- Governor applies silently — no post-apply msgbox (gov shown in menu status)
- BACKTITLE updated: "ELITE HYBRID"
- gptokeyb app name bumped to v2.1

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
