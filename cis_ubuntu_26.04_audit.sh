#!/usr/bin/env bash
# ==============================================================================
# CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0 - Standalone Security Audit Script
# Benchmark:   CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0 (08-26-2026)
# Coverage:    All 350 Recommendations (Sections 1 through 7, Level 1 & Level 2)
# Repository:  https://github.com/nmwafa/cis-audit
# ==============================================================================

set -u

BENCHMARK_NAME="CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0"
BENCHMARK_SHORT="CIS Ubuntu Linux 26.04 LTS v1.0.0"
BENCHMARK_CONTROLS="350 Controls (Sections 1-7)"
SCRIPT_NAME="$(basename "$0")"

# ------------------------------------------------------------------------------
# CLI Options & Defaults
# ------------------------------------------------------------------------------
PROFILE_LEVEL="all"      # 1, 2, or all
TARGET_SECTION="all"     # 1..7 or all
OUTPUT_FILE=""
USE_COLOR=1
FORCE_COLOR="${FORCE_COLOR:-0}"
QUIET_OK=0

usage() {
    cat << 'USAGE'
Usage: ./cis_ubuntu_26.04_audit.sh [OPTIONS]

Standalone, zero-install Bash script to audit an Ubuntu Linux server against
all 350 recommendations in the CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0.

Options:
  -l, --level <1|2|all>     Filter by CIS Profile Level (default: all)
  -s, --section <1..7|all>  Audit only a specific section (1-7) (default: all)
  -o, --output <file>       Save full audit report to a file
  -q, --quiet-ok            Hide [OK] results and only show findings/remediations
  -n, --no-color            Disable ANSI color output
      --color               Force ANSI color output even when piped
  -h, --help                Show this help message and exit
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--level)
            PROFILE_LEVEL="${2:-all}"
            shift 2
            ;;
        -s|--section)
            TARGET_SECTION="${2:-all}"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="${2:-}"
            shift 2
            ;;
        -q|--quiet-ok)
            QUIET_OK=1
            shift
            ;;
        -n|--no-color)
            USE_COLOR=0
            FORCE_COLOR=0
            shift
            ;;
        --color)
            USE_COLOR=1
            FORCE_COLOR=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

setup_colors_and_init() {
    PROFILE_LEVEL="$(normalize_profile_filter "$PROFILE_LEVEL")"
    setup_colors
    if [[ -n "$OUTPUT_FILE" ]]; then
        exec > >(tee "$OUTPUT_FILE") 2>&1
    fi
}

# ------------------------------------------------------------------------------
# Colors & Formatting (Standardized CIS Audit Suite Palette)
# ------------------------------------------------------------------------------
setup_colors() {
    if [[ "$USE_COLOR" -eq 0 ]] || [[ "${FORCE_COLOR:-0}" -eq 0 && ! -t 1 && -z "${OUTPUT_FILE:-}" ]]; then
        C_RESET=''
        C_BOLD=''
        C_DIM=''
        C_RED=''
        C_GREEN=''
        C_YELLOW=''
        C_BLUE=''
        C_MAGENTA=''
        C_CYAN=''
        C_WHITE=''
        C_BG_BLUE=''
        C_BG_RED=''
        C_BG_GREEN=''
        C_BG_YELLOW=''
        BG_BLUE=''
        BG_RED=''
        BG_GREEN=''
        BG_YELLOW=''
    else
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_RED=$'\033[1;31m'
        C_GREEN=$'\033[1;32m'
        C_YELLOW=$'\033[1;33m'
        C_BLUE=$'\033[1;34m'
        C_MAGENTA=$'\033[1;35m'
        C_CYAN=$'\033[1;36m'
        C_WHITE=$'\033[1;37m'
        C_BG_BLUE=$'\033[44;1;37m'
        C_BG_RED=$'\033[41;1;37m'
        C_BG_GREEN=$'\033[42;1;30m'
        C_BG_YELLOW=$'\033[43;1;30m'
        BG_BLUE="$C_BG_BLUE"
        BG_RED="$C_BG_RED"
        BG_GREEN="$C_BG_GREEN"
        BG_YELLOW="$C_BG_YELLOW"
    fi
}

normalize_level() {
    local lvl="${1:-all}"
    case "${lvl^^}" in
        1|L1|"LEVEL 1") echo "L1" ;;
        2|L2|"LEVEL 2") echo "L2" ;;
        *) echo "L1" ;;
    esac
}

normalize_profile_filter() {
    local flt="${1:-all}"
    case "${flt,,}" in
        1|l1|level1) echo "1" ;;
        2|l2|level2) echo "2" ;;
        *) echo "all" ;;
    esac
}

# Supports TARGET_SECTION="all", single ("3"), comma/space list ("1,3,5"), or ranges ("2-4")
is_section_selected() {
    local sec_num="$1"
    local filter="${TARGET_SECTION:-all}"
    [[ "${filter,,}" == "all" || -z "$filter" ]] && return 0

    local item start end i
    local normalized="${filter// /,}"
    IFS=',' read -ra items <<< "$normalized"
    for item in "${items[@]}"; do
        [[ -z "$item" ]] && continue
        if [[ "$item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            if (( sec_num >= start && sec_num <= end )); then
                return 0
            fi
        elif [[ "$item" == "$sec_num" ]]; then
            return 0
        fi
    done
    return 1
}

print_section_header() {
    local sec_num="$1"
    local sec_title="$2"
    CURRENT_SECTION="$sec_num"
    if ! is_section_selected "$sec_num"; then
        return 1
    fi
    echo -e "\n${C_BG_BLUE} [SECTION ${sec_num}] ${sec_title} ${C_RESET}"
    echo -e "${C_BLUE}====================================================================================${C_RESET}"
    return 0
}

print_subsection_header() {
    echo -e "\n${C_CYAN}${C_BOLD}[+] $1${C_RESET}"
    echo -e "${C_DIM}------------------------------------------------------------------------------------${C_RESET}"
}

should_run_check() {
    local id="$1"
    local level
    level="$(normalize_level "${2:-L1}")"
    local sec="${id%%.*}"
    [[ ! "$sec" =~ ^[0-9]+$ ]] && sec="${CURRENT_SECTION:-1}"

    if ! is_section_selected "$sec"; then
        return 1
    fi
    if [[ "$PROFILE_LEVEL" == "1" && "$level" == "L2" ]]; then
        return 1
    fi
    return 0
}

print_remediation_block() {
    local label="$1"
    local text="$2"
    [[ -z "$text" ]] && return 0
    if [[ "$text" != *$'\n'* ]]; then
        echo -e "         ${C_CYAN}${label}:${C_RESET} ${text}"
    else
        echo -e "         ${C_CYAN}${label}:${C_RESET}"
        while IFS= read -r line; do
            echo -e "           ${line}"
        done <<< "$text"
    fi
}

# Unified result reporter across all CIS audit scripts
# Usage: report_result <ID> <TITLE> <LEVEL> <TYPE> <STATUS> <FINDING> <REMEDIATION>
report_result() {
    local id="$1"
    local raw_title="$2"
    local raw_level="${3:-L1}"
    local status_type="${4:-Automated}"
    local status="${5:-OK}"
    local finding="${6:-}"
    local remediation="${7:-}"

    local level
    level="$(normalize_level "$raw_level")"
    local sec="${id%%.*}"
    [[ ! "$sec" =~ ^[0-9]+$ ]] && sec="${CURRENT_SECTION:-1}"

    should_run_check "$id" "$level" || return 0

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    case "$status" in
        OK|PASS)
            COUNT_OK=$((COUNT_OK + 1))
            SEC_OK[$sec]=$(( ${SEC_OK[$sec]:-0} + 1 ))
            if [[ "$QUIET_OK" -eq 0 ]]; then
                echo -e "${C_GREEN}[OK]${C_RESET}     ${C_BOLD}${id} - ${raw_title}${C_RESET} ${C_DIM}[${level} | ${status_type}]${C_RESET}"
                if [[ -n "$finding" ]]; then
                    echo -e "         ${C_DIM}Details: ${finding}${C_RESET}"
                fi
            fi
            ;;
        FAIL|"NOT COMPLIANT")
            COUNT_FAIL=$((COUNT_FAIL + 1))
            SEC_FAIL[$sec]=$(( ${SEC_FAIL[$sec]:-0} + 1 ))
            echo -e "${C_RED}[FAIL]${C_RESET}   ${C_BOLD}${id} - ${C_WHITE}${raw_title}${C_RESET} ${C_DIM}[${level} | ${status_type}]${C_RESET}"
            if [[ -n "$finding" ]]; then
                echo -e "         ${C_YELLOW}Finding:${C_RESET}     ${finding}"
            fi
            print_remediation_block "Remediation" "$remediation"
            ;;
        MANUAL|"MANUAL REVIEW")
            COUNT_MANUAL=$((COUNT_MANUAL + 1))
            SEC_MANUAL[$sec]=$(( ${SEC_MANUAL[$sec]:-0} + 1 ))
            echo -e "${C_YELLOW}[MANUAL]${C_RESET} ${C_BOLD}${id} - ${C_WHITE}${raw_title}${C_RESET} ${C_DIM}[${level} | ${status_type}]${C_RESET}"
            if [[ -n "$finding" ]]; then
                echo -e "         ${C_YELLOW}Details:${C_RESET}     ${finding}"
            fi
            print_remediation_block "Remediation" "$remediation"
            ;;
        SKIP|SKIPPED)
            COUNT_SKIP=$((COUNT_SKIP + 1))
            SEC_SKIP[$sec]=$(( ${SEC_SKIP[$sec]:-0} + 1 ))
            echo -e "${C_MAGENTA}[SKIP]${C_RESET}   ${C_BOLD}${id} - ${C_WHITE}${raw_title}${C_RESET} ${C_DIM}[${level} | ${status_type}]${C_RESET}"
            if [[ -n "$finding" ]]; then
                echo -e "         ${C_YELLOW}Reason:${C_RESET}      ${finding}"
            fi
            print_remediation_block "Remediation" "$remediation"
            ;;
    esac
}


# ------------------------------------------------------------------------------
# Global Counters & State Tracking
# ------------------------------------------------------------------------------
TOTAL_CHECKS=0
COUNT_OK=0
COUNT_FAIL=0
COUNT_MANUAL=0
COUNT_SKIP=0
CURRENT_SECTION="1"

declare -A SEC_OK=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0)
declare -A SEC_FAIL=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0)
declare -A SEC_MANUAL=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0)
declare -A SEC_SKIP=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0)

report_ok() {
    local id="$1"
    local title="$2"
    local level="$3"
    local status_type="$4"
    local note="${5:-}"
    report_result "$id" "$title" "$level" "$status_type" "OK" "$note" ""
}

report_fail() {
    local id="$1"
    local title="$2"
    local level="$3"
    local status_type="$4"
    local finding="$5"
    local remediation="$6"
    report_result "$id" "$title" "$level" "$status_type" "FAIL" "$finding" "$remediation"
}

report_manual() {
    local id="$1"
    local title="$2"
    local level="$3"
    local status_type="$4"
    local finding="$5"
    local remediation="$6"
    report_result "$id" "$title" "$level" "$status_type" "MANUAL" "$finding" "$remediation"
}

print_banner() {
    echo -e "${C_CYAN}${C_BOLD}"
    cat << 'BANNER'
  ____ ___ ____    _   _ _                 _           ____   ____    ___  _  _   
 / ___|_ _/ ___|  | | | | |__  _   _ _ __ | |_ _   _  |___ \ / /_    / _ \| || |  
| |    | |\___ \  | | | | '_ \| | | | '_ \| __| | | |   __) | '_ \  | | | | || |_ 
| |___ | | ___) | | |_| | |_) | |_| | | | | |_| |_| |  / __/| (_) | | |_| |__   _|
 \____|___|____/   \___/|_.__/ \__,_|_| |_|\__|\__,_| |_____|\___/ (_)___/   |_|  
 
BANNER
    echo -e "${C_BLUE}====================================================================================${C_RESET}"
    echo -e "  ${C_BOLD}Benchmark:${C_RESET}      ${BENCHMARK_NAME} (08-26-2026)"
    echo -e "  ${C_BOLD}Hostname:${C_RESET}       $(hostname 2>/dev/null || echo 'unknown')"
    echo -e "  ${C_BOLD}OS Release:${C_RESET}     $(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -sr)"
    echo -e "  ${C_BOLD}Kernel:${C_RESET}         $(uname -r 2>/dev/null || echo 'unknown') ($(uname -m 2>/dev/null || echo 'unknown'))"
    echo -e "  ${C_BOLD}Current User:${C_RESET}   $(id -un 2>/dev/null || echo 'unknown') (UID: $(id -u 2>/dev/null || echo '?'))"
    echo -e "  ${C_BOLD}Audit Date:${C_RESET}     $(date -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)"
    echo -e "  ${C_BOLD}Section Filter:${C_RESET} ${TARGET_SECTION} (Profile Level: ${PROFILE_LEVEL})"
    if [[ "$(id -u 2>/dev/null || echo 1)" -ne 0 ]]; then
        echo -e "  ${C_YELLOW}[!] WARNING: Script is not running as root (UID 0). Some checks (e.g. /etc/shadow, auditctl, sshd -T) require root privileges for accurate results.${C_RESET}"
    fi
    echo -e "${C_BLUE}====================================================================================${C_RESET}"
}

UID_MIN_VAL="$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs 2>/dev/null || echo 1000)"
[[ -z "$UID_MIN_VAL" ]] && UID_MIN_VAL=1000
OS_ID="$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo ubuntu)"
[[ -z "$OS_ID" ]] && OS_ID="ubuntu"

# Cache expensive command outputs for speed and consistency
SHOWCONFIG_CACHE="$(modprobe --showconfig 2>/dev/null || true)"
LSMOD_CACHE="$(lsmod 2>/dev/null || true)"
SYSTEMD_SYSCTL_BIN="$(readlink -e /lib/systemd/systemd-sysctl 2>/dev/null || readlink -e /usr/lib/systemd/systemd-sysctl 2>/dev/null || true)"
if [[ -n "$SYSTEMD_SYSCTL_BIN" ]]; then
    SYSCTL_CAT_CACHE="$("$SYSTEMD_SYSCTL_BIN" --cat-config 2>/dev/null || true)"
else
    SYSCTL_CAT_CACHE=""
fi
SSHD_BIN="$(readlink -e /usr/sbin/sshd 2>/dev/null || readlink -e /sbin/sshd 2>/dev/null || command -v sshd 2>/dev/null || true)"
if [[ -n "$SSHD_BIN" ]]; then
    SSHD_T_CACHE="$("$SSHD_BIN" -T -C user=root,host=localhost,addr=127.0.0.1 2>/dev/null || "$SSHD_BIN" -T 2>/dev/null || true)"
else
    SSHD_T_CACHE=""
fi
AUDITCTL_L_CACHE="$(auditctl -l 2>/dev/null || true)"
AUDITCTL_S_CACHE="$(auditctl -s 2>/dev/null || true)"

# Check if IPv6 is enabled on the system
is_ipv6_enabled() {
    if ! grep -Pqs -- '^\h*0\b' /sys/module/ipv6/parameters/disable 2>/dev/null; then
        return 1
    fi
    if sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -Pqs -- "^\h*net\.ipv6\.conf\.all\.disable_ipv6\h*=\h*1\b" && \
       sysctl net.ipv6.conf.default.disable_ipv6 2>/dev/null | grep -Pqs -- "^\h*net\.ipv6\.conf\.default\.disable_ipv6\h*=\h*1\b"; then
        return 1
    fi
    return 0
}

if is_ipv6_enabled; then
    IPV6_ENABLED=1
else
    IPV6_ENABLED=0
fi

# ------------------------------------------------------------------------------
# Common Reusable Audit Helpers
# ------------------------------------------------------------------------------

