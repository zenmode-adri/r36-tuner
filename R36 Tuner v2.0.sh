#!/bin/bash
# R36 Tuner v2.1 — CPU / GPU / DMC / Voltage tuning for R36S (RK3326)
# Part of dArkOSRE R36 — https://github.com/southoz/dArkOSRE-R36

if [ "$(id -u)" -ne 0 ]; then exec sudo -- "$0" "$@"; fi

VERSION="2.1"
CURR_TTY="/dev/tty1"
BACKTITLE="R36 Tuner v${VERSION} — ELITE HYBRID"
CONFIG_FILE="/etc/r36_tuner.ini"
BOOT_SCRIPT="/usr/local/bin/r36-tuner-apply.sh"
SVC_FILE="/etc/systemd/system/r36-tuner.service"
PANIC_FLAG="/etc/.r36_tuner_panic"

export TERM=linux
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# ── Hardware Discovery ────────────────────────────────────────────────────────

FindRegulatorDir() {
    for d in /sys/class/regulator/regulator.*; do
        [ "$(cat "$d/name" 2>/dev/null)" = "$1" ] && echo "$d" && return
    done
}

FindGPUDevfreq() {
    for d in /sys/class/devfreq/*; do
        case "$(basename "$d")" in *gpu*|*mali*|*ff400000*) echo "$d"; return ;; esac
    done
}

FindDMCDevfreq() {
    for d in /sys/class/devfreq/*; do
        case "$(basename "$d")" in *dmc*|*ff600000*) echo "$d"; return ;; esac
    done
}

CPU_POLICY="/sys/devices/system/cpu/cpufreq/policy0"
GPU_DEVFREQ=$(FindGPUDevfreq)
DMC_DEVFREQ=$(FindDMCDevfreq)
TEMP_ZONE="/sys/class/thermal/thermal_zone0/temp"
VDD_ARM=$(FindRegulatorDir "vdd_arm")
VDD_LOGIC=$(FindRegulatorDir "vdd_logic")
VCC_DDR=$(FindRegulatorDir "vcc_ddr")

# Detect gptokeyb — prefer system PATH, fall back to dArkOSRE location
GPTOKEYB_BIN=$(command -v gptokeyb 2>/dev/null || echo "/opt/inttools/gptokeyb")
GPTOKEYB_CFG="/opt/inttools/keys.gptk"

# ── UI Setup ─────────────────────────────────────────────────────────────────

sudo chmod 666 "$CURR_TTY"
sudo chmod 666 /dev/uinput
printf "\033c" > "$CURR_TTY"
printf "\e[?25l" > "$CURR_TTY"
dialog --clear

if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
    sudo setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz
else
    sudo setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz
fi

# ── Data Readers ──────────────────────────────────────────────────────────────

GetCPUCurMHz()  { local f; f=$(cat "$CPU_POLICY/scaling_cur_freq" 2>/dev/null); [ -n "$f" ] && echo $((f/1000)) || echo "N/A"; }
GetCPUMaxMHz()  { local f; f=$(cat "$CPU_POLICY/scaling_max_freq" 2>/dev/null); [ -n "$f" ] && echo $((f/1000)) || echo "N/A"; }
GetCPUMinMHz()  { local f; f=$(cat "$CPU_POLICY/scaling_min_freq" 2>/dev/null); [ -n "$f" ] && echo $((f/1000)) || echo "N/A"; }
GetGPUCurMHz()  { [ -z "$GPU_DEVFREQ" ] && echo "N/A" && return; local f; f=$(cat "$GPU_DEVFREQ/cur_freq" 2>/dev/null); [ -n "$f" ] && echo $((f/1000000)) || echo "N/A"; }
GetGPUMaxMHz()  { [ -z "$GPU_DEVFREQ" ] && echo "N/A" && return; local f; f=$(cat "$GPU_DEVFREQ/max_freq" 2>/dev/null); [ -n "$f" ] && echo $((f/1000000)) || echo "N/A"; }
GetDMCCurMHz()  { [ -z "$DMC_DEVFREQ" ] && echo "N/A" && return; local f; f=$(cat "$DMC_DEVFREQ/cur_freq" 2>/dev/null); [ -n "$f" ] && echo $((f/1000000)) || echo "N/A"; }
GetDMCMaxMHz()  { [ -z "$DMC_DEVFREQ" ] && echo "N/A" && return; local f; f=$(cat "$DMC_DEVFREQ/max_freq" 2>/dev/null); [ -n "$f" ] && echo $((f/1000000)) || echo "N/A"; }
GetTempC()      { local t; t=$(cat "$TEMP_ZONE" 2>/dev/null); [ -n "$t" ] && echo $((t/1000)) || echo "N/A"; }
GetGOV()        { cat "$CPU_POLICY/scaling_governor" 2>/dev/null || echo "N/A"; }
GetRegVoltMV()  { local d="$1"; [ -z "$d" ] && echo "N/A" && return; local u; u=$(cat "$d/microvolts" 2>/dev/null); [ -n "$u" ] && echo $((u/1000)) || echo "N/A"; }

GetCPUAvail()   { cat "$CPU_POLICY/scaling_available_frequencies" 2>/dev/null | tr ' ' '\n' | sort -rn | grep -v '^$'; }
GetGPUAvail()   { [ -z "$GPU_DEVFREQ" ] && return; cat "$GPU_DEVFREQ/available_frequencies" 2>/dev/null | tr ' ' '\n' | sort -rn | grep -v '^$'; }
GetDMCAvail()   { [ -z "$DMC_DEVFREQ" ] && return; cat "$DMC_DEVFREQ/available_frequencies" 2>/dev/null | tr ' ' '\n' | sort -rn | grep -v '^$'; }

# ── Voltage Write ────────────────────────────────────────────────────────────
# Returns: 0=ok 1=range 2=read-only 3=not found 4=OPP reverted

ApplyVolt() {
    local dir="$1" mv="$2"
    [ -z "$dir" ] && return 3
    if ! [[ "$mv" =~ ^[0-9]+$ ]]; then return 1; fi
    local reg_min_raw; reg_min_raw=$(cat "$dir/min_microvolts" 2>/dev/null || echo 0)
    local reg_max_raw; reg_max_raw=$(cat "$dir/max_microvolts" 2>/dev/null || echo 0)
    if [ "$reg_min_raw" -gt 0 ] && [ "$reg_max_raw" -gt 0 ]; then
        local reg_min=$(( reg_min_raw / 1000 ))
        local reg_max=$(( reg_max_raw / 1000 ))
        [ "$mv" -lt "$reg_min" ] || [ "$mv" -gt "$reg_max" ] && return 1
    fi
    [ ! -w "$dir/microvolts" ] && return 2
    local uv=$(( mv * 1000 ))
    local cur_min; cur_min=$(cat "$dir/min_microvolts" 2>/dev/null || echo 0)
    local cur_max; cur_max=$(cat "$dir/max_microvolts" 2>/dev/null || echo 9999999)
    [ "$uv" -lt "$cur_min" ] && echo "$uv" > "$dir/min_microvolts" 2>/dev/null
    [ "$uv" -gt "$cur_max" ] && echo "$uv" > "$dir/max_microvolts" 2>/dev/null
    echo "$uv" > "$dir/microvolts" 2>/dev/null
    sleep 0.1
    local actual; actual=$(cat "$dir/microvolts" 2>/dev/null || echo 0)
    [ "$actual" -eq "$uv" ] && return 0 || return 4
}

# ── Config & Boot Service ─────────────────────────────────────────────────────

SaveConfig() {
    local cpu_max_hz; cpu_max_hz=$(cat "$CPU_POLICY/scaling_max_freq" 2>/dev/null || echo "")
    local cpu_min_hz; cpu_min_hz=$(cat "$CPU_POLICY/scaling_min_freq" 2>/dev/null || echo "")
    local gpu_hz; gpu_hz=$([ -n "$GPU_DEVFREQ" ] && cat "$GPU_DEVFREQ/max_freq" 2>/dev/null || echo "")
    local dmc_hz; dmc_hz=$([ -n "$DMC_DEVFREQ" ] && cat "$DMC_DEVFREQ/max_freq" 2>/dev/null || echo "")
    local arm_mv; arm_mv=$(GetRegVoltMV "$VDD_ARM")
    local logic_mv; logic_mv=$(GetRegVoltMV "$VDD_LOGIC")
    local ddr_mv; ddr_mv=$(GetRegVoltMV "$VCC_DDR")
    local gov; gov=$(GetGOV)
    [ "$arm_mv"   = "N/A" ] && arm_mv=""
    [ "$logic_mv" = "N/A" ] && logic_mv=""
    [ "$ddr_mv"   = "N/A" ] && ddr_mv=""
    [ "$gov"      = "N/A" ] && gov=""
    printf "# R36 Tuner profile\nCPU_MAX_KHZ=%s\nCPU_MIN_KHZ=%s\nGPU_MAX_HZ=%s\nDMC_MAX_HZ=%s\nVDD_ARM_MV=%s\nVDD_LOGIC_MV=%s\nVCC_DDR_MV=%s\nCPU_GOV=%s\n" \
        "$cpu_max_hz" "$cpu_min_hz" "$gpu_hz" "$dmc_hz" "$arm_mv" "$logic_mv" "$ddr_mv" "$gov" > "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
}

SetupBootService() {
    cat > "$BOOT_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash
CFG="/etc/r36_tuner.ini"
PANIC="/etc/.r36_tuner_panic"

[ -f "$CFG" ] || exit 0

if [ -f "$PANIC" ]; then
    rm -f "$PANIC"
    mv "$CFG" "${CFG}.failed"
    exit 1
fi

touch "$PANIC" && sync
source "$CFG"

val_mv() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 800 ] && [ "$1" -le 1350 ]; }
val_hz() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 100000 ]; }

apply_reg() {
    local name="$1" mv="$2" dir
    for d in /sys/class/regulator/regulator.*; do
        [ "$(cat "$d/name" 2>/dev/null)" = "$name" ] && dir="$d" && break
    done
    [ -z "$dir" ] || ! val_mv "$mv" && return
    [ ! -w "$dir/microvolts" ] && return
    local uv=$(( mv * 1000 ))
    local cur_min; cur_min=$(cat "$dir/min_microvolts" 2>/dev/null || echo 0)
    local cur_max; cur_max=$(cat "$dir/max_microvolts" 2>/dev/null || echo 9999999)
    [ "$uv" -lt "$cur_min" ] && echo "$uv" > "$dir/min_microvolts" 2>/dev/null
    [ "$uv" -gt "$cur_max" ] && echo "$uv" > "$dir/max_microvolts" 2>/dev/null
    echo "$uv" > "$dir/microvolts" 2>/dev/null
    sleep 0.1
}

GPU_DIR="" DMC_DIR=""
for d in /sys/class/devfreq/*; do
    case "$(basename "$d")" in
        *gpu*|*mali*|*ff400000*) GPU_DIR="$d" ;;
        *dmc*|*ff600000*)        DMC_DIR="$d" ;;
    esac
done

CPU_POL="/sys/devices/system/cpu/cpufreq/policy0"
if val_hz "$CPU_MAX_KHZ" && [ -f "$CPU_POL/scaling_max_freq" ]; then
    CUR_KHZ=$(cat "$CPU_POL/scaling_max_freq" 2>/dev/null || echo 0)
    if [ "$CPU_MAX_KHZ" -gt "$CUR_KHZ" ]; then
        apply_reg "vdd_arm" "$VDD_ARM_MV"
        echo "$CPU_MAX_KHZ" > "$CPU_POL/scaling_max_freq"
    else
        echo "$CPU_MAX_KHZ" > "$CPU_POL/scaling_max_freq"
        sleep 0.1
        apply_reg "vdd_arm" "$VDD_ARM_MV"
    fi
fi

val_hz "$CPU_MIN_KHZ" && [ -f "$CPU_POL/scaling_min_freq" ] && echo "$CPU_MIN_KHZ" > "$CPU_POL/scaling_min_freq" 2>/dev/null

if [ -n "$CPU_GOV" ] && [ -f "$CPU_POL/scaling_available_governors" ]; then
    case " $(cat "$CPU_POL/scaling_available_governors" 2>/dev/null) " in
        *" $CPU_GOV "*) echo "$CPU_GOV" > "$CPU_POL/scaling_governor" 2>/dev/null ;;
    esac
fi

apply_reg "vdd_logic" "$VDD_LOGIC_MV"
[ -n "$GPU_DIR" ] && val_hz "$GPU_MAX_HZ" && echo "$GPU_MAX_HZ" > "$GPU_DIR/max_freq" 2>/dev/null && echo "simple_ondemand" > "$GPU_DIR/governor" 2>/dev/null

apply_reg "vcc_ddr" "$VCC_DDR_MV"
[ -n "$DMC_DIR" ] && val_hz "$DMC_MAX_HZ" && echo "$DMC_MAX_HZ" > "$DMC_DIR/max_freq" 2>/dev/null

sleep 2
rm -f "$PANIC" && sync
SCRIPTEOF
    chmod +x "$BOOT_SCRIPT"

    cat > "$SVC_FILE" << EOF
[Unit]
Description=R36 Tuner — apply CPU/GPU/DMC/Voltage profile at boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=$BOOT_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable r36-tuner.service >/dev/null 2>&1
}

RemoveBootService() {
    systemctl disable r36-tuner.service >/dev/null 2>&1
    rm -f "$SVC_FILE" "$BOOT_SCRIPT"
    systemctl daemon-reload
}

# ── CPU Tuning ────────────────────────────────────────────────────────────────

CPUTuningMenu() {
    local AVAIL; AVAIL=$(GetCPUAvail)
    if [ -z "$AVAIL" ]; then
        dialog --backtitle "$BACKTITLE" --title "CPU Tuning" \
            --msgbox "Cannot read $CPU_POLICY/scaling_available_frequencies" 6 55 > "$CURR_TTY"
        return
    fi

    local CUR_MAX; CUR_MAX=$(cat "$CPU_POLICY/scaling_max_freq" 2>/dev/null)
    local CHOICES=()
    while IFS= read -r hz; do
        local mhz=$((hz/1000))
        local m="  "; [ "$hz" = "$CUR_MAX" ] && m="★ "
        CHOICES+=("$hz" "${m}${mhz} MHz")
    done <<< "$AVAIL"

    local COUNT=$(( ${#CHOICES[@]} / 2 ))
    local H=$(( COUNT + 7 )); [ $H -gt 20 ] && H=20

    local SEL
    SEL=$(dialog --backtitle "$BACKTITLE" \
                 --title "[ CPU MAX FREQUENCY ]" \
                 --default-item "$CUR_MAX" \
                 --menu "Voltage auto via OPP  |  Voltage menu for undervolt  |  ★ = current" \
                 $H 62 $COUNT \
                 "${CHOICES[@]}" \
                 2>&1 > "$CURR_TTY")
    [ -z "$SEL" ] && return

    echo "$SEL" > "$CPU_POLICY/scaling_max_freq" 2>/dev/null
    local MHZ=$(( SEL / 1000 ))
    dialog --backtitle "$BACKTITLE" --title "✓ CPU Max Updated" \
        --msgbox "CPU max  →  ${MHZ} MHz\nvdd_arm  :  $(GetRegVoltMV "$VDD_ARM") mV  (OPP table)\nTemp     :  $(GetTempC)°C" 7 52 > "$CURR_TTY"
}

# ── CPU Min Frequency ─────────────────────────────────────────────────────────

CPUMinFreqMenu() {
    local AVAIL; AVAIL=$(GetCPUAvail)
    if [ -z "$AVAIL" ]; then
        dialog --backtitle "$BACKTITLE" --title "CPU Min Frequency" \
            --msgbox "Cannot read $CPU_POLICY/scaling_available_frequencies" 6 55 > "$CURR_TTY"
        return
    fi

    local CUR_MIN; CUR_MIN=$(cat "$CPU_POLICY/scaling_min_freq" 2>/dev/null)
    local CUR_MAX; CUR_MAX=$(cat "$CPU_POLICY/scaling_max_freq" 2>/dev/null)
    local CHOICES=()
    while IFS= read -r hz; do
        local mhz=$((hz/1000))
        local m="  "; [ "$hz" = "$CUR_MIN" ] && m="★ "
        CHOICES+=("$hz" "${m}${mhz} MHz")
    done <<< "$(echo "$AVAIL" | sort -n)"

    local COUNT=$(( ${#CHOICES[@]} / 2 ))
    local H=$(( COUNT + 7 )); [ $H -gt 20 ] && H=20

    local SEL
    SEL=$(dialog --backtitle "$BACKTITLE" \
                 --title "[ CPU MIN FREQUENCY ]" \
                 --default-item "$CUR_MIN" \
                 --menu "Floor freq when idle  |  Max is $(( CUR_MAX / 1000 )) MHz  |  ★ = current" \
                 $H 62 $COUNT \
                 "${CHOICES[@]}" \
                 2>&1 > "$CURR_TTY")
    [ -z "$SEL" ] && return

    local MAX_KHZ; MAX_KHZ=$(cat "$CPU_POLICY/scaling_max_freq" 2>/dev/null || echo 9999999)
    if [ "$SEL" -gt "$MAX_KHZ" ]; then
        dialog --backtitle "$BACKTITLE" --title "[ CPU MIN FREQUENCY ]" \
            --msgbox "Min freq cannot exceed max freq ($(( MAX_KHZ / 1000 )) MHz)." 6 52 > "$CURR_TTY"
        return
    fi

    echo "$SEL" > "$CPU_POLICY/scaling_min_freq" 2>/dev/null
    local MHZ=$(( SEL / 1000 ))
    dialog --backtitle "$BACKTITLE" --title "✓ CPU Min Updated" \
        --msgbox "CPU min  →  ${MHZ} MHz\nTemp     :  $(GetTempC)°C" 6 45 > "$CURR_TTY"
}

# ── CPU Governor ──────────────────────────────────────────────────────────────

GovernorMenu() {
    local AVAIL_GOV; AVAIL_GOV=$(cat "$CPU_POLICY/scaling_available_governors" 2>/dev/null)
    if [ -z "$AVAIL_GOV" ]; then
        dialog --backtitle "$BACKTITLE" --title "CPU Governor" \
            --msgbox "Cannot read available governors from:\n$CPU_POLICY/scaling_available_governors" 7 55 > "$CURR_TTY"
        return
    fi

    local CUR_GOV; CUR_GOV=$(GetGOV)
    local CHOICES=()
    for g in $AVAIL_GOV; do
        local m="  "; [ "$g" = "$CUR_GOV" ] && m="★ "
        local desc
        case "$g" in
            performance)  desc="Always max freq — best for gaming" ;;
            schedutil)    desc="Scheduler-aware scaling (balanced)" ;;
            ondemand)     desc="Load-based scaling — default" ;;
            conservative) desc="Gradual scaling — power-save" ;;
            powersave)    desc="Always min freq" ;;
            *)            desc="Custom" ;;
        esac
        CHOICES+=("$g" "${m}${desc}")
    done

    local SEL
    SEL=$(dialog --backtitle "$BACKTITLE" \
                 --title "[ CPU GOVERNOR ]" \
                 --default-item "$CUR_GOV" \
                 --menu "★ = active  |  Save Profile to persist at boot" \
                 15 62 8 \
                 "${CHOICES[@]}" \
                 2>&1 > "$CURR_TTY")
    [ -z "$SEL" ] && return

    echo "$SEL" > "$CPU_POLICY/scaling_governor" 2>/dev/null
}

# ── GPU Tuning ────────────────────────────────────────────────────────────────

GPUTuningMenu() {
    if [ -z "$GPU_DEVFREQ" ]; then
        dialog --backtitle "$BACKTITLE" --title "GPU Tuning" \
            --msgbox "GPU devfreq not found.\nSearched: *gpu*  *mali*  *ff400000*" 7 52 > "$CURR_TTY"
        return
    fi

    local AVAIL; AVAIL=$(GetGPUAvail)
    if [ -z "$AVAIL" ]; then
        dialog --backtitle "$BACKTITLE" --title "GPU Tuning" \
            --msgbox "Cannot read $GPU_DEVFREQ/available_frequencies" 6 58 > "$CURR_TTY"
        return
    fi

    local CUR_MAX; CUR_MAX=$(cat "$GPU_DEVFREQ/max_freq" 2>/dev/null)
    local CHOICES=()
    while IFS= read -r hz; do
        local mhz=$((hz/1000000))
        local m="  "; [ "$hz" = "$CUR_MAX" ] && m="★ "
        CHOICES+=("$hz" "${m}${mhz} MHz")
    done <<< "$AVAIL"

    local COUNT=$(( ${#CHOICES[@]} / 2 ))
    local H=$(( COUNT + 7 )); [ $H -gt 20 ] && H=20

    local SEL
    SEL=$(dialog --backtitle "$BACKTITLE" \
                 --title "[ GPU MAX FREQUENCY ]" \
                 --default-item "$CUR_MAX" \
                 --menu "devfreq: $(basename "$GPU_DEVFREQ")  |  ★ = current" \
                 $H 60 $COUNT \
                 "${CHOICES[@]}" \
                 2>&1 > "$CURR_TTY")
    [ -z "$SEL" ] && return

    echo "$SEL" > "$GPU_DEVFREQ/max_freq" 2>/dev/null
    echo "simple_ondemand" > "$GPU_DEVFREQ/governor" 2>/dev/null
    local MHZ=$(( SEL / 1000000 ))
    dialog --backtitle "$BACKTITLE" --title "✓ GPU Updated" \
        --msgbox "GPU max  →  ${MHZ} MHz\nGovernor : simple_ondemand\nTemp     : $(GetTempC)°C" 7 52 > "$CURR_TTY"
}

# ── DMC / RAM Tuning ──────────────────────────────────────────────────────────

DMCTuningMenu() {
    if [ -z "$DMC_DEVFREQ" ]; then
        dialog --backtitle "$BACKTITLE" --title "DMC / RAM Tuning" \
            --msgbox "DMC devfreq not found.\nSearched: *dmc*  *ff600000*" 7 52 > "$CURR_TTY"
        return
    fi

    local AVAIL; AVAIL=$(GetDMCAvail)
    if [ -z "$AVAIL" ]; then
        dialog --backtitle "$BACKTITLE" --title "DMC / RAM Tuning" \
            --msgbox "Cannot read $DMC_DEVFREQ/available_frequencies" 6 58 > "$CURR_TTY"
        return
    fi

    local CUR_MAX; CUR_MAX=$(cat "$DMC_DEVFREQ/max_freq" 2>/dev/null)
    local CHOICES=()
    while IFS= read -r hz; do
        local mhz=$((hz/1000000))
        local m="  "; [ "$hz" = "$CUR_MAX" ] && m="★ "
        local note=""; [ $mhz -ge 786 ] && note="  [DTB]"
        CHOICES+=("$hz" "${m}${mhz} MHz${note}")
    done <<< "$AVAIL"

    local COUNT=$(( ${#CHOICES[@]} / 2 ))
    local H=$(( COUNT + 8 )); [ $H -gt 20 ] && H=20

    local SEL
    SEL=$(dialog --backtitle "$BACKTITLE" \
                 --title "[ DMC / RAM MAX FREQUENCY ]" \
                 --default-item "$CUR_MAX" \
                 --menu "★ = current  |  [DTB] = needs DTB patch for 786MHz OPP" \
                 $H 62 $COUNT \
                 "${CHOICES[@]}" \
                 2>&1 > "$CURR_TTY")
    [ -z "$SEL" ] && return

    echo "$SEL" > "$DMC_DEVFREQ/max_freq" 2>/dev/null
    local MHZ=$(( SEL / 1000000 ))
    local EXTRA=""
    [ $MHZ -ge 786 ] && EXTRA="\n\n[!] 786 MHz OPP needs DTB patch.\nApplied live — may revert on reboot."

    dialog --backtitle "$BACKTITLE" --title "✓ DMC Updated" \
        --msgbox "DMC max  →  ${MHZ} MHz${EXTRA}" 9 55 > "$CURR_TTY"
}

# ── Voltage Tuning ────────────────────────────────────────────────────────────

SetVoltForReg() {
    local LABEL="$1" DIR="$2" DANGER="$3"
    if [ -z "$DIR" ]; then
        dialog --backtitle "$BACKTITLE" --title "Voltage — $LABEL" \
            --msgbox "$LABEL not found in /sys/class/regulator/\n\nKernel may not expose it." 7 55 > "$CURR_TTY"
        return
    fi

    local CUR_MV; CUR_MV=$(GetRegVoltMV "$DIR")
    local REG_MIN_RAW; REG_MIN_RAW=$(cat "$DIR/min_microvolts" 2>/dev/null || echo 0)
    local REG_MAX_RAW; REG_MAX_RAW=$(cat "$DIR/max_microvolts" 2>/dev/null || echo 0)
    local REG_MIN=$(( REG_MIN_RAW / 1000 ))
    local REG_MAX=$(( REG_MAX_RAW / 1000 ))
    # fallback: if sysfs doesn't expose valid range, use current ±200mV
    if [ "$REG_MIN" -eq 0 ] || [ "$REG_MAX" -eq 0 ] || [ "$REG_MAX" -le "$REG_MIN" ]; then
        local BASE; BASE=$([ "$CUR_MV" != "N/A" ] && echo "$CUR_MV" || echo 1100)
        REG_MIN=$(( BASE - 200 ))
        REG_MAX=$(( BASE + 200 ))
    fi
    local REG_MIN_R=$(( (REG_MIN / 25) * 25 ))
    local REG_MAX_R=$(( (REG_MAX / 25) * 25 ))
    local DANGER_MSG=""
    [ "$DANGER" = "1" ] && DANGER_MSG="\n[!] vcc_ddr: wrong voltage = data corruption / crash."

    local CHOICES=()
    for v in $(seq $REG_MAX_R -25 $REG_MIN_R); do
        local m="  "; [ "$v" = "$CUR_MV" ] && m="★ "
        CHOICES+=("$v" "${m}${v} mV")
    done

    local SEL
    SEL=$(dialog --backtitle "$BACKTITLE" \
                 --title "[ VOLTAGE — $LABEL ]" \
                 --default-item "$CUR_MV" \
                 --menu "Current: ${CUR_MV} mV  |  Range: ${REG_MIN_R}–${REG_MAX_R} mV  |  Step: 25 mV${DANGER_MSG}" \
                 20 55 15 \
                 "${CHOICES[@]}" \
                 2>&1 > "$CURR_TTY")
    [ -z "$SEL" ] && return

    ApplyVolt "$DIR" "$SEL"
    local RET=$?
    local ACTUAL_MV; ACTUAL_MV=$(GetRegVoltMV "$DIR")
    local MSG
    case $RET in
        0) MSG="Applied: ${SEL} mV  (read-back: ${ACTUAL_MV} mV)\n\nSave Profile → applies at boot.\nDTB patch = truly permanent." ;;
        4) MSG="Write sent but OPP reverted it.\nRead-back: ${ACTUAL_MV} mV\n\nOPP framework owns this regulator during\ncpufreq transitions. DTB patch required\nfor a permanent undervolt." ;;
        2) MSG="Write blocked — regulator is read-only.\n\nDTB patch required for undervolt." ;;
        1) MSG="Value ${SEL} mV out of range (${REG_MIN_R}–${REG_MAX_R} mV)." ;;
        3) MSG="Regulator directory not found." ;;
    esac

    dialog --backtitle "$BACKTITLE" --title "[ VOLTAGE — $LABEL ]" \
        --msgbox "$MSG" 11 58 > "$CURR_TTY"
}

VoltageMenu() {
    local ARM_MV; ARM_MV=$(GetRegVoltMV "$VDD_ARM")
    local LOGIC_MV; LOGIC_MV=$(GetRegVoltMV "$VDD_LOGIC")
    local DDR_MV; DDR_MV=$(GetRegVoltMV "$VCC_DDR")

    local CHOICE
    CHOICE=$(dialog --backtitle "$BACKTITLE" \
                    --title "[ VOLTAGE TUNING ]" \
                    --ok-label "Select" \
                    --cancel-label "Back" \
                    --menu "Step: ±25mV (RK805 PMIC)  |  [!] = high risk" \
                    13 62 4 \
                    1 "vdd_arm   — CPU cores     : ${ARM_MV} mV" \
                    2 "vdd_logic — SoC / GPU     : ${LOGIC_MV} mV" \
                    3 "vcc_ddr   — RAM       [!] : ${DDR_MV} mV" \
                    4 "Back" \
                    2>&1 > "$CURR_TTY")
    [ $? -ne 0 ] && return
    case $CHOICE in
        1) SetVoltForReg "vdd_arm"   "$VDD_ARM"   0 ;;
        2) SetVoltForReg "vdd_logic" "$VDD_LOGIC" 0 ;;
        3) SetVoltForReg "vcc_ddr"   "$VCC_DDR"   1 ;;
    esac
}

# ── Real-Time Monitor ─────────────────────────────────────────────────────────

MonitorMenu() {
    while true; do
        local TEMP; TEMP=$(GetTempC)
        local TEMP_DISP="${TEMP}°C"
        [[ "$TEMP" =~ ^[0-9]+$ ]] && [ "$TEMP" -ge 80 ] && TEMP_DISP="${TEMP}°C [HOT!]"

        local INFO
        INFO=$(printf \
"╔══════════ R36 TUNER MONITOR ══════════╗
║ Temperature : %-16s           ║
╠════════════════ CPU ═══════════════════╣
║ Cur / Max   : %-6s / %-6s MHz     ║
║ Min Freq    : %-6s MHz                ║
║ Voltage     : %-10s                ║
║ Governor    : %-15s           ║
╠════════════════ GPU ═══════════════════╣
║ Cur / Max   : %-6s / %-6s MHz     ║
║ Voltage     : %-10s                ║
╠══════════════ DMC / RAM ═══════════════╣
║ Cur / Max   : %-6s / %-6s MHz     ║
║ Voltage     : %-10s                ║
╚═══════════════════════════════════════╝" \
            "$TEMP_DISP" \
            "$(GetCPUCurMHz)" "$(GetCPUMaxMHz)" \
            "$(GetCPUMinMHz)" \
            "$(GetRegVoltMV "$VDD_ARM") mV" "$(GetGOV)" \
            "$(GetGPUCurMHz)" "$(GetGPUMaxMHz)" \
            "$(GetRegVoltMV "$VDD_LOGIC") mV" \
            "$(GetDMCCurMHz)" "$(GetDMCMaxMHz)" \
            "$(GetRegVoltMV "$VCC_DDR") mV")

        dialog --backtitle "$BACKTITLE" \
               --title "[ MONITOR — press Cancel to exit ]" \
               --pause "$INFO" 22 55 2 > "$CURR_TTY"
        [ $? -ne 0 ] && break
    done
}

# ── Benchmark ─────────────────────────────────────────────────────────────────

BenchmarkCPU() {
    dialog --backtitle "$BACKTITLE" --title "[ BENCHMARK — CPU ]" \
        --infobox "sha256 + gzip 64 MB...\nPlease wait ~15s" 5 45 > "$CURR_TTY"

    local SSL="openssl not found"
    if command -v openssl >/dev/null 2>&1; then
        local raw; raw=$(openssl speed sha256 2>&1 | grep -i "sha256" | grep -v "^Doing" | tail -1 | awk '{print $NF}')
        [ -n "$raw" ] && SSL="$raw" || SSL="N/A"
    fi

    local GZIP="N/A"
    local T1 T2 TMS
    T1=$(date +%s%N)
    dd if=/dev/urandom bs=1M count=64 2>/dev/null | gzip -1 -c > /dev/null
    T2=$(date +%s%N)
    TMS=$(( (T2 - T1) / 1000000 ))
    [ $TMS -gt 0 ] && GZIP="$(( 64 * 1000 / TMS )) MB/s"

    dialog --backtitle "$BACKTITLE" --title "[ CPU RESULTS ]" \
        --msgbox "Config: $(GetCPUMaxMHz) MHz  vdd_arm: $(GetRegVoltMV "$VDD_ARM") mV  gov: $(GetGOV)\nTemp: $(GetTempC)°C\n\nsha256    : $SSL\ngzip      : $GZIP" \
        10 62 > "$CURR_TTY"
}

BenchmarkRAM() {
    dialog --backtitle "$BACKTITLE" --title "[ BENCHMARK — RAM ]" \
        --infobox "128 MB write + read via /dev/shm...\nPlease wait ~8s" 5 50 > "$CURR_TTY"
    local RW="N/A" RR="N/A"
    local T1 T2 TMS
    T1=$(date +%s%N)
    dd if=/dev/zero of=/dev/shm/.r36bench bs=1M count=128 conv=fdatasync 2>/dev/null
    T2=$(date +%s%N)
    TMS=$(( (T2 - T1) / 1000000 ))
    [ $TMS -gt 0 ] && RW="$(( 128 * 1000 / TMS )) MB/s"

    T1=$(date +%s%N)
    dd if=/dev/shm/.r36bench of=/dev/null bs=1M 2>/dev/null
    T2=$(date +%s%N)
    TMS=$(( (T2 - T1) / 1000000 ))
    [ $TMS -gt 0 ] && RR="$(( 128 * 1000 / TMS )) MB/s"
    rm -f /dev/shm/.r36bench

    dialog --backtitle "$BACKTITLE" --title "[ RAM RESULTS ]" \
        --msgbox "Config: DMC $(GetDMCMaxMHz) MHz  vcc_ddr: $(GetRegVoltMV "$VCC_DDR") mV\nTemp: $(GetTempC)°C\n\nWrite : $RW\nRead  : $RR" \
        9 58 > "$CURR_TTY"
}

BenchmarkGPU() {
    if ! command -v glmark2-es2-fbdev >/dev/null 2>&1; then
        dialog --backtitle "$BACKTITLE" --title "[ BENCHMARK — GPU ]" \
            --msgbox "glmark2-es2-fbdev not installed.\n\napt install glmark2-es2-fbdev" 8 50 > "$CURR_TTY"
        return
    fi
    dialog --backtitle "$BACKTITLE" --title "[ BENCHMARK — GPU ]" \
        --infobox "Running glmark2-es2-fbdev...\nPlease wait ~30s" 5 45 > "$CURR_TTY"
    local SCORE
    SCORE=$(glmark2-es2-fbdev --size 320x240 2>&1 | grep "glmark2 Score" | awk '{print $NF}')
    local GPU_DISP="${SCORE} pts"
    [ -z "$SCORE" ] && GPU_DISP="ran — no score captured"

    dialog --backtitle "$BACKTITLE" --title "[ GPU RESULTS ]" \
        --msgbox "Config: GPU $(GetGPUMaxMHz) MHz  vdd_logic: $(GetRegVoltMV "$VDD_LOGIC") mV\nTemp: $(GetTempC)°C\n\nglmark2 score: $GPU_DISP" \
        8 58 > "$CURR_TTY"
}

BenchmarkMenu() {
    local CHOICE
    CHOICE=$(dialog --backtitle "$BACKTITLE" \
                    --title "[ BENCHMARK ]" \
                    --ok-label "Run" \
                    --cancel-label "Back" \
                    --menu "Select test to run" \
                    13 58 5 \
                    1 "CPU  — openssl sha256 + gzip (~15s)" \
                    2 "RAM  — 128MB write/read via /dev/shm (~8s)" \
                    3 "GPU  — glmark2-es2-fbdev (~30s)" \
                    4 "All  — CPU + RAM + GPU in sequence" \
                    5 "Back" \
                    2>&1 > "$CURR_TTY")
    [ $? -ne 0 ] && return
    case $CHOICE in
        1) BenchmarkCPU ;;
        2) BenchmarkRAM ;;
        3) BenchmarkGPU ;;
        4) BenchmarkCPU; BenchmarkRAM; BenchmarkGPU ;;
    esac
}

# ── Save / Reset / View Profile ───────────────────────────────────────────────

SaveProfileMenu() {
    local BOOT_ACTIVE="No"
    [ -f "$SVC_FILE" ] && systemctl is-enabled r36-tuner.service >/dev/null 2>&1 && BOOT_ACTIVE="Yes"

    dialog --backtitle "$BACKTITLE" --title "[ SAVE PROFILE ]" \
        --yesno "Save current tuning as boot profile?\n\nCPU max   : $(GetCPUMaxMHz) MHz\nCPU min   : $(GetCPUMinMHz) MHz\nGPU max   : $(GetGPUMaxMHz) MHz\nDMC max   : $(GetDMCMaxMHz) MHz\nvdd_arm   : $(GetRegVoltMV "$VDD_ARM") mV\nvdd_logic : $(GetRegVoltMV "$VDD_LOGIC") mV\nvcc_ddr   : $(GetRegVoltMV "$VCC_DDR") mV\nGovernor  : $(GetGOV)\n\nFail-safe : panic flag active at boot\nAutostart : $BOOT_ACTIVE" \
        22 55 > "$CURR_TTY"
    [ $? -ne 0 ] && return

    SaveConfig
    SetupBootService

    dialog --backtitle "$BACKTITLE" --title "✓ Profile Saved" \
        --msgbox "Profile saved!\n\nFile    : /etc/r36_tuner.ini\nService : r36-tuner.service  ✓ enabled\n\nFail-safe active: if boot hangs, next boot\nautomatically disables the profile." 12 55 > "$CURR_TTY"
}

ResetProfileMenu() {
    dialog --backtitle "$BACKTITLE" --title "[ RESET PROFILE ]" \
        --yesno "Delete saved profile and disable boot service?\n\nThis removes:\n  /etc/r36_tuner.ini\n  r36-tuner.service\n  panic flag (if any)\n\nLive settings are NOT changed." \
        12 55 > "$CURR_TTY"
    [ $? -ne 0 ] && return

    rm -f "$CONFIG_FILE" "$PANIC_FLAG"
    RemoveBootService

    dialog --backtitle "$BACKTITLE" --title "✓ Profile Reset" \
        --msgbox "Profile deleted.\nBoot service disabled.\n\nSystem will boot with kernel defaults." \
        9 50 > "$CURR_TTY"
}

ViewProfileMenu() {
    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --backtitle "$BACKTITLE" --title "[ SAVED PROFILE ]" \
            --msgbox "No profile saved.\n\n$CONFIG_FILE not found." 8 50 > "$CURR_TTY"
        return
    fi
    local CONTENT; CONTENT=$(cat "$CONFIG_FILE" 2>/dev/null)
    dialog --backtitle "$BACKTITLE" --title "[ SAVED PROFILE — $CONFIG_FILE ]" \
        --msgbox "$CONTENT" 16 52 > "$CURR_TTY"
}

# ── Exit ──────────────────────────────────────────────────────────────────────

ExitMenu() {
    printf "\033c" > "$CURR_TTY"
    printf "\e[?25h" > "$CURR_TTY"
    pkill -9 -f gptokeyb || true
    if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
        sudo setfont /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz
    fi
    exit 0
}

# ── Main Menu ─────────────────────────────────────────────────────────────────

MainMenu() {
    while true; do
        local ARM_MV; ARM_MV=$(GetRegVoltMV "$VDD_ARM")
        local PROF_STATUS="off"
        [ -f "$SVC_FILE" ] && systemctl is-enabled r36-tuner.service >/dev/null 2>&1 && PROF_STATUS="✓ on"
        local CHOICE
        CHOICE=$(dialog --backtitle "$BACKTITLE" \
                        --title "[ MAIN MENU ]" \
                        --ok-label "Select" \
                        --cancel-label "Exit" \
                        --menu "Temp: $(GetTempC)°C  CPU: $(GetCPUMaxMHz)MHz  GPU: $(GetGPUMaxMHz)MHz  arm: ${ARM_MV}mV" \
                        22 68 12 \
                        1  "CPU Max Freq        ($(GetCPUMaxMHz) MHz)" \
                        2  "CPU Min Freq        ($(GetCPUMinMHz) MHz)" \
                        3  "CPU Governor        ($(GetGOV))" \
                        4  "GPU Tuning          ($(GetGPUMaxMHz) MHz)" \
                        5  "DMC / RAM Tuning    ($(GetDMCMaxMHz) MHz)" \
                        6  "Voltage Tuning      (vdd_arm: ${ARM_MV} mV)" \
                        7  "Real-Time Monitor   ($(GetTempC)°C)" \
                        8  "Benchmark" \
                        9  "Save Profile (boot) [${PROF_STATUS}]" \
                        10 "View Saved Profile" \
                        11 "Reset Profile" \
                        12 "Exit" \
                        2>&1 > "$CURR_TTY")

        local RET=$?
        [ $RET -ne 0 ] && ExitMenu

        case $CHOICE in
            1)  CPUTuningMenu ;;
            2)  CPUMinFreqMenu ;;
            3)  GovernorMenu ;;
            4)  GPUTuningMenu ;;
            5)  DMCTuningMenu ;;
            6)  VoltageMenu ;;
            7)  MonitorMenu ;;
            8)  BenchmarkMenu ;;
            9)  SaveProfileMenu ;;
            10) ViewProfileMenu ;;
            11) ResetProfileMenu ;;
            12) ExitMenu ;;
        esac
    done
}

# ── Entry Point ───────────────────────────────────────────────────────────────

pkill -9 -f gptokeyb || true
sleep 1

# Warn if last boot profile caused a hang
if [ -f "${CONFIG_FILE}.failed" ]; then
    dialog --backtitle "$BACKTITLE" --title "[ BOOT PROFILE FAILED ]" \
        --yesno "Last boot: profile caused a hang and was auto-disabled.\n\nFailed config: ${CONFIG_FILE}.failed\n\nDelete the failed config file?" \
        11 62 > "$CURR_TTY"
    [ $? -eq 0 ] && rm -f "${CONFIG_FILE}.failed"
fi

export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
[ -x "$GPTOKEYB_BIN" ] && "$GPTOKEYB_BIN" -1 "R36_Tuner_v${VERSION}" \
    ${GPTOKEYB_CFG:+-c "$GPTOKEYB_CFG"} > /dev/null 2>&1 &

trap ExitMenu EXIT
MainMenu