# Check Kernel Module Availability (Sections 1.1.1.* and 3.2.*)
check_kernel_module() {
    local id="$1"
    local title="$2"
    local level="$3"
    local mod_name="$4"
    local mod_type="$5"
    local mod_dir_name="${6:-$mod_name}"

    should_run_check "$id" "$level" || return 0

    local mod_regex="${mod_name//-/[_-]}"
    local mod_under="${mod_name//-/_}"
    local exists_in=""
    local p

    for p in $(readlink -e /usr/lib/modules/*/kernel/"$mod_type" /lib/modules/*/kernel/"$mod_type" 2>/dev/null | sort -u); do
        if [[ -d "$p/${mod_dir_name//-/\/}" ]] && [[ -n "$(ls -A "$p/${mod_dir_name//-/\/}" 2>/dev/null)" ]]; then
            exists_in="$p"
            break
        elif find "$p" -name "${mod_name}.ko*" -o -name "${mod_under}.ko*" 2>/dev/null | grep -q .; then
            exists_in="$p"
            break
        fi
    done

    if [[ -z "$exists_in" ]] && ! grep -Pq -- "\b${mod_regex}\b" <<< "$LSMOD_CACHE"; then
        report_ok "$id" "$title" "$level" "Automated" "Module $mod_name not present on disk or loaded"
        return 0
    fi

    local issues=()
    if grep -Pq -- "\b${mod_regex}\b" <<< "$LSMOD_CACHE"; then
        issues+=("Module '$mod_name' is currently loaded in the running kernel")
    fi
    if ! grep -Pq -- "^\h*blacklist\h+${mod_regex}\b" <<< "$SHOWCONFIG_CACHE"; then
        issues+=("Module '$mod_name' is not blacklisted in modprobe configuration")
    fi
    if ! grep -Pq -- "^\h*install\h+${mod_regex}\h+(/usr)?/bin/(true|false)\b" <<< "$SHOWCONFIG_CACHE"; then
        issues+=("Module '$mod_name' does not have 'install $mod_name /bin/false' (or /bin/true) set")
    fi

    if [[ "${#issues[@]}" -eq 0 ]]; then
        report_ok "$id" "$title" "$level" "Automated"
    else
        local finding
        finding="$(IFS='; '; echo "${issues[*]}")"
        local rem="Run: printf '%s\n' 'install ${mod_name} /bin/false' 'blacklist ${mod_name}' >> /etc/modprobe.d/60-${mod_name}.conf && modprobe -r ${mod_name} 2>/dev/null; rmmod ${mod_name} 2>/dev/null"
        report_fail "$id" "$title" "$level" "Automated" "$finding" "$rem"
    fi
}

# Check Mount Point Existence
check_mount_exists() {
    local id="$1"
    local title="$2"
    local level="$3"
    local mnt="$4"
    local extra_systemd="${5:-}"

    should_run_check "$id" "$level" || return 0

    local out
    out="$(findmnt -kn "$mnt" 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        local rem="Configure a dedicated partition or tmpfs mount for ${mnt} in /etc/fstab (e.g., 'tmpfs ${mnt} tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0' or a dedicated volume) and mount it."
        [[ -n "$extra_systemd" ]] && rem="Run 'systemctl unmask ${extra_systemd}' and configure ${mnt} in /etc/fstab with defaults,nodev,nosuid,noexec."
        report_fail "$id" "$title" "$level" "Automated" "${mnt} is not mounted as a separate partition/tmpfs" "$rem"
        return 0
    fi

    if [[ -n "$extra_systemd" ]]; then
        local st
        st="$(systemctl is-enabled "$extra_systemd" 2>/dev/null || true)"
        if [[ "$st" == "masked" || "$st" == "disabled" ]]; then
            report_fail "$id" "$title" "$level" "Automated" "${mnt} is mounted, but systemd unit ${extra_systemd} is ${st}" "Run: systemctl unmask ${extra_systemd} && systemctl enable ${extra_systemd}"
            return 0
        fi
    fi

    report_ok "$id" "$title" "$level" "Automated"
}

# Check Mount Option (nodev, nosuid, noexec)
check_mount_option() {
    local id="$1"
    local title="$2"
    local level="$3"
    local mnt="$4"
    local opt="$5"

    should_run_check "$id" "$level" || return 0

    local out
    out="$(findmnt -kn "$mnt" 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        report_fail "$id" "$title" "$level" "Automated" "${mnt} is not a separate partition, so mount option '${opt}' cannot be verified on ${mnt}" "Create a separate partition/mount for ${mnt} in /etc/fstab including the '${opt}' mount option, then run: mount -o remount ${mnt}"
        return 0
    fi

    if echo "$out" | grep -v "$opt" | grep -q .; then
        report_fail "$id" "$title" "$level" "Automated" "Mount '${mnt}' is missing the '${opt}' option (current: $(echo "$out" | awk '{print $4}'))" "Edit /etc/fstab to add '${opt}' to the 4th field (mount options) for ${mnt}, then run: mount -o remount,${opt} ${mnt}"
    else
        report_ok "$id" "$title" "$level" "Automated"
    fi
}

# Check File/Directory Permissions & Ownership
check_file_perms() {
    local id="$1"
    local title="$2"
    local level="$3"
    local path="$4"
    local perm_mask="$5"
    local max_octal="$6"
    local expected_user_regex="$7"
    local expected_group_regex="$8"
    local missing_ok="${9:-1}"
    local chmod_fix="${10:-chmod ${max_octal} ${path}}"
    local chown_fix="${11:-chown root:root ${path}}"

    should_run_check "$id" "$level" || return 0

    if [[ ! -e "$path" ]]; then
        if [[ "$missing_ok" -eq 1 ]]; then
            report_ok "$id" "$title" "$level" "Automated" "${path} does not exist"
        else
            report_fail "$id" "$title" "$level" "Automated" "Required file/directory '${path}' does not exist" "Create '${path}' and run: ${chown_fix} && ${chmod_fix}"
        fi
        return 0
    fi

    local mode_oct user group
    read -r mode_oct user group <<< "$(stat -Lc '%#a %U %G' "$path" 2>/dev/null)"
    local issues=()
    if [[ $(( mode_oct & perm_mask )) -gt 0 ]]; then
        issues+=("Mode is ${mode_oct} (should be ${max_octal} or more restrictive)")
    fi
    if [[ ! "$user" =~ ^(${expected_user_regex})$ ]]; then
        issues+=("Owner is '${user}' (should be '${expected_user_regex}')")
    fi
    if [[ ! "$group" =~ ^(${expected_group_regex})$ ]]; then
        issues+=("Group is '${group}' (should be '${expected_group_regex}')")
    fi

    if [[ "${#issues[@]}" -eq 0 ]]; then
        report_ok "$id" "$title" "$level" "Automated" "${path} (${mode_oct} ${user}:${group})"
    else
        local finding
        finding="${path}: $(IFS=', '; echo "${issues[*]}")"
        report_fail "$id" "$title" "$level" "Automated" "$finding" "Run: ${chown_fix} && ${chmod_fix}"
    fi
}

# Check Sysctl Parameter (Active + Persistent config)
check_sysctl_param() {
    local id="$1"
    local title="$2"
    local level="$3"
    local param="$4"
    local expected_regex="$5"
    local recommended_val="$6"
    local conf_file="${7:-/etc/sysctl.d/60-cis-sysctl.conf}"

    should_run_check "$id" "$level" || return 0

    local running_val
    running_val="$(sysctl -n "$param" 2>/dev/null | xargs || true)"
    local issues=()

    if [[ -z "$running_val" ]]; then
        issues+=("Running sysctl '${param}' could not be read or is unavailable")
    elif [[ ! "$running_val" =~ ^(${expected_regex})$ ]]; then
        issues+=("Running '${param}' is '${running_val}' (expected: ${recommended_val})")
    fi

    # Check persistent configuration
    local p_grep="${param//./(\\.|\\/)}"
    local ufw_file=""
    if [[ -f /etc/default/ufw ]]; then
        ufw_file="$(awk -F= '/^\s*IPT_SYSCTL=/ {print $2}' /etc/default/ufw 2>/dev/null | tr -d '"'\'' ' || true)"
    fi
    local files_to_check=()
    [[ -n "$ufw_file" && -f "$ufw_file" ]] && files_to_check+=("$ufw_file")
    [[ -f /etc/sysctl.conf ]] && files_to_check+=("/etc/sysctl.conf")
    while IFS= read -r l_fname; do
        l_fname="$(readlink -e "${l_fname//# /}" 2>/dev/null || true)"
        if [[ -n "$l_fname" && -f "$l_fname" ]]; then
            local already=0
            local f
            for f in "${files_to_check[@]}"; do
                [[ "$f" == "$l_fname" ]] && already=1 && break
            done
            [[ "$already" -eq 0 ]] && files_to_check+=("$l_fname")
        fi
    done < <(grep -Psio -- '^\h*#\h*\/[^#\n\r\h]+\.conf\b' <<< "$SYSCTL_CAT_CACHE")

    local found_persistent=0
    local bad_persistent=()
    local f
    for f in "${files_to_check[@]}"; do
        local opt
        opt="$(grep -Psoi "^\h*${p_grep}\h*=\h*\H+\b" "$f" 2>/dev/null | tail -n 1 || true)"
        if [[ -n "$opt" ]]; then
            local val
            val="$(cut -d= -f2 <<< "$opt" | xargs)"
            if [[ "$val" =~ ^(${expected_regex})$ ]]; then
                found_persistent=1
            else
                bad_persistent+=("${f} sets ${param}=${val}")
            fi
        fi
    done

    if [[ "${#bad_persistent[@]}" -gt 0 ]]; then
        issues+=("Non-compliant persistent setting: $(IFS=', '; echo "${bad_persistent[*]}")")
    elif [[ "$found_persistent" -eq 0 ]]; then
        issues+=("Parameter '${param}' is not persisted in /etc/sysctl.conf or /etc/sysctl.d/*.conf")
    fi

    if [[ "${#issues[@]}" -eq 0 ]]; then
        report_ok "$id" "$title" "$level" "Automated" "${param} = ${running_val}"
    else
        local finding
        finding="$(IFS='; '; echo "${issues[*]}")"
        local rem="Comment out any conflicting '${param}' lines in /etc/sysctl.conf, /etc/sysctl.d/*.conf, and /etc/ufw/sysctl.conf, then run: printf '\n%s\n' '${param} = ${recommended_val}' >> ${conf_file} && sysctl -w ${param}=${recommended_val} && sysctl --system"
        report_fail "$id" "$title" "$level" "Automated" "$finding" "$rem"
    fi
}

# Check Service Not In Use (Section 2.1.*)
check_service_not_in_use() {
    local id="$1"
    local title="$2"
    local level="$3"
    local pkgs="$4"
    local units="$5"

    should_run_check "$id" "$level" || return 0

    local installed_pkgs=()
    local pkg
    for pkg in $pkgs; do
        if dpkg-query -s "$pkg" &>/dev/null; then
            installed_pkgs+=("$pkg")
        fi
    done

    if [[ "${#installed_pkgs[@]}" -eq 0 ]]; then
        report_ok "$id" "$title" "$level" "Automated" "Package(s) '${pkgs}' not installed"
        return 0
    fi

    # If installed, check if any unit is enabled or active
    local enabled_or_active=()
    local unit
    for unit in $units; do
        if systemctl is-enabled "$unit" 2>/dev/null | grep -q '^enabled'; then
            enabled_or_active+=("${unit} is enabled")
        fi
        if systemctl is-active "$unit" 2>/dev/null | grep -q '^active'; then
            enabled_or_active+=("${unit} is active")
        fi
    done

    if [[ "${#enabled_or_active[@]}" -eq 0 ]]; then
        report_ok "$id" "$title" "$level" "Automated" "Package(s) (${installed_pkgs[*]}) installed for dependency, but service/socket (${units}) disabled & inactive"
    else
        local finding="Package(s) (${installed_pkgs[*]}) installed and: $(IFS=', '; echo "${enabled_or_active[*]}")"
        local rem="Run: systemctl stop ${units} && apt purge -y ${pkgs} (or if required as a dependency: systemctl stop ${units} && systemctl mask ${units})"
        report_fail "$id" "$title" "$level" "Automated" "$finding" "$rem"
    fi
}
# ==============================================================================
# SECTION 1: INITIAL SETUP
# ==============================================================================
run_section_1() {
    print_section_header "1" "Initial Setup" || return 0

    # --------------------------------------------------------------------------
    # 1.1.1 Configure Filesystem Kernel Modules
    # --------------------------------------------------------------------------
    print_subsection_header "1.1.1 Configure Filesystem Kernel Modules"

    check_kernel_module "1.1.1.1" "Ensure cramfs kernel module is not available" "L1" "cramfs" "fs"
    check_kernel_module "1.1.1.2" "Ensure freevxfs kernel module is not available" "L1" "freevxfs" "fs"
    check_kernel_module "1.1.1.3" "Ensure hfs kernel module is not available" "L1" "hfs" "fs"
    check_kernel_module "1.1.1.4" "Ensure hfsplus kernel module is not available" "L1" "hfsplus" "fs"
    check_kernel_module "1.1.1.5" "Ensure jffs2 kernel module is not available" "L1" "jffs2" "fs"
    check_kernel_module "1.1.1.6" "Ensure overlay kernel module is not available" "L2" "overlay" "fs" "overlayfs"
    check_kernel_module "1.1.1.7" "Ensure squashfs kernel module is not available" "L2" "squashfs" "fs"
    check_kernel_module "1.1.1.8" "Ensure udf kernel module is not available" "L2" "udf" "fs"
    check_kernel_module "1.1.1.9" "Ensure firewire-core kernel module is not available" "L1" "firewire-core" "drivers" "firewire"
    check_kernel_module "1.1.1.10" "Ensure usb-storage kernel module is not available" "L1" "usb-storage" "drivers" "usb/storage"

    # 1.1.1.11 Ensure unused filesystems kernel modules are not available (Manual)
    if should_run_check "1.1.1.11" "L1"; then
        local a_mounted a_loaded_fs=() a_loadable_fs=()
        a_mounted="$(findmnt -Dkerno fstype 2>/dev/null | sort -u | tr '\n' ' ')"
        local cve_fs=("ceph" "cifs" "exfat" "ext" "fat" "fscache" "fuse" "gfs2" "nfs_common" "nfsd" "smbfs_common")
        local m
        for m in "${cve_fs[@]}"; do
            local m_under="${m//-/_}"
            if ! grep -Pq "\b${m}\b" <<< "$a_mounted"; then
                if grep -Pq "\b${m_under}\b" <<< "$LSMOD_CACHE"; then
                    a_loaded_fs+=("$m")
                elif ! grep -Pq "^\h*blacklist\h+${m_under}\b" <<< "$SHOWCONFIG_CACHE" || ! grep -Pq "^\h*install\h+${m_under}\h+/bin/(false|true)\b" <<< "$SHOWCONFIG_CACHE"; then
                    a_loadable_fs+=("$m")
                fi
            fi
        done
        local details="Mounted filesystems: [${a_mounted% }]."
        [[ "${#a_loaded_fs[@]}" -gt 0 ]] && details+=" Unmounted FS modules currently loaded: [${a_loaded_fs[*]}]."
        [[ "${#a_loadable_fs[@]}" -gt 0 ]] && details+=" Unmounted FS modules with known CVEs still loadable: [${a_loadable_fs[*]}]."
        report_manual "1.1.1.11" "Ensure unused filesystems kernel modules are not available" "L1" "Manual" \
            "$details" \
            "Review mounted filesystems ('findmnt -Dkerno fstype | sort -u') and disable unneeded FS modules (e.g. ceph, cifs, exfat, fat, fuse, gfs2, nfsd) by adding 'blacklist <mod>' and 'install <mod> /bin/false' in /etc/modprobe.d/<mod>.conf and unloading with 'modprobe -r <mod>'."
    fi

    # --------------------------------------------------------------------------
    # 1.1.2 Configure Filesystem Partitions
    # --------------------------------------------------------------------------
    print_subsection_header "1.1.2 Configure Filesystem Partitions"

    # 1.1.2.1 Configure /tmp
    check_mount_exists "1.1.2.1.1" "Ensure /tmp is tmpfs or a separate partition" "L1" "/tmp" "tmp.mount"
    check_mount_option "1.1.2.1.2" "Ensure nodev option set on /tmp partition" "L1" "/tmp" "nodev"
    check_mount_option "1.1.2.1.3" "Ensure nosuid option set on /tmp partition" "L1" "/tmp" "nosuid"
    check_mount_option "1.1.2.1.4" "Ensure noexec option set on /tmp partition" "L1" "/tmp" "noexec"

    # 1.1.2.2 Configure /dev/shm
    check_mount_exists "1.1.2.2.1" "Ensure /dev/shm is tmpfs or a separate partition" "L1" "/dev/shm"
    check_mount_option "1.1.2.2.2" "Ensure nodev option set on /dev/shm partition" "L1" "/dev/shm" "nodev"
    check_mount_option "1.1.2.2.3" "Ensure nosuid option set on /dev/shm partition" "L1" "/dev/shm" "nosuid"
    check_mount_option "1.1.2.2.4" "Ensure noexec option set on /dev/shm partition" "L1" "/dev/shm" "noexec"

    # 1.1.2.3 Configure /home
    check_mount_exists "1.1.2.3.1" "Ensure separate partition exists for /home" "L2" "/home"
    check_mount_option "1.1.2.3.2" "Ensure nodev option set on /home partition" "L1" "/home" "nodev"
    check_mount_option "1.1.2.3.3" "Ensure nosuid option set on /home partition" "L1" "/home" "nosuid"

    # 1.1.2.4 Configure /var
    check_mount_exists "1.1.2.4.1" "Ensure separate partition exists for /var" "L2" "/var"
    check_mount_option "1.1.2.4.2" "Ensure nodev option set on /var partition" "L1" "/var" "nodev"
    check_mount_option "1.1.2.4.3" "Ensure nosuid option set on /var partition" "L1" "/var" "nosuid"

    # 1.1.2.5 Configure /var/tmp
    check_mount_exists "1.1.2.5.1" "Ensure separate partition exists for /var/tmp" "L2" "/var/tmp"
    check_mount_option "1.1.2.5.2" "Ensure nodev option set on /var/tmp partition" "L1" "/var/tmp" "nodev"
    check_mount_option "1.1.2.5.3" "Ensure nosuid option set on /var/tmp partition" "L1" "/var/tmp" "nosuid"
    check_mount_option "1.1.2.5.4" "Ensure noexec option set on /var/tmp partition" "L1" "/var/tmp" "noexec"

    # 1.1.2.6 Configure /var/log
    check_mount_exists "1.1.2.6.1" "Ensure separate partition exists for /var/log" "L2" "/var/log"
    check_mount_option "1.1.2.6.2" "Ensure nodev option set on /var/log partition" "L1" "/var/log" "nodev"
    check_mount_option "1.1.2.6.3" "Ensure nosuid option set on /var/log partition" "L1" "/var/log" "nosuid"
    check_mount_option "1.1.2.6.4" "Ensure noexec option set on /var/log partition" "L1" "/var/log" "noexec"

    # 1.1.2.7 Configure /var/log/audit
    check_mount_exists "1.1.2.7.1" "Ensure separate partition exists for /var/log/audit" "L2" "/var/log/audit"
    check_mount_option "1.1.2.7.2" "Ensure nodev option set on /var/log/audit partition" "L1" "/var/log/audit" "nodev"
    check_mount_option "1.1.2.7.3" "Ensure nosuid option set on /var/log/audit partition" "L1" "/var/log/audit" "nosuid"
    check_mount_option "1.1.2.7.4" "Ensure noexec option set on /var/log/audit partition" "L1" "/var/log/audit" "noexec"

    # --------------------------------------------------------------------------
    # 1.2 Package Management
    # --------------------------------------------------------------------------
    print_subsection_header "1.2 Package Management"

    # 1.2.1.1 Ensure the source.list and .source files use the Signed-By option (Manual)
    if should_run_check "1.2.1.1" "L1"; then
        local unsigned_list unsigned_sources=""
        unsigned_list="$(grep -PRn -- '^\h*(deb(-src)?)\h+(\[(?![^\]]*\bSigned-By\b)[^\]]*\]|[^\[])' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true)"
        local sfile
        for sfile in /etc/apt/sources.list.d/*.sources; do
            [[ -f "$sfile" ]] || continue
            local sout
            sout="$(awk '
                BEGIN { uris=0; signed=0; lineno=0 }
                /^[[:blank:]]*$/ {
                    if (uris && !signed) print FILENAME ": stanza ending near line " lineno " is missing Signed-By"
                    uris=0; signed=0
                }
                /^[[:blank:]]*URIs:[[:blank:]]*\S/ { uris=1 }
                /^[[:blank:]]*Signed-By:[[:blank:]]*\S/ { signed=1 }
                { lineno=NR }
                END { if (uris && !signed) print FILENAME ": final stanza missing Signed-By" }
            ' "$sfile" 2>/dev/null)"
            [[ -n "$sout" ]] && unsigned_sources+="${sout}; "
        done
        if [[ -z "$unsigned_list" && -z "$unsigned_sources" ]]; then
            report_ok "1.2.1.1" "Ensure the source.list and .source files use the Signed-By option" "L1" "Manual" "All APT source entries include Signed-By"
        else
            report_fail "1.2.1.1" "Ensure the source.list and .source files use the Signed-By option" "L1" "Manual" \
                "Entries missing Signed-By: ${unsigned_list} ${unsigned_sources}" \
                "Update /etc/apt/sources.list and files in /etc/apt/sources.list.d/ so every repository stanza/line includes 'Signed-By=/usr/share/keyrings/<keyring>.gpg'."
        fi
    fi

    # 1.2.1.2 Ensure weak dependencies are configured (Automated)
    if should_run_check "1.2.1.2" "L2"; then
        local apt_rec apt_sug
        apt_rec="$(apt-config dump 2>/dev/null | grep -Pi '^\h*APT::Install-Recommends\h+"0";' || true)"
        apt_sug="$(apt-config dump 2>/dev/null | grep -Pi '^\h*APT::Install-Suggests\h+"0";' || true)"
        if [[ -n "$apt_rec" && -n "$apt_sug" ]]; then
            report_ok "1.2.1.2" "Ensure weak dependencies are configured" "L2" "Automated"
        else
            report_fail "1.2.1.2" "Ensure weak dependencies are configured" "L2" "Automated" \
                "APT::Install-Recommends and/or APT::Install-Suggests are not set to \"0\"" \
                "Run: printf '%s\n%s\n' '' 'APT::Install-Recommends \"0\";' 'APT::Install-Suggests \"0\";' > /etc/apt/apt.conf.d/60-no-weak-dependencies"
        fi
    fi

    # 1.2.1.3 Ensure access to gpg key files are configured (Automated)
    if should_run_check "1.2.1.3" "L1"; then
        local bad_gpg=()
        local f
        while IFS= read -r -d $'\0' f; do
            bad_gpg+=("$(stat -Lc '%n (%#a %U:%G)' "$f" 2>/dev/null)")
        done < <(find -L /usr/share/keyrings/ /etc/apt/trusted.gpg.d/ -mount -xdev -type f \( ! -user root -o ! -group root -o -perm /133 \) -name '*gpg' -print0 2>/dev/null)
        while IFS= read -r kpath; do
            local kfile
            kfile="$(readlink -e "$kpath" 2>/dev/null || true)"
            [[ -z "$kfile" ]] && continue
            case "$kfile" in /usr/share/keyrings/*|/etc/apt/trusted.gpg.d/*) continue ;; esac
            if stat -Lc 'Mode: (%#a) User: (%U) Group: (%G)' "$kfile" 2>/dev/null | grep -Pvq -- 'Mode: \(0?6[04][04]\) User: \(root\) Group: \(root\)'; then
                bad_gpg+=("$(stat -Lc '%n (%#a %U:%G)' "$kfile" 2>/dev/null)")
            fi
        done < <(grep -PRho -- '\bSigned-By\b\s*[=:]\s*\K\S+' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null | sort -u)
        if [[ "${#bad_gpg[@]}" -eq 0 ]]; then
            report_ok "1.2.1.3" "Ensure access to gpg key files are configured" "L1" "Automated"
        else
            report_fail "1.2.1.3" "Ensure access to gpg key files are configured" "L1" "Automated" \
                "Non-compliant GPG key files: ${bad_gpg[*]}" \
                "Run: chown root:root <file> && chmod u-x,go-wx <file> on all APT GPG key files in /usr/share/keyrings/, /etc/apt/trusted.gpg.d/, and Signed-By paths."
        fi
    fi

    # 1.2.1.4 Ensure access to /etc/apt/trusted.gpg.d directory is configured (Automated)
    check_file_perms "1.2.1.4" "Ensure access to /etc/apt/trusted.gpg.d directory is configured" "L1" \
        "/etc/apt/trusted.gpg.d" "0022" "0755" "root" "root" "1" \
        "chmod u=rwx,g=rx,o=rx /etc/apt/trusted.gpg.d" "chown root:root /etc/apt/trusted.gpg.d"

    # 1.2.1.5 Ensure access to /etc/apt/auth.conf.d directory is configured (Automated)
    check_file_perms "1.2.1.5" "Ensure access to /etc/apt/auth.conf.d directory is configured" "L1" \
        "/etc/apt/auth.conf.d" "0022" "0755" "root" "root" "1" \
        "chmod u=rwx,g=rx,o=rx /etc/apt/auth.conf.d" "chown root:root /etc/apt/auth.conf.d"

    # 1.2.1.6 Ensure access to files in the /etc/apt/auth.conf.d/ directory is configured (Automated)
    if should_run_check "1.2.1.6" "L1"; then
        local bad_auth=()
        if [[ -d /etc/apt/auth.conf.d ]]; then
            while IFS= read -r -d $'\0' f; do
                bad_auth+=("$(stat -Lc '%n (%#a %U:%G)' "$f" 2>/dev/null)")
            done < <(find /etc/apt/auth.conf.d/ -maxdepth 1 -type f \( ! -user root -o ! -group root -o -perm /137 \) -print0 2>/dev/null)
        fi
        if [[ "${#bad_auth[@]}" -eq 0 ]]; then
            report_ok "1.2.1.6" "Ensure access to files in the /etc/apt/auth.conf.d/ directory is configured" "L1" "Automated"
        else
            report_fail "1.2.1.6" "Ensure access to files in the /etc/apt/auth.conf.d/ directory is configured" "L1" "Automated" \
                "Files with excessive permissions or wrong owner: ${bad_auth[*]}" \
                "Run: chown root:root /etc/apt/auth.conf.d/* && chmod u-x,g-wx,o-rwx /etc/apt/auth.conf.d/*"
        fi
    fi

    # 1.2.1.7 Ensure access to /usr/share/keyrings directory is configured (Automated)
    check_file_perms "1.2.1.7" "Ensure access to /usr/share/keyrings directory is configured" "L1" \
        "/usr/share/keyrings" "0022" "0755" "root" "root" "1" \
        "chmod u=rwx,g=rx,o=rx /usr/share/keyrings" "chown root:root /usr/share/keyrings"

    # 1.2.1.8 Ensure access to /etc/apt/sources.list.d directory is configured (Automated)
    check_file_perms "1.2.1.8" "Ensure access to /etc/apt/sources.list.d directory is configured" "L1" \
        "/etc/apt/sources.list.d" "0022" "0755" "root" "root" "1" \
        "chmod u=rwx,g=rx,o=rx /etc/apt/sources.list.d" "chown root:root /etc/apt/sources.list.d"

    # 1.2.1.9 Ensure access to files in /etc/apt/sources.list.d are configured (Automated)
    if should_run_check "1.2.1.9" "L1"; then
        local bad_srcfiles=()
        if [[ -d /etc/apt/sources.list.d ]]; then
            while IFS= read -r -d $'\0' f; do
                bad_srcfiles+=("$(stat -Lc '%n (%#a %U:%G)' "$f" 2>/dev/null)")
            done < <(find /etc/apt/sources.list.d/ -maxdepth 1 -type f \( ! -user root -o ! -group root -o -perm /133 \) -print0 2>/dev/null)
        fi
        if [[ "${#bad_srcfiles[@]}" -eq 0 ]]; then
            report_ok "1.2.1.9" "Ensure access to files in /etc/apt/sources.list.d are configured" "L1" "Automated"
        else
            report_fail "1.2.1.9" "Ensure access to files in /etc/apt/sources.list.d are configured" "L1" "Automated" \
                "Non-compliant files in /etc/apt/sources.list.d: ${bad_srcfiles[*]}" \
                "Run: chown root:root /etc/apt/sources.list.d/* && chmod u-x,go-wx /etc/apt/sources.list.d/*"
        fi
    fi

    # 1.2.1.10 Ensure repositories are set to https in /etc/apt/sources.list (Automated)
    if should_run_check "1.2.1.10" "L1"; then
        local http_sl
        http_sl="$(grep -Pri -- '^\s*deb\s+http://' /etc/apt/sources.list 2>/dev/null || true)"
        if [[ -z "$http_sl" ]]; then
            report_ok "1.2.1.10" "Ensure repositories are set to https in /etc/apt/sources.list" "L1" "Automated"
        else
            report_fail "1.2.1.10" "Ensure repositories are set to https in /etc/apt/sources.list" "L1" "Automated" \
                "Plain HTTP repository found in /etc/apt/sources.list: ${http_sl}" \
                "Edit /etc/apt/sources.list and replace 'http://' with 'https://' for each repository URI."
        fi
    fi

    # 1.2.1.11 Ensure repositories are set to https in /etc/apt/sources.list.d directory (Automated)
    if should_run_check "1.2.1.11" "L1"; then
        local http_sld1 http_sld2
        http_sld1="$(grep -Pri -- '^\s*deb\s+http://' /etc/apt/sources.list.d/*.list 2>/dev/null || true)"
        http_sld2="$(grep -Pri -- '^\s*URIs:\s+http://' /etc/apt/sources.list.d/*.sources 2>/dev/null || true)"
        if [[ -z "$http_sld1" && -z "$http_sld2" ]]; then
            report_ok "1.2.1.11" "Ensure repositories are set to https in /etc/apt/sources.list.d directory" "L1" "Automated"
        else
            report_fail "1.2.1.11" "Ensure repositories are set to https in /etc/apt/sources.list.d directory" "L1" "Automated" \
                "Plain HTTP repository found in /etc/apt/sources.list.d/: ${http_sld1} ${http_sld2}" \
                "Edit files in /etc/apt/sources.list.d/ and replace 'http://' with 'https://' for each repository URI."
        fi
    fi

    # 1.2.1.12 Ensure AllowInsecureRepositories is configured (Automated)
    if should_run_check "1.2.1.12" "L1"; then
        if apt-config dump 2>/dev/null | grep -Fq 'Acquire::AllowInsecureRepositories "0";'; then
            report_ok "1.2.1.12" "Ensure AllowInsecureRepositories is configured" "L1" "Automated"
        else
            report_fail "1.2.1.12" "Ensure AllowInsecureRepositories is configured" "L1" "Automated" \
                "Acquire::AllowInsecureRepositories is not set to \"0\"" \
                "Run: printf '%s\n' '' 'Acquire::AllowInsecureRepositories \"0\";' >> /etc/apt/apt.conf.d/99-no-insecure-repositories"
        fi
    fi

    # 1.2.1.13 Ensure AllowWeakRepositories is configured (Automated)
    if should_run_check "1.2.1.13" "L1"; then
        if apt-config dump 2>/dev/null | grep -Fq 'Acquire::AllowWeakRepositories "0";'; then
            report_ok "1.2.1.13" "Ensure AllowWeakRepositories is configured" "L1" "Automated"
        else
            report_fail "1.2.1.13" "Ensure AllowWeakRepositories is configured" "L1" "Automated" \
                "Acquire::AllowWeakRepositories is not set to \"0\"" \
                "Run: printf '%s\n' '' 'Acquire::AllowWeakRepositories \"0\";' >> /etc/apt/apt.conf.d/99-no-insecure-repositories"
        fi
    fi

    # 1.2.1.14 Ensure AllowDowngradeToInsecureRepositories is configured (Automated)
    if should_run_check "1.2.1.14" "L1"; then
        if apt-config dump 2>/dev/null | grep -Fq 'Acquire::AllowDowngradeToInsecureRepositories "0";'; then
            report_ok "1.2.1.14" "Ensure AllowDowngradeToInsecureRepositories is configured" "L1" "Automated"
        else
            report_fail "1.2.1.14" "Ensure AllowDowngradeToInsecureRepositories is configured" "L1" "Automated" \
                "Acquire::AllowDowngradeToInsecureRepositories is not set to \"0\"" \
                "Run: echo 'Acquire::AllowDowngradeToInsecureRepositories \"0\";' >> /etc/apt/apt.conf.d/99-no-insecure-repositories"
        fi
    fi

    # 1.2.1.15 Ensure Acquire::Check-Date is configured (Automated)
    if should_run_check "1.2.1.15" "L1"; then
        if apt-config dump 2>/dev/null | grep -Psiq -- '^\h*Acquire::Check-Date\h+"true";'; then
            report_ok "1.2.1.15" "Ensure Acquire::Check-Date is configured" "L1" "Automated"
        else
            report_fail "1.2.1.15" "Ensure Acquire::Check-Date is configured" "L1" "Automated" \
                "Acquire::Check-Date is not explicitly set to \"true\"" \
                "Run: printf '%s\n' '' 'Acquire::Check-Date \"true\";' >> /etc/apt/apt.conf.d/99-no-insecure-repositories"
        fi
    fi

    # 1.2.2.1 Ensure updates, patches, and additional security software are installed (Manual)
    if should_run_check "1.2.2.1" "L1"; then
        local upg_count reboot_req=""
        upg_count="$(apt -s upgrade 2>/dev/null | awk '/^[0-9]+ upgraded/{print $1}' || echo 0)"
        [[ -f /var/run/reboot-required ]] && reboot_req="System reboot is required (/var/run/reboot-required exists)."
        if [[ "${upg_count:-0}" -eq 0 && -z "$reboot_req" ]]; then
            report_ok "1.2.2.1" "Ensure updates, patches, and additional security software are installed" "L1" "Manual" "0 packages pending upgrade; no reboot required"
        else
            report_manual "1.2.2.1" "Ensure updates, patches, and additional security software are installed" "L1" "Manual" \
                "${upg_count:-0} package(s) pending upgrade. ${reboot_req}" \
                "Run: apt update && apt upgrade (or apt dist-upgrade) and reboot if /var/run/reboot-required is present."
        fi
    fi

    # --------------------------------------------------------------------------
    # 1.3 Mandatory Access Control (AppArmor)
    # --------------------------------------------------------------------------
    print_subsection_header "1.3 Mandatory Access Control (AppArmor)"

    # 1.3.1.1 Ensure apparmor packages are installed (Automated)
    if should_run_check "1.3.1.1" "L1"; then
        if dpkg-query -s apparmor &>/dev/null && dpkg-query -s apparmor-utils &>/dev/null; then
            report_ok "1.3.1.1" "Ensure apparmor packages are installed" "L1" "Automated"
        else
            report_fail "1.3.1.1" "Ensure apparmor packages are installed" "L1" "Automated" \
                "Package 'apparmor' and/or 'apparmor-utils' is not installed" \
                "Run: apt install -y apparmor apparmor-utils"
        fi
    fi

    # 1.3.1.2 Ensure AppArmor is enabled (Automated)
    if should_run_check "1.3.1.2" "L1"; then
        local aa_grub1 aa_grub2 aa_en aa_act aa_prof
        aa_grub1="$(grep '^\s*linux' /boot/grub/grub.cfg 2>/dev/null | grep 'apparmor=0' || true)"
        aa_grub2="$(grep 'apparmor=0' /etc/default/grub.d/apparmor.cfg 2>/dev/null || true)"
        aa_en="$(systemctl is-enabled apparmor.service 2>/dev/null || true)"
        aa_act="$(systemctl is-active apparmor.service 2>/dev/null || true)"
        aa_prof="$(/usr/sbin/apparmor_status 2>/dev/null | awk '/profiles are loaded/{print $1}' || echo 0)"
        if [[ -z "$aa_grub1" && -z "$aa_grub2" && "$aa_en" == "enabled" && "$aa_act" == "active" && "${aa_prof:-0}" -gt 0 ]]; then
            report_ok "1.3.1.2" "Ensure AppArmor is enabled" "L1" "Automated" "${aa_prof} profiles loaded"
        else
            report_fail "1.3.1.2" "Ensure AppArmor is enabled" "L1" "Automated" \
                "apparmor.service enabled=${aa_en}, active=${aa_act}, profiles_loaded=${aa_prof:-0}, grub_disabled=${aa_grub1}${aa_grub2}" \
                "Remove 'apparmor=0' from /etc/default/grub and /etc/default/grub.d/*, run 'update-grub', enable 'systemctl --now enable apparmor.service', and reboot."
        fi
    fi

    # 1.3.1.3 Ensure all AppArmor Profiles are enforcing (Automated)
    if should_run_check "1.3.1.3" "L2"; then
        local aa_out loaded enforce complain unconfined_proc stub_profiles
        aa_out="$(/usr/sbin/apparmor_status 2>/dev/null || true)"
        loaded="$(awk '/profiles are loaded/{print $1}' <<< "$aa_out" || echo 0)"
        enforce="$(awk '/profiles are in enforce mode/{print $1}' <<< "$aa_out" || echo 0)"
        complain="$(awk '/profiles are in complain mode/{print $1}' <<< "$aa_out" || echo 0)"
        unconfined_proc="$(awk '/processes are unconfined but have a profile defined/{print $1}' <<< "$aa_out" || echo 0)"
        stub_profiles="$(grep -rl 'This profile exist only to give a name' /etc/apparmor.d/ 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -n "$aa_out" && "${loaded:-0}" -gt 0 && "$loaded" == "$enforce" && "${complain:-0}" -eq 0 && "${unconfined_proc:-0}" -eq 0 ]]; then
            report_ok "1.3.1.3" "Ensure all AppArmor Profiles are enforcing" "L2" "Automated" "${enforce}/${loaded} profiles enforcing"
        else
            report_fail "1.3.1.3" "Ensure all AppArmor Profiles are enforcing" "L2" "Automated" \
                "Loaded=${loaded:-0}, Enforce=${enforce:-0}, Complain=${complain:-0}, UnconfinedProcesses=${unconfined_proc:-0}, StubProfiles=[${stub_profiles% }]" \
                "Tune or remove any stub profiles in /etc/apparmor.d/, then enforce all profiles with: /usr/sbin/aa-enforce /etc/apparmor.d/*"
        fi
    fi

    # 1.3.1.4 Ensure kernel.apparmor_restrict_unprivileged_unconfined is enabled (Automated)
    check_sysctl_param "1.3.1.4" "Ensure kernel.apparmor_restrict_unprivileged_unconfined is enabled" "L1" \
        "kernel.apparmor_restrict_unprivileged_unconfined" "1" "1" "/etc/sysctl.d/60-kernel_sysctl.conf"

    # --------------------------------------------------------------------------
    # 1.4 Configure Bootloader
    # --------------------------------------------------------------------------
    print_subsection_header "1.4 Configure Bootloader"

    # 1.4.1 Ensure bootloader password is set (Automated)
    if should_run_check "1.4.1" "L1"; then
        local grub_su grub_pw
        grub_su="$(grep '^set superusers' /boot/grub/grub.cfg 2>/dev/null || true)"
        grub_pw="$(awk -F. '/^\s*password_pbkdf2/ {print $1"."$2"."$3}' /boot/grub/grub.cfg 2>/dev/null || true)"
        if [[ -n "$grub_su" && -n "$grub_pw" ]]; then
            report_ok "1.4.1" "Ensure bootloader password is set" "L1" "Automated"
        else
            report_fail "1.4.1" "Ensure bootloader password is set" "L1" "Automated" \
                "GRUB superusers and/or password_pbkdf2 not configured in /boot/grub/grub.cfg" \
                "Generate hash with 'grub-mkpasswd-pbkdf2 --iteration-count=600000 --salt=64', add 'set superusers=\"<user>\"' and 'password_pbkdf2 <user> <hash>' to a custom file in /etc/grub.d/, and run 'update-grub'."
        fi
    fi

    # 1.4.2 Ensure access to bootloader config is configured (Automated)
    check_file_perms "1.4.2" "Ensure access to bootloader config is configured" "L1" \
        "/boot/grub/grub.cfg" "0177" "0600" "root" "root" "0" \
        "chmod u-x,go-rwx /boot/grub/grub.cfg" "chown root:root /boot/grub/grub.cfg"

    # --------------------------------------------------------------------------
    # 1.5 Configure Additional Process Hardening
    # --------------------------------------------------------------------------
    print_subsection_header "1.5 Configure Additional Process Hardening"

    check_sysctl_param "1.5.1" "Ensure fs.protected_hardlinks is configured" "L1" \
        "fs.protected_hardlinks" "1" "1" "/etc/sysctl.d/60-fs_sysctl.conf"

    check_sysctl_param "1.5.2" "Ensure fs.protected_symlinks is configured" "L2" \
        "fs.protected_symlinks" "1" "1" "/etc/sysctl.d/60-fs_sysctl.conf"

    check_sysctl_param "1.5.3" "Ensure kernel.yama.ptrace_scope is configured" "L1" \
        "kernel.yama.ptrace_scope" "1|2|3" "1" "/etc/sysctl.d/60-kernel_sysctl.conf"

    check_sysctl_param "1.5.4" "Ensure fs.suid_dumpable is configured" "L1" \
        "fs.suid_dumpable" "0" "0" "/etc/sysctl.d/60-fs_sysctl.conf"

    check_sysctl_param "1.5.5" "Ensure kernel.dmesg_restrict is configured" "L1" \
        "kernel.dmesg_restrict" "1" "1" "/etc/sysctl.d/60-kernel_sysctl.conf"

    # 1.5.6 Ensure prelink is not installed (Automated)
    if should_run_check "1.5.6" "L1"; then
        if ! dpkg-query -s prelink &>/dev/null; then
            report_ok "1.5.6" "Ensure prelink is not installed" "L1" "Automated"
        else
            report_fail "1.5.6" "Ensure prelink is not installed" "L1" "Automated" \
                "Package 'prelink' is installed" \
                "Run: prelink -ua && apt purge -y prelink"
        fi
    fi

    # 1.5.7 Ensure Automatic Error Reporting is configured (Automated)
    if should_run_check "1.5.7" "L1"; then
        local apport_en="" apport_act=""
        if dpkg-query -s apport &>/dev/null; then
            apport_en="$(grep -Psi -- '^\h*enabled\h*=\h*[^0]\b' /etc/default/apport 2>/dev/null || true)"
        fi
        apport_act="$(systemctl is-active apport.service 2>/dev/null | grep '^active' || true)"
        if [[ -z "$apport_en" && -z "$apport_act" ]]; then
            report_ok "1.5.7" "Ensure Automatic Error Reporting is configured" "L1" "Automated"
        else
            report_fail "1.5.7" "Ensure Automatic Error Reporting is configured" "L1" "Automated" \
                "Apport is enabled (${apport_en}) or apport.service is active (${apport_act})" \
                "Set 'enabled=0' in /etc/default/apport and run: systemctl stop apport.service && systemctl mask apport.service (or 'apt purge -y apport')."
        fi
    fi

    check_sysctl_param "1.5.8" "Ensure kernel.kptr_restrict is configured" "L1" \
        "kernel.kptr_restrict" "1|2" "2" "/etc/sysctl.d/60-kernel_sysctl.conf"

    check_sysctl_param "1.5.9" "Ensure kernel.randomize_va_space is configured" "L1" \
        "kernel.randomize_va_space" "2" "2" "/etc/sysctl.d/60-kernel_sysctl.conf"

    # 1.5.10 Ensure core file size is configured (Automated)
    if should_run_check "1.5.10" "L1"; then
        local core_zero core_gt0
        core_zero="$(grep -Psi -- '^\h*\*\h+hard\h+core\h+0\b' /etc/security/limits.conf /etc/security/limits.d/* 2>/dev/null || true)"
        core_gt0="$(grep -Psi -- '^\h*\*\h+hard\h+core\h+([1-9][0-9]*)\b' /etc/security/limits.conf /etc/security/limits.d/* 2>/dev/null || true)"
        if [[ -n "$core_zero" && -z "$core_gt0" ]]; then
            report_ok "1.5.10" "Ensure core file size is configured" "L1" "Automated"
        else
            report_fail "1.5.10" "Ensure core file size is configured" "L1" "Automated" \
                "Missing '* hard core 0' or non-zero hard core limit present (${core_gt0})" \
                "Run: sed -ri '/^\s*[^#\n\r]+\s+hard\s+core\s+([1-9][0-9]*)/s/^/# /' /etc/security/limits.conf /etc/security/limits.d/* 2>/dev/null; printf '\n%s\n' '* hard core 0' >> /etc/security/limits.d/60-limits.conf"
        fi
    fi

    # 1.5.11 Ensure systemd-coredump ProcessSizeMax is configured (Automated)
    if should_run_check "1.5.11" "L1"; then
        if ! dpkg-query -s systemd-coredump &>/dev/null && [[ ! -e /etc/systemd/coredump.conf && ! -e /usr/lib/systemd/coredump.conf ]]; then
            report_ok "1.5.11" "Ensure systemd-coredump ProcessSizeMax is configured" "L1" "Automated" "systemd-coredump not installed"
        else
            local psm_val=""
            local cf
            for cf in /etc/systemd/coredump.conf /etc/systemd/coredump.conf.d/*.conf; do
                [[ -f "$cf" ]] || continue
                local v
                v="$(awk '/\[Coredump\]/{a=1;next}/\[/{a=0}a' "$cf" 2>/dev/null | grep -Poi '^\h*ProcessSizeMax\h*=\h*\K\H+' | tail -n 1 || true)"
                [[ -n "$v" ]] && psm_val="$v"
            done
            if [[ "$psm_val" == "0" ]]; then
                report_ok "1.5.11" "Ensure systemd-coredump ProcessSizeMax is configured" "L1" "Automated" "ProcessSizeMax=0"
            else
                report_fail "1.5.11" "Ensure systemd-coredump ProcessSizeMax is configured" "L1" "Automated" \
                    "ProcessSizeMax is '${psm_val:-not set (default 2G)}' (expected: 0)" \
                    "Create /etc/systemd/coredump.conf.d/60-coredump.conf with '[Coredump]' and 'ProcessSizeMax=0', then run: systemctl reload-or-restart systemd-coredump.socket"
            fi
        fi
    fi

    # 1.5.12 Ensure systemd-coredump Storage is configured (Automated)
    if should_run_check "1.5.12" "L1"; then
        if ! dpkg-query -s systemd-coredump &>/dev/null && [[ ! -e /etc/systemd/coredump.conf && ! -e /usr/lib/systemd/coredump.conf ]]; then
            report_ok "1.5.12" "Ensure systemd-coredump Storage is configured" "L1" "Automated" "systemd-coredump not installed"
        else
            local st_val=""
            local cf
            for cf in /etc/systemd/coredump.conf /etc/systemd/coredump.conf.d/*.conf; do
                [[ -f "$cf" ]] || continue
                local v
                v="$(awk '/\[Coredump\]/{a=1;next}/\[/{a=0}a' "$cf" 2>/dev/null | grep -Poi '^\h*Storage\h*=\h*\K\H+' | tail -n 1 || true)"
                [[ -n "$v" ]] && st_val="$v"
            done
            if [[ "${st_val,,}" == "none" ]]; then
                report_ok "1.5.12" "Ensure systemd-coredump Storage is configured" "L1" "Automated" "Storage=none"
            else
                report_fail "1.5.12" "Ensure systemd-coredump Storage is configured" "L1" "Automated" \
                    "Storage is '${st_val:-not set (default external)}' (expected: none)" \
                    "Create /etc/systemd/coredump.conf.d/60-coredump.conf with '[Coredump]' and 'Storage=none', then run: systemctl reload-or-restart systemd-coredump.socket"
            fi
        fi
    fi

    # --------------------------------------------------------------------------
    # 1.6 Configure Command Line Warning Banners
    # --------------------------------------------------------------------------
    print_subsection_header "1.6 Configure Command Line Warning Banners"

    # 1.6.1 Ensure /etc/motd is configured (Automated)
    if should_run_check "1.6.1" "L1"; then
        local motd_bad
        motd_bad="$(grep -Psi -- "(\\\v|\\\r|\\\m|\\\s|\b${OS_ID}\b)" /etc/motd /etc/motd.d/* 2>/dev/null || true)"
        if [[ -z "$motd_bad" ]]; then
            report_ok "1.6.1" "Ensure /etc/motd is configured" "L1" "Automated"
        else
            report_fail "1.6.1" "Ensure /etc/motd is configured" "L1" "Automated" \
                "OS/system information found in MOTD: ${motd_bad}" \
                "Edit /etc/motd and /etc/motd.d/* to remove any instances of \m, \r, \s, \v, or references to the OS platform (or 'rm /etc/motd' if not used)."
        fi
    fi

    # 1.6.2 Ensure /etc/issue is configured (Automated)
    if should_run_check "1.6.2" "L1"; then
        local issue_bad
        issue_bad="$(grep -Psi -- "(\\\v|\\\r|\\\m|\\\s|\b${OS_ID}\b)" /etc/issue /usr/lib/issue.d/* /etc/issue.d/* /run/issue.d/* 2>/dev/null || true)"
        if [[ -s /etc/issue && -z "$issue_bad" ]]; then
            report_ok "1.6.2" "Ensure /etc/issue is configured" "L1" "Automated"
        else
            report_fail "1.6.2" "Ensure /etc/issue is configured" "L1" "Automated" \
                "/etc/issue is empty or contains OS escape sequences/identifiers: ${issue_bad}" \
                "Run: echo 'Authorized users only. All activity may be monitored and reported.' > /etc/issue (and remove OS info from /etc/issue.d/*)."
        fi
    fi

    # 1.6.3 Ensure /etc/issue.net is configured (Automated)
    if should_run_check "1.6.3" "L1"; then
        local issuenet_bad
        issuenet_bad="$(grep -Psi -- "(\\\v|\\\r|\\\m|\\\s|\b${OS_ID}\b)" /etc/issue.net 2>/dev/null || true)"
        if [[ -s /etc/issue.net && -z "$issuenet_bad" ]]; then
            report_ok "1.6.3" "Ensure /etc/issue.net is configured" "L1" "Automated"
        else
            report_fail "1.6.3" "Ensure /etc/issue.net is configured" "L1" "Automated" \
                "/etc/issue.net is missing/empty or contains OS escape sequences/identifiers: ${issuenet_bad}" \
                "Run: echo 'Authorized users only. All activity may be monitored and reported.' > /etc/issue.net"
        fi
    fi

    # 1.6.4 Ensure pam_motd is configured (Automated)
    if should_run_check "1.6.4" "L1"; then
        local pam_motd_bad=()
        local svc file line motd_path
        for svc in sshd login su gdm-password; do
            if [[ -f "/etc/pam.d/$svc" ]]; then file="/etc/pam.d/$svc"
            elif [[ -f "/usr/lib/pam.d/$svc" ]]; then file="/usr/lib/pam.d/$svc"
            else continue; fi
            while IFS= read -r line; do
                while IFS= read -r motd_path; do
                    motd_path="${motd_path%\"}"; motd_path="${motd_path#\"}"
                    motd_path="${motd_path%\'}"; motd_path="${motd_path#\'}"
                    [[ -r "$motd_path" ]] || continue
                    if grep -Piq -- "(\\\v|\\\r|\\\m|\\\s|\b${OS_ID}\b)" "$motd_path" 2>/dev/null; then
                        pam_motd_bad+=("${file} -> ${motd_path}")
                    fi
                done < <(printf '%s\n' "$line" | grep -oP '\bmotd=\K"[^"]+"|\bmotd=\K'\''[^'\'']+'\''|\bmotd=\K\S+')
            done < <(grep -Pi '^\h*session\h+(required|optional)\h+pam_motd\.so\b.*\bmotd=' "$file" 2>/dev/null)
        done
        if [[ "${#pam_motd_bad[@]}" -eq 0 ]]; then
            report_ok "1.6.4" "Ensure pam_motd is configured" "L1" "Automated"
        else
            report_fail "1.6.4" "Ensure pam_motd is configured" "L1" "Automated" \
                "pam_motd files contain OS/system info: ${pam_motd_bad[*]}" \
                "Edit the referenced MOTD files and scripts in /etc/update-motd.d/ (e.g. 10-uname) to remove OS/kernel/platform-identifying information."
        fi
    fi

    # 1.6.5 Ensure sshd warning Banner is configured (Automated)
    if should_run_check "1.6.5" "L1"; then
        if [[ -z "$SSHD_BIN" ]]; then
            report_ok "1.6.5" "Ensure sshd warning Banner is configured" "L1" "Automated" "openssh-server not installed"
        else
            local bfile
            bfile="$(awk '$1 == "banner" {print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ -n "$bfile" && "$bfile" != "none" && -s "$bfile" ]]; then
                local b_bad
                b_bad="$(grep -Psi -- "(\\\v|\\\r|\\\m|\\\s|\b${OS_ID}\b)" "$bfile" 2>/dev/null || true)"
                if [[ -z "$b_bad" ]]; then
                    report_ok "1.6.5" "Ensure sshd warning Banner is configured" "L1" "Automated" "Banner=${bfile}"
                else
                    report_fail "1.6.5" "Ensure sshd warning Banner is configured" "L1" "Automated" \
                        "SSH banner file '${bfile}' contains OS/platform identifiers: ${b_bad}" \
                        "Run: printf '%s\n' 'Authorized users only. All activity may be monitored and reported.' > ${bfile}"
                fi
            else
                report_fail "1.6.5" "Ensure sshd warning Banner is configured" "L1" "Automated" \
                    "sshd Banner is not configured or banner file '${bfile:-none}' is empty/missing" \
                    "Set 'Banner /etc/issue.net' in /etc/ssh/sshd_config.d/60-cis.conf, populate /etc/issue.net with site policy text, and run: systemctl reload sshd"
            fi
        fi
    fi

    # 1.6.6 Ensure access to /etc/motd is configured (Automated)
    if should_run_check "1.6.6" "L1"; then
        local bad_motd_perms=()
        local mf
        for mf in /etc/motd /run/motd /usr/lib/motd /etc/motd.d/* /run/motd.d/* /usr/lib/motd.d/* /etc/update-motd.d/*; do
            [[ -e "$mf" ]] || continue
            local rmf
            rmf="$(readlink -e "$mf" 2>/dev/null || true)"
            [[ -f "$rmf" ]] || continue
            local m u g
            read -r m u g <<< "$(stat -Lc '%#a %U %G' "$rmf" 2>/dev/null)"
            if [[ $(( m & 0133 )) -gt 0 && ! "$rmf" =~ ^/etc/update-motd\.d/ ]] || [[ $(( m & 0022 )) -gt 0 ]] || [[ "$u" != "root" || "$g" != "root" ]]; then
                bad_motd_perms+=("${rmf} (${m} ${u}:${g})")
            fi
        done
        if [[ "${#bad_motd_perms[@]}" -eq 0 ]]; then
            report_ok "1.6.6" "Ensure access to /etc/motd is configured" "L1" "Automated"
        else
            report_fail "1.6.6" "Ensure access to /etc/motd is configured" "L1" "Automated" \
                "Improper permissions/ownership on MOTD files: ${bad_motd_perms[*]}" \
                "Run: chown root:root \$(readlink -e /etc/motd) && chmod u-x,go-wx \$(readlink -e /etc/motd)"
        fi
    fi

    # 1.6.7 Ensure access to /etc/issue is configured (Automated)
    check_file_perms "1.6.7" "Ensure access to /etc/issue is configured" "L1" \
        "$(readlink -e /etc/issue 2>/dev/null || echo /etc/issue)" "0133" "0644" "root" "root" "0" \
        "chmod u-x,go-wx \$(readlink -e /etc/issue)" "chown root:root \$(readlink -e /etc/issue)"

    # 1.6.8 Ensure access to /etc/issue.net is configured (Automated)
    check_file_perms "1.6.8" "Ensure access to /etc/issue.net is configured" "L1" \
        "$(readlink -e /etc/issue.net 2>/dev/null || echo /etc/issue.net)" "0133" "0644" "root" "root" "0" \
        "chmod u-x,go-wx \$(readlink -e /etc/issue.net)" "chown root:root \$(readlink -e /etc/issue.net)"

    # 1.6.9 Ensure access to pam_motd file is configured (Automated)
    if should_run_check "1.6.9" "L1"; then
        local bad_pm=()
        local pmf
        while IFS= read -r pmf; do
            [[ -e "$pmf" ]] || continue
            local m u g
            read -r m u g <<< "$(stat -Lc '%#a %U %G' "$pmf" 2>/dev/null)"
            if [[ $(( m & 0133 )) -gt 0 || "$u" != "root" || "$g" != "root" ]]; then
                bad_pm+=("${pmf} (${m} ${u}:${g})")
            fi
        done < <(grep -hPo 'motd=\K\S+' /etc/pam.d/* 2>/dev/null | sort -u)
        if [[ "${#bad_pm[@]}" -eq 0 ]]; then
            report_ok "1.6.9" "Ensure access to pam_motd file is configured" "L1" "Automated"
        else
            report_fail "1.6.9" "Ensure access to pam_motd file is configured" "L1" "Automated" \
                "pam_motd files have improper access: ${bad_pm[*]}" \
                "Run: chown root:root <path/to/motd> && chmod u-x,go-wx <path/to/motd>"
        fi
    fi

    # 1.6.10 Ensure access to sshd warning banner is configured (Automated)
    if should_run_check "1.6.10" "L1"; then
        local ssh_bfile
        ssh_bfile="$(awk '$1 == "banner" {print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
        if [[ -z "$SSHD_BIN" || -z "$ssh_bfile" || "$ssh_bfile" == "none" ]]; then
            report_ok "1.6.10" "Ensure access to sshd warning banner is configured" "L1" "Automated" "No custom sshd banner file active"
        else
            check_file_perms "1.6.10" "Ensure access to sshd warning banner is configured" "L1" \
                "$ssh_bfile" "0133" "0644" "root" "root" "0" \
                "chmod u-x,go-wx ${ssh_bfile}" "chown root:root ${ssh_bfile}"
        fi
    fi

    # 1.6.11 Ensure update-notifier-motd.service is not in use (Automated)
    if should_run_check "1.6.11" "L1"; then
        local un_en un_act
        un_en="$(systemctl is-enabled update-notifier-motd.service 2>/dev/null | grep 'enabled' || true)"
        un_act="$(systemctl is-active update-notifier-motd.service 2>/dev/null | grep '^active' || true)"
        if [[ -z "$un_en" && -z "$un_act" ]]; then
            report_ok "1.6.11" "Ensure update-notifier-motd.service is not in use" "L1" "Automated"
        else
            report_fail "1.6.11" "Ensure update-notifier-motd.service is not in use" "L1" "Automated" \
                "update-notifier-motd.service is enabled (${un_en}) or active (${un_act})" \
                "Run: systemctl stop update-notifier-motd.service && systemctl mask update-notifier-motd.service"
        fi
    fi

    # 1.6.12 Ensure update-notifier-motd.timer is not in use (Automated)
    if should_run_check "1.6.12" "L1"; then
        local unt_en unt_act
        unt_en="$(systemctl is-enabled update-notifier-motd.timer 2>/dev/null | grep 'enabled' || true)"
        unt_act="$(systemctl is-active update-notifier-motd.timer 2>/dev/null | grep '^active' || true)"
        if [[ -z "$unt_en" && -z "$unt_act" ]]; then
            report_ok "1.6.12" "Ensure update-notifier-motd.timer is not in use" "L1" "Automated"
        else
            report_fail "1.6.12" "Ensure update-notifier-motd.timer is not in use" "L1" "Automated" \
                "update-notifier-motd.timer is enabled (${unt_en}) or active (${unt_act})" \
                "Run: systemctl stop update-notifier-motd.timer && systemctl mask update-notifier-motd.timer"
        fi
    fi

    # --------------------------------------------------------------------------
    # 1.7 Configure GNOME Display Manager
    # --------------------------------------------------------------------------
    print_subsection_header "1.7 Configure GNOME Display Manager"

    local gdm_installed=0
    if dpkg-query -s gdm3 &>/dev/null || dpkg-query -s gdm &>/dev/null; then
        gdm_installed=1
    fi

    # 1.7.1 Ensure GDM login banner is configured (Automated)
    if should_run_check "1.7.1" "L1"; then
        if [[ "$gdm_installed" -eq 0 ]]; then
            report_ok "1.7.1" "Ensure GDM login banner is configured" "L1" "Automated" "GDM is not installed"
        else
            local b_en b_txt b_lock1 b_lock2
            b_en="$(grep -RPsi -- '^\h*banner-message-enable\h*=\h*true\b' /etc/dconf/db/ 2>/dev/null || true)"
            b_txt="$(grep -RPsi -- '^\h*banner-message-text\h*=\h*'\''[^'\'']+'\''' /etc/dconf/db/ 2>/dev/null || true)"
            b_lock1="$(grep -RPsi -- '^\h*/org/gnome/login-screen/banner-message-enable\b' /etc/dconf/db/ 2>/dev/null || true)"
            b_lock2="$(grep -RPsi -- '^\h*/org/gnome/login-screen/banner-message-text\b' /etc/dconf/db/ 2>/dev/null || true)"
            if [[ -n "$b_en" && -n "$b_txt" && -n "$b_lock1" && -n "$b_lock2" ]]; then
                report_ok "1.7.1" "Ensure GDM login banner is configured" "L1" "Automated"
            else
                report_fail "1.7.1" "Ensure GDM login banner is configured" "L1" "Automated" \
                    "GDM banner-message-enable / banner-message-text not configured or not locked in /etc/dconf/db/" \
                    "Configure [org/gnome/login-screen] banner-message-enable=true and banner-message-text in /etc/dconf/db/local.d/60-banner-message, lock them in /etc/dconf/db/local.d/locks/, and run 'dconf update'."
            fi
        fi
    fi

    # 1.7.2 Ensure GDM disable-user-list is configured (Automated)
    if should_run_check "1.7.2" "L1"; then
        if [[ "$gdm_installed" -eq 0 ]]; then
            report_ok "1.7.2" "Ensure GDM disable-user-list is configured" "L1" "Automated" "GDM is not installed"
        else
            local dul_en dul_lock
            dul_en="$(grep -RPsi -- '^\h*disable-user-list\h*=\h*true\b' /etc/dconf/db/ 2>/dev/null || true)"
            dul_lock="$(grep -RPsi -- '^\h*/org/gnome/login-screen/disable-user-list\b' /etc/dconf/db/ 2>/dev/null || true)"
            if [[ -n "$dul_en" && -n "$dul_lock" ]]; then
                report_ok "1.7.2" "Ensure GDM disable-user-list is configured" "L1" "Automated"
            else
                report_fail "1.7.2" "Ensure GDM disable-user-list is configured" "L1" "Automated" \
                    "GDM disable-user-list=true is not set or not locked in /etc/dconf/db/" \
                    "Set 'disable-user-list=true' under [org/gnome/login-screen] in /etc/dconf/db/local.d/60-login-screen, lock '/org/gnome/login-screen/disable-user-list' in /etc/dconf/db/local.d/locks/, and run 'dconf update'."
            fi
        fi
    fi

    # 1.7.3 Ensure GDM screen lock is configured (Automated)
    if should_run_check "1.7.3" "L1"; then
        if [[ "$gdm_installed" -eq 0 ]]; then
            report_ok "1.7.3" "Ensure GDM screen lock is configured" "L1" "Automated" "GDM is not installed"
        else
            local id_val ld_val id_lock ld_lock
            id_val="$(grep -RPo -- '^\h*idle-delay\h*=\h*uint32\h+\K\d+' /etc/dconf/db/ 2>/dev/null | tail -n 1 || true)"
            ld_val="$(grep -RPo -- '^\h*lock-delay\h*=\h*uint32\h+\K\d+' /etc/dconf/db/ 2>/dev/null | tail -n 1 || true)"
            id_lock="$(grep -RPsi -- '^\h*/org/gnome/desktop/session/idle-delay\b' /etc/dconf/db/ 2>/dev/null || true)"
            ld_lock="$(grep -RPsi -- '^\h*/org/gnome/desktop/screensaver/lock-delay\b' /etc/dconf/db/ 2>/dev/null || true)"
            if [[ -n "$id_val" && "$id_val" -gt 0 && "$id_val" -le 900 && -n "$ld_val" && "$ld_val" -le 5 && -n "$id_lock" && -n "$ld_lock" ]]; then
                report_ok "1.7.3" "Ensure GDM screen lock is configured" "L1" "Automated"
            else
                report_fail "1.7.3" "Ensure GDM screen lock is configured" "L1" "Automated" \
                    "GDM idle-delay (${id_val:-unset}, need 1..900) or lock-delay (${ld_val:-unset}, need <=5) not compliant or not locked" \
                    "Set 'idle-delay=uint32 900' and 'lock-delay=uint32 5' in /etc/dconf/db/local.d/60-screensaver, lock both keys in /etc/dconf/db/local.d/locks/60-screensaver, and run 'dconf update'."
            fi
        fi
    fi

    # 1.7.4 Ensure GDM automount is configured (Automated)
    if should_run_check "1.7.4" "L1"; then
        if [[ "$gdm_installed" -eq 0 ]]; then
            report_ok "1.7.4" "Ensure GDM automount is configured" "L1" "Automated" "GDM is not installed"
        else
            local am1 am2 aml1 aml2
            am1="$(grep -RPsi -- '^\h*automount\h*=\h*false\b' /etc/dconf/db/ 2>/dev/null || true)"
            am2="$(grep -RPsi -- '^\h*automount-open\h*=\h*false\b' /etc/dconf/db/ 2>/dev/null || true)"
            aml1="$(grep -RPsi -- '^\h*/org/gnome/desktop/media-handling/automount\b' /etc/dconf/db/ 2>/dev/null || true)"
            aml2="$(grep -RPsi -- '^\h*/org/gnome/desktop/media-handling/automount-open\b' /etc/dconf/db/ 2>/dev/null || true)"
            if [[ -n "$am1" && -n "$am2" && -n "$aml1" && -n "$aml2" ]]; then
                report_ok "1.7.4" "Ensure GDM automount is configured" "L1" "Automated"
            else
                report_fail "1.7.4" "Ensure GDM automount is configured" "L1" "Automated" \
                    "GDM automount=false and/or automount-open=false not configured or not locked" \
                    "Configure 'automount=false' and 'automount-open=false' under [org/gnome/desktop/media-handling] in /etc/dconf/db/local.d/60-media-automount, lock both keys, and run 'dconf update'."
            fi
        fi
    fi

    # 1.7.5 Ensure GDM autorun-never is configured (Automated)
    if should_run_check "1.7.5" "L1"; then
        if [[ "$gdm_installed" -eq 0 ]]; then
            report_ok "1.7.5" "Ensure GDM autorun-never is configured" "L1" "Automated" "GDM is not installed"
        else
            local arn arnl
            arn="$(grep -RPsi -- '^\h*autorun-never\h*=\h*true\b' /etc/dconf/db/ 2>/dev/null || true)"
            arnl="$(grep -RPsi -- '^\h*/org/gnome/desktop/media-handling/autorun-never\b' /etc/dconf/db/ 2>/dev/null || true)"
            if [[ -n "$arn" && -n "$arnl" ]]; then
                report_ok "1.7.5" "Ensure GDM autorun-never is configured" "L1" "Automated"
            else
                report_fail "1.7.5" "Ensure GDM autorun-never is configured" "L1" "Automated" \
                    "GDM autorun-never=true is not set or not locked" \
                    "Set 'autorun-never=true' under [org/gnome/desktop/media-handling] in /etc/dconf/db/local.d/60-media-autorun, lock '/org/gnome/desktop/media-handling/autorun-never', and run 'dconf update'."
            fi
        fi
    fi

    # 1.7.6 Ensure XDMCP is not enabled (Automated)
    if should_run_check "1.7.6" "L1"; then
        local xdmcp_bad=""
        local gf
        for gf in /etc/gdm3/custom.conf /etc/gdm3/daemon.conf /etc/gdm/custom.conf /etc/gdm/daemon.conf; do
            [[ -f "$gf" ]] || continue
            local out
            out="$(awk '/\[xdmcp\]/{f=1;next}/\[/{f=0}f{if(/^\s*Enable\s*=\s*true/) print FILENAME ":" $0}' "$gf" 2>/dev/null || true)"
            [[ -n "$out" ]] && xdmcp_bad+="$out "
        done
        if [[ -z "$xdmcp_bad" ]]; then
            report_ok "1.7.6" "Ensure XDMCP is not enabled" "L1" "Automated"
        else
            report_fail "1.7.6" "Ensure XDMCP is not enabled" "L1" "Automated" \
                "XDMCP Enable=true found in: ${xdmcp_bad}" \
                "Remove or comment out 'Enable=true' under the [xdmcp] block in /etc/gdm3/custom.conf (or daemon.conf)."
        fi
    fi

    # 1.7.7 Ensure Xwayland is configured (Automated)
    if should_run_check "1.7.7" "L2"; then
        if [[ "$gdm_installed" -eq 0 ]]; then
            report_ok "1.7.7" "Ensure Xwayland is configured" "L2" "Automated" "GDM is not installed"
        else
            local wl_disabled=""
            local gf
            for gf in /etc/gdm3/custom.conf /etc/gdm3/daemon.conf /etc/gdm/custom.conf /etc/gdm/daemon.conf; do
                [[ -f "$gf" ]] && grep -Piq '^\h*WaylandEnable\h*=\h*false\b' "$gf" 2>/dev/null && wl_disabled="$gf"
            done
            if [[ -n "$wl_disabled" ]]; then
                report_ok "1.7.7" "Ensure Xwayland is configured" "L2" "Automated" "WaylandEnable=false in ${wl_disabled}"
            else
                report_fail "1.7.7" "Ensure Xwayland is configured" "L2" "Automated" \
                    "WaylandEnable=false not set in GDM configuration" \
                    "Add 'WaylandEnable=false' under the [daemon] block in /etc/gdm3/custom.conf."
            fi
        fi
    fi
}
# ==============================================================================
# SECTION 2: SERVICES
# ==============================================================================
run_section_2() {
    print_section_header "2" "Services" || return 0

    # --------------------------------------------------------------------------
    # 2.1 Configure Server Services
    # --------------------------------------------------------------------------
    print_subsection_header "2.1 Configure Server Services"

    check_service_not_in_use "2.1.1" "Ensure autofs services are not in use" "L1" "autofs" "autofs.service"
    check_service_not_in_use "2.1.2" "Ensure avahi daemon services are not in use" "L1" "avahi-daemon" "avahi-daemon.socket avahi-daemon.service"
    check_service_not_in_use "2.1.3" "Ensure dhcp server services are not in use" "L1" "kea isc-dhcp-server" "kea-dhcp-ddns-server.service kea-dhcp4-server.service kea-dhcp6-server.service isc-dhcp-server.service isc-dhcp-server6.service"
    check_service_not_in_use "2.1.4" "Ensure dns server services are not in use" "L1" "bind9" "named.service"
    check_service_not_in_use "2.1.5" "Ensure dnsmasq services are not in use" "L1" "dnsmasq" "dnsmasq.service"
    check_service_not_in_use "2.1.6" "Ensure ftp server services are not in use" "L1" "vsftpd" "vsftpd.service"
    check_service_not_in_use "2.1.7" "Ensure ldap server services are not in use" "L1" "slapd" "slapd.service"
    check_service_not_in_use "2.1.8" "Ensure message access server services are not in use" "L1" "dovecot-imapd dovecot-pop3d" "dovecot.socket dovecot.service"
    check_service_not_in_use "2.1.9" "Ensure network file system services are not in use" "L1" "nfs-kernel-server" "nfs-server.service"
    check_service_not_in_use "2.1.10" "Ensure nis server services are not in use" "L1" "ypserv" "ypserv.service"
    check_service_not_in_use "2.1.11" "Ensure print server services are not in use" "L1" "cups" "cups.socket cups.service"
    check_service_not_in_use "2.1.12" "Ensure rpcbind services are not in use" "L1" "rpcbind" "rpcbind.socket rpcbind.service"
    check_service_not_in_use "2.1.13" "Ensure rsync services are not in use" "L1" "rsync" "rsync.service"
    check_service_not_in_use "2.1.14" "Ensure samba file server services are not in use" "L1" "samba" "smbd.service"
    check_service_not_in_use "2.1.15" "Ensure snmp services are not in use" "L1" "snmpd" "snmpd.service"
    check_service_not_in_use "2.1.16" "Ensure telnet server services are not in use" "L1" "telnetd telnetd-ssl" "inetutils-inetd.service"
    check_service_not_in_use "2.1.17" "Ensure tftp server services are not in use" "L1" "tftpd-hpa" "tftpd-hpa.service"
    check_service_not_in_use "2.1.18" "Ensure web proxy server services are not in use" "L1" "squid" "squid.service"
    check_service_not_in_use "2.1.19" "Ensure web server services are not in use" "L1" "apache2 nginx" "apache2.socket apache2.service nginx.service"
    check_service_not_in_use "2.1.20" "Ensure xinetd services are not in use" "L1" "xinetd" "xinetd.service"

    # 2.1.21 Ensure X window server services are not in use (Automated)
    if should_run_check "2.1.21" "L2"; then
        if ! dpkg-query -s xserver-common &>/dev/null; then
            report_ok "2.1.21" "Ensure X window server services are not in use" "L2" "Automated"
        else
            report_fail "2.1.21" "Ensure X window server services are not in use" "L2" "Automated" \
                "Package 'xserver-common' is installed" \
                "Run: apt purge -y xserver-common"
        fi
    fi

    # 2.1.22 Ensure mail transfer agents are configured for local-only mode (Automated)
    if should_run_check "2.1.22" "L1"; then
        local mta_issues=()
        local port
        for port in 25 465 587; do
            if ss -plntu 2>/dev/null | grep -P -- ":${port}\h" | grep -Pvq -- "\h+(127\.0\.0\.1|\[?::1\]?):${port}\b"; then
                mta_issues+=("Port ${port} is listening on a non-loopback network interface")
            fi
        done
        local l_interfaces=""
        if command -v postconf &>/dev/null; then
            l_interfaces="$(postconf -n inet_interfaces 2>/dev/null || true)"
        elif command -v exim &>/dev/null; then
            l_interfaces="$(exim -bP local_interfaces 2>/dev/null || true)"
        elif command -v sendmail &>/dev/null && [[ -f /etc/mail/sendmail.cf ]]; then
            l_interfaces="$(grep -i 'O DaemonPortOptions=' /etc/mail/sendmail.cf 2>/dev/null | grep -oP '(?<=Addr=)[^,+]+' | grep -v '^127\.0\.0\.1$' || true)"
        fi
        if [[ -n "$l_interfaces" ]]; then
            if grep -Pqi '\ball\b' <<< "$l_interfaces" || ! grep -Pqi '(inet_interfaces\h*=\h*)?(127\.0\.0\.1|0\.0\.0\.0|::1|loopback-only)' <<< "$l_interfaces"; then
                mta_issues+=("MTA is bound to non-loopback interface (${l_interfaces})")
            fi
        fi
        if [[ "${#mta_issues[@]}" -eq 0 ]]; then
            report_ok "2.1.22" "Ensure mail transfer agents are configured for local-only mode" "L1" "Automated"
        else
            report_fail "2.1.22" "Ensure mail transfer agents are configured for local-only mode" "L1" "Automated" \
                "$(IFS='; '; echo "${mta_issues[*]}")" \
                "Edit /etc/postfix/main.cf to set 'inet_interfaces = loopback-only' and run: systemctl restart postfix"
        fi
    fi

    # 2.1.23 Ensure only approved services are listening on a network interface (Manual)
    if should_run_check "2.1.23" "L1"; then
        local listening_ports
        listening_ports="$(ss -plntu 2>/dev/null | awk 'NR>1 {print $1, $5, $7}' | tr '\n' '; ' || true)"
        report_manual "2.1.23" "Ensure only approved services are listening on a network interface" "L1" "Manual" \
            "Active listening sockets: ${listening_ports:-none}" \
            "Review 'ss -plntu' output and stop/mask or purge any unapproved listening services ('systemctl stop <svc> && apt purge <pkg>')."
    fi

    # --------------------------------------------------------------------------
    # 2.2 Configure Client Services
    # --------------------------------------------------------------------------
    print_subsection_header "2.2 Configure Client Services"

    # 2.2.1 Ensure nis client is not installed (Automated)
    if should_run_check "2.2.1" "L1"; then
        if ! dpkg-query -s nis &>/dev/null; then
            report_ok "2.2.1" "Ensure nis client is not installed" "L1" "Automated"
        else
            report_fail "2.2.1" "Ensure nis client is not installed" "L1" "Automated" "Package 'nis' is installed" "Run: apt purge -y nis"
        fi
    fi

    # 2.2.2 Ensure rsh client is not installed (Automated)
    if should_run_check "2.2.2" "L1"; then
        if ! dpkg-query -s rsh-client &>/dev/null; then
            report_ok "2.2.2" "Ensure rsh client is not installed" "L1" "Automated"
        else
            report_fail "2.2.2" "Ensure rsh client is not installed" "L1" "Automated" "Package 'rsh-client' is installed" "Run: apt purge -y rsh-client"
        fi
    fi

    # 2.2.3 Ensure talk client is not installed (Automated)
    if should_run_check "2.2.3" "L1"; then
        if ! dpkg-query -s talk &>/dev/null; then
            report_ok "2.2.3" "Ensure talk client is not installed" "L1" "Automated"
        else
            report_fail "2.2.3" "Ensure talk client is not installed" "L1" "Automated" "Package 'talk' is installed" "Run: apt purge -y talk"
        fi
    fi

    # 2.2.4 Ensure telnet client is not installed (Automated)
    if should_run_check "2.2.4" "L1"; then
        local tel_pkgs=() p
        for p in telnet inetutils-telnet telnet-ssl; do
            dpkg-query -s "$p" 2>/dev/null | grep -q '^Status: install ok installed' && tel_pkgs+=("$p")
        done
        if [[ "${#tel_pkgs[@]}" -eq 0 ]]; then
            report_ok "2.2.4" "Ensure telnet client is not installed" "L1" "Automated"
        else
            report_fail "2.2.4" "Ensure telnet client is not installed" "L1" "Automated" \
                "Installed telnet client package(s): ${tel_pkgs[*]}" \
                "Run: apt purge -y telnet inetutils-telnet telnet-ssl"
        fi
    fi

    # 2.2.5 Ensure ldap client is not installed (Automated)
    if should_run_check "2.2.5" "L1"; then
        if ! dpkg-query -s ldap-utils &>/dev/null; then
            report_ok "2.2.5" "Ensure ldap client is not installed" "L1" "Automated"
        else
            report_fail "2.2.5" "Ensure ldap client is not installed" "L1" "Automated" "Package 'ldap-utils' is installed" "Run: apt purge -y ldap-utils"
        fi
    fi

    # 2.2.6 Ensure ftp client is not installed (Automated)
    if should_run_check "2.2.6" "L1"; then
        local ftp_pkgs=() p
        for p in ftp tnftp atftp inetutils-ftp ftp-ssl; do
            dpkg-query -s "$p" 2>/dev/null | grep -q '^Status: install ok installed' && ftp_pkgs+=("$p")
        done
        if [[ "${#ftp_pkgs[@]}" -eq 0 ]]; then
            report_ok "2.2.6" "Ensure ftp client is not installed" "L1" "Automated"
        else
            report_fail "2.2.6" "Ensure ftp client is not installed" "L1" "Automated" \
                "Installed FTP client package(s): ${ftp_pkgs[*]}" \
                "Run: apt purge -y ftp tnftp atftp inetutils-ftp ftp-ssl"
        fi
    fi

    # --------------------------------------------------------------------------
    # 2.3 Configure Time Synchronization
    # --------------------------------------------------------------------------
    print_subsection_header "2.3 Configure Time Synchronization"

    local tsd_in_use=0 chrony_in_use=0
    if systemctl is-enabled systemd-timesyncd.service 2>/dev/null | grep -q 'enabled' || systemctl is-active systemd-timesyncd.service 2>/dev/null | grep -q '^active'; then
        tsd_in_use=1
    fi
    if systemctl is-enabled chrony.service 2>/dev/null | grep -q 'enabled' || systemctl is-active chrony.service 2>/dev/null | grep -q '^active'; then
        chrony_in_use=1
    fi

    # 2.3.1.1 Ensure a single time synchronization daemon is in use (Automated)
    if should_run_check "2.3.1.1" "L1"; then
        if [[ "$tsd_in_use" -eq 1 && "$chrony_in_use" -eq 0 ]]; then
            report_ok "2.3.1.1" "Ensure a single time synchronization daemon is in use" "L1" "Automated" "systemd-timesyncd in use"
        elif [[ "$tsd_in_use" -eq 0 && "$chrony_in_use" -eq 1 ]]; then
            report_ok "2.3.1.1" "Ensure a single time synchronization daemon is in use" "L1" "Automated" "chrony in use"
        elif [[ "$tsd_in_use" -eq 1 && "$chrony_in_use" -eq 1 ]]; then
            report_fail "2.3.1.1" "Ensure a single time synchronization daemon is in use" "L1" "Automated" \
                "Both systemd-timesyncd and chrony are active/enabled" \
                "Select one time sync daemon: either stop/mask systemd-timesyncd.service or purge chrony."
        else
            report_fail "2.3.1.1" "Ensure a single time synchronization daemon is in use" "L1" "Automated" \
                "Neither systemd-timesyncd nor chrony is enabled and active" \
                "Install and enable chrony ('apt install -y chrony && systemctl --now enable chrony.service') or enable systemd-timesyncd.service."
        fi
    fi

    # 2.3.2.1 Ensure systemd-timesyncd configured with authorized timeserver (Automated)
    if should_run_check "2.3.2.1" "L1"; then
        if [[ "$chrony_in_use" -eq 1 && "$tsd_in_use" -eq 0 ]]; then
            report_ok "2.3.2.1" "Ensure systemd-timesyncd configured with authorized timeserver" "L1" "Automated" "Skipped: chrony is used instead of systemd-timesyncd"
        else
            local ntp_cfg
            ntp_cfg="$(grep -PRsi -- '^\h*(NTP|FallbackNTP)\h*=\h*[^#\n\r]+' /etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf.d/ 2>/dev/null || true)"
            if [[ -n "$ntp_cfg" ]]; then
                report_ok "2.3.2.1" "Ensure systemd-timesyncd configured with authorized timeserver" "L1" "Automated"
            else
                report_fail "2.3.2.1" "Ensure systemd-timesyncd configured with authorized timeserver" "L1" "Automated" \
                    "NTP and/or FallbackNTP is not configured in /etc/systemd/timesyncd.conf or /etc/systemd/timesyncd.conf.d/*.conf" \
                    "Create /etc/systemd/timesyncd.conf.d/60-timesyncd.conf with '[Time]', 'NTP=time.nist.gov', and 'FallbackNTP=time-a-g.nist.gov time-b-g.nist.gov', then run: systemctl reload-or-restart systemd-timesyncd"
            fi
        fi
    fi

    # 2.3.2.2 Ensure systemd-timesyncd is enabled and running (Automated)
    if should_run_check "2.3.2.2" "L1"; then
        if [[ "$chrony_in_use" -eq 1 && "$tsd_in_use" -eq 0 ]]; then
            report_ok "2.3.2.2" "Ensure systemd-timesyncd is enabled and running" "L1" "Automated" "Skipped: chrony is used"
        else
            local t_en t_act
            t_en="$(systemctl is-enabled systemd-timesyncd.service 2>/dev/null || true)"
            t_act="$(systemctl is-active systemd-timesyncd.service 2>/dev/null || true)"
            if [[ "$t_en" == "enabled" && "$t_act" == "active" ]]; then
                report_ok "2.3.2.2" "Ensure systemd-timesyncd is enabled and running" "L1" "Automated"
            else
                report_fail "2.3.2.2" "Ensure systemd-timesyncd is enabled and running" "L1" "Automated" \
                    "systemd-timesyncd.service is enabled=${t_en:-no}, active=${t_act:-no}" \
                    "Run: systemctl unmask systemd-timesyncd.service && systemctl --now enable systemd-timesyncd.service"
            fi
        fi
    fi

    # 2.3.3.1 Ensure chrony is configured (Automated)
    if should_run_check "2.3.3.1" "L1"; then
        if [[ "$tsd_in_use" -eq 1 && "$chrony_in_use" -eq 0 ]]; then
            report_ok "2.3.3.1" "Ensure chrony is configured" "L1" "Automated" "Skipped: systemd-timesyncd is used"
        else
            local chr_srv
            chr_srv="$(grep -PRsi -- '^\h*(server|pool)\h+\S+' /etc/chrony/chrony.conf /etc/chrony/sources.d/ /etc/chrony/conf.d/ 2>/dev/null || true)"
            if [[ -n "$chr_srv" ]]; then
                report_ok "2.3.3.1" "Ensure chrony is configured" "L1" "Automated"
            else
                report_fail "2.3.3.1" "Ensure chrony is configured" "L1" "Automated" \
                    "No 'server' or 'pool' directive found in /etc/chrony/chrony.conf or /etc/chrony/sources.d/" \
                    "Add 'pool time.nist.gov iburst maxsources 4' to /etc/chrony/sources.d/60-sources.sources and run: systemctl reload-or-restart chronyd"
            fi
        fi
    fi

    # 2.3.3.2 Ensure chrony is running as user _chrony (Automated)
    if should_run_check "2.3.3.2" "L1"; then
        if [[ "$tsd_in_use" -eq 1 && "$chrony_in_use" -eq 0 ]]; then
            report_ok "2.3.3.2" "Ensure chrony is running as user _chrony" "L1" "Automated" "Skipped: systemd-timesyncd is used"
        else
            local bad_chr_usr
            bad_chr_usr="$(ps -ef 2>/dev/null | awk '(/[c]hronyd/ && $1!="_chrony") { print $1 }' || true)"
            if [[ -z "$bad_chr_usr" && "$chrony_in_use" -eq 1 ]]; then
                report_ok "2.3.3.2" "Ensure chrony is running as user _chrony" "L1" "Automated"
            else
                report_fail "2.3.3.2" "Ensure chrony is running as user _chrony" "L1" "Automated" \
                    "chronyd is not running or running as unauthorized user '${bad_chr_usr}'" \
                    "Add 'user _chrony' to /etc/chrony/chrony.conf and restart chrony.service."
            fi
        fi
    fi

    # 2.3.3.3 Ensure chrony is enabled and running (Automated)
    if should_run_check "2.3.3.3" "L1"; then
        if [[ "$tsd_in_use" -eq 1 && "$chrony_in_use" -eq 0 ]]; then
            report_ok "2.3.3.3" "Ensure chrony is enabled and running" "L1" "Automated" "Skipped: systemd-timesyncd is used"
        else
            local c_en c_act
            c_en="$(systemctl is-enabled chrony.service 2>/dev/null || true)"
            c_act="$(systemctl is-active chrony.service 2>/dev/null || true)"
            if [[ "$c_en" == "enabled" && "$c_act" == "active" ]]; then
                report_ok "2.3.3.3" "Ensure chrony is enabled and running" "L1" "Automated"
            else
                report_fail "2.3.3.3" "Ensure chrony is enabled and running" "L1" "Automated" \
                    "chrony.service is enabled=${c_en:-no}, active=${c_act:-no}" \
                    "Run: systemctl unmask chrony.service && systemctl --now enable chrony.service"
            fi
        fi
    fi

    # --------------------------------------------------------------------------
    # 2.4 Job Schedulers
    # --------------------------------------------------------------------------
    print_subsection_header "2.4 Job Schedulers"

    # 2.4.1.1 Ensure cron daemon is enabled and active (Automated)
    if should_run_check "2.4.1.1" "L1"; then
        if ! dpkg-query -s cron &>/dev/null && ! dpkg-query -s cronie &>/dev/null; then
            report_ok "2.4.1.1" "Ensure cron daemon is enabled and active" "L1" "Automated" "cron is not installed"
        else
            local cr_en cr_act
            cr_en="$(systemctl list-unit-files 2>/dev/null | awk '$1~/^crond?\.service/{print $2}' || true)"
            cr_act="$(systemctl list-units 2>/dev/null | awk '$1~/^crond?\.service/{print $3}' || true)"
            if [[ "$cr_en" == "enabled" && "$cr_act" == "active" ]]; then
                report_ok "2.4.1.1" "Ensure cron daemon is enabled and active" "L1" "Automated"
            else
                report_fail "2.4.1.1" "Ensure cron daemon is enabled and active" "L1" "Automated" \
                    "cron service is enabled=${cr_en:-no}, active=${cr_act:-no}" \
                    "Run: systemctl unmask cron.service && systemctl --now enable cron.service"
            fi
        fi
    fi

    check_file_perms "2.4.1.2" "Ensure access to /etc/crontab is configured" "L1" \
        "/etc/crontab" "0177" "0600" "root" "root" "1" \
        "chmod og-rwx /etc/crontab" "chown root:root /etc/crontab"

    check_file_perms "2.4.1.3" "Ensure access to /etc/cron.hourly is configured" "L1" \
        "/etc/cron.hourly" "0077" "0700" "root" "root" "1" \
        "chmod og-rwx /etc/cron.hourly" "chown root:root /etc/cron.hourly"

    check_file_perms "2.4.1.4" "Ensure access to /etc/cron.daily is configured" "L1" \
        "/etc/cron.daily" "0077" "0700" "root" "root" "1" \
        "chmod og-rwx /etc/cron.daily" "chown root:root /etc/cron.daily"

    check_file_perms "2.4.1.5" "Ensure access to /etc/cron.weekly is configured" "L1" \
        "/etc/cron.weekly" "0077" "0700" "root" "root" "1" \
        "chmod og-rwx /etc/cron.weekly" "chown root:root /etc/cron.weekly"

    check_file_perms "2.4.1.6" "Ensure access to /etc/cron.monthly is configured" "L1" \
        "/etc/cron.monthly" "0077" "0700" "root" "root" "1" \
        "chmod og-rwx /etc/cron.monthly" "chown root:root /etc/cron.monthly"

    check_file_perms "2.4.1.7" "Ensure access to /etc/cron.yearly is configured" "L1" \
        "/etc/cron.yearly" "0077" "0700" "root" "root" "1" \
        "chmod og-rwx /etc/cron.yearly" "chown root:root /etc/cron.yearly"

    check_file_perms "2.4.1.8" "Ensure access to /etc/cron.d is configured" "L1" \
        "/etc/cron.d" "0077" "0700" "root" "root" "1" \
        "chmod og-rwx /etc/cron.d" "chown root:root /etc/cron.d"

    # 2.4.1.9 Ensure access to crontab is configured (Automated)
    if should_run_check "2.4.1.9" "L1"; then
        if ! dpkg-query -s cron &>/dev/null && ! dpkg-query -s cronie &>/dev/null; then
            report_ok "2.4.1.9" "Ensure access to crontab is configured" "L1" "Automated" "cron not installed"
        else
            local ca_issues=()
            if [[ ! -e /etc/cron.allow ]]; then
                ca_issues+=("/etc/cron.allow does not exist")
            else
                local m u g
                read -r m u g <<< "$(stat -Lc '%#a %U %G' /etc/cron.allow 2>/dev/null)"
                [[ $(( m & 0137 )) -gt 0 ]] && ca_issues+=("/etc/cron.allow mode is ${m} (should be 0640 or more restrictive)")
                [[ "$u" != "root" ]] && ca_issues+=("/etc/cron.allow owner is ${u} (should be root)")
                [[ "$g" != "root" && "$g" != "crontab" ]] && ca_issues+=("/etc/cron.allow group is ${g} (should be root or crontab)")
            fi
            if [[ -e /etc/cron.deny ]]; then
                local m u g
                read -r m u g <<< "$(stat -Lc '%#a %U %G' /etc/cron.deny 2>/dev/null)"
                [[ $(( m & 0137 )) -gt 0 ]] && ca_issues+=("/etc/cron.deny mode is ${m} (should be 0640 or more restrictive)")
                [[ "$u" != "root" ]] && ca_issues+=("/etc/cron.deny owner is ${u} (should be root)")
                [[ "$g" != "root" && "$g" != "crontab" ]] && ca_issues+=("/etc/cron.deny group is ${g} (should be root or crontab)")
            fi
            if [[ "${#ca_issues[@]}" -eq 0 ]]; then
                report_ok "2.4.1.9" "Ensure access to crontab is configured" "L1" "Automated"
            else
                report_fail "2.4.1.9" "Ensure access to crontab is configured" "L1" "Automated" \
                    "$(IFS='; '; echo "${ca_issues[*]}")" \
                    "Run: touch /etc/cron.allow && chown root:crontab /etc/cron.allow && chmod u-x,g-wx,o-rwx /etc/cron.allow (and if /etc/cron.deny exists, set chown root:crontab and chmod 0640)."
            fi
        fi
    fi

    # 2.4.2.1 Ensure access to at is configured (Automated)
    if should_run_check "2.4.2.1" "L1"; then
        if ! dpkg-query -s at &>/dev/null; then
            report_ok "2.4.2.1" "Ensure access to at is configured" "L1" "Automated" "at is not installed"
        else
            local at_issues=()
            if [[ ! -e /etc/at.allow ]]; then
                at_issues+=("/etc/at.allow does not exist")
            else
                local m u g
                read -r m u g <<< "$(stat -Lc '%#a %U %G' /etc/at.allow 2>/dev/null)"
                [[ $(( m & 0137 )) -gt 0 ]] && at_issues+=("/etc/at.allow mode is ${m} (should be 0640 or more restrictive)")
                [[ "$u" != "root" ]] && at_issues+=("/etc/at.allow owner is ${u} (should be root)")
                [[ "$g" != "root" && "$g" != "daemon" ]] && at_issues+=("/etc/at.allow group is ${g} (should be root or daemon)")
            fi
            if [[ -e /etc/at.deny ]]; then
                local m u g
                read -r m u g <<< "$(stat -Lc '%#a %U %G' /etc/at.deny 2>/dev/null)"
                [[ $(( m & 0137 )) -gt 0 ]] && at_issues+=("/etc/at.deny mode is ${m} (should be 0640 or more restrictive)")
                [[ "$u" != "root" ]] && at_issues+=("/etc/at.deny owner is ${u} (should be root)")
                [[ "$g" != "root" && "$g" != "daemon" ]] && at_issues+=("/etc/at.deny group is ${g} (should be root or daemon)")
            fi
            if [[ "${#at_issues[@]}" -eq 0 ]]; then
                report_ok "2.4.2.1" "Ensure access to at is configured" "L1" "Automated"
            else
                report_fail "2.4.2.1" "Ensure access to at is configured" "L1" "Automated" \
                    "$(IFS='; '; echo "${at_issues[*]}")" \
                    "Run: touch /etc/at.allow && chown root:daemon /etc/at.allow && chmod u-x,g-wx,o-rwx /etc/at.allow (and if /etc/at.deny exists, set chown root:daemon and chmod 0640)."
            fi
        fi
    fi
}

# ==============================================================================
# SECTION 3: NETWORK
# ==============================================================================
run_section_3() {
    print_section_header "3" "Network" || return 0

    # --------------------------------------------------------------------------
    # 3.1 Configure Network Devices
    # --------------------------------------------------------------------------
    print_subsection_header "3.1 Configure Network Devices"

    # 3.1.1 Ensure IPv6 status is identified (Manual)
    if should_run_check "3.1.1" "L1"; then
        local ipv6_state="disabled"
        [[ "$IPV6_ENABLED" -eq 1 ]] && ipv6_state="enabled"
        report_manual "3.1.1" "Ensure IPv6 status is identified" "L1" "Manual" \
            "IPv6 is currently ${ipv6_state} on this system." \
            "Verify that IPv6 state (${ipv6_state}) aligns with site policy. Enable or disable IPv6 via sysctl net.ipv6.conf.all.disable_ipv6 and net.ipv6.conf.default.disable_ipv6 as required."
    fi

    # 3.1.2 Ensure wireless interfaces are not available (Automated)
    if should_run_check "3.1.2" "L1"; then
        local wl_dirs
        wl_dirs="$(find /sys/class/net/*/ -type d -name wireless 2>/dev/null || true)"
        if [[ -z "$wl_dirs" ]]; then
            report_ok "3.1.2" "Ensure wireless interfaces are not available" "L1" "Automated" "No wireless NICs present"
        else
            local wl_bad=() d mname
            for d in $wl_dirs; do
                mname="$(basename "$(readlink -f "$(dirname "$d")/device/driver/module" 2>/dev/null)" 2>/dev/null || true)"
                [[ -z "$mname" ]] && continue
                if grep -Pq "\b${mname}\b" <<< "$LSMOD_CACHE" || ! grep -Pq "^\h*blacklist\h+${mname}\b" <<< "$SHOWCONFIG_CACHE" || ! grep -Pq "^\h*install\h+${mname}\h+/bin/(false|true)\b" <<< "$SHOWCONFIG_CACHE"; then
                    wl_bad+=("$mname")
                fi
            done
            if [[ "${#wl_bad[@]}" -eq 0 ]]; then
                report_ok "3.1.2" "Ensure wireless interfaces are not available" "L1" "Automated"
            else
                report_fail "3.1.2" "Ensure wireless interfaces are not available" "L1" "Automated" \
                    "Active/loadable wireless kernel module(s): ${wl_bad[*]}" \
                    "Run: find /lib/modules/\$(uname -r)/kernel/drivers/net/wireless -name '*.ko*' -printf 'install %f /bin/false\nblacklist %f\n\n' | sed -E 's/\.ko(\.[xg]z|\.zst)?//g' >> /etc/modprobe.d/blacklist-wireless.conf && modprobe -r ${wl_bad[*]}"
            fi
        fi
    fi

    # 3.1.3 Ensure bluetooth services are not in use (Automated)
    check_service_not_in_use "3.1.3" "Ensure bluetooth services are not in use" "L1" "bluez" "bluetooth.service"

    # --------------------------------------------------------------------------
    # 3.2 Configure Network Kernel Modules
    # --------------------------------------------------------------------------
    print_subsection_header "3.2 Configure Network Kernel Modules"

    check_kernel_module "3.2.1" "Ensure atm kernel module is not available" "L1" "atm" "net"
    check_kernel_module "3.2.2" "Ensure can kernel module is not available" "L1" "can" "net"
    check_kernel_module "3.2.3" "Ensure dccp kernel module is not available" "L1" "dccp" "net"
    check_kernel_module "3.2.4" "Ensure rds kernel module is not available" "L1" "rds" "net"
    check_kernel_module "3.2.5" "Ensure sctp kernel module is not available" "L1" "sctp" "net"
    check_kernel_module "3.2.6" "Ensure tipc kernel module is not available" "L1" "tipc" "net"

    # 3.2.7 Ensure unneeded network protocol kernel modules are not available (Manual)
    if should_run_check "3.2.7" "L1"; then
        local net_mods_check=("esp4" "esp6" "rxrpc" "appletalk" "decnet" "ipx" "x25" "rose" "ax25" "netrom" "econet" "llc" "llc2")
        local loadable_net=() nm
        for nm in "${net_mods_check[@]}"; do
            if ! grep -Pq "^\h*blacklist\h+${nm}\b" <<< "$SHOWCONFIG_CACHE" || ! grep -Pq "^\h*install\h+${nm}\h+/bin/(false|true)\b" <<< "$SHOWCONFIG_CACHE"; then
                loadable_net+=("$nm")
            fi
        done
        report_manual "3.2.7" "Ensure unneeded network protocol kernel modules are not available" "L1" "Manual" \
            "Uncommon network protocol modules not explicitly denylisted: [${loadable_net[*]}]" \
            "Inventory required network protocols and denylist unneeded modules (e.g. esp4, esp6, rxrpc) in /etc/modprobe.d/60-cis-network-disabled.conf with 'install <mod> /bin/false' and 'blacklist <mod>', then run 'update-initramfs -u'."
    fi

    # --------------------------------------------------------------------------
    # 3.3 Configure Network Kernel Parameters
    # --------------------------------------------------------------------------
    print_subsection_header "3.3.1 Configure IPv4 Parameters"

    check_sysctl_param "3.3.1.1" "Ensure net.ipv4.ip_forward is configured" "L1" "net.ipv4.ip_forward" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.2" "Ensure net.ipv4.conf.all.forwarding is configured" "L1" "net.ipv4.conf.all.forwarding" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.3" "Ensure net.ipv4.conf.default.forwarding is configured" "L1" "net.ipv4.conf.default.forwarding" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.4" "Ensure net.ipv4.conf.all.send_redirects is configured" "L1" "net.ipv4.conf.all.send_redirects" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.5" "Ensure net.ipv4.conf.default.send_redirects is configured" "L1" "net.ipv4.conf.default.send_redirects" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.6" "Ensure net.ipv4.icmp_ignore_bogus_error_responses is configured" "L1" "net.ipv4.icmp_ignore_bogus_error_responses" "1" "1" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.7" "Ensure net.ipv4.icmp_echo_ignore_broadcasts is configured" "L1" "net.ipv4.icmp_echo_ignore_broadcasts" "1" "1" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.8" "Ensure net.ipv4.conf.all.accept_redirects is configured" "L1" "net.ipv4.conf.all.accept_redirects" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.9" "Ensure net.ipv4.conf.default.accept_redirects is configured" "L1" "net.ipv4.conf.default.accept_redirects" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.10" "Ensure net.ipv4.conf.all.secure_redirects is configured" "L1" "net.ipv4.conf.all.secure_redirects" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.11" "Ensure net.ipv4.conf.default.secure_redirects is configured" "L1" "net.ipv4.conf.default.secure_redirects" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.12" "Ensure net.ipv4.conf.all.rp_filter is configured" "L1" "net.ipv4.conf.all.rp_filter" "1" "1" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.13" "Ensure net.ipv4.conf.default.rp_filter is configured" "L1" "net.ipv4.conf.default.rp_filter" "1" "1" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.14" "Ensure net.ipv4.conf.all.accept_source_route is configured" "L1" "net.ipv4.conf.all.accept_source_route" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.15" "Ensure net.ipv4.conf.default.accept_source_route is configured" "L1" "net.ipv4.conf.default.accept_source_route" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.16" "Ensure net.ipv4.conf.all.log_martians is configured" "L1" "net.ipv4.conf.all.log_martians" "1" "1" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.17" "Ensure net.ipv4.conf.default.log_martians is configured" "L1" "net.ipv4.conf.default.log_martians" "1" "1" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.18" "Ensure net.ipv4.tcp_syncookies is configured" "L1" "net.ipv4.tcp_syncookies" "1" "1" "/etc/sysctl.d/60-ipv4_sysctl.conf"
    check_sysctl_param "3.3.1.19" "Ensure net.ipv4.conf.all.route_localnet is configured" "L1" "net.ipv4.conf.all.route_localnet" "0" "0" "/etc/sysctl.d/60-ipv4_sysctl.conf"

    print_subsection_header "3.3.2 Configure IPv6 Parameters"

    local ipv6_params=(
        "3.3.2.1|Ensure net.ipv6.conf.all.forwarding is configured|net.ipv6.conf.all.forwarding"
        "3.3.2.2|Ensure net.ipv6.conf.default.forwarding is configured|net.ipv6.conf.default.forwarding"
        "3.3.2.3|Ensure net.ipv6.conf.all.accept_redirects is configured|net.ipv6.conf.all.accept_redirects"
        "3.3.2.4|Ensure net.ipv6.conf.default.accept_redirects is configured|net.ipv6.conf.default.accept_redirects"
        "3.3.2.5|Ensure net.ipv6.conf.all.accept_source_route is configured|net.ipv6.conf.all.accept_source_route"
        "3.3.2.6|Ensure net.ipv6.conf.default.accept_source_route is configured|net.ipv6.conf.default.accept_source_route"
        "3.3.2.7|Ensure net.ipv6.conf.all.accept_ra is configured|net.ipv6.conf.all.accept_ra"
        "3.3.2.8|Ensure net.ipv6.conf.default.accept_ra is configured|net.ipv6.conf.default.accept_ra"
    )
    local item cid ctitle cparam
    for item in "${ipv6_params[@]}"; do
        IFS='|' read -r cid ctitle cparam <<< "$item"
        if [[ "$IPV6_ENABLED" -eq 0 ]]; then
            should_run_check "$cid" "L1" && report_ok "$cid" "$ctitle" "L1" "Automated" "IPv6 is disabled on the system"
        else
            check_sysctl_param "$cid" "$ctitle" "L1" "$cparam" "0" "0" "/etc/sysctl.d/60-ipv6_sysctl.conf"
        fi
    done
}
# ==============================================================================
# SECTION 4: HOST BASED FIREWALL
# ==============================================================================
run_section_4() {
    print_section_header "4" "Host Based Firewall" || return 0

    print_subsection_header "4.1 Configure Uncomplicated Firewall"

    # 4.1.1 Ensure ufw is installed (Automated)
    if should_run_check "4.1.1" "L1"; then
        if dpkg-query -s ufw &>/dev/null; then
            report_ok "4.1.1" "Ensure ufw is installed" "L1" "Automated"
        else
            report_fail "4.1.1" "Ensure ufw is installed" "L1" "Automated" \
                "Package 'ufw' is not installed" \
                "Run: apt install -y ufw"
        fi
    fi

    # 4.1.2 Ensure ufw service is configured (Automated)
    if should_run_check "4.1.2" "L1"; then
        local ufw_en ufw_act ufw_st
        ufw_en="$(systemctl is-enabled ufw.service 2>/dev/null || true)"
        ufw_act="$(systemctl is-active ufw.service 2>/dev/null || true)"
        ufw_st="$(ufw status 2>/dev/null | awk '/^Status:/{print $2}' || true)"
        if [[ "$ufw_en" == "enabled" && "$ufw_act" == "active" && "$ufw_st" == "active" ]]; then
            report_ok "4.1.2" "Ensure ufw service is configured" "L1" "Automated"
        else
            report_fail "4.1.2" "Ensure ufw service is configured" "L1" "Automated" \
                "ufw.service enabled=${ufw_en:-no}, active=${ufw_act:-no}, ufw status=${ufw_st:-inactive}" \
                "Ensure SSH port is allowed ('ufw allow proto tcp from any to any port 22'), then run: systemctl unmask ufw.service && systemctl --now enable ufw.service && ufw --force enable"
        fi
    fi

    # 4.1.3 Ensure ufw incoming default is configured (Automated)
    if should_run_check "4.1.3" "L1"; then
        local ufw_in_def=""
        ufw_in_def="$(ufw status verbose 2>/dev/null | awk -F',' '$1~/^Default:/ {print $1}' | grep -Po '(deny|reject)\h+\(incoming\)' || true)"
        [[ -z "$ufw_in_def" && -f /etc/default/ufw ]] && ufw_in_def="$(grep -Pi '^\h*DEFAULT_INPUT_POLICY\h*=\h*"(DROP|REJECT)"' /etc/default/ufw 2>/dev/null || true)"
        if [[ -n "$ufw_in_def" ]]; then
            report_ok "4.1.3" "Ensure ufw incoming default is configured" "L1" "Automated"
        else
            report_fail "4.1.3" "Ensure ufw incoming default is configured" "L1" "Automated" \
                "UFW default incoming policy is not set to deny or reject" \
                "Run: ufw default deny incoming"
        fi
    fi

    # 4.1.4 Ensure ufw outgoing default is configured (Automated)
    if should_run_check "4.1.4" "L2"; then
        local ufw_out_def=""
        ufw_out_def="$(ufw status verbose 2>/dev/null | awk -F',' '$1~/^Default:/ {print $2}' | grep -Po '(deny|reject)\h+\(outgoing\)' || true)"
        [[ -z "$ufw_out_def" && -f /etc/default/ufw ]] && ufw_out_def="$(grep -Pi '^\h*DEFAULT_OUTPUT_POLICY\h*=\h*"(DROP|REJECT)"' /etc/default/ufw 2>/dev/null || true)"
        if [[ -n "$ufw_out_def" ]]; then
            report_ok "4.1.4" "Ensure ufw outgoing default is configured" "L2" "Automated"
        else
            report_fail "4.1.4" "Ensure ufw outgoing default is configured" "L2" "Automated" \
                "UFW default outgoing policy is not set to deny or reject" \
                "Allow required outbound ports (e.g. DNS, NTP, HTTP/HTTPS) and run: ufw default deny outgoing"
        fi
    fi

    # 4.1.5 Ensure ufw routed default is configured (Automated)
    if should_run_check "4.1.5" "L1"; then
        local ufw_rt_def=""
        ufw_rt_def="$(ufw status verbose 2>/dev/null | awk '/^Default:/{print}' | grep -Po '(deny|disabled)\h+\(routed\)' || true)"
        [[ -z "$ufw_rt_def" && -f /etc/default/ufw ]] && ufw_rt_def="$(grep -Pi '^\h*DEFAULT_FORWARD_POLICY\h*=\h*"(DROP|REJECT)"' /etc/default/ufw 2>/dev/null || true)"
        if [[ -n "$ufw_rt_def" ]]; then
            report_ok "4.1.5" "Ensure ufw routed default is configured" "L1" "Automated"
        else
            report_fail "4.1.5" "Ensure ufw routed default is configured" "L1" "Automated" \
                "UFW default routed policy is not set to deny/disabled" \
                "Run: ufw default deny routed"
        fi
    fi
}

# ==============================================================================
# SECTION 5: ACCESS CONTROL
# ==============================================================================
run_section_5() {
    print_section_header "5" "Access Control" || return 0

    # --------------------------------------------------------------------------
    # 5.1 Configure SSH Server
    # --------------------------------------------------------------------------
    print_subsection_header "5.1 Configure SSH Server"

    local sshd_installed=0
    [[ -n "$SSHD_BIN" || -f /etc/ssh/sshd_config ]] && sshd_installed=1

    # 5.1.1 Ensure access to /etc/ssh/sshd_config is configured (Automated)
    if should_run_check "5.1.1" "L1"; then
        if [[ "$sshd_installed" -eq 0 ]]; then
            report_ok "5.1.1" "Ensure access to /etc/ssh/sshd_config is configured" "L1" "Automated" "SSH server not installed"
        else
            local sshd_cfg_bad=()
            if [[ -f /etc/ssh/sshd_config ]]; then
                local m u g
                read -r m u g <<< "$(stat -Lc '%#a %U %G' /etc/ssh/sshd_config 2>/dev/null)"
                if [[ $(( m & 0177 )) -gt 0 || "$u" != "root" || "$g" != "root" ]]; then
                    sshd_cfg_bad+=("/etc/ssh/sshd_config (${m} ${u}:${g})")
                fi
            fi
            if [[ -d /etc/ssh/sshd_config.d ]]; then
                while IFS= read -r -d $'\0' f; do
                    sshd_cfg_bad+=("$(stat -Lc '%n (%#a %U:%G)' "$f" 2>/dev/null)")
                done < <(find /etc/ssh/sshd_config.d/ -xdev -mount -type f -name '*.conf' \( -perm /077 -o ! -user root -o ! -group root \) -print0 2>/dev/null)
            fi
            if [[ "${#sshd_cfg_bad[@]}" -eq 0 ]]; then
                report_ok "5.1.1" "Ensure access to /etc/ssh/sshd_config is configured" "L1" "Automated"
            else
                report_fail "5.1.1" "Ensure access to /etc/ssh/sshd_config is configured" "L1" "Automated" \
                    "Non-compliant sshd_config files: ${sshd_cfg_bad[*]}" \
                    "Run: chown root:root /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf && chmod u-x,og-rwx /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf"
            fi
        fi
    fi

    # 5.1.2 Ensure access to /etc/ssh/sshd_config.d/ directory is configured (Automated)
    if should_run_check "5.1.2" "L1"; then
        if [[ "$sshd_installed" -eq 0 || ! -d /etc/ssh/sshd_config.d ]]; then
            report_ok "5.1.2" "Ensure access to /etc/ssh/sshd_config.d/ directory is configured" "L1" "Automated" "Directory not present or SSH server not installed"
        else
            check_file_perms "5.1.2" "Ensure access to /etc/ssh/sshd_config.d/ directory is configured" "L1" \
                "/etc/ssh/sshd_config.d" "0077" "0700" "root" "root" "1" \
                "chmod 0700 /etc/ssh/sshd_config.d/" "chown root:root /etc/ssh/sshd_config.d/"
        fi
    fi

    # 5.1.3 Ensure access to SSH private host key files is configured (Automated)
    if should_run_check "5.1.3" "L1"; then
        local bad_priv_keys=() kf
        for kf in /etc/ssh/ssh_host_*_key; do
            [[ -f "$kf" ]] || continue
            local m u g pmask="0177"
            read -r m u g <<< "$(stat -Lc '%#a %U %G' "$kf" 2>/dev/null)"
            [[ "$g" == "ssh_keys" ]] && pmask="0137"
            if [[ $(( m & pmask )) -gt 0 || "$u" != "root" || ( "$g" != "root" && "$g" != "ssh_keys" ) ]]; then
                bad_priv_keys+=("${kf} (${m} ${u}:${g})")
            fi
        done
        if [[ "${#bad_priv_keys[@]}" -eq 0 ]]; then
            report_ok "5.1.3" "Ensure access to SSH private host key files is configured" "L1" "Automated"
        else
            report_fail "5.1.3" "Ensure access to SSH private host key files is configured" "L1" "Automated" \
                "Non-compliant SSH private host keys: ${bad_priv_keys[*]}" \
                "Run: chown root:root /etc/ssh/ssh_host_*_key && chmod u-x,go-rwx /etc/ssh/ssh_host_*_key (or 0640 if group is ssh_keys)"
        fi
    fi

    # 5.1.4 Ensure access to SSH public host key files is configured (Automated)
    if should_run_check "5.1.4" "L1"; then
        local bad_pub_keys=() kf
        for kf in /etc/ssh/ssh_host_*_key.pub; do
            [[ -f "$kf" ]] || continue
            local m u g
            read -r m u g <<< "$(stat -Lc '%#a %U %G' "$kf" 2>/dev/null)"
            if [[ $(( m & 0133 )) -gt 0 || "$u" != "root" || "$g" != "root" ]]; then
                bad_pub_keys+=("${kf} (${m} ${u}:${g})")
            fi
        done
        if [[ "${#bad_pub_keys[@]}" -eq 0 ]]; then
            report_ok "5.1.4" "Ensure access to SSH public host key files is configured" "L1" "Automated"
        else
            report_fail "5.1.4" "Ensure access to SSH public host key files is configured" "L1" "Automated" \
                "Non-compliant SSH public host keys: ${bad_pub_keys[*]}" \
                "Run: chown root:root /etc/ssh/ssh_host_*_key.pub && chmod u-x,go-wx /etc/ssh/ssh_host_*_key.pub"
        fi
    fi

    # Helper for sshd -T / sshd_config checks when sshd is not installed
    if [[ "$sshd_installed" -eq 0 ]]; then
        local ssh_skip_ids=(
            "5.1.5|Ensure sshd access is configured|Automated"
            "5.1.6|Ensure sshd Banner is configured|Automated"
            "5.1.7|Ensure sshd Ciphers are configured|Automated"
            "5.1.8|Ensure sshd ClientAliveInterval and ClientAliveCountMax are configured|Automated"
            "5.1.9|Ensure sshd DisableForwarding is enabled|Automated"
            "5.1.10|Ensure sshd GSSAPIAuthentication is disabled|Automated"
            "5.1.11|Ensure sshd HostbasedAuthentication is disabled|Automated"
            "5.1.12|Ensure sshd IgnoreRhosts is enabled|Automated"
            "5.1.13|Ensure sshd KexAlgorithms is configured|Automated"
            "5.1.14|Ensure sshd post-quantum cryptography key exchange algorithms are configured|Manual"
            "5.1.15|Ensure sshd LoginGraceTime is configured|Automated"
            "5.1.16|Ensure sshd LogLevel is configured|Automated"
            "5.1.17|Ensure sshd MACs are configured|Automated"
            "5.1.18|Ensure sshd MaxAuthTries is configured|Automated"
            "5.1.19|Ensure sshd MaxSessions is configured|Automated"
            "5.1.20|Ensure sshd MaxStartups is configured|Automated"
            "5.1.21|Ensure sshd PermitEmptyPasswords is disabled|Automated"
            "5.1.22|Ensure sshd PermitRootLogin is disabled|Automated"
            "5.1.23|Ensure sshd PermitUserEnvironment is disabled|Automated"
            "5.1.24|Ensure sshd UsePAM is enabled|Automated"
        )
        local s_item s_id s_title s_type
        for s_item in "${ssh_skip_ids[@]}"; do
            IFS='|' read -r s_id s_title s_type <<< "$s_item"
            should_run_check "$s_id" "L1" && report_ok "$s_id" "$s_title" "L1" "$s_type" "openssh-server not installed"
        done
    else
        # 5.1.5 Ensure sshd access is configured (Automated)
        if should_run_check "5.1.5" "L1"; then
            if grep -Piq -- '^\h*(allow|deny)(users|groups)\h+\H+' <<< "$SSHD_T_CACHE" || grep -PRsiq -- '^\h*(Allow|Deny)(Users|Groups)\h+\H+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
                report_ok "5.1.5" "Ensure sshd access is configured" "L1" "Automated"
            else
                report_fail "5.1.5" "Ensure sshd access is configured" "L1" "Automated" \
                    "None of AllowUsers, AllowGroups, DenyUsers, or DenyGroups are configured in sshd" \
                    "Add 'AllowUsers <userlist>' or 'AllowGroups <grouplist>' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.6 Ensure sshd Banner is configured (Automated)
        if should_run_check "5.1.6" "L1"; then
            local b_path
            b_path="$(awk '$1=="banner"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ -n "$b_path" && "$b_path" != "none" && -s "$b_path" ]] && ! grep -Psiq -- "(\\\v|\\\r|\\\m|\\\s|\b${OS_ID}\b)" "$b_path" 2>/dev/null; then
                report_ok "5.1.6" "Ensure sshd Banner is configured" "L1" "Automated" "Banner=${b_path}"
            else
                report_fail "5.1.6" "Ensure sshd Banner is configured" "L1" "Automated" \
                    "sshd Banner is '${b_path:-none}' or banner file is empty/contains OS info" \
                    "Set 'Banner /etc/issue.net' in /etc/ssh/sshd_config.d/60-cis.conf, populate /etc/issue.net without OS escape sequences, and run: systemctl reload sshd"
            fi
        fi

        # 5.1.7 Ensure sshd Ciphers are configured (Automated)
        if should_run_check "5.1.7" "L1"; then
            local weak_ciphers
            weak_ciphers="$(grep -Pi -- '^ciphers\h+\"?([^#\n\r]+,)?((3des|blowfish|cast128|aes(128|192|256))-cbc|arcfour(128|256)?|rijndael-cbc@lysator\.liu\.se)\b' <<< "$SSHD_T_CACHE" || true)"
            if [[ -z "$weak_ciphers" ]]; then
                report_ok "5.1.7" "Ensure sshd Ciphers are configured" "L1" "Automated"
            else
                report_fail "5.1.7" "Ensure sshd Ciphers are configured" "L1" "Automated" \
                    "Weak SSH ciphers enabled: ${weak_ciphers}" \
                    "Run: printf '%s\n' 'Ciphers -3des-cbc,blowfish-cbc,cast128-cbc,aes128-cbc,aes192-cbc,aes256-cbc,arcfour,arcfour128,arcfour256,rijndael-cbc@lysator.liu.se' >> /etc/ssh/sshd_config.d/10-cis-sshd.conf && systemctl reload sshd"
            fi
        fi

        # 5.1.8 Ensure sshd ClientAliveInterval and ClientAliveCountMax are configured (Automated)
        if should_run_check "5.1.8" "L1"; then
            local cai cacm
            cai="$(awk '$1=="clientaliveinterval"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            cacm="$(awk '$1=="clientalivecountmax"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "${cai:-0}" -gt 0 && "${cacm:-0}" -gt 0 ]]; then
                report_ok "5.1.8" "Ensure sshd ClientAliveInterval and ClientAliveCountMax are configured" "L1" "Automated" "ClientAliveInterval=${cai}, ClientAliveCountMax=${cacm}"
            else
                report_fail "5.1.8" "Ensure sshd ClientAliveInterval and ClientAliveCountMax are configured" "L1" "Automated" \
                    "ClientAliveInterval=${cai:-0}, ClientAliveCountMax=${cacm:-0} (both must be > 0)" \
                    "Add 'ClientAliveInterval 15' and 'ClientAliveCountMax 3' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.9 Ensure sshd DisableForwarding is enabled (Automated)
        if should_run_check "5.1.9" "L1"; then
            local df_val
            df_val="$(awk '$1=="disableforwarding"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "$df_val" == "yes" ]]; then
                report_ok "5.1.9" "Ensure sshd DisableForwarding is enabled" "L1" "Automated"
            else
                report_fail "5.1.9" "Ensure sshd DisableForwarding is enabled" "L1" "Automated" \
                    "DisableForwarding is '${df_val:-no}' (expected: yes)" \
                    "Add 'DisableForwarding yes' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.10 Ensure sshd GSSAPIAuthentication is disabled (Automated)
        if should_run_check "5.1.10" "L1"; then
            local gss_val
            gss_val="$(awk '$1=="gssapiauthentication"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "$gss_val" == "no" ]]; then
                report_ok "5.1.10" "Ensure sshd GSSAPIAuthentication is disabled" "L1" "Automated"
            else
                report_fail "5.1.10" "Ensure sshd GSSAPIAuthentication is disabled" "L1" "Automated" \
                    "GSSAPIAuthentication is '${gss_val:-yes}' (expected: no)" \
                    "Add 'GSSAPIAuthentication no' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.11 Ensure sshd HostbasedAuthentication is disabled (Automated)
        if should_run_check "5.1.11" "L1"; then
            local hba_val
            hba_val="$(awk '$1=="hostbasedauthentication"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "$hba_val" == "no" ]]; then
                report_ok "5.1.11" "Ensure sshd HostbasedAuthentication is disabled" "L1" "Automated"
            else
                report_fail "5.1.11" "Ensure sshd HostbasedAuthentication is disabled" "L1" "Automated" \
                    "HostbasedAuthentication is '${hba_val:-yes}' (expected: no)" \
                    "Add 'HostbasedAuthentication no' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.12 Ensure sshd IgnoreRhosts is enabled (Automated)
        if should_run_check "5.1.12" "L1"; then
            local ir_val
            ir_val="$(awk '$1=="ignorerhosts"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "$ir_val" == "yes" ]]; then
                report_ok "5.1.12" "Ensure sshd IgnoreRhosts is enabled" "L1" "Automated"
            else
                report_fail "5.1.12" "Ensure sshd IgnoreRhosts is enabled" "L1" "Automated" \
                    "IgnoreRhosts is '${ir_val:-no}' (expected: yes)" \
                    "Add 'IgnoreRhosts yes' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.13 Ensure sshd KexAlgorithms is configured (Automated)
        if should_run_check "5.1.13" "L1"; then
            local weak_kex
            weak_kex="$(grep -Pi -- '^kexalgorithms\h+([^#\n\r]+,)?(diffie-hellman-group1-sha1|diffie-hellman-group14-sha1|diffie-hellman-group-exchange-sha1)\b' <<< "$SSHD_T_CACHE" || true)"
            if [[ -z "$weak_kex" ]]; then
                report_ok "5.1.13" "Ensure sshd KexAlgorithms is configured" "L1" "Automated"
            else
                report_fail "5.1.13" "Ensure sshd KexAlgorithms is configured" "L1" "Automated" \
                    "Weak KexAlgorithms enabled: ${weak_kex}" \
                    "Add 'KexAlgorithms -diffie-hellman-group1-sha1,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1' to /etc/ssh/sshd_config.d/10-cis-sshd.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.14 Ensure sshd post-quantum cryptography key exchange algorithms are configured (Manual)
        if should_run_check "5.1.14" "L1"; then
            local kex_line
            kex_line="$(awk '$1=="kexalgorithms"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if grep -Pq 'sntrup761x25519-sha512' <<< "$kex_line"; then
                report_ok "5.1.14" "Ensure sshd post-quantum cryptography key exchange algorithms are configured" "L1" "Manual" "PQC KexAlgorithms enabled"
            else
                report_manual "5.1.14" "Ensure sshd post-quantum cryptography key exchange algorithms are configured" "L1" "Manual" \
                    "Post-quantum KexAlgorithms (sntrup761x25519-sha512 / mlkem768x25519-sha256) not found in active kexalgorithms (${kex_line})" \
                    "Add 'KexAlgorithms +sntrup761x25519-sha512,mlkem768x25519-sha256' (or +sntrup761x25519-sha512 for OpenSSH < 9.9) to /etc/ssh/sshd_config.d/10-cis-sshd.conf and reload sshd."
            fi
        fi

        # 5.1.15 Ensure sshd LoginGraceTime is configured (Automated)
        if should_run_check "5.1.15" "L1"; then
            local lgt_val
            lgt_val="$(awk '$1=="logingracetime"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "${lgt_val:-0}" -ge 1 && "${lgt_val:-0}" -le 60 ]]; then
                report_ok "5.1.15" "Ensure sshd LoginGraceTime is configured" "L1" "Automated" "LoginGraceTime=${lgt_val}"
            else
                report_fail "5.1.15" "Ensure sshd LoginGraceTime is configured" "L1" "Automated" \
                    "LoginGraceTime is '${lgt_val:-120}' (must be between 1 and 60 seconds)" \
                    "Add 'LoginGraceTime 60' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.16 Ensure sshd LogLevel is configured (Automated)
        if should_run_check "5.1.16" "L1"; then
            local ll_val
            ll_val="$(awk '$1=="loglevel"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "$ll_val" == "VERBOSE" || "$ll_val" == "INFO" ]]; then
                report_ok "5.1.16" "Ensure sshd LogLevel is configured" "L1" "Automated" "LogLevel=${ll_val}"
            else
                report_fail "5.1.16" "Ensure sshd LogLevel is configured" "L1" "Automated" \
                    "LogLevel is '${ll_val:-unset}' (expected: VERBOSE or INFO)" \
                    "Add 'LogLevel VERBOSE' (or INFO) to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.17 Ensure sshd MACs are configured (Automated)
        if should_run_check "5.1.17" "L1"; then
            local weak_macs
            weak_macs="$(grep -Pi -- '^macs\h+([^#\n\r]+,)?(hmac-md5|hmac-md5-96|hmac-ripemd160|hmac-sha1-96|umac-64@openssh\.com|hmac-md5-etm@openssh\.com|hmac-md5-96-etm@openssh\.com|hmac-ripemd160-etm@openssh\.com|hmac-sha1-96-etm@openssh\.com|umac-64-etm@openssh\.com|umac-128-etm@openssh\.com)\b' <<< "$SSHD_T_CACHE" || true)"
            if [[ -z "$weak_macs" ]]; then
                report_ok "5.1.17" "Ensure sshd MACs are configured" "L1" "Automated"
            else
                report_fail "5.1.17" "Ensure sshd MACs are configured" "L1" "Automated" \
                    "Weak SSH MACs enabled: ${weak_macs}" \
                    "Add 'MACs -hmac-md5,hmac-md5-96,hmac-ripemd160,hmac-sha1-96,umac-64@openssh.com,hmac-md5-etm@openssh.com,hmac-md5-96-etm@openssh.com,hmac-ripemd160-etm@openssh.com,hmac-sha1-96-etm@openssh.com,umac-64-etm@openssh.com,umac-128-etm@openssh.com' to /etc/ssh/sshd_config.d/10-cis-sshd.conf and reload sshd."
            fi
        fi

        # 5.1.18 Ensure sshd MaxAuthTries is configured (Automated)
        if should_run_check "5.1.18" "L1"; then
            local mat_val
            mat_val="$(awk '$1=="maxauthtries"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "${mat_val:-99}" -le 4 && "${mat_val:-0}" -ge 1 ]]; then
                report_ok "5.1.18" "Ensure sshd MaxAuthTries is configured" "L1" "Automated" "MaxAuthTries=${mat_val}"
            else
                report_fail "5.1.18" "Ensure sshd MaxAuthTries is configured" "L1" "Automated" \
                    "MaxAuthTries is '${mat_val:-6}' (must be 4 or less)" \
                    "Add 'MaxAuthTries 4' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.19 Ensure sshd MaxSessions is configured (Automated)
        if should_run_check "5.1.19" "L1"; then
            local ms_val ms_bad_cfg
            ms_val="$(awk '$1=="maxsessions"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            ms_bad_cfg="$(grep -Psi -- '^\h*MaxSessions\h+\"?(1[1-9]|[2-9][0-9]|[1-9][0-9][0-9]+)\b' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true)"
            if [[ "${ms_val:-99}" -le 10 && "${ms_val:-0}" -ge 1 && -z "$ms_bad_cfg" ]]; then
                report_ok "5.1.19" "Ensure sshd MaxSessions is configured" "L1" "Automated" "MaxSessions=${ms_val}"
            else
                report_fail "5.1.19" "Ensure sshd MaxSessions is configured" "L1" "Automated" \
                    "MaxSessions is '${ms_val:-unset}' (must be 10 or less)" \
                    "Add 'MaxSessions 10' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.20 Ensure sshd MaxStartups is configured (Automated)
        if should_run_check "5.1.20" "L1"; then
            local msu_bad
            msu_bad="$(awk '$1 ~ /^\s*maxstartups/{split($2, a, ":"); if(a[1] > 10 || a[2] > 30 || a[3] > 60) print $0}' <<< "$SSHD_T_CACHE" || true)"
            if [[ -z "$msu_bad" && -n "$SSHD_T_CACHE" ]]; then
                report_ok "5.1.20" "Ensure sshd MaxStartups is configured" "L1" "Automated"
            else
                report_fail "5.1.20" "Ensure sshd MaxStartups is configured" "L1" "Automated" \
                    "MaxStartups is less restrictive than 10:30:60 (${msu_bad:-default 10:30:100})" \
                    "Add 'MaxStartups 10:30:60' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.21 Ensure sshd PermitEmptyPasswords is disabled (Automated)
        if should_run_check "5.1.21" "L1"; then
            local pep_val
            pep_val="$(awk '$1=="permitemptypasswords"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "$pep_val" == "no" ]]; then
                report_ok "5.1.21" "Ensure sshd PermitEmptyPasswords is disabled" "L1" "Automated"
            else
                report_fail "5.1.21" "Ensure sshd PermitEmptyPasswords is disabled" "L1" "Automated" \
                    "PermitEmptyPasswords is '${pep_val:-yes}' (expected: no)" \
                    "Add 'PermitEmptyPasswords no' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.22 Ensure sshd PermitRootLogin is disabled (Automated)
        if should_run_check "5.1.22" "L1"; then
            local prl_val
            prl_val="$(awk '$1=="permitrootlogin"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "$prl_val" == "no" ]]; then
                report_ok "5.1.22" "Ensure sshd PermitRootLogin is disabled" "L1" "Automated"
            else
                report_fail "5.1.22" "Ensure sshd PermitRootLogin is disabled" "L1" "Automated" \
                    "PermitRootLogin is '${prl_val:-prohibit-password}' (expected: no)" \
                    "Add 'PermitRootLogin no' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.23 Ensure sshd PermitUserEnvironment is disabled (Automated)
        if should_run_check "5.1.23" "L1"; then
            local pue_val
            pue_val="$(awk '$1=="permituserenvironment"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "$pue_val" == "no" ]]; then
                report_ok "5.1.23" "Ensure sshd PermitUserEnvironment is disabled" "L1" "Automated"
            else
                report_fail "5.1.23" "Ensure sshd PermitUserEnvironment is disabled" "L1" "Automated" \
                    "PermitUserEnvironment is '${pue_val:-yes}' (expected: no)" \
                    "Add 'PermitUserEnvironment no' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi

        # 5.1.24 Ensure sshd UsePAM is enabled (Automated)
        if should_run_check "5.1.24" "L1"; then
            local upam_val
            upam_val="$(awk '$1=="usepam"{print $2}' <<< "$SSHD_T_CACHE" | head -n 1)"
            if [[ "$upam_val" == "yes" ]]; then
                report_ok "5.1.24" "Ensure sshd UsePAM is enabled" "L1" "Automated"
            else
                report_fail "5.1.24" "Ensure sshd UsePAM is enabled" "L1" "Automated" \
                    "UsePAM is '${upam_val:-no}' (expected: yes)" \
                    "Add 'UsePAM yes' to /etc/ssh/sshd_config.d/60-cis.conf and run: systemctl reload sshd"
            fi
        fi
    fi

    # --------------------------------------------------------------------------
    # 5.2 Configure privilege escalation
    # --------------------------------------------------------------------------
    print_subsection_header "5.2 Configure Privilege Escalation"

    # 5.2.1 Ensure sudo is installed (Automated)
    if should_run_check "5.2.1" "L1"; then
        local sudo_pkg
        sudo_pkg="$(dpkg-query -W -f='${db:Status-Status} ${Package}\n' sudo-rs sudo 2>/dev/null | awk '$1=="installed"{print $2}' | tr '\n' ' ' || true)"
        if [[ -n "$sudo_pkg" ]]; then
            report_ok "5.2.1" "Ensure sudo is installed" "L1" "Automated" "${sudo_pkg% } installed"
        else
            report_fail "5.2.1" "Ensure sudo is installed" "L1" "Automated" \
                "Neither 'sudo-rs' nor 'sudo' is installed" \
                "Run: apt install -y sudo-rs (or 'apt install -y sudo')"
        fi
    fi

    # 5.2.2 Ensure sudo commands use pty (Automated)
    if should_run_check "5.2.2" "L1"; then
        local not_pty use_pty
        not_pty="$(grep -rPi -- '^\h*Defaults\h+([^#\n\r]+,\h*)?!use_pty\b' /etc/sudoers /etc/sudoers.d/ 2>/dev/null || true)"
        use_pty="$(grep -rPi -- '^\h*Defaults\h+([^#\n\r]+,\h*)?use_pty\b' /etc/sudoers /etc/sudoers.d/ 2>/dev/null || true)"
        if [[ -z "$not_pty" && -n "$use_pty" ]]; then
            report_ok "5.2.2" "Ensure sudo commands use pty" "L1" "Automated"
        else
            report_fail "5.2.2" "Ensure sudo commands use pty" "L1" "Automated" \
                "Defaults use_pty not explicitly set or !use_pty present (${not_pty})" \
                "Use 'visudo' or 'visudo -f /etc/sudoers.d/60-cis' to add 'Defaults use_pty' and remove any '!use_pty' entries."
        fi
    fi

    # 5.2.3 Ensure sudo log file exists (Automated)
    if should_run_check "5.2.3" "L1"; then
        local sudo_logfile_cfg sudo_rsyslog_cfg
        sudo_logfile_cfg="$(grep -rPsi "^\h*Defaults\h+([^#]+,\h*)?logfile\h*=\h*(\"|')?\H+(\"|')?(,\h*\H+\h*)*\h*(#.*)?$" /etc/sudoers /etc/sudoers.d/ 2>/dev/null || true)"
        sudo_rsyslog_cfg="$(grep -RPsi 'authpriv\.\*\h+/var/log/sudo\.log' /etc/rsyslog.conf /etc/rsyslog.d/ 2>/dev/null || true)"
        if [[ -n "$sudo_logfile_cfg" || -n "$sudo_rsyslog_cfg" ]]; then
            report_ok "5.2.3" "Ensure sudo log file exists" "L1" "Automated"
        else
            report_fail "5.2.3" "Ensure sudo log file exists" "L1" "Automated" \
                "Dedicated sudo log file (/var/log/sudo.log) is not configured in /etc/sudoers* or /etc/rsyslog.d/" \
                "For sudo-rs/syslog: run 'printf \"%s\n\" \"authpriv.* /var/log/sudo.log\" > /etc/rsyslog.d/30-sudo.conf && systemctl restart rsyslog'. For classic sudo: add 'Defaults logfile=\"/var/log/sudo.log\"' via visudo."
        fi
    fi

    # 5.2.4 Ensure users must provide password for escalation (Automated)
    if should_run_check "5.2.4" "L2"; then
        local nopasswd_lines
        nopasswd_lines="$(grep -rPi -- '^\s*[^#].*\bNOPASSWD\s*:' /etc/sudoers /etc/sudoers.d/ 2>/dev/null || true)"
        if [[ -z "$nopasswd_lines" ]]; then
            report_ok "5.2.4" "Ensure users must provide password for escalation" "L2" "Automated"
        else
            report_fail "5.2.4" "Ensure users must provide password for escalation" "L2" "Automated" \
                "NOPASSWD tag found in sudoers: ${nopasswd_lines}" \
                "Use 'visudo' to remove any occurrences of NOPASSWD tags in /etc/sudoers and /etc/sudoers.d/*."
        fi
    fi

    # 5.2.5 Ensure re-authentication for privilege escalation is not disabled globally (Automated)
    if should_run_check "5.2.5" "L1"; then
        local noauth_lines
        noauth_lines="$(grep -rPi -- '^\s*[^#].*!authenticate\b' /etc/sudoers /etc/sudoers.d/ 2>/dev/null || true)"
        if [[ -z "$noauth_lines" ]]; then
            report_ok "5.2.5" "Ensure re-authentication for privilege escalation is not disabled globally" "L1" "Automated"
        else
            report_fail "5.2.5" "Ensure re-authentication for privilege escalation is not disabled globally" "L1" "Automated" \
                "!authenticate tag found in sudoers: ${noauth_lines}" \
                "Use 'visudo' to remove any occurrences of '!authenticate' in /etc/sudoers and /etc/sudoers.d/*."
        fi
    fi

    # 5.2.6 Ensure sudo timestamp_timeout is configured (Automated)
    if should_run_check "5.2.6" "L1"; then
        local ts_vals
        ts_vals="$(grep -rPo -- '^\h*Defaults\h+([^#\n\r]+,\h*)?timestamp_timeout\h*=\h*\K[-0-9]+' /etc/sudoers /etc/sudoers.d/ 2>/dev/null || true)"
        if [[ -n "$ts_vals" ]]; then
            local ts_bad=0 v
            for v in $ts_vals; do
                if [[ "$v" -lt 0 || "$v" -gt 15 ]]; then
                    ts_bad=1
                fi
            done
            if [[ "$ts_bad" -eq 0 ]]; then
                report_ok "5.2.6" "Ensure sudo timestamp_timeout is configured" "L1" "Automated"
            else
                report_fail "5.2.6" "Ensure sudo timestamp_timeout is configured" "L1" "Automated" \
                    "Invalid timestamp_timeout value(s) (${ts_vals}) found (must be between 0 and 15)" \
                    "Use 'visudo' to set 'Defaults timestamp_timeout=15' (15 minutes or less, not -1) in /etc/sudoers."
            fi
        else
            report_fail "5.2.6" "Ensure sudo timestamp_timeout is configured" "L1" "Automated" \
                "timestamp_timeout is not explicitly configured in /etc/sudoers or /etc/sudoers.d/" \
                "Use 'visudo' to add 'Defaults timestamp_timeout=15' in /etc/sudoers or /etc/sudoers.d/60-cis."
        fi
    fi

    # 5.2.7 Ensure access to the su command is restricted (Automated)
    if should_run_check "5.2.7" "L1"; then
        local su_line su_grp grp_members
        su_line="$(grep -Pi '^\s*auth\s+(?:required|requisite)\s+pam_wheel\.so(?=.*\buse_uid\b)(?=.*\bgroup=\S+).*' /etc/pam.d/su 2>/dev/null || true)"
        if [[ -n "$su_line" ]]; then
            su_grp="$(grep -oP '\bgroup=\K\S+' <<< "$su_line" | head -n 1)"
            if grep -Pq "^${su_grp}:" /etc/group 2>/dev/null; then
                grp_members="$(awk -F: -v g="$su_grp" '$1==g {print $4}' /etc/group 2>/dev/null | xargs || true)"
                if [[ -z "$grp_members" ]]; then
                    report_ok "5.2.7" "Ensure access to the su command is restricted" "L1" "Automated" "pam_wheel group=${su_grp} (empty)"
                else
                    report_fail "5.2.7" "Ensure access to the su command is restricted" "L1" "Automated" \
                        "Group '${su_grp}' specified in /etc/pam.d/su is not empty (members: ${grp_members})" \
                        "Remove all users from group '${su_grp}' in /etc/group."
                fi
            else
                report_fail "5.2.7" "Ensure access to the su command is restricted" "L1" "Automated" \
                    "Group '${su_grp}' referenced in /etc/pam.d/su does not exist in /etc/group" \
                    "Run: groupadd ${su_grp}"
            fi
        else
            report_fail "5.2.7" "Ensure access to the su command is restricted" "L1" "Automated" \
                "pam_wheel.so with use_uid and group=<empty_group> is not configured in /etc/pam.d/su" \
                "Run: groupadd sugroup && echo 'auth required pam_wheel.so use_uid group=sugroup' >> /etc/pam.d/su"
        fi
    fi

    # --------------------------------------------------------------------------
    # 5.3 Pluggable Authentication Modules (PAM)
    # --------------------------------------------------------------------------
    print_subsection_header "5.3 Pluggable Authentication Modules (PAM)"

    # 5.3.1.1 - 5.3.1.4 PAM Software Packages
    local pam_pkgs=(
        "5.3.1.1|Ensure latest version of pam is installed|libpam-runtime"
        "5.3.1.2|Ensure latest version of libpam-modules is installed|libpam-modules"
        "5.3.1.3|Ensure latest version of libpam-pwquality is installed|libpam-pwquality"
        "5.3.1.4|Ensure latest version of cracklib-runtime is installed|cracklib-runtime"
    )
    local pp_item pp_id pp_title pp_pkg
    for pp_item in "${pam_pkgs[@]}"; do
        IFS='|' read -r pp_id pp_title pp_pkg <<< "$pp_item"
        if should_run_check "$pp_id" "L1"; then
            if dpkg-query -s "$pp_pkg" &>/dev/null; then
                if ! apt list --upgradable 2>/dev/null | grep -Pq "^${pp_pkg}/"; then
                    report_ok "$pp_id" "$pp_title" "L1" "Automated"
                else
                    report_fail "$pp_id" "$pp_title" "L1" "Automated" \
                        "Package '${pp_pkg}' has an available upgrade" \
                        "Run: apt install --only-upgrade -y ${pp_pkg}"
                fi
            else
                report_fail "$pp_id" "$pp_title" "L1" "Automated" \
                    "Package '${pp_pkg}' is not installed" \
                    "Run: apt install -y ${pp_pkg}"
            fi
        fi
    done

    # 5.3.2.1 Ensure pam_unix module is enabled (Automated)
    if should_run_check "5.3.2.1" "L1"; then
        local unix_missing=() f
        for f in account auth password session session-noninteractive; do
            if ! grep -Pq '\bpam_unix\.so\b' "/etc/pam.d/common-${f}" 2>/dev/null; then
                unix_missing+=("/etc/pam.d/common-${f}")
            fi
        done
        if [[ "${#unix_missing[@]}" -eq 0 ]]; then
            report_ok "5.3.2.1" "Ensure pam_unix module is enabled" "L1" "Automated"
        else
            report_fail "5.3.2.1" "Ensure pam_unix module is enabled" "L1" "Automated" \
                "pam_unix.so missing in: ${unix_missing[*]}" \
                "Run: pam-auth-update --enable unix"
        fi
    fi

    # 5.3.2.2 Ensure pam_faillock module is enabled (Automated)
    if should_run_check "5.3.2.2" "L1"; then
        if grep -Pq '\bpam_faillock\.so\b.*\bpreauth\b' /etc/pam.d/common-auth 2>/dev/null && \
           grep -Pq '\bpam_faillock\.so\b.*\bauthfail\b' /etc/pam.d/common-auth 2>/dev/null && \
           grep -Pq '\bpam_faillock\.so\b' /etc/pam.d/common-account 2>/dev/null; then
            report_ok "5.3.2.2" "Ensure pam_faillock module is enabled" "L1" "Automated"
        else
            report_fail "5.3.2.2" "Ensure pam_faillock module is enabled" "L1" "Automated" \
                "pam_faillock.so (preauth/authfail/account) is not enabled in /etc/pam.d/common-auth and /etc/pam.d/common-account" \
                "Create /usr/share/pam-configs/faillock and /usr/share/pam-configs/faillock_notify profiles and run: pam-auth-update --enable faillock faillock_notify"
        fi
    fi

    # 5.3.2.3 Ensure pam_pwquality module is enabled (Automated)
    if should_run_check "5.3.2.3" "L1"; then
        if grep -Pq '\bpam_pwquality\.so\b' /etc/pam.d/common-password 2>/dev/null; then
            report_ok "5.3.2.3" "Ensure pam_pwquality module is enabled" "L1" "Automated"
        else
            report_fail "5.3.2.3" "Ensure pam_pwquality module is enabled" "L1" "Automated" \
                "pam_pwquality.so is not enabled in /etc/pam.d/common-password" \
                "Install libpam-pwquality and run: pam-auth-update --enable pwquality"
        fi
    fi

    # 5.3.2.4 Ensure pam_pwhistory module is enabled (Automated)
    if should_run_check "5.3.2.4" "L1"; then
        if grep -Pq '\bpam_pwhistory\.so\b' /etc/pam.d/common-password 2>/dev/null; then
            report_ok "5.3.2.4" "Ensure pam_pwhistory module is enabled" "L1" "Automated"
        else
            report_fail "5.3.2.4" "Ensure pam_pwhistory module is enabled" "L1" "Automated" \
                "pam_pwhistory.so is not enabled in /etc/pam.d/common-password" \
                "Create /usr/share/pam-configs/pwhistory profile (or use built-in pwhistory profile) and run: pam-auth-update --enable pwhistory"
        fi
    fi

    # 5.3.3.1.1 Ensure password failed attempts lockout is configured (Automated)
    if should_run_check "5.3.3.1.1" "L1"; then
        local fl_deny fl_bad_pam
        fl_deny="$(grep -Pi -- '^\h*deny\h*=\h*[1-5]\b' /etc/security/faillock.conf 2>/dev/null || true)"
        fl_bad_pam="$(grep -Pi -- '^\h*auth\h+(requisite|required|sufficient)\h+pam_faillock\.so\h+([^#\n\r]+\h+)?deny\h*=\h*(0|[6-9]|[1-9][0-9]+)\b' /etc/pam.d/common-auth 2>/dev/null || true)"
        if [[ -n "$fl_deny" && -z "$fl_bad_pam" ]]; then
            report_ok "5.3.3.1.1" "Ensure password failed attempts lockout is configured" "L1" "Automated"
        else
            report_fail "5.3.3.1.1" "Ensure password failed attempts lockout is configured" "L1" "Automated" \
                "deny is not set to 1..5 in /etc/security/faillock.conf or overridden in /etc/pam.d/common-auth" \
                "Set 'deny = 5' in /etc/security/faillock.conf and remove any 'deny=' argument from pam_faillock.so in /usr/share/pam-configs/*."
        fi
    fi

    # 5.3.3.1.2 Ensure password unlock time is configured (Automated)
    if should_run_check "5.3.3.1.2" "L1"; then
        local fl_ut fl_bad_ut
        fl_ut="$(grep -Pi -- '^\h*unlock_time\h*=\h*(0|9[0-9][0-9]|[1-9][0-9]{3,})\b' /etc/security/faillock.conf 2>/dev/null || true)"
        fl_bad_ut="$(grep -Pi -- '^\h*auth\h+(requisite|required|sufficient)\h+pam_faillock\.so\h+([^#\n\r]+\h+)?unlock_time\h*=\h*([1-9]|[1-9][0-9]|[1-8][0-9][0-9])\b' /etc/pam.d/common-auth 2>/dev/null || true)"
        if [[ -n "$fl_ut" && -z "$fl_bad_ut" ]]; then
            report_ok "5.3.3.1.2" "Ensure password unlock time is configured" "L1" "Automated"
        else
            report_fail "5.3.3.1.2" "Ensure password unlock time is configured" "L1" "Automated" \
                "unlock_time is not set to 0 or >= 900 in /etc/security/faillock.conf" \
                "Set 'unlock_time = 900' in /etc/security/faillock.conf and remove any 'unlock_time=' argument from pam_faillock.so in /usr/share/pam-configs/*."
        fi
    fi

    # 5.3.3.1.3 Ensure password failed attempts lockout includes root account (Automated)
    if should_run_check "5.3.3.1.3" "L2"; then
        local fl_root fl_bad_rut1 fl_bad_rut2
        fl_root="$(grep -Pi -- '^\h*(even_deny_root|root_unlock_time\h*=\h*\d+)\b' /etc/security/faillock.conf 2>/dev/null || true)"
        fl_bad_rut1="$(grep -Pi -- '^\h*root_unlock_time\h*=\h*([1-9]|[1-5][0-9])\b' /etc/security/faillock.conf 2>/dev/null || true)"
        fl_bad_rut2="$(grep -Pi -- '^\h*auth\h+([^#\n\r]+\h+)pam_faillock\.so\h+([^#\n\r]+\h+)?root_unlock_time\h*=\h*([1-9]|[1-5][0-9])\b' /etc/pam.d/common-auth 2>/dev/null || true)"
        if [[ -n "$fl_root" && -z "$fl_bad_rut1" && -z "$fl_bad_rut2" ]]; then
            report_ok "5.3.3.1.3" "Ensure password failed attempts lockout includes root account" "L2" "Automated"
        else
            report_fail "5.3.3.1.3" "Ensure password failed attempts lockout includes root account" "L2" "Automated" \
                "even_deny_root is not enabled or root_unlock_time < 60 in /etc/security/faillock.conf" \
                "Add 'even_deny_root' (and optionally 'root_unlock_time = 60' or more) in /etc/security/faillock.conf."
        fi
    fi

    # 5.3.3.2.1 Ensure password number of changed characters is configured (Automated)
    if should_run_check "5.3.3.2.1" "L1"; then
        local difok_ok difok_bad
        difok_ok="$(grep -Psi -- '^\h*difok\h*=\h*([2-9]|[1-9][0-9]+)\b' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf 2>/dev/null || true)"
        difok_bad="$(grep -Psi -- '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?difok\h*=\h*([0-1])\b' /etc/pam.d/common-password 2>/dev/null || true)"
        if [[ -n "$difok_ok" && -z "$difok_bad" ]]; then
            report_ok "5.3.3.2.1" "Ensure password number of changed characters is configured" "L1" "Automated"
        else
            report_fail "5.3.3.2.1" "Ensure password number of changed characters is configured" "L1" "Automated" \
                "difok is not set to 2 or more in /etc/security/pwquality.conf or /etc/security/pwquality.conf.d/*.conf" \
                "Run: printf '\n%s\n' 'difok = 2' > /etc/security/pwquality.conf.d/50-pwdifok.conf"
        fi
    fi

    # 5.3.3.2.2 Ensure password length is configured (Automated)
    if should_run_check "5.3.3.2.2" "L1"; then
        local minlen_ok minlen_bad
        minlen_ok="$(grep -Psi -- '^\h*minlen\h*=\h*(1[4-9]|[2-9][0-9]|[1-9][0-9]{2,})\b' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf 2>/dev/null || true)"
        minlen_bad="$(grep -Psi -- '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?minlen\h*=\h*([0-9]|1[0-3])\b' /etc/pam.d/common-password 2>/dev/null || true)"
        if [[ -n "$minlen_ok" && -z "$minlen_bad" ]]; then
            report_ok "5.3.3.2.2" "Ensure password length is configured" "L1" "Automated"
        else
            report_fail "5.3.3.2.2" "Ensure password length is configured" "L1" "Automated" \
                "minlen is not set to 14 or more in /etc/security/pwquality.conf or /etc/security/pwquality.conf.d/*.conf" \
                "Run: printf '\n%s\n' 'minlen = 14' > /etc/security/pwquality.conf.d/50-pwlength.conf"
        fi
    fi

    # 5.3.3.2.3 Ensure password complexity is configured (Manual)
    if should_run_check "5.3.3.2.3" "L1"; then
        local comp_cfg comp_pos comp_pam_bad
        comp_cfg="$(grep -Psi -- '^\h*(minclass|[dulo]credit)\h*=\h*[-0-9]+' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf 2>/dev/null | tr '\n' ' ' || true)"
        comp_pos="$(grep -Psi -- '^\h*[dulo]credit\h*=\h*[1-9][0-9]*\b' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf 2>/dev/null || true)"
        comp_pam_bad="$(grep -Psi -- '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?(minclass\h*=\h*[0-2]|[dulo]credit\h*=\h*[0-9]+)\b' /etc/pam.d/common-password 2>/dev/null || true)"
        if [[ -n "$comp_cfg" && -z "$comp_pos" && -z "$comp_pam_bad" ]]; then
            report_ok "5.3.3.2.3" "Ensure password complexity is configured" "L1" "Manual" "${comp_cfg% }"
        else
            report_manual "5.3.3.2.3" "Ensure password complexity is configured" "L1" "Manual" \
                "Password complexity settings in pwquality: '${comp_cfg:-none configured}' (positive credits: ${comp_pos:-none})" \
                "Configure 'minclass = 3' (or 'dcredit = -1', 'ucredit = -1', 'lcredit = -1', 'ocredit = -1') in /etc/security/pwquality.conf.d/50-pwcomplexity.conf."
        fi
    fi

    # 5.3.3.2.4 Ensure password same consecutive characters is configured (Automated)
    if should_run_check "5.3.3.2.4" "L1"; then
        local maxrep_ok maxrep_bad
        maxrep_ok="$(grep -Psi -- '^\h*maxrepeat\h*=\h*[1-3]\b' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf 2>/dev/null || true)"
        maxrep_bad="$(grep -Psi -- '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?maxrepeat\h*=\h*(0|[4-9]|[1-9][0-9]+)\b' /etc/pam.d/common-password 2>/dev/null || true)"
        if [[ -n "$maxrep_ok" && -z "$maxrep_bad" ]]; then
            report_ok "5.3.3.2.4" "Ensure password same consecutive characters is configured" "L1" "Automated"
        else
            report_fail "5.3.3.2.4" "Ensure password same consecutive characters is configured" "L1" "Automated" \
                "maxrepeat is not set to 1..3 in /etc/security/pwquality.conf or /etc/security/pwquality.conf.d/*.conf" \
                "Run: printf '\n%s\n' 'maxrepeat = 3' > /etc/security/pwquality.conf.d/50-pwrepeat.conf"
        fi
    fi

    # 5.3.3.2.5 Ensure password maximum sequential characters is configured (Automated)
    if should_run_check "5.3.3.2.5" "L1"; then
        local maxseq_ok maxseq_bad
        maxseq_ok="$(grep -Psi -- '^\h*maxsequence\h*=\h*[1-3]\b' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf 2>/dev/null || true)"
        maxseq_bad="$(grep -Psi -- '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?maxsequence\h*=\h*(0|[4-9]|[1-9][0-9]+)\b' /etc/pam.d/common-password 2>/dev/null || true)"
        if [[ -n "$maxseq_ok" && -z "$maxseq_bad" ]]; then
            report_ok "5.3.3.2.5" "Ensure password maximum sequential characters is configured" "L1" "Automated"
        else
            report_fail "5.3.3.2.5" "Ensure password maximum sequential characters is configured" "L1" "Automated" \
                "maxsequence is not set to 1..3 in /etc/security/pwquality.conf or /etc/security/pwquality.conf.d/*.conf" \
                "Run: printf '\n%s\n' 'maxsequence = 3' > /etc/security/pwquality.conf.d/50-pwmaxsequence.conf"
        fi
    fi

    # 5.3.3.2.6 Ensure password dictionary check is enabled (Automated)
    if should_run_check "5.3.3.2.6" "L1"; then
        local dict_bad1 dict_bad2
        dict_bad1="$(grep -Psi -- '^\h*dictcheck\h*=\h*0\b' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf 2>/dev/null || true)"
        dict_bad2="$(grep -Psi -- '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?dictcheck\h*=\h*0\b' /etc/pam.d/common-password 2>/dev/null || true)"
        if [[ -z "$dict_bad1" && -z "$dict_bad2" ]]; then
            report_ok "5.3.3.2.6" "Ensure password dictionary check is enabled" "L1" "Automated"
        else
            report_fail "5.3.3.2.6" "Ensure password dictionary check is enabled" "L1" "Automated" \
                "dictcheck=0 is set in pwquality configuration or PAM common-password" \
                "Remove or comment out 'dictcheck = 0' in /etc/security/pwquality.conf, /etc/security/pwquality.conf.d/*.conf, and /usr/share/pam-configs/*."
        fi
    fi

    # 5.3.3.2.7 Ensure password quality checking is enforced (Automated)
    if should_run_check "5.3.3.2.7" "L1"; then
        local enf_bad1 enf_bad2
        enf_bad1="$(grep -PHsi -- '^\h*enforcing\h*=\h*0\b' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf 2>/dev/null || true)"
        enf_bad2="$(grep -PHsi -- '^\h*password\h+[^#\n\r]+\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?enforcing=0\b' /etc/pam.d/common-password 2>/dev/null || true)"
        if [[ -z "$enf_bad1" && -z "$enf_bad2" ]]; then
            report_ok "5.3.3.2.7" "Ensure password quality checking is enforced" "L1" "Automated"
        else
            report_fail "5.3.3.2.7" "Ensure password quality checking is enforced" "L1" "Automated" \
                "enforcing=0 found in pwquality config or PAM common-password" \
                "Remove or comment out 'enforcing = 0' in /etc/security/pwquality.conf, /etc/security/pwquality.conf.d/*.conf, and /usr/share/pam-configs/*."
        fi
    fi

    # 5.3.3.2.8 Ensure password quality is enforced for the root user (Automated)
    if should_run_check "5.3.3.2.8" "L1"; then
        if grep -Psiq -- '^\h*enforce_for_root\b' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf 2>/dev/null || \
           grep -Psiq -- '^\h*password\h+[^#\n\r]+\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?enforce_for_root\b' /etc/pam.d/common-password 2>/dev/null; then
            report_ok "5.3.3.2.8" "Ensure password quality is enforced for the root user" "L1" "Automated"
        else
            report_fail "5.3.3.2.8" "Ensure password quality is enforced for the root user" "L1" "Automated" \
                "enforce_for_root is not enabled in /etc/security/pwquality.conf or /etc/security/pwquality.conf.d/*.conf" \
                "Run: printf '\n%s\n' 'enforce_for_root' > /etc/security/pwquality.conf.d/50-pwroot.conf"
        fi
    fi

    # 5.3.3.3.1 Ensure password history remember is configured (Automated)
    if should_run_check "5.3.3.3.1" "L1"; then
        local pwh_rem1 pwh_rem2
        pwh_rem1="$(grep -Pi -- '^\h*remember\h*=\h*(2[4-9]|[3-9][0-9]|[1-9][0-9]{2,})\b' /etc/security/pwhistory.conf 2>/dev/null || true)"
        pwh_rem2="$(grep -Pi -- '^\h*password\h+[^#\n\r]+\h+pam_pwhistory\.so\b.*\bremember=(2[4-9]|[3-9][0-9]|[1-9][0-9]{2,})\b' /etc/pam.d/common-password 2>/dev/null || true)"
        if [[ -n "$pwh_rem1" || -n "$pwh_rem2" ]]; then
            report_ok "5.3.3.3.1" "Ensure password history remember is configured" "L1" "Automated"
        else
            report_fail "5.3.3.3.1" "Ensure password history remember is configured" "L1" "Automated" \
                "pwhistory remember is not set to 24 or more in /etc/security/pwhistory.conf or /etc/pam.d/common-password" \
                "Add 'remember = 24' to /etc/security/pwhistory.conf (and remove conflicting remember=<N> from /usr/share/pam-configs/pwhistory)."
        fi
    fi

    # 5.3.3.3.2 Ensure password history is enforced for the root user (Automated)
    if should_run_check "5.3.3.3.2" "L1"; then
        local pwh_root1 pwh_root2
        pwh_root1="$(grep -Pi -- '^\h*enforce_for_root\b' /etc/security/pwhistory.conf 2>/dev/null || true)"
        pwh_root2="$(grep -Psi -- '^\h*password\h+[^#\n\r]+\h+pam_pwhistory\.so\h+([^#\n\r]+\h+)?enforce_for_root\b' /etc/pam.d/common-password 2>/dev/null || true)"
        if [[ -n "$pwh_root1" || -n "$pwh_root2" ]]; then
            report_ok "5.3.3.3.2" "Ensure password history is enforced for the root user" "L1" "Automated"
        else
            report_fail "5.3.3.3.2" "Ensure password history is enforced for the root user" "L1" "Automated" \
                "enforce_for_root is not set for pam_pwhistory in /etc/security/pwhistory.conf or /etc/pam.d/common-password" \
                "Add 'enforce_for_root' to /etc/security/pwhistory.conf."
        fi
    fi

    # 5.3.3.3.3 Ensure pam_pwhistory includes use_authtok (Automated)
    if should_run_check "5.3.3.3.3" "L1"; then
        local pwh_atok1 pwh_atok2
        pwh_atok1="$(grep -Pi -- '^\h*use_authtok\b' /etc/security/pwhistory.conf 2>/dev/null || true)"
        pwh_atok2="$(grep -Psi -- '^\h*password\h+[^#\n\r]+\h+pam_pwhistory\.so\h+([^#\n\r]+\h+)?use_authtok\b' /etc/pam.d/common-password 2>/dev/null || true)"
        if [[ -n "$pwh_atok1" || -n "$pwh_atok2" ]]; then
            report_ok "5.3.3.3.3" "Ensure pam_pwhistory includes use_authtok" "L1" "Automated"
        else
            report_fail "5.3.3.3.3" "Ensure pam_pwhistory includes use_authtok" "L1" "Automated" \
                "use_authtok is not set for pam_pwhistory in /etc/security/pwhistory.conf or /etc/pam.d/common-password" \
                "Add 'use_authtok' to /etc/security/pwhistory.conf (or to the pam_pwhistory.so line in /usr/share/pam-configs/pwhistory and run 'pam-auth-update --enable pwhistory')."
        fi
    fi

    # 5.3.3.4.1 Ensure pam_unix does not include nullok (Automated)
    if should_run_check "5.3.3.4.1" "L1"; then
        local unix_nullok
        unix_nullok="$(grep -PHs -- '^\h*[^#\n\r]+\h+pam_unix\.so\h+([^#\n\r]+\h+)?nullok\b' /etc/pam.d/common-{password,auth,account,session,session-noninteractive} 2>/dev/null || true)"
        if [[ -z "$unix_nullok" ]]; then
            report_ok "5.3.3.4.1" "Ensure pam_unix does not include nullok" "L1" "Automated"
        else
            report_fail "5.3.3.4.1" "Ensure pam_unix does not include nullok" "L1" "Automated" \
                "nullok found on pam_unix.so: ${unix_nullok}" \
                "Remove 'nullok' from /usr/share/pam-configs/unix and run: pam-auth-update --enable unix"
        fi
    fi

    # 5.3.3.4.2 Ensure pam_unix does not include remember (Automated)
    if should_run_check "5.3.3.4.2" "L1"; then
        local unix_rem
        unix_rem="$(grep -PHs -- '^\h*[^#\n\r]+\h+pam_unix\.so\h+([^#\n\r]+\h+)?remember=\d+\b' /etc/pam.d/common-{password,auth,account,session,session-noninteractive} 2>/dev/null || true)"
        if [[ -z "$unix_rem" ]]; then
            report_ok "5.3.3.4.2" "Ensure pam_unix does not include remember" "L1" "Automated"
        else
            report_fail "5.3.3.4.2" "Ensure pam_unix does not include remember" "L1" "Automated" \
                "remember=<N> found on pam_unix.so: ${unix_rem}" \
                "Remove 'remember=<N>' from pam_unix.so lines in /usr/share/pam-configs/* and run: pam-auth-update --enable unix"
        fi
    fi

    # 5.3.3.4.3 Ensure pam_unix includes a strong password hashing algorithm (Automated)
    if should_run_check "5.3.3.4.3" "L1"; then
        if grep -PHq -- '^\h*password\h+([^#\n\r]+)\h+pam_unix\.so\h+([^#\n\r]+\h+)?(sha512|yescrypt)\b' /etc/pam.d/common-password 2>/dev/null; then
            report_ok "5.3.3.4.3" "Ensure pam_unix includes a strong password hashing algorithm" "L1" "Automated"
        else
            report_fail "5.3.3.4.3" "Ensure pam_unix includes a strong password hashing algorithm" "L1" "Automated" \
                "pam_unix.so in /etc/pam.d/common-password does not specify sha512 or yescrypt" \
                "Ensure 'yescrypt' (or 'sha512') is set on the pam_unix.so Password line in /usr/share/pam-configs/unix and run: pam-auth-update --enable unix"
        fi
    fi

    # 5.3.3.4.4 Ensure pam_unix includes use_authtok (Automated)
    if should_run_check "5.3.3.4.4" "L1"; then
        if grep -PHq -- '^\h*password\h+([^#\n\r]+)\h+pam_unix\.so\h+([^#\n\r]+\h+)?use_authtok\b' /etc/pam.d/common-password 2>/dev/null; then
            report_ok "5.3.3.4.4" "Ensure pam_unix includes use_authtok" "L1" "Automated"
        else
            report_fail "5.3.3.4.4" "Ensure pam_unix includes use_authtok" "L1" "Automated" \
                "pam_unix.so in /etc/pam.d/common-password does not include use_authtok" \
                "Add 'use_authtok' to the pam_unix.so Password line in /usr/share/pam-configs/unix and run: pam-auth-update --enable unix"
        fi
    fi

    # --------------------------------------------------------------------------
    # 5.4 User Accounts and Environment
    # --------------------------------------------------------------------------
    print_subsection_header "5.4 User Accounts and Environment"

    # 5.4.1.1 Ensure password expiration is configured (Automated)
    if should_run_check "5.4.1.1" "L1"; then
        local pmax bad_sh_max
        pmax="$(awk '/^\s*PASS_MAX_DAYS\s+[0-9]+/{print $2}' /etc/login.defs 2>/dev/null | tail -n 1)"
        bad_sh_max="$(awk -F: '($2~/^\$.+\$/) {if($5 > 365 || $5 < 1) print $1 ":" $5}' /etc/shadow 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -n "$pmax" && "$pmax" -ge 1 && "$pmax" -le 365 && -z "$bad_sh_max" ]]; then
            report_ok "5.4.1.1" "Ensure password expiration is configured" "L1" "Automated" "PASS_MAX_DAYS=${pmax}"
        else
            report_fail "5.4.1.1" "Ensure password expiration is configured" "L1" "Automated" \
                "PASS_MAX_DAYS=${pmax:-unset} in /etc/login.defs (must be 1..365); non-compliant shadow users: [${bad_sh_max% }]" \
                "Set 'PASS_MAX_DAYS 365' in /etc/login.defs and run: awk -F: '(\$2~/^\$.+\$/) {if(\$5 > 365 || \$5 < 1) system(\"chage --maxdays 365 \" \$1)}' /etc/shadow"
        fi
    fi

    # 5.4.1.2 Ensure minimum password days is configured (Manual)
    if should_run_check "5.4.1.2" "L2"; then
        local pmin bad_sh_min
        pmin="$(awk '/^\s*PASS_MIN_DAYS\s+[0-9]+/{print $2}' /etc/login.defs 2>/dev/null | tail -n 1)"
        bad_sh_min="$(awk -F: '($2~/^\$.+\$/) {if($4 < 1) print $1 ":" $4}' /etc/shadow 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -n "$pmin" && "$pmin" -ge 1 && -z "$bad_sh_min" ]]; then
            report_ok "5.4.1.2" "Ensure minimum password days is configured" "L2" "Manual" "PASS_MIN_DAYS=${pmin}"
        else
            report_fail "5.4.1.2" "Ensure minimum password days is configured" "L2" "Manual" \
                "PASS_MIN_DAYS=${pmin:-0} in /etc/login.defs (must be >= 1); users with PASS_MIN_DAYS < 1: [${bad_sh_min% }]" \
                "Set 'PASS_MIN_DAYS 1' in /etc/login.defs and run: awk -F: '(\$2~/^\$.+\$/) {if(\$4 < 1) system(\"chage --mindays 1 \" \$1)}' /etc/shadow"
        fi
    fi

    # 5.4.1.3 Ensure password expiration warning days is configured (Automated)
    if should_run_check "5.4.1.3" "L1"; then
        local pwarn bad_sh_warn
        pwarn="$(awk '/^\s*PASS_WARN_AGE\s+[0-9]+/{print $2}' /etc/login.defs 2>/dev/null | tail -n 1)"
        bad_sh_warn="$(awk -F: '($2~/^\$.+\$/) {if($6 < 7) print $1 ":" $6}' /etc/shadow 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -n "$pwarn" && "$pwarn" -ge 7 && -z "$bad_sh_warn" ]]; then
            report_ok "5.4.1.3" "Ensure password expiration warning days is configured" "L1" "Automated" "PASS_WARN_AGE=${pwarn}"
        else
            report_fail "5.4.1.3" "Ensure password expiration warning days is configured" "L1" "Automated" \
                "PASS_WARN_AGE=${pwarn:-unset} (must be >= 7); users with PASS_WARN_AGE < 7: [${bad_sh_warn% }]" \
                "Set 'PASS_WARN_AGE 7' in /etc/login.defs and run: awk -F: '(\$2~/^\$.+\$/) {if(\$6 < 7) system(\"chage --warndays 7 \" \$1)}' /etc/shadow"
        fi
    fi

    # 5.4.1.4 Ensure strong password hashing algorithm is configured (Automated)
    if should_run_check "5.4.1.4" "L1"; then
        local enc_m
        enc_m="$(grep -Pi -- '^\h*ENCRYPT_METHOD\h+(SHA512|YESCRYPT)\b' /etc/login.defs 2>/dev/null || true)"
        if [[ -n "$enc_m" ]]; then
            report_ok "5.4.1.4" "Ensure strong password hashing algorithm is configured" "L1" "Automated" "${enc_m}"
        else
            report_fail "5.4.1.4" "Ensure strong password hashing algorithm is configured" "L1" "Automated" \
                "ENCRYPT_METHOD in /etc/login.defs is not set to SHA512 or YESCRYPT" \
                "Set 'ENCRYPT_METHOD YESCRYPT' (or SHA512) in /etc/login.defs."
        fi
    fi

    # 5.4.1.5 Ensure inactive password lock is configured (Automated)
    if should_run_check "5.4.1.5" "L1"; then
        local inact_def bad_sh_inact
        inact_def="$(useradd -D 2>/dev/null | awk -F= '/^INACTIVE=/{print $2}' || echo -1)"
        bad_sh_inact="$(awk -F: '($2~/^\$.+\$/) {if($7 > 45 || $7 < 0 || $7 == "") print $1 ":" $7}' /etc/shadow 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -n "$inact_def" && "$inact_def" -ge 0 && "$inact_def" -le 45 && -z "$bad_sh_inact" ]]; then
            report_ok "5.4.1.5" "Ensure inactive password lock is configured" "L1" "Automated" "INACTIVE=${inact_def}"
        else
            report_fail "5.4.1.5" "Ensure inactive password lock is configured" "L1" "Automated" \
                "Default INACTIVE=${inact_def} (must be 0..45); users with non-compliant INACTIVE: [${bad_sh_inact% }]" \
                "Run: useradd -D -f 45 && awk -F: '(\$2~/^\$.+\$/) {if(\$7 > 45 || \$7 < 0 || \$7 == \"\") system(\"chage --inactive 45 \" \$1)}' /etc/shadow"
        fi
    fi

    # 5.4.1.6 Ensure all users last password change date is in the past (Automated)
    if should_run_check "5.4.1.6" "L1"; then
        local future_pw_users=() l_user
        while IFS= read -r l_user; do
            [[ -z "$l_user" ]] && continue
            local l_change_raw l_change
            l_change_raw="$(chage --list "$l_user" 2>/dev/null | grep '^Last password change' | cut -d: -f2 | xargs || true)"
            [[ -z "$l_change_raw" || "$l_change_raw" == "never" ]] && continue
            l_change="$(date -u -d "$l_change_raw" +%s 2>/dev/null || echo 0)"
            if [[ "$l_change" -gt "$(date +%s)" ]]; then
                future_pw_users+=("${l_user} (${l_change_raw})")
            fi
        done < <(awk -F: '$2~/^\$.+\$/{print $1}' /etc/shadow 2>/dev/null)
        if [[ "${#future_pw_users[@]}" -eq 0 ]]; then
            report_ok "5.4.1.6" "Ensure all users last password change date is in the past" "L1" "Automated"
        else
            report_fail "5.4.1.6" "Ensure all users last password change date is in the past" "L1" "Automated" \
                "Users with future password change date: ${future_pw_users[*]}" \
                "Run: chage -d \"\$(date +%Y-%m-%d)\" <user> && chage -d 0 <user>"
        fi
    fi

    # 5.4.2.1 Ensure root is the only UID 0 account (Automated)
    if should_run_check "5.4.2.1" "L1"; then
        local uid0_users
        uid0_users="$(awk -F: '($3 == 0) { print $1 }' /etc/passwd 2>/dev/null | tr '\n' ' ' | xargs || true)"
        if [[ "$uid0_users" == "root" ]]; then
            report_ok "5.4.2.1" "Ensure root is the only UID 0 account" "L1" "Automated"
        else
            report_fail "5.4.2.1" "Ensure root is the only UID 0 account" "L1" "Automated" \
                "Accounts with UID 0: [${uid0_users}]" \
                "Ensure 'root' has UID 0 ('usermod -u 0 root') and assign a new non-zero UID to any other account with UID 0."
        fi
    fi

    # 5.4.2.2 Ensure root is the only GID 0 account (Automated)
    if should_run_check "5.4.2.2" "L1"; then
        local gid0_users
        gid0_users="$(awk -F: '($1 !~ /^(sync|shutdown|halt|operator)/ && $4=="0") {print $1":"$4}' /etc/passwd 2>/dev/null | tr '\n' ' ' | xargs || true)"
        if [[ "$gid0_users" == "root:0" ]]; then
            report_ok "5.4.2.2" "Ensure root is the only GID 0 account" "L1" "Automated"
        else
            report_fail "5.4.2.2" "Ensure root is the only GID 0 account" "L1" "Automated" \
                "Accounts with primary GID 0: [${gid0_users}]" \
                "Run 'usermod -g 0 root' and assign a non-0 primary GID to any other non-exempt user."
        fi
    fi

    # 5.4.2.3 Ensure group root is the only GID 0 group (Automated)
    if should_run_check "5.4.2.3" "L1"; then
        local gid0_grps
        gid0_grps="$(awk -F: '$3=="0"{print $1":"$3}' /etc/group 2>/dev/null | tr '\n' ' ' | xargs || true)"
        if [[ "$gid0_grps" == "root:0" ]]; then
            report_ok "5.4.2.3" "Ensure group root is the only GID 0 group" "L1" "Automated"
        else
            report_fail "5.4.2.3" "Ensure group root is the only GID 0 group" "L1" "Automated" \
                "Groups with GID 0: [${gid0_grps}]" \
                "Run 'groupmod -g 0 root' and assign a new GID to any other group with GID 0."
        fi
    fi

    # 5.4.2.4 Ensure root account access is controlled (Automated)
    if should_run_check "5.4.2.4" "L1"; then
        local root_pw_st
        root_pw_st="$(passwd -S root 2>/dev/null | awk '$2 ~ /^(P|L)/ {print $2}' || true)"
        if [[ -z "$root_pw_st" && -r /etc/shadow ]]; then
            root_pw_st="$(awk -F: '$1=="root" {if ($2 ~ /^\$/ || $2 ~ /^!/) print "P_OR_L"}' /etc/shadow 2>/dev/null || true)"
        fi
        if [[ -n "$root_pw_st" ]]; then
            report_ok "5.4.2.4" "Ensure root account access is controlled" "L1" "Automated"
        else
            report_fail "5.4.2.4" "Ensure root account access is controlled" "L1" "Automated" \
                "Root account has neither a password set (P) nor is locked (L)" \
                "Lock the root account with 'usermod -L root' (or set a strong password with 'passwd root')."
        fi
    fi

    # 5.4.2.5 Ensure root path integrity (Automated)
    if should_run_check "5.4.2.5" "L1"; then
        local rpath path_issues=() pmask=0022
        rpath="$(sudo su - root -c env 2>/dev/null | awk -F= '$1=="PATH"{print $2}' || echo "$PATH")"
        grep -q -- "::" <<< "$rpath" && path_issues+=("Root PATH contains empty directory (::)")
        grep -Pq -- ":\h*$" <<< "$rpath" && path_issues+=("Root PATH contains trailing colon (:)")
        grep -Pq -- '(^\h*|:)\.(:|\h*$)' <<< "$rpath" && path_issues+=("Root PATH contains current working directory (.)")
        local a_path_loc=() pdir
        IFS=":" read -ra a_path_loc <<< "$rpath"
        for pdir in "${a_path_loc[@]}"; do
            [[ -z "$pdir" || "$pdir" == "." ]] && continue
            if [[ -d "$pdir" ]]; then
                local m u
                read -r m u <<< "$(stat -Lc '%#a %U' "$pdir" 2>/dev/null)"
                [[ "$u" != "root" ]] && path_issues+=("Directory '${pdir}' is owned by '${u}' (should be root)")
                [[ $(( m & pmask )) -gt 0 ]] && path_issues+=("Directory '${pdir}' is mode ${m} (should be 0755 or more restrictive)")
            else
                path_issues+=("'${pdir}' in root PATH is not a directory")
            fi
        done
        if [[ "${#path_issues[@]}" -eq 0 ]]; then
            report_ok "5.4.2.5" "Ensure root path integrity" "L1" "Automated"
        else
            report_fail "5.4.2.5" "Ensure root path integrity" "L1" "Automated" \
                "$(IFS='; '; echo "${path_issues[*]}")" \
                "Fix root's PATH in /root/.profile, /root/.bashrc, /etc/profile, and /etc/environment to remove '.', '::', trailing ':', and fix directory ownership/permissions ('chown root:root <dir> && chmod go-w <dir>')."
        fi
    fi

    # 5.4.2.6 Ensure root user umask is configured (Automated)
    if should_run_check "5.4.2.6" "L1"; then
        local bad_root_umask
        bad_root_umask="$(grep -Psi -- '^\h*umask\h+((\d{1,2}(\d[^7]|[^2-7]\d)\b)|(u=[rwx]{1,3},)?(((g=[rx]?[rx]?w[rx]?[rx]?\b)(,o=[rwx]{1,3})?)|((g=[wrx]{1,3},)?o=[wrx]{1,3}\b)))' /root/.profile /root/.bashrc 2>/dev/null || true)"
        if [[ -z "$bad_root_umask" ]]; then
            report_ok "5.4.2.6" "Ensure root user umask is configured" "L1" "Automated"
        else
            report_fail "5.4.2.6" "Ensure root user umask is configured" "L1" "Automated" \
                "Permissive umask found in /root/.profile or /root/.bashrc: ${bad_root_umask}" \
                "Edit /root/.profile and /root/.bashrc to set 'umask 027' (or more restrictive) or remove permissive umask lines."
        fi
    fi

    # 5.4.2.7 Ensure system accounts do not have a valid login shell (Automated)
    if should_run_check "5.4.2.7" "L1"; then
        local valid_shells bad_sys_accts
        valid_shells="^($(awk -F/ '$NF != "nologin" {print}' /etc/shells 2>/dev/null | sed -rn '/^\//{s,/,\\\\/,g;p}' | paste -s -d '|' - ))$"
        bad_sys_accts="$(awk -v pat="$valid_shells" -v umin="$UID_MIN_VAL" -F: '($1!~/^(root|halt|sync|shutdown|nfsnobody)$/ && ($3<umin || $3 == 65534) && $(NF) ~ pat) {print $1 ":" $7}' /etc/passwd 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -z "$bad_sys_accts" ]]; then
            report_ok "5.4.2.7" "Ensure system accounts do not have a valid login shell" "L1" "Automated"
        else
            report_fail "5.4.2.7" "Ensure system accounts do not have a valid login shell" "L1" "Automated" \
                "System accounts with valid login shells: [${bad_sys_accts% }]" \
                "Run: usermod -s \$(command -v nologin) <user> for each listed system account."
        fi
    fi

    # 5.4.2.8 Ensure accounts without a valid login shell are locked (Automated)
    if should_run_check "5.4.2.8" "L1"; then
        local valid_shells unlocked_nologin=() u
        valid_shells="^($(awk -F/ '$NF != "nologin" {print}' /etc/shells 2>/dev/null | sed -rn '/^\//{s,/,\\\\/,g;p}' | paste -s -d '|' - ))$"
        while IFS= read -r u; do
            [[ -z "$u" ]] && continue
            local st
            st="$(passwd -S "$u" 2>/dev/null | awk '$2 !~ /^L/ {print $1 ":" $2}' || true)"
            if [[ -z "$st" && -r /etc/shadow ]]; then
                st="$(awk -F: -v usr="$u" '$1==usr && $2 !~ /^(!|\*)/ {print $1}' /etc/shadow 2>/dev/null || true)"
            fi
            [[ -n "$st" ]] && unlocked_nologin+=("$st")
        done < <(awk -v pat="$valid_shells" -F: '($1 != "root" && $(NF) !~ pat) {print $1}' /etc/passwd 2>/dev/null)
        if [[ "${#unlocked_nologin[@]}" -eq 0 ]]; then
            report_ok "5.4.2.8" "Ensure accounts without a valid login shell are locked" "L1" "Automated"
        else
            report_fail "5.4.2.8" "Ensure accounts without a valid login shell are locked" "L1" "Automated" \
                "Accounts without valid login shell that are not locked: [${unlocked_nologin[*]}]" \
                "Run: usermod -L <user> for each listed account."
        fi
    fi

    # 5.4.3.1 Ensure nologin is not listed in /etc/shells (Automated)
    if should_run_check "5.4.3.1" "L2"; then
        local nologin_in_shells
        nologin_in_shells="$(grep -Ps '^\h*([^#\n\r]+)?\/nologin\b' /etc/shells 2>/dev/null || true)"
        if [[ -z "$nologin_in_shells" ]]; then
            report_ok "5.4.3.1" "Ensure nologin is not listed in /etc/shells" "L2" "Automated"
        else
            report_fail "5.4.3.1" "Ensure nologin is not listed in /etc/shells" "L2" "Automated" \
                "nologin listed in /etc/shells: ${nologin_in_shells}" \
                "Edit /etc/shells and remove any lines containing 'nologin'."
        fi
    fi

    # 5.4.3.2 Ensure default user shell timeout is configured (Automated)
    if should_run_check "5.4.3.2" "L1"; then
        local tmout_ok=0 tmout_bad=() tf
        while IFS= read -r tf; do
            [[ -f "$tf" ]] || continue
            local tval tread texp
            tval="$(grep -Po -- '^([^#\n\r]+)?\bTMOUT=\K\d+\b' "$tf" 2>/dev/null | tail -n 1 || true)"
            tread="$(grep -P -- '^\h*(typeset\h+-xr\h+TMOUT=\d+|([^#\n\r]+)?\breadonly\h+TMOUT\b)' "$tf" 2>/dev/null || true)"
            texp="$(grep -P -- '^\h*(typeset\h+-xr\h+TMOUT=\d+|([^#\n\r]+)?\bexport\b([^#\n\r]+\b)?TMOUT\b)' "$tf" 2>/dev/null || true)"
            if [[ -n "$tval" && "$tval" -gt 0 && "$tval" -le 900 && -n "$tread" && -n "$texp" ]]; then
                tmout_ok=1
            else
                tmout_bad+=("${tf} (TMOUT=${tval:-unset}, readonly=${tread:+yes}, export=${texp:+yes})")
            fi
        done < <(grep -Pls -- '^([^#\n\r]+)?\bTMOUT\b' /etc/*bashrc /etc/profile /etc/profile.d/*.sh 2>/dev/null)
        if [[ "$tmout_ok" -eq 1 && "${#tmout_bad[@]}" -eq 0 ]]; then
            report_ok "5.4.3.2" "Ensure default user shell timeout is configured" "L1" "Automated"
        else
            report_fail "5.4.3.2" "Ensure default user shell timeout is configured" "L1" "Automated" \
                "TMOUT is not properly configured (1..900, readonly, exported): ${tmout_bad[*]:-not set}" \
                "Run: printf '%s\n' '# Set TMOUT to 900 seconds' 'typeset -xr TMOUT=900' > /etc/profile.d/50-tmout.sh"
        fi
    fi

    # 5.4.3.3 Ensure default user umask is configured (Automated)
    if should_run_check "5.4.3.3" "L1"; then
        local umask_bad1 umask_bad2 umask_set
        umask_bad1="$(grep -PHsi -- '^\h*umask\h+(?!0?[02367]7\b)' /etc/profile /etc/profile.d/*.sh /etc/bash.bashrc 2>/dev/null || true)"
        umask_bad2="$(grep -PHsi -- '^\h*UMASK\h+(?!0?[02367]7\b)' /etc/login.defs 2>/dev/null || true)"
        umask_set="$(grep -PHsi -- '^\h*(umask|UMASK)\h+0?[02367]7\b' /etc/profile /etc/profile.d/*.sh /etc/login.defs 2>/dev/null || true)"
        if [[ -z "$umask_bad1" && -z "$umask_bad2" && -n "$umask_set" ]]; then
            report_ok "5.4.3.3" "Ensure default user umask is configured" "L1" "Automated"
        else
            report_fail "5.4.3.3" "Ensure default user umask is configured" "L1" "Automated" \
                "Permissive umask found (${umask_bad1} ${umask_bad2}) or 027 umask not configured" \
                "Set 'UMASK 027' in /etc/login.defs and run: printf '\n%s\n' 'umask 027' >> /etc/profile.d/60-default_umask.sh"
        fi
    fi
}
# ==============================================================================
# SECTION 6: LOGGING AND AUDITING
# ==============================================================================
run_section_6() {
    print_section_header "6" "Logging and Auditing" || return 0

    # --------------------------------------------------------------------------
    # 6.1.1 Configure journald
    # --------------------------------------------------------------------------
    print_subsection_header "6.1.1 Configure journald"

    # 6.1.1.1.1 Ensure journald service is active (Automated)
    if should_run_check "6.1.1.1.1" "L1"; then
        if [[ "$(systemctl is-active systemd-journald.service 2>/dev/null || true)" == "active" ]]; then
            report_ok "6.1.1.1.1" "Ensure journald service is active" "L1" "Automated"
        else
            report_fail "6.1.1.1.1" "Ensure journald service is active" "L1" "Automated" \
                "systemd-journald.service is not active" \
                "Run: systemctl unmask systemd-journald.service && systemctl --now enable systemd-journald.service"
        fi
    fi

    # 6.1.1.1.2 Ensure systemd-journal-remote service is not in use (Automated)
    if should_run_check "6.1.1.1.2" "L1"; then
        local jr_en jr_act
        jr_en="$(systemctl is-enabled systemd-journal-remote.socket systemd-journal-remote.service 2>/dev/null | grep -P '^enabled' || true)"
        jr_act="$(systemctl is-active systemd-journal-remote.socket systemd-journal-remote.service 2>/dev/null | grep -P '^active' || true)"
        if [[ -z "$jr_en" && -z "$jr_act" ]]; then
            report_ok "6.1.1.1.2" "Ensure systemd-journal-remote service is not in use" "L1" "Automated"
        else
            report_fail "6.1.1.1.2" "Ensure systemd-journal-remote service is not in use" "L1" "Automated" \
                "systemd-journal-remote.socket/.service is enabled or active" \
                "Run: systemctl stop systemd-journal-remote.socket systemd-journal-remote.service && systemctl mask systemd-journal-remote.socket systemd-journal-remote.service"
        fi
    fi

    # 6.1.1.1.3 Ensure journald is configured to send logs to rsyslog (Automated)
    if should_run_check "6.1.1.1.3" "L1"; then
        local fwd_sys
        fwd_sys="$(grep -PRsi -- '^\h*ForwardToSyslog\h*=\h*yes\b' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/ 2>/dev/null || true)"
        if [[ -n "$fwd_sys" ]]; then
            report_ok "6.1.1.1.3" "Ensure journald is configured to send logs to rsyslog" "L1" "Automated"
        else
            report_fail "6.1.1.1.3" "Ensure journald is configured to send logs to rsyslog" "L1" "Automated" \
                "ForwardToSyslog=yes is not configured in /etc/systemd/journald.conf or /etc/systemd/journald.conf.d/*.conf" \
                "Create /etc/systemd/journald.conf.d/60-journald.conf with '[Journal]' and 'ForwardToSyslog=yes', then run: systemctl reload-or-restart systemd-journald.service"
        fi
    fi

    # 6.1.1.1.4 Ensure journald log file access is configured (Manual)
    if should_run_check "6.1.1.1.4" "L1"; then
        local j_perm_bad=() tf
        for tf in /etc/tmpfiles.d/systemd.conf /usr/lib/tmpfiles.d/systemd.conf; do
            [[ -f "$tf" ]] || continue
            while read -r type path perm _; do
                if [[ "$type" == "f" && "$perm" =~ ^0?[0-7]{3,4}$ && -f "$path" ]]; then
                    local actual
                    actual="$(stat -c '%a' "$path" 2>/dev/null || echo 0)"
                    if [[ $(( 0$actual & 0137 )) -ne 0 ]]; then
                        j_perm_bad+=("${path} (mode ${actual} in ${tf})")
                    fi
                fi
            done < "$tf"
        done
        if [[ "${#j_perm_bad[@]}" -eq 0 ]]; then
            report_ok "6.1.1.1.4" "Ensure journald log file access is configured" "L1" "Manual" "All tmpfiles.d journald log files are 0640 or more restrictive"
        else
            report_manual "6.1.1.1.4" "Ensure journald log file access is configured" "L1" "Manual" \
                "Journald log files more permissive than 0640: ${j_perm_bad[*]}" \
                "Copy /usr/lib/tmpfiles.d/systemd.conf to /etc/tmpfiles.d/systemd.conf and set log file permissions to 0640 or more restrictive."
        fi
    fi

    # 6.1.1.1.5 Ensure journald log file rotation is configured (Manual)
    if should_run_check "6.1.1.1.5" "L1"; then
        local j_rot
        j_rot="$(grep -PRsi -- '^\h*(SystemMaxUse|SystemKeepFree|RuntimeMaxUse|RuntimeKeepFree|MaxFileSec)\h*=\h*\S+' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/ 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -n "$j_rot" ]]; then
            report_ok "6.1.1.1.5" "Ensure journald log file rotation is configured" "L1" "Manual" "${j_rot% }"
        else
            report_manual "6.1.1.1.5" "Ensure journald log file rotation is configured" "L1" "Manual" \
                "Journald rotation parameters (SystemMaxUse, SystemKeepFree, RuntimeMaxUse, RuntimeKeepFree, MaxFileSec) are not explicitly configured" \
                "Configure SystemMaxUse, SystemKeepFree, RuntimeMaxUse, RuntimeKeepFree, and MaxFileSec under [Journal] in /etc/systemd/journald.conf.d/60-journald.conf and run: systemctl reload-or-restart systemd-journald"
        fi
    fi

    # 6.1.1.1.6 Ensure journald Storage is configured (Automated)
    if should_run_check "6.1.1.1.6" "L1"; then
        if grep -PRsiq -- '^\h*Storage\h*=\h*persistent\b' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/ 2>/dev/null; then
            report_ok "6.1.1.1.6" "Ensure journald Storage is configured" "L1" "Automated"
        else
            report_fail "6.1.1.1.6" "Ensure journald Storage is configured" "L1" "Automated" \
                "Storage=persistent is not configured in /etc/systemd/journald.conf or /etc/systemd/journald.conf.d/*.conf" \
                "Add '[Journal]' and 'Storage=persistent' to /etc/systemd/journald.conf.d/60-journald.conf and run: systemctl reload-or-restart systemd-journald"
        fi
    fi

    # 6.1.1.1.7 Ensure journald Compress is configured (Automated)
    if should_run_check "6.1.1.1.7" "L1"; then
        if grep -PRsiq -- '^\h*Compress\h*=\h*yes\b' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/ 2>/dev/null; then
            report_ok "6.1.1.1.7" "Ensure journald Compress is configured" "L1" "Automated"
        else
            report_fail "6.1.1.1.7" "Ensure journald Compress is configured" "L1" "Automated" \
                "Compress=yes is not explicitly configured in /etc/systemd/journald.conf or /etc/systemd/journald.conf.d/*.conf" \
                "Add '[Journal]' and 'Compress=yes' to /etc/systemd/journald.conf.d/60-journald.conf and run: systemctl reload-or-restart systemd-journald"
        fi
    fi

    # --------------------------------------------------------------------------
    # 6.1.2 Configure rsyslog
    # --------------------------------------------------------------------------
    print_subsection_header "6.1.2 Configure rsyslog"

    # 6.1.2.1 Ensure rsyslog is installed (Automated)
    if should_run_check "6.1.2.1" "L1"; then
        if dpkg-query -s rsyslog &>/dev/null; then
            report_ok "6.1.2.1" "Ensure rsyslog is installed" "L1" "Automated"
        else
            report_fail "6.1.2.1" "Ensure rsyslog is installed" "L1" "Automated" \
                "Package 'rsyslog' is not installed" \
                "Run: apt install -y rsyslog"
        fi
    fi

    # 6.1.2.2 Ensure rsyslog service is enabled and active (Automated)
    if should_run_check "6.1.2.2" "L1"; then
        local rs_en rs_act
        rs_en="$(systemctl is-enabled rsyslog.service 2>/dev/null || true)"
        rs_act="$(systemctl is-active rsyslog.service 2>/dev/null || true)"
        if [[ "$rs_en" == "enabled" && "$rs_act" == "active" ]]; then
            report_ok "6.1.2.2" "Ensure rsyslog service is enabled and active" "L1" "Automated"
        else
            report_fail "6.1.2.2" "Ensure rsyslog service is enabled and active" "L1" "Automated" \
                "rsyslog.service enabled=${rs_en:-no}, active=${rs_act:-no}" \
                "Run: systemctl unmask rsyslog.service && systemctl --now enable rsyslog.service"
        fi
    fi

    # 6.1.2.3 Ensure rsyslog log file creation mode is configured (Automated)
    if should_run_check "6.1.2.3" "L1"; then
        local fcm_vals fcm_ok=0 fcm_bad=0 m
        fcm_vals="$(grep -Phsi -- '^\h*\$FileCreateMode\h+\K0[0-7]{3}\b' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null || true)"
        for m in $fcm_vals; do
            if [[ $(( m & 0137 )) -eq 0 ]]; then
                fcm_ok=1
            else
                fcm_bad=1
            fi
        done
        if [[ "$fcm_ok" -eq 1 && "$fcm_bad" -eq 0 ]]; then
            report_ok "6.1.2.3" "Ensure rsyslog log file creation mode is configured" "L1" "Automated"
        else
            report_fail "6.1.2.3" "Ensure rsyslog log file creation mode is configured" "L1" "Automated" \
                "\$FileCreateMode is not set to 0640 or more restrictive (found: ${fcm_vals:-none})" \
                "Add '\$FileCreateMode 0640' to /etc/rsyslog.conf or /etc/rsyslog.d/60-cis.conf and run: systemctl restart rsyslog"
        fi
    fi

    # 6.1.2.4 Ensure rsyslog logging is configured (Manual)
    if should_run_check "6.1.2.4" "L1"; then
        local auth_rule
        auth_rule="$(grep -PRsi 'auth,authpriv\.\*' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -n "$auth_rule" ]]; then
            report_ok "6.1.2.4" "Ensure rsyslog logging is configured" "L1" "Manual" "${auth_rule% }"
        else
            report_manual "6.1.2.4" "Ensure rsyslog logging is configured" "L1" "Manual" \
                "Standard rsyslog facility rules (e.g. auth,authpriv.*) not found in /etc/rsyslog.conf or /etc/rsyslog.d/*.conf" \
                "Configure logging rules in /etc/rsyslog.conf or /etc/rsyslog.d/50-default.conf (e.g., 'auth,authpriv.* /var/log/auth.log') and restart rsyslog."
        fi
    fi

    # 6.1.2.5 Ensure rsyslog is configured to send logs to a remote log host (Manual)
    if should_run_check "6.1.2.5" "L1"; then
        local rem_basic rem_adv
        rem_basic="$(grep -Psi -- '^\h*\*\.\*\h+@{1,2}\H+' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null || true)"
        rem_adv="$(grep -Psiz -- '^\s*([^#]+\s+)?action\(([^#]+\s+)?\btarget=\"?[^#\"]+\"?\b' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null | tr '\0' '\n' || true)"
        if [[ -n "$rem_basic" || -n "$rem_adv" ]]; then
            report_ok "6.1.2.5" "Ensure rsyslog is configured to send logs to a remote log host" "L1" "Manual"
        else
            report_manual "6.1.2.5" "Ensure rsyslog is configured to send logs to a remote log host" "L1" "Manual" \
                "No remote log host forwarding rule found in /etc/rsyslog.conf or /etc/rsyslog.d/*.conf" \
                "Add '*.* action(type=\"omfwd\" target=\"loghost.example.com\" port=\"514\" protocol=\"tcp\" action.resumeRetryCount=\"100\" queue.type=\"LinkedList\" queue.size=\"1000\")' to /etc/rsyslog.d/60-remote.conf and restart rsyslog."
        fi
    fi

    # 6.1.2.6 Ensure rsyslog is not configured to receive logs from a remote client (Automated)
    if should_run_check "6.1.2.6" "L1"; then
        local rcv_cfg
        rcv_cfg="$(grep -Psi -- '^\h*(module\(load=\"?im(tcp|udp)\"?\)|input\(type=\"?im(tcp|udp)\"?\b|\$ModLoad\h+im(tcp|udp)\b|\$(InputTCP|UDP)ServerRun\b)' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null || true)"
        if [[ -z "$rcv_cfg" ]]; then
            report_ok "6.1.2.6" "Ensure rsyslog is not configured to receive logs from a remote client" "L1" "Automated"
        else
            report_fail "6.1.2.6" "Ensure rsyslog is not configured to receive logs from a remote client" "L1" "Automated" \
                "Remote log reception enabled in rsyslog: ${rcv_cfg}" \
                "Remove or comment out imtcp/imudp module/input lines and \$InputTCPServerRun/\$UDPServerRun from /etc/rsyslog.conf and /etc/rsyslog.d/*.conf, then run: systemctl restart rsyslog"
        fi
    fi

    # 6.1.2.7 Ensure logrotate is configured (Manual)
    if should_run_check "6.1.2.7" "L1"; then
        if [[ -f /etc/logrotate.conf && -f /etc/logrotate.d/rsyslog ]]; then
            report_ok "6.1.2.7" "Ensure logrotate is configured" "L1" "Manual" "/etc/logrotate.conf and /etc/logrotate.d/rsyslog present"
        else
            report_manual "6.1.2.7" "Ensure logrotate is configured" "L1" "Manual" \
                "/etc/logrotate.conf or /etc/logrotate.d/rsyslog is missing" \
                "Review and configure /etc/logrotate.conf and /etc/logrotate.d/* in accordance with site policy."
        fi
    fi

    # 6.1.2.8 Ensure rsyslog-gnutls is installed (Automated)
    if should_run_check "6.1.2.8" "L2"; then
        if dpkg-query -s rsyslog-gnutls &>/dev/null || dpkg-query -s rsyslog-openssl &>/dev/null; then
            report_ok "6.1.2.8" "Ensure rsyslog-gnutls is installed" "L2" "Automated"
        else
            report_fail "6.1.2.8" "Ensure rsyslog-gnutls is installed" "L2" "Automated" \
                "Package 'rsyslog-gnutls' is not installed" \
                "Run: apt install -y rsyslog-gnutls"
        fi
    fi

    # 6.1.2.9 Ensure rsyslog forwarding uses gtls (Automated)
    if should_run_check "6.1.2.9" "L2"; then
        if grep -Psiq -- '^[^#]*StreamDriver\s*=\s*"?(gtls|ossl)"?' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
            report_ok "6.1.2.9" "Ensure rsyslog forwarding uses gtls" "L2" "Automated"
        else
            report_fail "6.1.2.9" "Ensure rsyslog forwarding uses gtls" "L2" "Automated" \
                "StreamDriver=\"gtls\" is not configured in /etc/rsyslog.conf or /etc/rsyslog.d/*.conf" \
                "Configure 'StreamDriver=\"gtls\" StreamDriverMode=\"1\" StreamDriverAuthMode=\"anon\"' in the omfwd action block in /etc/rsyslog.d/40-forward.conf and restart rsyslog."
        fi
    fi

    # 6.1.2.10 Ensure rsyslog CA certificates are configured (Manual)
    if should_run_check "6.1.2.10" "L2"; then
        local ca_files
        ca_files="$(grep -PEsi -- '(DefaultNetstreamDriverCAFile|StreamDriver\.CAFile)\s*=' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null || true)"
        if [[ -n "$ca_files" ]]; then
            report_ok "6.1.2.10" "Ensure rsyslog CA certificates are configured" "L2" "Manual" "${ca_files}"
        else
            report_manual "6.1.2.10" "Ensure rsyslog CA certificates are configured" "L2" "Manual" \
                "DefaultNetstreamDriverCAFile / StreamDriver.CAFile is not configured in rsyslog" \
                "Add 'global(DefaultNetstreamDriverCAFile=\"/etc/ssl/certs/ca-certificates.crt\")' to /etc/rsyslog.d/40-forward.conf and run: systemctl restart rsyslog"
        fi
    fi

    # --------------------------------------------------------------------------
    # 6.1.3 Configure Logfiles
    # --------------------------------------------------------------------------
    print_subsection_header "6.1.3 Configure Logfiles"

    # 6.1.3.1 Ensure access to all logfiles has been configured (Automated)
    if should_run_check "6.1.3.1" "L1"; then
        local bad_logs=() l_file
        while IFS= read -r -d $'\0' l_file; do
            local fname mode usr grp pmask="0137" auser="(root|syslog)" agrp="(root|adm)"
            IFS=: read -r fname mode usr grp <<< "$(stat -Lc '%n:%#a:%U:%G' "$l_file" 2>/dev/null)"
            if grep -Pq '\/(apt)\h*$' <<< "$(dirname "$fname")"; then
                pmask="0133"; auser="root"; agrp="(root|adm)"
            else
                case "$(basename "$fname")" in
                    lastlog|lastlog.*|wtmp|wtmp.*|wtmp-*|btmp|btmp.*|btmp-*|README)
                        pmask="0113"; auser="root"; agrp="(root|utmp)" ;;
                    cloud-init.log*|localmessages*|waagent.log*)
                        pmask="0133"; auser="(root|syslog)"; agrp="(root|adm)" ;;
                    secure*|auth.log|syslog|messages)
                        pmask="0137"; auser="(root|syslog)"; agrp="(root|adm)" ;;
                    SSSD|sssd)
                        pmask="0117"; auser="(root|SSSD)"; agrp="(root|SSSD)" ;;
                    gdm|gdm3)
                        pmask="0117"; auser="root"; agrp="(root|gdm|gdm3)" ;;
                    *.journal|*.journal~)
                        pmask="0137"; auser="root"; agrp="(root|systemd-journal)" ;;
                    *)
                        pmask="0137"; auser="(root|syslog)"; agrp="(root|adm)"
                        local ushell
                        ushell="$(awk -F: -v u="$usr" '$1==u {print $7}' /etc/passwd 2>/dev/null || true)"
                        if [[ "$usr" == "root" ]] || ! grep -Pq "^\h*${ushell}\b" /etc/shells 2>/dev/null; then
                            [[ ! "$usr" =~ ^$auser$ ]] && auser="(root|syslog|${usr})"
                            [[ ! "$grp" =~ ^$agrp$ ]] && agrp="(root|adm|${grp})"
                        fi ;;
                esac
            fi
            if [[ $(( mode & pmask )) -gt 0 ]] || [[ ! "$usr" =~ ^$auser$ ]] || [[ ! "$grp" =~ ^$agrp$ ]]; then
                bad_logs+=("${fname} (${mode} ${usr}:${grp})")
            fi
        done < <(find -L /var/log -type f \( -perm /0137 -o ! -user root -o ! -group root \) -print0 2>/dev/null)
        if [[ "${#bad_logs[@]}" -eq 0 ]]; then
            report_ok "6.1.3.1" "Ensure access to all logfiles has been configured" "L1" "Automated"
        else
            report_fail "6.1.3.1" "Ensure access to all logfiles has been configured" "L1" "Automated" \
                "Found ${#bad_logs[@]} log file(s) with excessive permissions/ownership (e.g. ${bad_logs[0]})" \
                "Run: find /var/log -type f -perm /0137 -exec chmod u-x,g-wx,o-rwx {} + and ensure logrotate files use 'create 0640 root adm'."
        fi
    fi

    # --------------------------------------------------------------------------
    # 6.2 System Auditing
    # --------------------------------------------------------------------------
    print_subsection_header "6.2 System Auditing (auditd)"

    # 6.2.1.1 Ensure auditd packages are installed (Automated)
    if should_run_check "6.2.1.1" "L2"; then
        if dpkg-query -s auditd &>/dev/null && dpkg-query -s audispd-plugins &>/dev/null; then
            report_ok "6.2.1.1" "Ensure auditd packages are installed" "L2" "Automated"
        else
            report_fail "6.2.1.1" "Ensure auditd packages are installed" "L2" "Automated" \
                "Package 'auditd' and/or 'audispd-plugins' is not installed" \
                "Run: apt install -y auditd audispd-plugins"
        fi
    fi

    # 6.2.1.2 Ensure auditd service is enabled and active (Automated)
    if should_run_check "6.2.1.2" "L2"; then
        local au_en au_act
        au_en="$(systemctl is-enabled auditd 2>/dev/null | grep '^enabled' || true)"
        au_act="$(systemctl is-active auditd 2>/dev/null | grep '^active' || true)"
        if [[ "$au_en" == "enabled" && "$au_act" == "active" ]]; then
            report_ok "6.2.1.2" "Ensure auditd service is enabled and active" "L2" "Automated"
        else
            report_fail "6.2.1.2" "Ensure auditd service is enabled and active" "L2" "Automated" \
                "auditd is enabled=${au_en:-no}, active=${au_act:-no}" \
                "Run: systemctl unmask auditd && systemctl enable auditd && systemctl start auditd"
        fi
    fi

    # 6.2.1.3 Ensure auditing for processes that start prior to auditd is enabled (Automated)
    if should_run_check "6.2.1.3" "L2"; then
        local grub_files no_audit1
        grub_files="$(find /boot -type f -name 'grub.cfg' 2>/dev/null || true)"
        no_audit1="$(find /boot -type f -name 'grub.cfg' -exec grep -Ph -- '^\h*linux' {} + 2>/dev/null | grep -v 'audit=1' || true)"
        if [[ -n "$grub_files" && -z "$no_audit1" ]]; then
            report_ok "6.2.1.3" "Ensure auditing for processes that start prior to auditd is enabled" "L2" "Automated"
        else
            report_fail "6.2.1.3" "Ensure auditing for processes that start prior to auditd is enabled" "L2" "Automated" \
                "Kernel boot lines missing 'audit=1' or grub.cfg not found" \
                "Append 'audit=1' to GRUB_CMDLINE_LINUX in /etc/default/grub (or /etc/default/grub.d/40-custom.cfg) and run: update-grub"
        fi
    fi

    # 6.2.1.4 Ensure audit_backlog_limit is configured (Automated)
    if should_run_check "6.2.1.4" "L2"; then
        local grub_files no_abl
        grub_files="$(find /boot -type f -name 'grub.cfg' 2>/dev/null || true)"
        no_abl="$(find /boot -type f -name 'grub.cfg' -exec grep -Ph -- '^\h*linux' {} + 2>/dev/null | grep -Pv 'audit_backlog_limit=(819[2-9]|8[2-9][0-9]{2}|9[0-9]{3}|[1-9][0-9]{4,})\b' || true)"
        if [[ -n "$grub_files" && -z "$no_abl" ]]; then
            report_ok "6.2.1.4" "Ensure audit_backlog_limit is configured" "L2" "Automated"
        else
            report_fail "6.2.1.4" "Ensure audit_backlog_limit is configured" "L2" "Automated" \
                "Kernel boot lines missing 'audit_backlog_limit=<N>' (recommended >= 8192)" \
                "Append 'audit_backlog_limit=8192' to GRUB_CMDLINE_LINUX in /etc/default/grub (or /etc/default/grub.d/40-custom.cfg) and run: update-grub"
        fi
    fi

    # --------------------------------------------------------------------------
    # 6.2.2 Configure Data Retention
    # --------------------------------------------------------------------------
    print_subsection_header "6.2.2 Configure Data Retention"

    # 6.2.2.1 Ensure audit log storage size is configured (Automated)
    if should_run_check "6.2.2.1" "L2"; then
        local mlf
        mlf="$(grep -Po -- '^\h*max_log_file\h*=\h*\K\d+\b' /etc/audit/auditd.conf 2>/dev/null || true)"
        if [[ -n "$mlf" && "$mlf" -gt 0 ]]; then
            report_ok "6.2.2.1" "Ensure audit log storage size is configured" "L2" "Automated" "max_log_file = ${mlf}"
        else
            report_fail "6.2.2.1" "Ensure audit log storage size is configured" "L2" "Automated" \
                "max_log_file is not configured in /etc/audit/auditd.conf" \
                "Set 'max_log_file = 8' (or larger per site policy) in /etc/audit/auditd.conf."
        fi
    fi

    # 6.2.2.2 Ensure audit logs are not automatically deleted (Automated)
    if should_run_check "6.2.2.2" "L2"; then
        if grep -Piq -- '^\h*max_log_file_action\h*=\h*keep_logs\b' /etc/audit/auditd.conf 2>/dev/null; then
            report_ok "6.2.2.2" "Ensure audit logs are not automatically deleted" "L2" "Automated"
        else
            report_fail "6.2.2.2" "Ensure audit logs are not automatically deleted" "L2" "Automated" \
                "max_log_file_action is not set to keep_logs in /etc/audit/auditd.conf" \
                "Set 'max_log_file_action = keep_logs' in /etc/audit/auditd.conf."
        fi
    fi

    # 6.2.2.3 Ensure system is disabled when audit logs are full (Automated)
    if should_run_check "6.2.2.3" "L2"; then
        local dfa dea
        dfa="$(grep -Pi -- '^\h*disk_full_action\h*=\h*(halt|single)\b' /etc/audit/auditd.conf 2>/dev/null || true)"
        dea="$(grep -Pi -- '^\h*disk_error_action\h*=\h*(syslog|single|halt)\b' /etc/audit/auditd.conf 2>/dev/null || true)"
        if [[ -n "$dfa" && -n "$dea" ]]; then
            report_ok "6.2.2.3" "Ensure system is disabled when audit logs are full" "L2" "Automated"
        else
            report_fail "6.2.2.3" "Ensure system is disabled when audit logs are full" "L2" "Automated" \
                "disk_full_action (need halt|single) and/or disk_error_action (need syslog|single|halt) not properly set in /etc/audit/auditd.conf" \
                "Set 'disk_full_action = halt' (or single) and 'disk_error_action = halt' (or single/syslog) in /etc/audit/auditd.conf."
        fi
    fi

    # 6.2.2.4 Ensure system warns when audit logs are low on space (Automated)
    if should_run_check "6.2.2.4" "L2"; then
        local sla asla
        sla="$(grep -Pi -- '^\h*space_left_action\h*=\h*(email|exec|single|halt)\b' /etc/audit/auditd.conf 2>/dev/null || true)"
        asla="$(grep -Pi -- '^\h*admin_space_left_action\h*=\h*(single|halt)\b' /etc/audit/auditd.conf 2>/dev/null || true)"
        if [[ -n "$sla" && -n "$asla" ]]; then
            report_ok "6.2.2.4" "Ensure system warns when audit logs are low on space" "L2" "Automated"
        else
            report_fail "6.2.2.4" "Ensure system warns when audit logs are low on space" "L2" "Automated" \
                "space_left_action (need email|exec|single|halt) and/or admin_space_left_action (need single|halt) not properly set in /etc/audit/auditd.conf" \
                "Set 'space_left_action = email' and 'admin_space_left_action = single' (or halt) in /etc/audit/auditd.conf."
        fi
    fi

    # --------------------------------------------------------------------------
    # 6.2.3 Configure auditd Rules
    # --------------------------------------------------------------------------
    print_subsection_header "6.2.3 Configure auditd Rules"

    # Multi-pattern audit rule validator: verifies every required pattern exists both on disk (/etc/audit/rules.d/*.rules) and in running auditctl -l
    check_audit_rule_multi() {
        local id="$1"
        local title="$2"
        local rem_rule="$3"
        local rule_file="$4"
        shift 4
        local patterns=("$@")

        should_run_check "$id" "L2" || return 0

        local missing_disk=() missing_run=() pat
        for pat in "${patterns[@]}"; do
            grep -PRsq -- "$pat" /etc/audit/rules.d/*.rules 2>/dev/null || missing_disk+=("$pat")
            grep -Psq -- "$pat" <<< "$AUDITCTL_L_CACHE" || missing_run+=("$pat")
        done

        if [[ "${#missing_disk[@]}" -eq 0 && "${#missing_run[@]}" -eq 0 ]]; then
            report_ok "$id" "$title" "L2" "Automated"
        else
            local reason=""
            [[ "${#missing_disk[@]}" -gt 0 ]] && reason+="Missing in /etc/audit/rules.d/*.rules (${#missing_disk[@]}/${#patterns[@]} pattern(s)); "
            [[ "${#missing_run[@]}" -gt 0 ]] && reason+="Not loaded in running auditctl -l (${#missing_run[@]}/${#patterns[@]} pattern(s))."
            report_fail "$id" "$title" "L2" "Automated" \
                "$reason" \
                "Add '${rem_rule}' to ${rule_file} and run: augenrules --load"
        fi
    }

    # 6.2.3.1 Ensure modification of the /etc/sudoers file is collected
    check_audit_rule_multi "6.2.3.1" "Ensure modification of the /etc/sudoers file is collected" \
        '-a always,exit -F arch=b64 -F path=/etc/sudoers -F perm=wa -k scope && -a always,exit -F arch=b64 -F dir=/etc/sudoers.d -F perm=wa -k scope' \
        '/etc/audit/rules.d/50-scope.rules' \
        '/etc/sudoers\b' '/etc/sudoers\.d\b'

    # 6.2.3.2 Ensure actions as another user are always logged
    check_audit_rule_multi "6.2.3.2" "Ensure actions as another user are always logged" \
        '-a always,exit -F arch=b64 -C euid!=uid -F auid!=unset -S execve -k user_emulation (and arch=b32)' \
        '/etc/audit/rules.d/50-user_emulation.rules' \
        'arch=b64.*execve' 'arch=b32.*execve'

    # 6.2.3.3 Ensure events that modify the sudo log file are collected
    check_audit_rule_multi "6.2.3.3" "Ensure events that modify the sudo log file are collected" \
        '-a always,exit -F arch=b64 -F path=/var/log/sudo.log -F perm=wa -k sudo_log_file' \
        '/etc/audit/rules.d/50-sudo.rules' \
        'sudo\.log'

    # 6.2.3.4 Ensure events that modify date and time information are collected
    check_audit_rule_multi "6.2.3.4" "Ensure events that modify date and time information are collected" \
        '-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time-change (and arch=b32) && -a always,exit -F arch=b64 -F path=/etc/localtime -F perm=wa -k localtime-change' \
        '/etc/audit/rules.d/50-time-change.rules' \
        'adjtimex' 'settimeofday' 'clock_settime' '/etc/localtime'

    # 6.2.3.5 Ensure events that modify sethostname and setdomainname are collected
    check_audit_rule_multi "6.2.3.5" "Ensure events that modify sethostname and setdomainname are collected" \
        '-a always,exit -F arch=b64 -S sethostname,setdomainname -k system-locale (and arch=b32)' \
        '/etc/audit/rules.d/50-system_locale.rules' \
        'sethostname' 'setdomainname'

    # 6.2.3.6 Ensure events that modify /etc/issue and /etc/issue.net are collected
    check_audit_rule_multi "6.2.3.6" "Ensure events that modify /etc/issue and /etc/issue.net are collected" \
        '-a always,exit -F arch=b64 -F path=/etc/issue -F perm=wa -k system-locale && -a always,exit -F arch=b64 -F path=/etc/issue.net -F perm=wa -k system-locale' \
        '/etc/audit/rules.d/50-etc_issue_system_locale.rules' \
        '/etc/issue\b' '/etc/issue\.net\b'

    # 6.2.3.7 Ensure events that modify /etc/hosts and /etc/hostname are collected
    check_audit_rule_multi "6.2.3.7" "Ensure events that modify /etc/hosts and /etc/hostname are collected" \
        '-a always,exit -F arch=b64 -F path=/etc/hosts -F perm=wa -k system-locale && -a always,exit -F arch=b64 -F path=/etc/hostname -F perm=wa -k system-locale' \
        '/etc/audit/rules.d/50-etc_host_system_locale.rules' \
        '/etc/hosts\b' '/etc/hostname\b'

    # 6.2.3.8 Ensure events that modify the system's network environment are collected
    check_audit_rule_multi "6.2.3.8" "Ensure events that modify the system's network environment are collected" \
        '-a always,exit -F arch=b64 -F path=/etc/network/interfaces -F perm=wa -k system-locale && -a always,exit -F arch=b64 -F dir=/etc/network/interfaces.d -F perm=wa -k system-locale && -a always,exit -F arch=b64 -F dir=/etc/netplan/ -F perm=wa -k system-locale' \
        '/etc/audit/rules.d/50-etc_sysconfig_system_locale.rules' \
        '/etc/network/interfaces\b' '/etc/network/interfaces\.d\b' '/etc/netplan'

    # 6.2.3.9 Ensure events that modify /etc/NetworkManager directory are collected
    if should_run_check "6.2.3.9" "L2"; then
        if [[ ! -d /etc/NetworkManager ]]; then
            report_ok "6.2.3.9" "Ensure events that modify /etc/NetworkManager directory are collected" "L2" "Automated" "/etc/NetworkManager does not exist"
        else
            check_audit_rule_multi "6.2.3.9" "Ensure events that modify /etc/NetworkManager directory are collected" \
                '-a always,exit -F arch=b64 -F dir=/etc/NetworkManager/ -F perm=wa -k system-locale' \
                '/etc/audit/rules.d/50-etc_NetworkManager_system_locale.rules' \
                '/etc/NetworkManager'
        fi
    fi

    # 6.2.3.10 Ensure use of privileged commands are collected
    if should_run_check "6.2.3.10" "L2"; then
        local priv_missing_disk=() priv_missing_run=() part pbin
        for part in $(findmnt -n -l -k -it "$(awk '/nodev/ { print $2 }' /proc/filesystems | paste -sd,)" 2>/dev/null | grep -Pv "noexec|nosuid|\/run|\/sys|\/proc|\/dev" | awk '{print $1}'); do
            while IFS= read -r pbin; do
                [[ -z "$pbin" ]] && continue
                grep -qrF "$pbin" /etc/audit/rules.d/ 2>/dev/null || priv_missing_disk+=("$pbin")
                grep -qF "$pbin" <<< "$AUDITCTL_L_CACHE" || priv_missing_run+=("$pbin")
            done < <(find "$part" -xdev -perm /6000 -type f 2>/dev/null | head -n 30)
        done
        if [[ "${#priv_missing_disk[@]}" -eq 0 && "${#priv_missing_run[@]}" -eq 0 ]]; then
            report_ok "6.2.3.10" "Ensure use of privileged commands are collected" "L2" "Automated"
        else
            report_fail "6.2.3.10" "Ensure use of privileged commands are collected" "L2" "Automated" \
                "Privileged binaries missing from audit rules (disk: ${#priv_missing_disk[@]}, running: ${#priv_missing_run[@]}, e.g. ${priv_missing_disk[0]:-${priv_missing_run[0]:-none}})" \
                "Generate audit rules for all SUID/SGID binaries into /etc/audit/rules.d/50-privileged.rules ('-a always,exit -F arch=b64 -F path=<bin> -F perm=x -F auid>=${UID_MIN_VAL} -F auid!=unset -k privileged') and run: augenrules --load"
        fi
    fi

    # 6.2.3.11 Ensure unsuccessful file access attempts are collected
    check_audit_rule_multi "6.2.3.11" "Ensure unsuccessful file access attempts are collected" \
        "-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=${UID_MIN_VAL} -F auid!=unset -k access (and -F exit=-EPERM, plus b32)" \
        '/etc/audit/rules.d/50-access.rules' \
        'exit=-EACCES' 'exit=-EPERM' 'creat' 'open' 'openat' 'truncate' 'ftruncate'

    # 6.2.3.12 Ensure events that modify /etc/group information are collected
    check_audit_rule_multi "6.2.3.12" "Ensure events that modify /etc/group information are collected" \
        '-a always,exit -F arch=b64 -F path=/etc/group -F perm=wa -k identity' \
        '/etc/audit/rules.d/50-identity.rules' \
        '/etc/group\b'

    # 6.2.3.13 Ensure events that modify /etc/passwd information are collected
    check_audit_rule_multi "6.2.3.13" "Ensure events that modify /etc/passwd information are collected" \
        '-a always,exit -F arch=b64 -F path=/etc/passwd -F perm=wa -k identity' \
        '/etc/audit/rules.d/50-identity.rules' \
        '/etc/passwd\b'

    # 6.2.3.14 Ensure events that modify /etc/shadow and /etc/gshadow are collected
    check_audit_rule_multi "6.2.3.14" "Ensure events that modify /etc/shadow and /etc/gshadow are collected" \
        '-a always,exit -F arch=b64 -F path=/etc/gshadow -F perm=wa -k identity && -a always,exit -F arch=b64 -F path=/etc/shadow -F perm=wa -k identity' \
        '/etc/audit/rules.d/50-identity.rules' \
        '/etc/shadow\b' '/etc/gshadow\b'

    # 6.2.3.15 Ensure events that modify /etc/security/opasswd are collected
    check_audit_rule_multi "6.2.3.15" "Ensure events that modify /etc/security/opasswd are collected" \
        '-a always,exit -F arch=b64 -F path=/etc/security/opasswd -F perm=wa -k identity' \
        '/etc/audit/rules.d/50-identity.rules' \
        '/etc/security/opasswd\b'

    # 6.2.3.16 Ensure events that modify /etc/nsswitch.conf file are collected
    check_audit_rule_multi "6.2.3.16" "Ensure events that modify /etc/nsswitch.conf file are collected" \
        '-a always,exit -F arch=b64 -F path=/etc/nsswitch.conf -F perm=wa -k identity' \
        '/etc/audit/rules.d/50-identity.rules' \
        '/etc/nsswitch\.conf\b'

    # 6.2.3.17 Ensure events that modify /etc/pam.conf and /etc/pam.d/ information are collected
    check_audit_rule_multi "6.2.3.17" "Ensure events that modify /etc/pam.conf and /etc/pam.d/ information are collected" \
        '-a always,exit -F arch=b64 -F path=/etc/pam.conf -F perm=wa -k identity && -a always,exit -F arch=b64 -F dir=/etc/pam.d -F perm=wa -k identity' \
        '/etc/audit/rules.d/50-identity.rules' \
        '/etc/pam\.conf\b' '/etc/pam\.d\b'

    # 6.2.3.18 Ensure discretionary access control permission modification events chmod,fchmod,fchmodat,fchmodat2 are collected
    check_audit_rule_multi "6.2.3.18" "Ensure discretionary access control permission modification events chmod,fchmod,fchmodat,fchmodat2 are collected" \
        "-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat,fchmodat2 -F auid>=${UID_MIN_VAL} -F auid!=unset -k perm_mod (and arch=b32)" \
        '/etc/audit/rules.d/50-perm_mod.rules' \
        '\bchmod\b' '\bfchmod\b' '\bfchmodat\b' '\bfchmodat2\b'

    # 6.2.3.19 Ensure discretionary access control permission modification events chown,fchown,lchown,fchownat are collected
    check_audit_rule_multi "6.2.3.19" "Ensure discretionary access control permission modification events chown,fchown,lchown,fchownat are collected" \
        "-a always,exit -F arch=b64 -S chown,fchown,lchown,fchownat -F auid>=${UID_MIN_VAL} -F auid!=unset -k perm_mod (and arch=b32)" \
        '/etc/audit/rules.d/50-perm_mod.rules' \
        '\bchown\b' '\bfchown\b' '\blchown\b' '\bfchownat\b'

    # 6.2.3.20 Ensure discretionary access control permission modification events setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr collected
    check_audit_rule_multi "6.2.3.20" "Ensure discretionary access control permission modification events setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr collected" \
        "-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=${UID_MIN_VAL} -F auid!=unset -k perm_mod (and arch=b32)" \
        '/etc/audit/rules.d/50-perm_mod.rules' \
        '\bsetxattr\b' '\blsetxattr\b' '\bfsetxattr\b' '\bremovexattr\b' '\blremovexattr\b' '\bfremovexattr\b'

    # 6.2.3.21 Ensure successful file system mounts are collected
    check_audit_rule_multi "6.2.3.21" "Ensure successful file system mounts are collected" \
        "-a always,exit -F arch=b64 -S mount -F auid>=${UID_MIN_VAL} -F auid!=unset -k mounts (and arch=b32)" \
        '/etc/audit/rules.d/50-mounts.rules' \
        'arch=b64.*-S mount\b' 'arch=b32.*-S mount\b'

    # 6.2.3.22 Ensure session initiation information is collected
    check_audit_rule_multi "6.2.3.22" "Ensure session initiation information is collected" \
        '-a always,exit -F arch=b64 -F path=/var/run/utmp -F perm=wa -k session (and /var/log/wtmp, /var/log/btmp)' \
        '/etc/audit/rules.d/50-session.rules' \
        '/var/run/utmp\b' '/var/log/wtmp\b' '/var/log/btmp\b'

    # 6.2.3.23 Ensure login and logout events are collected
    check_audit_rule_multi "6.2.3.23" "Ensure login and logout events are collected" \
        '-a always,exit -F arch=b64 -F path=/var/log/lastlog -F perm=wa -k logins && -a always,exit -F arch=b64 -F path=/var/run/faillock -F perm=wa -k logins' \
        '/etc/audit/rules.d/50-login.rules' \
        '/var/log/lastlog\b' '/var/run/faillock\b'

    # 6.2.3.24 Ensure unlink file deletion events by users are collected
    check_audit_rule_multi "6.2.3.24" "Ensure unlink file deletion events by users are collected" \
        "-a always,exit -F arch=b64 -S unlink,unlinkat -F auid>=${UID_MIN_VAL} -F auid!=unset -k delete (and arch=b32)" \
        '/etc/audit/rules.d/50-delete.rules' \
        '\bunlink\b' '\bunlinkat\b'

    # 6.2.3.25 Ensure rename file deletion events by users are collected
    check_audit_rule_multi "6.2.3.25" "Ensure rename file deletion events by users are collected" \
        "-a always,exit -F arch=b64 -S rename,renameat,renameat2 -F auid>=${UID_MIN_VAL} -F auid!=unset -k delete (and arch=b32)" \
        '/etc/audit/rules.d/50-delete.rules' \
        '\brename\b' '\brenameat\b' '\brenameat2\b'

    # 6.2.3.26 Ensure events that modify the system's Mandatory Access Controls are collected
    check_audit_rule_multi "6.2.3.26" "Ensure events that modify the system's Mandatory Access Controls are collected" \
        '-a always,exit -F arch=b64 -F dir=/etc/apparmor -F perm=wa -k MAC-policy && -a always,exit -F arch=b64 -F dir=/etc/apparmor.d -F perm=wa -k MAC-policy' \
        '/etc/audit/rules.d/50-MAC-policy.rules' \
        '/etc/apparmor\b' '/etc/apparmor\.d\b'

    # 6.2.3.27 Ensure successful and unsuccessful attempts to use the chcon command are collected
    check_audit_rule_multi "6.2.3.27" "Ensure successful and unsuccessful attempts to use the chcon command are collected" \
        "-a always,exit -F arch=b64 -F path=/usr/bin/chcon -F perm=x -F auid>=${UID_MIN_VAL} -F auid!=unset -k perm_chng" \
        '/etc/audit/rules.d/50-perm_chng.rules' \
        '/usr/bin/chcon\b'

    # 6.2.3.28 Ensure successful and unsuccessful attempts to use the setfacl command are collected
    check_audit_rule_multi "6.2.3.28" "Ensure successful and unsuccessful attempts to use the setfacl command are collected" \
        "-a always,exit -F arch=b64 -F path=/usr/bin/setfacl -F perm=x -F auid>=${UID_MIN_VAL} -F auid!=unset -k perm_chng" \
        '/etc/audit/rules.d/50-perm_chng.rules' \
        '/usr/bin/setfacl\b'

    # 6.2.3.29 Ensure successful and unsuccessful attempts to use the chacl command are collected
    check_audit_rule_multi "6.2.3.29" "Ensure successful and unsuccessful attempts to use the chacl command are collected" \
        "-a always,exit -F arch=b64 -F path=/usr/bin/chacl -F perm=x -F auid>=${UID_MIN_VAL} -F auid!=unset -k perm_chng" \
        '/etc/audit/rules.d/50-perm_chng.rules' \
        '/usr/bin/chacl\b'

    # 6.2.3.30 Ensure successful and unsuccessful attempts to use the usermod command are collected
    check_audit_rule_multi "6.2.3.30" "Ensure successful and unsuccessful attempts to use the usermod command are collected" \
        "-a always,exit -F arch=b64 -F path=/usr/sbin/usermod -F perm=x -F auid>=${UID_MIN_VAL} -F auid!=unset -k usermod" \
        '/etc/audit/rules.d/50-usermod.rules' \
        '/usr/sbin/usermod\b'

    # 6.2.3.31 Ensure kernel module loading unloading and modification is collected
    if should_run_check "6.2.3.31" "L2"; then
        local kmod_symlinks_bad=() ksym
        for ksym in /sbin/lsmod /sbin/rmmod /sbin/insmod /sbin/modinfo /sbin/modprobe /sbin/depmod; do
            [[ -e "$ksym" ]] || continue
            local target
            target="$(readlink -f "$ksym" 2>/dev/null || true)"
            [[ "$target" != "/bin/kmod" && "$target" != "/usr/bin/kmod" ]] && kmod_symlinks_bad+=("$ksym -> $target")
        done
        if [[ "${#kmod_symlinks_bad[@]}" -gt 0 ]]; then
            report_fail "6.2.3.31" "Ensure kernel module loading unloading and modification is collected" "L2" "Automated" \
                "kmod symlinks corrupted: ${kmod_symlinks_bad[*]}" \
                "Verify kmod symlinks and add '-a always,exit -F arch=b64 -F path=/usr/bin/kmod -F perm=x -F auid>=${UID_MIN_VAL} -F auid!=unset -k kernel_modules' to /etc/audit/rules.d/50-kernel_modules.rules."
        else
            check_audit_rule_multi "6.2.3.31" "Ensure kernel module loading unloading and modification is collected" \
                "-a always,exit -F arch=b64 -F path=/usr/bin/kmod -F perm=x -F auid>=${UID_MIN_VAL} -F auid!=unset -k kernel_modules" \
                '/etc/audit/rules.d/50-kernel_modules.rules' \
                '(/usr)?/bin/kmod\b'
        fi
    fi

    # 6.2.3.32 Ensure kernel "init_module" and "finit_module" loading unloading and modification is collected
    check_audit_rule_multi "6.2.3.32" "Ensure kernel \"init_module\" and \"finit_module\" loading unloading and modification is collected" \
        "-a always,exit -F arch=b64 -S init_module,finit_module -F auid>=${UID_MIN_VAL} -F auid!=unset -k kernel_modules (and arch=b32)" \
        '/etc/audit/rules.d/50-kernel_modules.rules' \
        '\binit_module\b' '\bfinit_module\b'

    # 6.2.3.33 Ensure kernel "delete_module" loading unloading and modification is collected
    check_audit_rule_multi "6.2.3.33" "Ensure kernel \"delete_module\" loading unloading and modification is collected" \
        "-a always,exit -F arch=b64 -S delete_module -F auid>=${UID_MIN_VAL} -F auid!=unset -k kernel_modules (and arch=b32)" \
        '/etc/audit/rules.d/50-kernel_modules.rules' \
        'arch=b64.*delete_module' 'arch=b32.*delete_module'

    # 6.2.3.34 Ensure the audit configuration is loaded regardless of errors (Automated)
    if should_run_check "6.2.3.34" "L2"; then
        if grep -Phq -- '^\h*-c\b' /etc/audit/rules.d/*.rules 2>/dev/null; then
            report_ok "6.2.3.34" "Ensure the audit configuration is loaded regardless of errors" "L2" "Automated"
        else
            report_fail "6.2.3.34" "Ensure the audit configuration is loaded regardless of errors" "L2" "Automated" \
                "'-c' flag is not present in /etc/audit/rules.d/*.rules" \
                "Run: printf '\n%s\n' '-c' >> /etc/audit/rules.d/01-initialize.rules && augenrules --load"
        fi
    fi

    # 6.2.3.35 Ensure the audit configuration is immutable (Automated)
    if should_run_check "6.2.3.35" "L2"; then
        if grep -Phq -- '^\h*-e\h+2\b' /etc/audit/rules.d/*.rules 2>/dev/null && grep -Pq 'enabled\h+2\b' <<< "$AUDITCTL_S_CACHE"; then
            report_ok "6.2.3.35" "Ensure the audit configuration is immutable" "L2" "Automated"
        else
            report_fail "6.2.3.35" "Ensure the audit configuration is immutable" "L2" "Automated" \
                "'-e 2' flag is not present in /etc/audit/rules.d/*.rules or auditd running state is not 'enabled 2'" \
                "Run: printf '\n%s\n' '-e 2' >> /etc/audit/rules.d/99-finalize.rules && augenrules --load"
        fi
    fi

    # 6.2.3.36 Ensure the running and on disk configuration is the same (Manual)
    if should_run_check "6.2.3.36" "L2"; then
        local aug_chk
        aug_chk="$(augenrules --check 2>&1 || true)"
        if grep -Pq 'No change' <<< "$aug_chk"; then
            report_ok "6.2.3.36" "Ensure the running and on disk configuration is the same" "L2" "Manual" "augenrules --check: No change"
        else
            report_manual "6.2.3.36" "Ensure the running and on disk configuration is the same" "L2" "Manual" \
                "augenrules --check output: ${aug_chk:-augenrules not available or rules differ}" \
                "Run: augenrules --load (and reboot if auditd is in immutable mode '-e 2')."
        fi
    fi

    # --------------------------------------------------------------------------
    # 6.2.4 Configure auditd File Access
    # --------------------------------------------------------------------------
    print_subsection_header "6.2.4 Configure auditd File Access"

    local audit_log_dir="/var/log/audit"
    if [[ -f /etc/audit/auditd.conf ]]; then
        local cfg_lf
        cfg_lf="$(awk -F= '/^\s*log_file\s*/{print $2}' /etc/audit/auditd.conf 2>/dev/null | xargs || true)"
        [[ -n "$cfg_lf" ]] && audit_log_dir="$(dirname "$cfg_lf")"
    fi

    # 6.2.4.1 Ensure audit log files mode is configured (Automated)
    if should_run_check "6.2.4.1" "L2"; then
        if [[ ! -d "$audit_log_dir" ]]; then
            report_fail "6.2.4.1" "Ensure audit log files mode is configured" "L2" "Automated" \
                "Audit log directory '${audit_log_dir}' does not exist" \
                "Install auditd, ensure ${audit_log_dir} exists, and run: chmod u-x,g-wx,o-rwx ${audit_log_dir}/*"
        else
            local bad_alm
            bad_alm="$(find "$audit_log_dir" -maxdepth 1 -type f -perm /0137 2>/dev/null | tr '\n' ' ' || true)"
            if [[ -z "$bad_alm" ]]; then
                report_ok "6.2.4.1" "Ensure audit log files mode is configured" "L2" "Automated"
            else
                report_fail "6.2.4.1" "Ensure audit log files mode is configured" "L2" "Automated" \
                    "Audit log files more permissive than 0640: [${bad_alm% }]" \
                    "Run: find ${audit_log_dir} -type f -perm /0137 -exec chmod u-x,g-wx,o-rwx {} +"
            fi
        fi
    fi

    # 6.2.4.2 Ensure audit log files owner is configured (Automated)
    if should_run_check "6.2.4.2" "L2"; then
        if [[ ! -d "$audit_log_dir" ]]; then
            report_fail "6.2.4.2" "Ensure audit log files owner is configured" "L2" "Automated" \
                "Audit log directory '${audit_log_dir}' does not exist" \
                "Run: chown root ${audit_log_dir}/*"
        else
            local bad_alo
            bad_alo="$(find "$audit_log_dir" -maxdepth 1 -type f ! -user root 2>/dev/null | tr '\n' ' ' || true)"
            if [[ -z "$bad_alo" ]]; then
                report_ok "6.2.4.2" "Ensure audit log files owner is configured" "L2" "Automated"
            else
                report_fail "6.2.4.2" "Ensure audit log files owner is configured" "L2" "Automated" \
                    "Audit log files not owned by root: [${bad_alo% }]" \
                    "Run: find ${audit_log_dir} -type f ! -user root -exec chown root {} +"
            fi
        fi
    fi

    # 6.2.4.3 Ensure audit log files group owner is configured (Automated)
    if should_run_check "6.2.4.3" "L2"; then
        local lg_cfg bad_alg=""
        lg_cfg="$(grep -Piws -- '^\h*log_group\h*=\h*(adm|root)\b' /etc/audit/auditd.conf 2>/dev/null || true)"
        [[ -d "$audit_log_dir" ]] && bad_alg="$(find -L "$audit_log_dir" -not -path "${audit_log_dir}/lost+found" -type f \( ! -group root -a ! -group adm \) 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -n "$lg_cfg" && -z "$bad_alg" ]]; then
            report_ok "6.2.4.3" "Ensure audit log files group owner is configured" "L2" "Automated"
        else
            report_fail "6.2.4.3" "Ensure audit log files group owner is configured" "L2" "Automated" \
                "log_group in /etc/audit/auditd.conf not set to adm/root or files have wrong group: [${bad_alg% }]" \
                "Set 'log_group = adm' in /etc/audit/auditd.conf, run 'chgrp adm ${audit_log_dir}/*', and restart auditd."
        fi
    fi

    # 6.2.4.4 Ensure the audit log file directory mode is configured (Automated)
    check_file_perms "6.2.4.4" "Ensure the audit log file directory mode is configured" "L2" \
        "$audit_log_dir" "0027" "0750" "root" "root|adm" "0" \
        "chmod g-w,o-rwx ${audit_log_dir}" "chown root:adm ${audit_log_dir}"

    # 6.2.4.5 Ensure audit configuration files mode is configured (Automated)
    if should_run_check "6.2.4.5" "L2"; then
        local bad_acm=""
        [[ -d /etc/audit ]] && bad_acm="$(find /etc/audit/ -type f \( -name '*.conf' -o -name '*.rules' \) -perm /0137 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -d /etc/audit && -z "$bad_acm" ]]; then
            report_ok "6.2.4.5" "Ensure audit configuration files mode is configured" "L2" "Automated"
        else
            report_fail "6.2.4.5" "Ensure audit configuration files mode is configured" "L2" "Automated" \
                "/etc/audit missing or config files more permissive than 0640: [${bad_acm% }]" \
                "Run: find /etc/audit/ -type f \( -name '*.conf' -o -name '*.rules' \) -exec chmod u-x,g-wx,o-rwx {} +"
        fi
    fi

    # 6.2.4.6 Ensure audit configuration files owner is configured (Automated)
    if should_run_check "6.2.4.6" "L2"; then
        local bad_aco=""
        [[ -d /etc/audit ]] && bad_aco="$(find /etc/audit/ -type f \( -name '*.conf' -o -name '*.rules' \) ! -user root 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -d /etc/audit && -z "$bad_aco" ]]; then
            report_ok "6.2.4.6" "Ensure audit configuration files owner is configured" "L2" "Automated"
        else
            report_fail "6.2.4.6" "Ensure audit configuration files owner is configured" "L2" "Automated" \
                "/etc/audit missing or config files not owned by root: [${bad_aco% }]" \
                "Run: find /etc/audit/ -type f \( -name '*.conf' -o -name '*.rules' \) ! -user root -exec chown root {} +"
        fi
    fi

    # 6.2.4.7 Ensure audit configuration files group owner is configured (Automated)
    if should_run_check "6.2.4.7" "L2"; then
        local bad_acg=""
        [[ -d /etc/audit ]] && bad_acg="$(find /etc/audit/ -type f \( -name '*.conf' -o -name '*.rules' \) ! -group root 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -d /etc/audit && -z "$bad_acg" ]]; then
            report_ok "6.2.4.7" "Ensure audit configuration files group owner is configured" "L2" "Automated"
        else
            report_fail "6.2.4.7" "Ensure audit configuration files group owner is configured" "L2" "Automated" \
                "/etc/audit missing or config files not group-owned by root: [${bad_acg% }]" \
                "Run: find /etc/audit/ -type f \( -name '*.conf' -o -name '*.rules' \) ! -group root -exec chgrp root {} +"
        fi
    fi

    # 6.2.4.8 - 6.2.4.10 Audit tools mode, owner, group owner
    local audit_tools=("/sbin/auditctl" "/sbin/aureport" "/sbin/ausearch" "/sbin/autrace" "/sbin/auditd" "/sbin/augenrules")

    if should_run_check "6.2.4.8" "L2"; then
        local bad_atm=() at_exist=0 at
        for at in "${audit_tools[@]}"; do
            [[ -e "$at" ]] || continue
            at_exist=1
            local m
            m="$(stat -Lc '%#a' "$at" 2>/dev/null)"
            [[ $(( m & 0022 )) -gt 0 ]] && bad_atm+=("${at} (${m})")
        done
        if [[ "$at_exist" -eq 1 && "${#bad_atm[@]}" -eq 0 ]]; then
            report_ok "6.2.4.8" "Ensure audit tools mode is configured" "L2" "Automated"
        else
            report_fail "6.2.4.8" "Ensure audit tools mode is configured" "L2" "Automated" \
                "Audit tools missing or mode less restrictive than 0755: [${bad_atm[*]}]" \
                "Run: chmod go-w /sbin/auditctl /sbin/aureport /sbin/ausearch /sbin/autrace /sbin/auditd /sbin/augenrules"
        fi
    fi

    if should_run_check "6.2.4.9" "L2"; then
        local bad_ato=() at_exist=0 at
        for at in "${audit_tools[@]}"; do
            [[ -e "$at" ]] || continue
            at_exist=1
            local u
            u="$(stat -Lc '%U' "$at" 2>/dev/null)"
            [[ "$u" != "root" ]] && bad_ato+=("${at} (${u})")
        done
        if [[ "$at_exist" -eq 1 && "${#bad_ato[@]}" -eq 0 ]]; then
            report_ok "6.2.4.9" "Ensure audit tools owner is configured" "L2" "Automated"
        else
            report_fail "6.2.4.9" "Ensure audit tools owner is configured" "L2" "Automated" \
                "Audit tools missing or not owned by root: [${bad_ato[*]}]" \
                "Run: chown root /sbin/auditctl /sbin/aureport /sbin/ausearch /sbin/autrace /sbin/auditd /sbin/augenrules"
        fi
    fi

    if should_run_check "6.2.4.10" "L2"; then
        local bad_atg=() at_exist=0 at
        for at in "${audit_tools[@]}"; do
            [[ -e "$at" ]] || continue
            at_exist=1
            local g
            g="$(stat -Lc '%G' "$at" 2>/dev/null)"
            [[ "$g" != "root" ]] && bad_atg+=("${at} (${g})")
        done
        if [[ "$at_exist" -eq 1 && "${#bad_atg[@]}" -eq 0 ]]; then
            report_ok "6.2.4.10" "Ensure audit tools group owner is configured" "L2" "Automated"
        else
            report_fail "6.2.4.10" "Ensure audit tools group owner is configured" "L2" "Automated" \
                "Audit tools missing or not group-owned by root: [${bad_atg[*]}]" \
                "Run: chgrp root /sbin/auditctl /sbin/aureport /sbin/ausearch /sbin/autrace /sbin/auditd /sbin/augenrules"
        fi
    fi

    # --------------------------------------------------------------------------
    # 6.3 Configure Integrity Checking
    # --------------------------------------------------------------------------
    print_subsection_header "6.3 Configure Integrity Checking (AIDE)"

    # 6.3.1 Ensure AIDE is installed (Automated)
    if should_run_check "6.3.1" "L1"; then
        if dpkg-query -s aide &>/dev/null && dpkg-query -s aide-common &>/dev/null; then
            report_ok "6.3.1" "Ensure AIDE is installed" "L1" "Automated"
        else
            report_fail "6.3.1" "Ensure AIDE is installed" "L1" "Automated" \
                "Packages 'aide' and/or 'aide-common' are not installed" \
                "Run: apt install -y aide aide-common && aideinit && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db"
        fi
    fi

    # 6.3.2 Ensure filesystem integrity is regularly checked (Automated)
    if should_run_check "6.3.2" "L1"; then
        local aide_tmr_en aide_tmr_act aide_svc_st
        aide_tmr_en="$(systemctl is-enabled dailyaidecheck.timer 2>/dev/null || true)"
        aide_tmr_act="$(systemctl is-active dailyaidecheck.timer 2>/dev/null || true)"
        aide_svc_st="$(systemctl is-enabled dailyaidecheck.service 2>/dev/null || true)"
        if [[ "$aide_tmr_en" == "enabled" && "$aide_tmr_act" == "active" && ( "$aide_svc_st" == "static" || "$aide_svc_st" == "enabled" ) ]]; then
            report_ok "6.3.2" "Ensure filesystem integrity is regularly checked" "L1" "Automated"
        else
            report_fail "6.3.2" "Ensure filesystem integrity is regularly checked" "L1" "Automated" \
                "dailyaidecheck.timer enabled=${aide_tmr_en:-no}, active=${aide_tmr_act:-no}" \
                "Run: systemctl unmask dailyaidecheck.timer dailyaidecheck.service && systemctl --now enable dailyaidecheck.timer"
        fi
    fi

    # 6.3.3 Ensure cryptographic mechanisms are used to protect the integrity of audit tools (Automated)
    if should_run_check "6.3.3" "L2"; then
        local aide_missing_tools=() at_name
        for at_name in auditctl auditd ausearch aureport autrace augenrules; do
            if ! grep -PRsq -- "\b${at_name}\b.*p\+i\+n\+u\+g\+s\+b\+acl\+xattrs\+sha512" /etc/aide/ 2>/dev/null; then
                aide_missing_tools+=("$at_name")
            fi
        done
        if [[ "${#aide_missing_tools[@]}" -eq 0 ]]; then
            report_ok "6.3.3" "Ensure cryptographic mechanisms are used to protect the integrity of audit tools" "L2" "Automated"
        else
            report_fail "6.3.3" "Ensure cryptographic mechanisms are used to protect the integrity of audit tools" "L2" "Automated" \
                "AIDE configuration missing p+i+n+u+g+s+b+acl+xattrs+sha512 rules for: [${aide_missing_tools[*]}]" \
                "Add '<PATH>/{auditctl,auditd,ausearch,aureport,autrace,augenrules} p+i+n+u+g+s+b+acl+xattrs+sha512' to /etc/aide/aide.conf."
        fi
    fi
}
# ==============================================================================
# SECTION 7: SYSTEM MAINTENANCE
# ==============================================================================
run_section_7() {
    print_section_header "7" "System Maintenance" || return 0

    # --------------------------------------------------------------------------
    # 7.1 Configure system file and directory access
    # --------------------------------------------------------------------------
    print_subsection_header "7.1 Configure System File and Directory Access"

    check_file_perms "7.1.1" "Ensure access to /etc/passwd is configured" "L1" \
        "/etc/passwd" "0133" "0644" "root" "root" "0" \
        "chmod u-x,go-wx /etc/passwd" "chown root:root /etc/passwd"

    check_file_perms "7.1.2" "Ensure access to /etc/passwd- is configured" "L1" \
        "/etc/passwd-" "0133" "0644" "root" "root" "1" \
        "chmod u-x,go-wx /etc/passwd-" "chown root:root /etc/passwd-"

    check_file_perms "7.1.3" "Ensure access to /etc/group is configured" "L1" \
        "/etc/group" "0133" "0644" "root" "root" "0" \
        "chmod u-x,go-wx /etc/group" "chown root:root /etc/group"

    check_file_perms "7.1.4" "Ensure access to /etc/group- is configured" "L1" \
        "/etc/group-" "0133" "0644" "root" "root" "1" \
        "chmod u-x,go-wx /etc/group-" "chown root:root /etc/group-"

    check_file_perms "7.1.5" "Ensure access to /etc/shadow is configured" "L1" \
        "/etc/shadow" "0137" "0640" "root" "root|shadow" "0" \
        "chmod u-x,g-wx,o-rwx /etc/shadow" "chown root:shadow /etc/shadow"

    check_file_perms "7.1.6" "Ensure access to /etc/shadow- is configured" "L1" \
        "/etc/shadow-" "0137" "0640" "root" "root|shadow" "1" \
        "chmod u-x,g-wx,o-rwx /etc/shadow-" "chown root:shadow /etc/shadow-"

    check_file_perms "7.1.7" "Ensure access to /etc/gshadow is configured" "L1" \
        "/etc/gshadow" "0137" "0640" "root" "root|shadow" "0" \
        "chmod u-x,g-wx,o-rwx /etc/gshadow" "chown root:shadow /etc/gshadow"

    check_file_perms "7.1.8" "Ensure access to /etc/gshadow- is configured" "L1" \
        "/etc/gshadow-" "0137" "0640" "root" "root|shadow" "1" \
        "chmod u-x,g-wx,o-rwx /etc/gshadow-" "chown root:shadow /etc/gshadow-"

    check_file_perms "7.1.9" "Ensure access to /etc/shells is configured" "L1" \
        "/etc/shells" "0133" "0644" "root" "root" "0" \
        "chmod u-x,go-wx /etc/shells" "chown root:root /etc/shells"

    # 7.1.10 Ensure access to /etc/security/opasswd is configured (Automated)
    if should_run_check "7.1.10" "L1"; then
        local op_issues=() opf
        for opf in /etc/security/opasswd /etc/security/opasswd.old; do
            [[ -e "$opf" ]] || continue
            local m u g
            read -r m u g <<< "$(stat -Lc '%#a %U %G' "$opf" 2>/dev/null)"
            if [[ $(( m & 0177 )) -gt 0 || "$u" != "root" || "$g" != "root" ]]; then
                op_issues+=("${opf} (${m} ${u}:${g})")
            fi
        done
        if [[ "${#op_issues[@]}" -eq 0 ]]; then
            report_ok "7.1.10" "Ensure access to /etc/security/opasswd is configured" "L1" "Automated"
        else
            report_fail "7.1.10" "Ensure access to /etc/security/opasswd is configured" "L1" "Automated" \
                "Improper permissions/owner on opasswd file(s): ${op_issues[*]}" \
                "Run: chmod u-x,go-rwx /etc/security/opasswd* && chown root:root /etc/security/opasswd*"
        fi
    fi

    # Fast single-pass C-native filesystem scan for 7.1.11, 7.1.12, and 7.1.13 (zero per-file stat subshells)
    local wwf_cnt=0 wwd_cnt=0 nouser_cnt=0 nogroup_cnt=0 suid_cnt=0 sgid_cnt=0
    local wwf_samp="" wwd_samp="" nouser_samp="" nogroup_samp="" suid_samp=""
    local scan_mounts=() raw_mounts=() m
    local fs_exclude="nfs|nfs4|proc|cifs|smb|smbfs|vfat|iso9660|efivarfs|selinuxfs|ncpfs|overlay|tmpfs|devtmpfs|squashfs|fuse|fuseblk|autofs|bpf|cgroup|cgroup2|debugfs|mqueue|pstore|securityfs|sysfs|tracefs|9p"
    local mnt_exclude="\/run|\/tmp|\/var\/tmp|\/proc|\/sys|\/dev|\/snap|\/var\/snap|\/var\/lib\/docker|\/var\/lib\/containerd|\/var\/lib\/containers|\/var\/lib\/kubelet|\/mnt|\/media|\/working_dir"

    mapfile -t raw_mounts < <(findmnt -Dkerno fstype,source,target 2>/dev/null | awk '
        ($1 !~ /^\s*('"$fs_exclude"')/ && $3 !~ /^('"$mnt_exclude"')(\/|$)/) {
            src = $2
            sub(/\[.*\]$/, "", src)
            if (src != "none" && src != "" && seen[src]++) next
            print $3
        }' | sort -u)
    for m in "${raw_mounts[@]}"; do
        [[ -n "$m" && -d "$m" ]] && scan_mounts+=("$m")
    done
    if [[ "${#scan_mounts[@]}" -eq 0 ]]; then
        for m in /usr /bin /sbin /etc /var /home; do
            [[ -d "$m" && ! -L "$m" ]] && scan_mounts+=("$m")
        done
    fi

    [[ -t 1 ]] && printf "         ${C_DIM}[~] Scanning local filesystems for 7.1.11, 7.1.12 & 7.1.13...${C_RESET}\r"
    local scan_summary
    scan_summary="$(find "${scan_mounts[@]}" -xdev \
        -type d \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /snap \
           -o -path /var/snap -o -path /var/lib/docker -o -path /var/lib/containerd \
           -o -path /var/lib/containers -o -path /var/lib/kubelet -o -path /var/lib/lxcfs \
           -o -path /boot/efi -o -path /mnt -o -path /media -o -path /working_dir \) -prune -o \
        \( \
            \( -type f -perm -0002 -printf 'WWF\t%p\n' \) , \
            \( -type d -perm -0002 ! -perm -1000 -printf 'WWD\t%p\n' \) , \
            \( ! -uid 0 -nouser -printf 'NOUSER\t%p\n' \) , \
            \( ! -gid 0 -nogroup -printf 'NOGROUP\t%p\n' \) , \
            \( -type f -perm -4000 -printf 'SUID\t%p\n' \) , \
            \( -type f -perm -2000 -printf 'SGID\t%p\n' \) \
        \) 2>/dev/null | awk -F'\t' '
            $1=="WWF"     { wwf++;     if (wwf<=5)     wwf_s = wwf_s (wwf_s?" ":"") $2 }
            $1=="WWD"     { wwd++;     if (wwd<=5)     wwd_s = wwd_s (wwd_s?" ":"") $2 }
            $1=="NOUSER"  { nou++;     if (nou<=5)     nou_s = nou_s (nou_s?" ":"") $2 }
            $1=="NOGROUP" { nog++;     if (nog<=5)     nog_s = nog_s (nog_s?" ":"") $2 }
            $1=="SUID"    { suid++;    if (suid<=6)    suid_s = suid_s (suid_s?" ":"") $2 }
            $1=="SGID"    { sgid++ }
            END {
                printf "%d|%d|%d|%d|%d|%d|%s|%s|%s|%s|%s\n", wwf+0, wwd+0, nou+0, nog+0, suid+0, sgid+0, wwf_s, wwd_s, nou_s, nog_s, suid_s
            }
        ')"

    [[ -t 1 ]] && printf "\033[2K\r"
    IFS='|' read -r wwf_cnt wwd_cnt nouser_cnt nogroup_cnt suid_cnt sgid_cnt wwf_samp wwd_samp nouser_samp nogroup_samp suid_samp <<< "$scan_summary"

    # 7.1.11 Ensure world writable files and directories are secured (Automated)
    if should_run_check "7.1.11" "L1"; then
        if [[ "${wwf_cnt:-0}" -eq 0 && "${wwd_cnt:-0}" -eq 0 ]]; then
            report_ok "7.1.11" "Ensure world writable files and directories are secured" "L1" "Automated"
        else
            report_fail "7.1.11" "Ensure world writable files and directories are secured" "L1" "Automated" \
                "${wwf_cnt} world-writable file(s) (${wwf_samp:-none}) and ${wwd_cnt} world-writable dir(s) without sticky bit (${wwd_samp:-none})" \
                "Run 'chmod o-w <file>' on world-writable files and 'chmod a+t <dir>' on world-writable directories."
        fi
    fi

    # 7.1.12 Ensure no files or directories without an owner and a group exist (Automated)
    if should_run_check "7.1.12" "L1"; then
        if [[ "${nouser_cnt:-0}" -eq 0 && "${nogroup_cnt:-0}" -eq 0 ]]; then
            report_ok "7.1.12" "Ensure no files or directories without an owner and a group exist" "L1" "Automated"
        else
            report_fail "7.1.12" "Ensure no files or directories without an owner and a group exist" "L1" "Automated" \
                "${nouser_cnt} unowned item(s) (${nouser_samp:-none}) and ${nogroup_cnt} ungrouped item(s) (${nogroup_samp:-none}) found" \
                "Remove or assign valid ownership ('chown <user>:<group> <path>') to all unowned/ungrouped files and directories."
        fi
    fi

    # 7.1.13 Ensure SUID and SGID files are reviewed (Manual)
    if should_run_check "7.1.13" "L1"; then
        report_manual "7.1.13" "Ensure SUID and SGID files are reviewed" "L1" "Manual" \
            "Found ${suid_cnt} SUID file(s) and ${sgid_cnt} SGID file(s) (sample: ${suid_samp:-none})" \
            "Review all SUID/SGID files ('find / -xdev -type f \( -perm -4000 -o -perm -2000 \)') and remove SUID/SGID bits ('chmod u-s / g-s <file>') from any unauthorized binaries."
    fi

    # --------------------------------------------------------------------------
    # 7.2 Local User and Group Settings
    # --------------------------------------------------------------------------
    print_subsection_header "7.2 Local User and Group Settings"

    # 7.2.1 Ensure accounts in /etc/passwd use shadowed passwords (Automated)
    if should_run_check "7.2.1" "L1"; then
        local unshadowed
        unshadowed="$(awk -F: '($2 != "x") { print $1 }' /etc/passwd 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -z "$unshadowed" ]]; then
            report_ok "7.2.1" "Ensure accounts in /etc/passwd use shadowed passwords" "L1" "Automated"
        else
            report_fail "7.2.1" "Ensure accounts in /etc/passwd use shadowed passwords" "L1" "Automated" \
                "Users not using shadowed passwords in /etc/passwd: [${unshadowed% }]" \
                "Run: pwconv"
        fi
    fi

    # 7.2.2 Ensure /etc/shadow password fields are not empty (Automated)
    if should_run_check "7.2.2" "L1"; then
        local empty_pw
        empty_pw="$(awk -F: '($2 == "") { print $1 }' /etc/shadow 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -z "$empty_pw" ]]; then
            report_ok "7.2.2" "Ensure /etc/shadow password fields are not empty" "L1" "Automated"
        else
            report_fail "7.2.2" "Ensure /etc/shadow password fields are not empty" "L1" "Automated" \
                "Accounts with empty password field in /etc/shadow: [${empty_pw% }]" \
                "Run: passwd -l <username> for each listed account."
        fi
    fi

    # 7.2.3 Ensure all groups in /etc/passwd exist in /etc/group (Automated)
    if should_run_check "7.2.3" "L1"; then
        local missing_gids=() u g
        while IFS=: read -r u _ _ g _; do
            [[ -z "$u" || -z "$g" ]] && continue
            if ! awk -F: -v gid="$g" '$3==gid {found=1} END{exit !found}' /etc/group 2>/dev/null; then
                missing_gids+=("${u}(GID:${g})")
            fi
        done < /etc/passwd
        if [[ "${#missing_gids[@]}" -eq 0 ]]; then
            report_ok "7.2.3" "Ensure all groups in /etc/passwd exist in /etc/group" "L1" "Automated"
        else
            report_fail "7.2.3" "Ensure all groups in /etc/passwd exist in /etc/group" "L1" "Automated" \
                "Users with GIDs absent from /etc/group: [${missing_gids[*]}]" \
                "Create the missing group in /etc/group or update the user's primary GID ('usermod -g <valid_group> <user>')."
        fi
    fi

    # 7.2.4 Ensure shadow group is empty (Automated)
    if should_run_check "7.2.4" "L1"; then
        local sh_members sh_gid sh_pri_users=""
        sh_members="$(awk -F: '($1=="shadow") {print $NF}' /etc/group 2>/dev/null || true)"
        sh_gid="$(awk -F: '($1=="shadow") {print $3}' /etc/group 2>/dev/null | xargs || true)"
        [[ -n "$sh_gid" ]] && sh_pri_users="$(awk -F: -v g="$sh_gid" '($4 == g) {print $1}' /etc/passwd 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -z "$sh_members" && -z "$sh_pri_users" ]]; then
            report_ok "7.2.4" "Ensure shadow group is empty" "L1" "Automated"
        else
            report_fail "7.2.4" "Ensure shadow group is empty" "L1" "Automated" \
                "shadow group members: [${sh_members}], primary group shadow users: [${sh_pri_users% }]" \
                "Run: sed -ri 's/(^shadow:[^:]*:[^:]*:)([^:]+$)/\1/' /etc/group and change primary group of any user with shadow GID ('usermod -g <group> <user>')."
        fi
    fi

    # 7.2.5 Ensure no duplicate UIDs exist (Automated)
    if should_run_check "5" "L1" || should_run_check "7.2.5" "L1"; then
        if should_run_check "7.2.5" "L1"; then
            local dup_uids
            dup_uids="$(cut -f3 -d: /etc/passwd 2>/dev/null | sort -n | uniq -d | tr '\n' ' ' || true)"
            if [[ -z "$dup_uids" ]]; then
                report_ok "7.2.5" "Ensure no duplicate UIDs exist" "L1" "Automated"
            else
                report_fail "7.2.5" "Ensure no duplicate UIDs exist" "L1" "Automated" \
                    "Duplicate UID(s) found in /etc/passwd: [${dup_uids% }]" \
                    "Assign unique UIDs to affected users ('usermod -u <new_uid> <user>')."
            fi
        fi
    fi

    # 7.2.6 Ensure no duplicate GIDs exist (Automated)
    if should_run_check "7.2.6" "L1"; then
        local dup_gids
        dup_gids="$(cut -f3 -d: /etc/group 2>/dev/null | sort -n | uniq -d | tr '\n' ' ' || true)"
        if [[ -z "$dup_gids" ]]; then
            report_ok "7.2.6" "Ensure no duplicate GIDs exist" "L1" "Automated"
        else
            report_fail "7.2.6" "Ensure no duplicate GIDs exist" "L1" "Automated" \
                "Duplicate GID(s) found in /etc/group: [${dup_gids% }]" \
                "Assign unique GIDs to affected groups ('groupmod -g <new_gid> <group>')."
        fi
    fi

    # 7.2.7 Ensure no duplicate user names exist (Automated)
    if should_run_check "7.2.7" "L1"; then
        local dup_users
        dup_users="$(cut -f1 -d: /etc/passwd 2>/dev/null | sort | uniq -d | tr '\n' ' ' || true)"
        if [[ -z "$dup_users" ]]; then
            report_ok "7.2.7" "Ensure no duplicate user names exist" "L1" "Automated"
        else
            report_fail "7.2.7" "Ensure no duplicate user names exist" "L1" "Automated" \
                "Duplicate username(s) found in /etc/passwd: [${dup_users% }]" \
                "Establish unique usernames in /etc/passwd."
        fi
    fi

    # 7.2.8 Ensure no duplicate group names exist (Automated)
    if should_run_check "7.2.8" "L1"; then
        local dup_grps
        dup_grps="$(cut -f1 -d: /etc/group 2>/dev/null | sort | uniq -d | tr '\n' ' ' || true)"
        if [[ -z "$dup_grps" ]]; then
            report_ok "7.2.8" "Ensure no duplicate group names exist" "L1" "Automated"
        else
            report_fail "7.2.8" "Ensure no duplicate group names exist" "L1" "Automated" \
                "Duplicate group name(s) found in /etc/group: [${dup_grps% }]" \
                "Establish unique group names in /etc/group."
        fi
    fi

    # Helper list of local interactive users and home directories for 7.2.9 - 7.2.11
    local valid_shells
    valid_shells="^($(awk -F/ '$NF != "nologin" {print}' /etc/shells 2>/dev/null | sed -rn '/^\//{s,/,\\\\/,g;p}' | paste -s -d '|' - ))$"

    # 7.2.9 Ensure local interactive user home directories are configured (Automated)
    if should_run_check "7.2.9" "L1"; then
        local home_issues=() u h
        while IFS=" " read -r u h; do
            [[ -z "$u" || -z "$h" ]] && continue
            if [[ ! -d "$h" ]]; then
                home_issues+=("User '${u}' home '${h}' does not exist")
            else
                local m o
                read -r o m <<< "$(stat -Lc '%U %#a' "$h" 2>/dev/null)"
                [[ "$o" != "$u" ]] && home_issues+=("User '${u}' home '${h}' owned by '${o}'")
                [[ $(( m & 0027 )) -gt 0 ]] && home_issues+=("User '${u}' home '${h}' mode is ${m} (should be 0750 or more restrictive)")
            fi
        done < <(awk -v pat="$valid_shells" -F: '$(NF) ~ pat { print $1 " " $(NF-1) }' /etc/passwd 2>/dev/null)
        if [[ "${#home_issues[@]}" -eq 0 ]]; then
            report_ok "7.2.9" "Ensure local interactive user home directories are configured" "L1" "Automated"
        else
            report_fail "7.2.9" "Ensure local interactive user home directories are configured" "L1" "Automated" \
                "$(IFS='; '; echo "${home_issues[*]}")" \
                "Create missing home directories, set ownership ('chown <user> <home>'), and set mode 0750 or more restrictive ('chmod g-w,o-rwx <home>')."
        fi
    fi

    # 7.2.10 Ensure local interactive user dot files access is configured (Automated)
    if should_run_check "7.2.10" "L1"; then
        local dotfile_issues=() u h
        while IFS=" " read -r u h; do
            [[ -z "$u" || -z "$h" || ! -d "$h" ]] && continue
            local fstype pgrp df
            fstype="$(findmnt -no FSTYPE --target "$h" 2>/dev/null || true)"
            case "$fstype" in nfs|nfs4|cifs|smbfs|smb3|fuse.sshfs|afs|ncpfs|glusterfs|ceph) continue ;; esac
            pgrp="$(id -gn "$u" 2>/dev/null | xargs || echo "$u")"
            while IFS= read -r -d $'\0' df; do
                local bname m o g mask="0133"
                bname="$(basename "$df")"
                read -r m o g <<< "$(stat -Lc '%#a %U %G' "$df" 2>/dev/null)"
                case "$bname" in
                    .forward|.rhosts)
                        dotfile_issues+=("${df} exists (must be removed)")
                        continue ;;
                    .netrc|.bash_history)
                        mask="0177" ;;
                    *)
                        mask="0133" ;;
                esac
                [[ $(( m & mask )) -gt 0 ]] && dotfile_issues+=("${df} mode ${m} (mask ${mask} violated)")
                [[ "$o" != "$u" ]] && dotfile_issues+=("${df} owned by ${o} (expected ${u})")
                [[ "$g" != "$pgrp" ]] && dotfile_issues+=("${df} group ${g} (expected ${pgrp})")
            done < <(find "$h" -xdev -maxdepth 2 -type f -name '.*' -print0 2>/dev/null)
        done < <(awk -v pat="$valid_shells" -F: '$(NF) ~ pat { print $1 " " $(NF-1) }' /etc/passwd 2>/dev/null)
        if [[ "${#dotfile_issues[@]}" -eq 0 ]]; then
            report_ok "7.2.10" "Ensure local interactive user dot files access is configured" "L1" "Automated"
        else
            report_fail "7.2.10" "Ensure local interactive user dot files access is configured" "L1" "Automated" \
                "$(IFS='; '; echo "${dotfile_issues[*]:0:5}")" \
                "Remove .forward/.rhosts files, set .bash_history/.netrc to 0600 ('chmod u-x,go-rwx'), set other dot files to 0644 ('chmod u-x,go-wx'), and set owner/group to <user>:<primary_group>."
        fi
    fi

    # 7.2.11 Ensure local interactive user dot directories access is configured (Automated)
    if should_run_check "7.2.11" "L1"; then
        local dotdir_issues=() u h
        while IFS=" " read -r u h; do
            [[ -z "$u" || -z "$h" || ! -d "$h" ]] && continue
            local fstype pgrp dd
            fstype="$(findmnt -no FSTYPE --target "$h" 2>/dev/null || true)"
            case "$fstype" in nfs|nfs4|cifs|smbfs|smb3|fuse.sshfs|afs|ncpfs|glusterfs|ceph) continue ;; esac
            pgrp="$(id -gn "$u" 2>/dev/null | xargs || echo "$u")"
            while IFS= read -r -d $'\0' dd; do
                local bname m o g mask="0027"
                bname="$(basename "$dd")"
                [[ "$bname" == "." || "$bname" == ".." ]] && continue
                read -r m o g <<< "$(stat -Lc '%#a %U %G' "$dd" 2>/dev/null)"
                [[ "$bname" == ".ssh" ]] && mask="0077"
                [[ $(( m & mask )) -gt 0 ]] && dotdir_issues+=("${dd} mode ${m} (mask ${mask} violated)")
                [[ "$o" != "$u" ]] && dotdir_issues+=("${dd} owned by ${o} (expected ${u})")
                [[ "$g" != "$pgrp" ]] && dotdir_issues+=("${dd} group ${g} (expected ${pgrp})")
            done < <(find "$h" -xdev -mindepth 1 -maxdepth 2 -type d -name '.*' -print0 2>/dev/null)
        done < <(awk -v pat="$valid_shells" -F: '$(NF) ~ pat { print $1 " " $(NF-1) }' /etc/passwd 2>/dev/null)
        if [[ "${#dotdir_issues[@]}" -eq 0 ]]; then
            report_ok "7.2.11" "Ensure local interactive user dot directories access is configured" "L1" "Automated"
        else
            report_fail "7.2.11" "Ensure local interactive user dot directories access is configured" "L1" "Automated" \
                "$(IFS='; '; echo "${dotdir_issues[*]:0:5}")" \
                "Set .ssh directories to 0700 ('chmod g-rwx,o-rwx'), other dot directories to 0750 ('chmod g-w,o-rwx'), and set owner/group to <user>:<primary_group>."
        fi
    fi
}

# ==============================================================================
# MAIN EXECUTION & SUMMARY SCORECARD

# ==============================================================================
# MAIN EXECUTION & SUMMARY SCORECARD
# ==============================================================================
print_summary() {
    echo -e "\n${C_BG_BLUE} [SUMMARY] ${BENCHMARK_NAME^^} AUDIT REPORT ${C_RESET}"
    echo -e "${C_BLUE}==========================================================================================${C_RESET}"
    printf "  %-36s | %7s | %7s | %7s | %7s | %7s\n" "Section" "OK" "FAIL" "MANUAL" "SKIP" "Total"
    echo -e "${C_DIM}------------------------------------------------------------------------------------------${C_RESET}"
    local s_names=(
        ""
        "1. Initial Setup"
        "2. Services"
        "3. Network"
        "4. Host Based Firewall"
        "5. Access Control"
        "6. Logging and Auditing"
        "7. System Maintenance"
    )
    local s
    for s in 1 2 3 4 5 6 7; do
        local ok="${SEC_OK[$s]:-0}"
        local fl="${SEC_FAIL[$s]:-0}"
        local mn="${SEC_MANUAL[$s]:-0}"
        local sk="${SEC_SKIP[$s]:-0}"
        local tot=$(( ok + fl + mn + sk ))
        [[ "$tot" -eq 0 ]] && ! is_section_selected "$s" && continue
        printf "  %-36s | %7d | %7d | %7d | %7d | %7d\n" "${s_names[$s]}" "$ok" "$fl" "$mn" "$sk" "$tot"
    done
    echo -e "${C_BLUE}==========================================================================================${C_RESET}"
    echo -e "  ${C_BOLD}Total Checks Executed:${C_RESET}  ${TOTAL_CHECKS}"
    echo -e "  ${C_GREEN}${C_BOLD}[OK] Compliant:${C_RESET}         ${COUNT_OK}"
    echo -e "  ${C_RED}${C_BOLD}[FAIL] Non-Compliant:${C_RESET}   ${COUNT_FAIL}"
    echo -e "  ${C_YELLOW}${C_BOLD}[MANUAL] Site Review:${C_RESET}   ${COUNT_MANUAL}"
    echo -e "  ${C_MAGENTA}${C_BOLD}[SKIP] Skipped:${C_RESET}         ${COUNT_SKIP}"
    if [[ "$TOTAL_CHECKS" -gt 0 ]]; then
        local pct=$(( (COUNT_OK * 100) / TOTAL_CHECKS ))
        echo -e "  ${C_CYAN}${C_BOLD}Automated Pass Rate:${C_RESET}    ${pct}% (${COUNT_OK}/${TOTAL_CHECKS})"
    fi
    echo -e "${C_BLUE}==========================================================================================${C_RESET}"
}

main() {
    setup_colors_and_init
    print_banner
    run_section_1
    run_section_2
    run_section_3
    run_section_4
    run_section_5
    run_section_6
    run_section_7
    print_summary
}

main "$@"
