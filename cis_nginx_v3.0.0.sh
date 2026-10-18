#!/usr/bin/env bash
# ==============================================================================
# CIS NGINX Benchmark v3.0.0 - Standalone Security Audit Script
# Benchmark:   CIS NGINX Benchmark v3.0.0 (12-24-2025)
# Coverage:    All 44 Recommendations (Sections 1 through 6, Level 1 & Level 2)
# Repository:  https://github.com/nmwafa/cis-audit
# ==============================================================================

set -u

SEP_LINE="=========================================================================================="
DIV_LINE="------------------------------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# CLI Options & Defaults
# ------------------------------------------------------------------------------
PROFILE_LEVEL="all"      # 1, 2, or all
TARGET_SECTION="all"     # 1..6 or all
NGINX_CONF_DIR=""
NGINX_BIN=""
AUTHORIZED_PORTS="80,443"
OUTPUT_FILE=""
USE_COLOR=1
FORCE_COLOR="${FORCE_COLOR:-0}"
QUIET_OK=0

usage() {
    cat <<'EOF'
Usage: ./cis_nginx_v3.0.0.sh [OPTIONS]

Standalone, zero-install Bash script to audit NGINX against all 44
recommendations in the CIS NGINX Benchmark v3.0.0 (12-24-2025).

Options:
  -l, --level <1|2|all>     Filter by CIS Profile Level (default: all)
  -s, --section <1..6|all>  Audit only a specific section (1-6) (default: all)
  -c, --config-dir <dir>    Specify NGINX configuration directory (default: auto-detected or /etc/nginx)
  -b, --binary <path>       Specify NGINX binary path (default: auto-detected from PATH)
  -p, --ports <ports>       Comma-separated list of authorized ports (default: 80,443)
  -o, --output <file>       Save full audit report to a file
  -q, --quiet-ok            Hide [OK] results and only show findings/remediations
  -n, --no-color            Disable ANSI color codes in output
      --color               Force ANSI color output even when piped
  -h, --help                Display this help message and exit
EOF
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
        -c|--config-dir)
            NGINX_CONF_DIR="${2:-}"
            shift 2
            ;;
        -b|--binary)
            NGINX_BIN="${2:-}"
            shift 2
            ;;
        -p|--ports)
            AUTHORIZED_PORTS="${2:-80,443}"
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
    echo -e "\n${C_BG_BLUE} [SECTION ${sec_num}] ${sec_title} ${C_RESET}\n"
    return 0
}

print_subsection_header() {
    echo -e "\n${C_CYAN}${C_BOLD}[+] $1${C_RESET}\n"
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

declare -A SEC_OK=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0)
declare -A SEC_FAIL=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0)
declare -A SEC_MANUAL=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0)
declare -A SEC_SKIP=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0)

setup_colors_and_init() {
    PROFILE_LEVEL="$(normalize_profile_filter "$PROFILE_LEVEL")"
    setup_colors
    if [[ -n "$OUTPUT_FILE" ]]; then
        exec > >(tee "$OUTPUT_FILE") 2>&1
    fi
}

parse_nginx_meta() {
    local raw_title="$1"
    local raw_profile="$2"
    NGX_CLEAN_TITLE="$(echo "$raw_title" | sed -E 's/[[:space:]]*\((Manual|Automated)\)[[:space:]]*$//')"
    if [[ "$raw_profile" == *"Level 2"* ]]; then
        NGX_LEVEL="L2"
    else
        NGX_LEVEL="L1"
    fi
    NGX_TYPE="Automated (${raw_profile})"
}

report_ok() {
    local id="$1"
    local title="$2"
    local profile="$3"
    local details="${4:-}"
    parse_nginx_meta "$title" "$profile"
    report_result "$id" "$NGX_CLEAN_TITLE" "$NGX_LEVEL" "$NGX_TYPE" "OK" "$details" ""
}

report_fail() {
    local id="$1"
    local title="$2"
    local profile="$3"
    local finding="$4"
    local remediation="$5"
    parse_nginx_meta "$title" "$profile"
    report_result "$id" "$NGX_CLEAN_TITLE" "$NGX_LEVEL" "$NGX_TYPE" "FAIL" "$finding" "$remediation"
}

print_warning() {
    if [[ "$(id -u 2>/dev/null || echo 1)" -ne 0 ]]; then
        echo -e "\n${C_YELLOW}[!] WARNING: Script is not running as root (UID 0). Some file permission, shadow, sudo, and live 'nginx -T' checks may require root privileges.${C_RESET}"
    fi
}

discover_nginx() {
    if [[ -z "$NGINX_BIN" ]]; then
        if command -v nginx >/dev/null 2>&1; then
            NGINX_BIN="$(command -v nginx)"
        elif [[ -x /usr/sbin/nginx ]]; then
            NGINX_BIN="/usr/sbin/nginx"
        elif [[ -x /usr/local/nginx/sbin/nginx ]]; then
            NGINX_BIN="/usr/local/nginx/sbin/nginx"
        elif [[ -x /usr/local/sbin/nginx ]]; then
            NGINX_BIN="/usr/local/sbin/nginx"
        fi
    fi

    NGINX_V_OUTPUT=""
    if [[ -n "$NGINX_BIN" && -x "$NGINX_BIN" ]]; then
        NGINX_V_OUTPUT="$("$NGINX_BIN" -V 2>&1 || true)"
    fi

    # Determine NGINX main configuration file and directory
    NGINX_CONF_FILE=""
    if [[ -n "$NGINX_CONF_DIR" ]]; then
        if [[ -f "$NGINX_CONF_DIR" ]]; then
            NGINX_CONF_FILE="$NGINX_CONF_DIR"
            NGINX_CONF_DIR="$(dirname "$NGINX_CONF_FILE")"
        else
            NGINX_CONF_FILE="${NGINX_CONF_DIR%/}/nginx.conf"
        fi
    else
        local conf_path_arg=""
        if [[ -n "$NGINX_V_OUTPUT" ]]; then
            conf_path_arg="$(echo "$NGINX_V_OUTPUT" | grep -oE '\-\-conf-path=[^ ]+' | cut -d= -f2 || true)"
        fi
        if [[ -n "$conf_path_arg" ]]; then
            NGINX_CONF_FILE="$conf_path_arg"
            NGINX_CONF_DIR="$(dirname "$conf_path_arg")"
        else
            NGINX_CONF_DIR="/etc/nginx"
            NGINX_CONF_FILE="/etc/nginx/nginx.conf"
        fi
    fi

    # Determine PID path
    NGINX_PID_FILE=""
    if [[ -n "$NGINX_V_OUTPUT" ]]; then
        NGINX_PID_FILE="$(echo "$NGINX_V_OUTPUT" | grep -oE '\-\-pid-path=[^ ]+' | cut -d= -f2 || true)"
    fi

    # Load full configuration via 'nginx -T' or fallback to reading config files directly
    NGINX_DUMP=""
    if [[ -n "$NGINX_BIN" && -x "$NGINX_BIN" ]]; then
        if [[ -f "$NGINX_CONF_FILE" ]]; then
            NGINX_DUMP="$("$NGINX_BIN" -T -c "$NGINX_CONF_FILE" 2>/dev/null || "$NGINX_BIN" -T 2>/dev/null || true)"
        else
            NGINX_DUMP="$("$NGINX_BIN" -T 2>/dev/null || true)"
        fi
    fi

    if [[ -z "$NGINX_DUMP" && -d "$NGINX_CONF_DIR" ]]; then
        local files=()
        while IFS= read -r -d '' f; do
            files+=("$f")
        done < <(find "$NGINX_CONF_DIR" -type f \( -name "*.conf" -o -path "*/sites-enabled/*" -o -path "*/modules-enabled/*" -o -path "*/conf.d/*" \) -print0 2>/dev/null)
        if [[ ${#files[@]} -gt 0 ]]; then
            NGINX_DUMP="$(cat "${files[@]}" 2>/dev/null || true)"
        fi
    fi

    # Strip comment lines and blank lines for clean directive parsing
    NGINX_ACTIVE_CONF="$(echo "$NGINX_DUMP" | sed -e 's/#.*$//' -e '/^[[:space:]]*$/d')"

    # Fallback PID path from active config or standard paths
    if [[ -z "$NGINX_PID_FILE" ]]; then
        local cfg_pid=""
        cfg_pid="$(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "pid" {gsub(/;/, "", $2); print $2; exit}')"
        if [[ -n "$cfg_pid" ]]; then
            NGINX_PID_FILE="$cfg_pid"
        elif [[ -f /run/nginx.pid ]]; then
            NGINX_PID_FILE="/run/nginx.pid"
        elif [[ -f /var/run/nginx.pid ]]; then
            NGINX_PID_FILE="/var/run/nginx.pid"
        else
            NGINX_PID_FILE="/run/nginx.pid"
        fi
    fi
}

# Compare two semantic versions: returns 0 if $1 >= $2, 1 otherwise
version_ge() {
    local v1="$1"
    local v2="$2"
    local IFS=.
    local i ver1=($v1) ver2=($v2)
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]:-} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 0
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 1
        fi
    done
    return 0
}

# Convert NGINX time value (e.g., 10, 10s, 1m, 500ms) to seconds
parse_time_to_seconds() {
    local val="${1//;/}"
    val="${val//[[:space:]]/}"
    if [[ "$val" =~ ^([0-9]+)ms$ ]]; then
        echo $(( (${BASH_REMATCH[1]} + 999) / 1000 ))
    elif [[ "$val" =~ ^([0-9]+)s?$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$val" =~ ^([0-9]+)m$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 60 ))
    elif [[ "$val" =~ ^([0-9]+)h$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 3600 ))
    elif [[ "$val" =~ ^([0-9]+)d$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 86400 ))
    else
        echo "-1"
    fi
}

# Retrieve configured NGINX worker user
get_nginx_user() {
    local usr=""
    usr="$(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "user" {gsub(/;/, "", $2); print $2; exit}')"
    if [[ -z "$usr" && -n "$NGINX_V_OUTPUT" ]]; then
        usr="$(echo "$NGINX_V_OUTPUT" | grep -oE '\-\-user=[^ ]+' | cut -d= -f2 || true)"
    fi
    echo "$usr"
}

# ==============================================================================
# SECTION 1: INITIAL SETUP
# ==============================================================================

check_1_1_1() {
    local id="1.1.1"
    local title="Ensure NGINX is installed (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Install or upgrade NGINX to version 1.28.0 or later from the official nginx.org repository.
2. Verify installation with: nginx -V
3. Test configuration syntax before restarting: nginx -t"

    if [[ -z "$NGINX_BIN" || ! -x "$NGINX_BIN" ]]; then
        report_fail "$id" "$title" "$profile" \
            "NGINX binary was not found on the system." \
            "$remediation"
        return
    fi

    local ver=""
    ver="$(echo "$NGINX_V_OUTPUT" | grep -oE 'nginx/[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d/ -f2 || true)"
    if [[ -z "$ver" ]]; then
        report_fail "$id" "$title" "$profile" \
            "NGINX binary found at ${NGINX_BIN}, but version could not be parsed from 'nginx -V'." \
            "$remediation"
        return
    fi

    if version_ge "$ver" "1.28.0"; then
        report_ok "$id" "$title" "$profile" "NGINX is installed (version ${ver} >= 1.28.0)."
    else
        report_fail "$id" "$title" "$profile" \
            "Installed NGINX version is ${ver}, which is older than the required minimum version 1.28.0." \
            "$remediation"
    fi
}

check_1_2_1() {
    local id="1.2.1"
    local title="Ensure package manager repositories are properly configured (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Configure your package manager to use a trusted repository (preferably official nginx.org repository for HTTP/3 and modern TLS support).
2. Follow instructions at https://nginx.org/en/linux_packages.html to add the NGINX signing key and repository configuration file.
3. Verify repository configuration with:
   - RHEL/Rocky: dnf repolist -v | grep -i nginx
   - Debian/Ubuntu: apt-cache policy nginx"

    if command -v dnf >/dev/null 2>&1; then
        local repo_out=""
        repo_out="$(dnf repolist -v 2>/dev/null | grep -iE 'nginx|rhel|rocky|alma|centos|fedora' || true)"
        if [[ -n "$repo_out" ]] && echo "$repo_out" | grep -qi "nginx.org"; then
            report_ok "$id" "$title" "$profile" "Official nginx.org repository is configured in dnf."
        elif [[ -n "$repo_out" ]]; then
            report_fail "$id" "$title" "$profile" \
                "OS vendor repository detected in dnf, but official nginx.org repository was not confirmed. Verify repository trust and version support manually." \
                "$remediation"
        else
            report_fail "$id" "$title" "$profile" \
                "No enabled NGINX package repository was found via 'dnf repolist -v'." \
                "$remediation"
        fi
    elif command -v apt-cache >/dev/null 2>&1; then
        local policy_out=""
        policy_out="$(apt-cache policy nginx 2>/dev/null || true)"
        if echo "$policy_out" | grep -qE 'https?://([^/]*\.)?(nginx\.org|ubuntu\.com|debian\.org)'; then
            if echo "$policy_out" | grep -qE 'https?://([^/]*\.)?nginx\.org'; then
                report_ok "$id" "$title" "$profile" "Official nginx.org repository is configured in APT."
            else
                local cand_ver=""
                cand_ver="$(echo "$policy_out" | awk '/Candidate:/ {print $2}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
                if [[ -n "$cand_ver" ]] && version_ge "$cand_ver" "1.28.0"; then
                    report_ok "$id" "$title" "$profile" "Trusted OS repository configured with modern NGINX candidate (${cand_ver})."
                else
                    report_fail "$id" "$title" "$profile" \
                        "APT uses OS default repository (candidate: ${cand_ver:-none}) rather than official nginx.org repository required for NGINX >= 1.28.0." \
                        "$remediation"
                fi
            fi
        else
            report_fail "$id" "$title" "$profile" \
                "No trusted NGINX package repository found via 'apt-cache policy nginx'." \
                "$remediation"
        fi
    elif command -v yum >/dev/null 2>&1; then
        local yum_out=""
        yum_out="$(yum repolist -v 2>/dev/null | grep -i nginx || true)"
        if [[ -n "$yum_out" ]] && echo "$yum_out" | grep -qi "nginx.org"; then
            report_ok "$id" "$title" "$profile" "Official nginx.org repository is configured in yum."
        else
            report_fail "$id" "$title" "$profile" \
                "Official nginx.org repository was not detected in yum." \
                "$remediation"
        fi
    else
        report_fail "$id" "$title" "$profile" \
            "Supported package manager (dnf/apt-cache/yum) not detected or no NGINX repository configured." \
            "$remediation"
    fi
}

check_1_2_2() {
    local id="1.2.2"
    local title="Ensure the latest software package is installed (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Update the NGINX package using your system package manager:
   - RHEL/Rocky: dnf update nginx -y
   - Debian/Ubuntu: apt-get update && apt-get install --only-upgrade nginx -y
2. Reload or restart the NGINX service after verifying syntax with 'nginx -t'."

    if command -v dnf >/dev/null 2>&1; then
        if ! rpm -q nginx >/dev/null 2>&1; then
            report_fail "$id" "$title" "$profile" \
                "The 'nginx' RPM package is not installed." \
                "$remediation"
            return
        fi
        local upd_rc=0
        dnf check-update nginx >/dev/null 2>&1 || upd_rc=$?
        if [[ "$upd_rc" -eq 0 ]]; then
            report_ok "$id" "$title" "$profile" "Installed NGINX package is up to date according to dnf."
        else
            report_fail "$id" "$title" "$profile" \
                "A newer NGINX package is available or package update status could not be verified (dnf check-update exit code: ${upd_rc})." \
                "$remediation"
        fi
    elif command -v apt-cache >/dev/null 2>&1; then
        local policy_out=""
        policy_out="$(apt-cache policy nginx 2>/dev/null || true)"
        local inst=""
        local cand=""
        inst="$(echo "$policy_out" | awk '/Installed:/ {print $2}')"
        cand="$(echo "$policy_out" | awk '/Candidate:/ {print $2}')"
        if [[ -z "$inst" || "$inst" == "(none)" ]]; then
            report_fail "$id" "$title" "$profile" \
                "NGINX package is not installed (Installed: ${inst:-none})." \
                "$remediation"
        elif [[ "$inst" == "$cand" ]]; then
            report_ok "$id" "$title" "$profile" "Installed NGINX package (${inst}) matches latest repository candidate."
        else
            report_fail "$id" "$title" "$profile" \
                "Installed NGINX package (${inst}) is older than repository candidate (${cand})." \
                "$remediation"
        fi
    else
        report_fail "$id" "$title" "$profile" \
            "Unable to verify NGINX package update status automatically." \
            "$remediation"
    fi
}

# ==============================================================================
# SECTION 2: BASIC CONFIGURATION
# ==============================================================================

check_2_1_1() {
    local id="2.1.1"
    local title="Ensure only required dynamic modules are loaded (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Open the main configuration file (${NGINX_CONF_FILE}) or include files in ${NGINX_CONF_DIR}/modules-enabled/.
2. Comment out or remove the 'load_module' directive for any dynamic module that is not strictly required for business logic.
3. For static modules compiled into the binary, ensure risky directives (such as 'autoindex on;' or 'stub_status;') are not enabled in any server or location block."

    if [[ -z "$NGINX_ACTIVE_CONF" ]]; then
        report_fail "$id" "$title" "$profile" \
            "NGINX configuration could not be loaded to inspect dynamic modules." \
            "$remediation"
        return
    fi

    local dyn_modules=""
    dyn_modules="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*load_module[[:space:]]+' || true)"
    local risky_directives=""
    risky_directives="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*(autoindex[[:space:]]+on|stub_status)[[:space:];]' || true)"

    if [[ -z "$dyn_modules" && -z "$risky_directives" ]]; then
        report_ok "$id" "$title" "$profile" "No dynamic modules ('load_module') or risky module directives ('autoindex on', 'stub_status') are loaded."
    else
        local msg=""
        [[ -n "$dyn_modules" ]] && msg+="Loaded dynamic modules found requiring review: $(echo "$dyn_modules" | tr '\n' ' '). "
        [[ -n "$risky_directives" ]] && msg+="Risky static module directives enabled: $(echo "$risky_directives" | tr '\n' ' ')."
        report_fail "$id" "$title" "$profile" "$msg" "$remediation"
    fi
}

check_2_2_1() {
    local id="2.2.1"
    local title="Ensure that NGINX is run using a non-privileged, dedicated service account (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Create a dedicated system user with no login shell (if missing):
   useradd -r -d /var/cache/nginx -s /sbin/nologin nginx
2. Set the user directive in the main context of ${NGINX_CONF_FILE}:
   user nginx;
3. Ensure the user UID is not 0 (root), is not a member of privileged groups (root, wheel, sudo), and has no sudo access:
   usermod -s /sbin/nologin nginx
   usermod -L nginx"

    local usr=""
    usr="$(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "user" {gsub(/;/, "", $2); print $2; exit}')"
    if [[ -z "$usr" ]]; then
        report_fail "$id" "$title" "$profile" \
            "The 'user' directive is not explicitly defined in the NGINX configuration." \
            "$remediation"
        return
    fi

    if ! id "$usr" >/dev/null 2>&1; then
        report_fail "$id" "$title" "$profile" \
            "Configured NGINX user '${usr}' does not exist on the operating system." \
            "$remediation"
        return
    fi

    local uid=""
    uid="$(id -u "$usr" 2>/dev/null || echo 0)"
    local groups_list=""
    groups_list="$(id -Gn "$usr" 2>/dev/null || true)"

    local issues=()
    if [[ "$uid" -eq 0 || "$usr" == "root" ]]; then
        issues+=("User '${usr}' has UID 0 (root).")
    fi
    if echo " $groups_list " | grep -qE ' (root|wheel|sudo|adm|admin) '; then
        issues+=("User '${usr}' belongs to a privileged group (${groups_list}).")
    fi
    if command -v sudo >/dev/null 2>&1 && [[ "$(id -u)" -eq 0 ]]; then
        local sudo_out=""
        sudo_out="$(sudo -l -U "$usr" 2>/dev/null || true)"
        if [[ -n "$sudo_out" ]] && ! echo "$sudo_out" | grep -qiE "not allowed to run sudo|no matching"; then
            issues+=("User '${usr}' has sudo privileges configured.")
        fi
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "NGINX is configured to run as non-privileged dedicated user '${usr}' (UID: ${uid}, Groups: ${groups_list})."
    else
        report_fail "$id" "$title" "$profile" "${issues[*]}" "$remediation"
    fi
}

check_2_2_2() {
    local id="2.2.2"
    local title="Ensure the NGINX service account is locked (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local usr
    usr="$(get_nginx_user)"
    local target_user="${usr:-nginx}"
    local remediation="1. Lock the NGINX service account using the passwd command:
   passwd -l ${target_user}
2. Verify lock status with:
   passwd -S ${target_user}"

    if [[ -z "$usr" ]] || ! id "$usr" >/dev/null 2>&1; then
        report_fail "$id" "$title" "$profile" \
            "Cannot verify account lock status because NGINX service user ('${usr:-unset}') is not configured or does not exist." \
            "$remediation"
        return
    fi

    local passwd_status=""
    passwd_status="$(passwd -S "$usr" 2>/dev/null || true)"
    if [[ -n "$passwd_status" ]]; then
        local status_code=""
        status_code="$(echo "$passwd_status" | awk '{print $2}')"
        if [[ "$status_code" == "LK" || "$status_code" == "L" ]] || echo "$passwd_status" | grep -qi "Password locked"; then
            report_ok "$id" "$title" "$profile" "Service account '${usr}' is locked (${passwd_status})."
            return
        else
            report_fail "$id" "$title" "$profile" \
                "Service account '${usr}' is not locked (passwd -S output: ${passwd_status})." \
                "$remediation"
            return
        fi
    fi

    # Fallback to /etc/shadow if readable
    if [[ -r /etc/shadow ]]; then
        local shadow_field=""
        shadow_field="$(awk -F: -v u="$usr" '$1 == u {print $2}' /etc/shadow)"
        if [[ "$shadow_field" =~ ^[\!\*] ]]; then
            report_ok "$id" "$title" "$profile" "Service account '${usr}' is locked in /etc/shadow."
            return
        else
            report_fail "$id" "$title" "$profile" \
                "Service account '${usr}' does not have a locked password entry in /etc/shadow." \
                "$remediation"
            return
        fi
    fi

    report_fail "$id" "$title" "$profile" \
        "Unable to verify lock status for user '${usr}' (run script as root to execute 'passwd -S ${usr}')." \
        "$remediation"
}

check_2_2_3() {
    local id="2.2.3"
    local title="Ensure the NGINX service account has an invalid shell (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local usr
    usr="$(get_nginx_user)"
    local target_user="${usr:-nginx}"
    local remediation="1. Change the login shell for the NGINX service user to /sbin/nologin:
   usermod -s /sbin/nologin ${target_user}
2. Verify with:
   getent passwd ${target_user}"

    if [[ -z "$usr" ]]; then
        report_fail "$id" "$title" "$profile" \
            "NGINX service user is not defined in configuration." \
            "$remediation"
        return
    fi

    local passwd_entry=""
    passwd_entry="$(getent passwd "$usr" 2>/dev/null || grep -E "^${usr}:" /etc/passwd 2>/dev/null || true)"
    if [[ -z "$passwd_entry" ]]; then
        report_fail "$id" "$title" "$profile" \
            "User '${usr}' was not found in system passwd database." \
            "$remediation"
        return
    fi

    local user_shell=""
    user_shell="$(echo "$passwd_entry" | awk -F: '{print $NF}')"
    case "$user_shell" in
        /sbin/nologin|/usr/sbin/nologin|/bin/nologin|/usr/bin/nologin|/bin/false|/usr/bin/false)
            report_ok "$id" "$title" "$profile" "User '${usr}' has an invalid login shell (${user_shell})."
            ;;
        *)
            report_fail "$id" "$title" "$profile" \
                "User '${usr}' is configured with an interactive or non-standard shell (${user_shell})." \
                "$remediation"
            ;;
    esac
}

check_2_3_1() {
    local id="2.3.1"
    local title="Ensure NGINX directories and files are owned by root (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Set ownership of the NGINX configuration directory and all contained files to root:root:
   chown -R root:root ${NGINX_CONF_DIR}"

    if [[ ! -d "$NGINX_CONF_DIR" ]]; then
        report_fail "$id" "$title" "$profile" \
            "NGINX configuration directory '${NGINX_CONF_DIR}' does not exist." \
            "$remediation"
        return
    fi

    local bad_files=""
    bad_files="$(find "$NGINX_CONF_DIR" \( -not -user root -o -not -group root \) -exec ls -ld {} \; 2>/dev/null || true)"
    if [[ -z "$bad_files" ]]; then
        report_ok "$id" "$title" "$profile" "All files and directories in ${NGINX_CONF_DIR} are owned by root:root."
    else
        local sample=""
        sample="$(echo "$bad_files" | head -n 5 | tr '\n' '; ')"
        report_fail "$id" "$title" "$profile" \
            "Found files/directories in ${NGINX_CONF_DIR} not owned by root:root: ${sample}" \
            "$remediation"
    fi
}

check_2_3_2() {
    local id="2.3.2"
    local title="Ensure access to NGINX directories and files is restricted (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Restrict directory permissions in ${NGINX_CONF_DIR} to 750 or stricter:
   find ${NGINX_CONF_DIR} -type d -exec chmod 750 {} +
2. Restrict file permissions in ${NGINX_CONF_DIR} to 640 or stricter:
   find ${NGINX_CONF_DIR} -type f -exec chmod 640 {} +"

    if [[ ! -d "$NGINX_CONF_DIR" ]]; then
        report_fail "$id" "$title" "$profile" \
            "NGINX configuration directory '${NGINX_CONF_DIR}' does not exist." \
            "$remediation"
        return
    fi

    # Directories must not have group write (020) or any world permissions (007) -> /027
    local loose_dirs=""
    loose_dirs="$(find "$NGINX_CONF_DIR" -type d -perm /027 -exec stat -Lc "%n (%a)" {} + 2>/dev/null || true)"
    # Files must not have owner exec (100), group write/exec (030), or any world permissions (007) -> /137
    local loose_files=""
    loose_files="$(find "$NGINX_CONF_DIR" -type f -perm /137 -exec stat -Lc "%n (%a)" {} + 2>/dev/null || true)"

    if [[ -z "$loose_dirs" && -z "$loose_files" ]]; then
        report_ok "$id" "$title" "$profile" "All directories (<=750) and files (<=640) in ${NGINX_CONF_DIR} have restricted permissions."
    else
        local msg=""
        [[ -n "$loose_dirs" ]] && msg+="Directories with permissions looser than 750: $(echo "$loose_dirs" | head -n 5 | tr '\n' ' '). "
        [[ -n "$loose_files" ]] && msg+="Files with permissions looser than 640: $(echo "$loose_files" | head -n 5 | tr '\n' ' ')."
        report_fail "$id" "$title" "$profile" "$msg" "$remediation"
    fi
}

check_2_3_3() {
    local id="2.3.3"
    local title="Ensure the NGINX process ID (PID) file is secured (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Set ownership of the NGINX PID file to root:root and permissions to 644 or stricter:
   chown root:root ${NGINX_PID_FILE}
   chmod 644 ${NGINX_PID_FILE}"

    if [[ ! -e "$NGINX_PID_FILE" ]]; then
        report_fail "$id" "$title" "$profile" \
            "NGINX PID file '${NGINX_PID_FILE}' does not exist (NGINX may not be running)." \
            "$remediation"
        return
    fi

    local owner_group=""
    local perms=""
    owner_group="$(stat -Lc "%U:%G" "$NGINX_PID_FILE" 2>/dev/null || true)"
    perms="$(stat -Lc "%a" "$NGINX_PID_FILE" 2>/dev/null || true)"

    local loose_perm=""
    loose_perm="$(find -L "$NGINX_PID_FILE" -perm /133 2>/dev/null || true)"

    if [[ "$owner_group" == "root:root" && -z "$loose_perm" ]]; then
        report_ok "$id" "$title" "$profile" "PID file ${NGINX_PID_FILE} is owned by root:root with permissions ${perms} (<=644)."
    else
        report_fail "$id" "$title" "$profile" \
            "PID file ${NGINX_PID_FILE} has owner '${owner_group}' and permissions '${perms}' (expected root:root and <=644)." \
            "$remediation"
    fi
}

check_2_4_1() {
    local id="2.4.1"
    local title="Ensure NGINX only listens for network connections on authorized ports (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Inspect all 'listen' directives in your NGINX configuration:
   nginx -T 2>/dev/null | grep -r \"listen\"
2. Remove or comment out any 'listen' directives that bind to unauthorized ports.
3. Keep only authorized ports (e.g., TCP 80 for HTTP redirect, TCP 443 ssl for HTTPS, and UDP 443 quic for HTTP/3)."

    local listen_lines=""
    listen_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*listen[[:space:]]+' || true)"
    if [[ -z "$listen_lines" ]]; then
        report_fail "$id" "$title" "$profile" \
            "No 'listen' directives were found in the NGINX configuration." \
            "$remediation"
        return
    fi

    local IFS=,
    local allowed_list=($AUTHORIZED_PORTS)
    unset IFS

    local unauthorized=()
    local found_ports=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local token=""
        token="$(echo "$line" | awk '{print $2}' | sed 's/;//g')"
        if [[ "$token" =~ ^unix: ]]; then
            continue
        fi
        local port=""
        if [[ "$token" =~ :([0-9]+)$ ]]; then
            port="${BASH_REMATCH[1]}"
        elif [[ "$token" =~ ^([0-9]+)$ ]]; then
            port="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$port" ]]; then
            if [[ ! " ${found_ports[*]:-} " =~ " ${port} " ]]; then
                found_ports+=("$port")
            fi
            local is_allowed=0
            local p
            for p in "${allowed_list[@]}"; do
                if [[ "$port" == "$p" ]]; then
                    is_allowed=1
                    break
                fi
            done
            if [[ "$is_allowed" -eq 0 ]]; then
                unauthorized+=("${port} (${line##*listen })")
            fi
        fi
    done <<< "$listen_lines"

    if [[ ${#unauthorized[@]} -eq 0 && ${#found_ports[@]} -gt 0 ]]; then
        report_ok "$id" "$title" "$profile" "All configured listen ports (${found_ports[*]}) are in the authorized list (${AUTHORIZED_PORTS})."
    else
        report_fail "$id" "$title" "$profile" \
            "Unauthorized listen port(s) detected: ${unauthorized[*]:-none} (Authorized ports: ${AUTHORIZED_PORTS})." \
            "$remediation"
    fi
}

check_2_4_2() {
    local id="2.4.2"
    local title="Ensure requests for unknown host names are rejected (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Configure a catch-all 'default_server' block in your NGINX configuration:
   server {
       listen 80 default_server;
       listen [::]:80 default_server;
       listen 443 ssl default_server;
       listen [::]:443 ssl default_server;
       listen 443 quic default_server;
       listen [::]:443 quic default_server;
       ssl_reject_handshake on;
       server_name _;
       return 444;
   }
2. Ensure all valid applications have their own server blocks with explicit 'server_name' directives."

    local has_default_server=""
    has_default_server="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*listen[[:space:]].*default_server' || true)"
    local has_ssl_reject=""
    has_ssl_reject="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*ssl_reject_handshake[[:space:]]+on[[:space:]]*;' || true)"
    local has_return_444=""
    has_return_444="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*return[[:space:]]+(444|40[034])[[:space:]]*;' || true)"

    if [[ -n "$has_default_server" && -n "$has_ssl_reject" && -n "$has_return_444" ]]; then
        report_ok "$id" "$title" "$profile" "Default catch-all server block with 'default_server', 'ssl_reject_handshake on;', and connection rejection ('return 444;') is present."
    else
        local missing=()
        [[ -z "$has_default_server" ]] && missing+=("'listen ... default_server'")
        [[ -z "$has_ssl_reject" ]] && missing+=("'ssl_reject_handshake on;'")
        [[ -z "$has_return_444" ]] && missing+=("'return 444;' (or 4xx rejection)")
        report_fail "$id" "$title" "$profile" \
            "Missing unknown host rejection components: ${missing[*]}." \
            "$remediation"
    fi
}

check_2_4_3() {
    local id="2.4.3"
    local title="Ensure keepalive_timeout is 10 seconds or less, but not 0 (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Add or update the 'keepalive_timeout' directive in the 'http' or 'server' block of ${NGINX_CONF_FILE}:
   keepalive_timeout 10;
2. Ensure the value is between 1 and 10 seconds (not 0)."

    local lines=""
    lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*keepalive_timeout[[:space:]]+' || true)"
    if [[ -z "$lines" ]]; then
        report_fail "$id" "$title" "$profile" \
            "'keepalive_timeout' is not explicitly set (defaults to 75s)." \
            "$remediation"
        return
    fi

    local bad_vals=()
    local ok_vals=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local raw_val=""
        raw_val="$(echo "$line" | awk '{print $2}' | sed 's/;//g')"
        local secs
        secs="$(parse_time_to_seconds "$raw_val")"
        if [[ "$secs" -ge 1 && "$secs" -le 10 ]]; then
            ok_vals+=("${raw_val}")
        else
            bad_vals+=("${raw_val}")
        fi
    done <<< "$lines"

    if [[ ${#bad_vals[@]} -eq 0 && ${#ok_vals[@]} -gt 0 ]]; then
        report_ok "$id" "$title" "$profile" "keepalive_timeout is properly configured (${ok_vals[*]})."
    else
        report_fail "$id" "$title" "$profile" \
            "Invalid keepalive_timeout value(s) detected: ${bad_vals[*]} (must be between 1 and 10 seconds, not 0)." \
            "$remediation"
    fi
}

check_2_4_4() {
    local id="2.4.4"
    local title="Ensure send_timeout is set to 10 seconds or less, but not 0 (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Add or update the 'send_timeout' directive in the 'http' or 'server' block of ${NGINX_CONF_FILE}:
   send_timeout 10;
2. Ensure the value is between 1 and 10 seconds (not 0)."

    local lines=""
    lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*send_timeout[[:space:]]+' || true)"
    if [[ -z "$lines" ]]; then
        report_fail "$id" "$title" "$profile" \
            "'send_timeout' is not explicitly set (defaults to 60s)." \
            "$remediation"
        return
    fi

    local bad_vals=()
    local ok_vals=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local raw_val=""
        raw_val="$(echo "$line" | awk '{print $2}' | sed 's/;//g')"
        local secs
        secs="$(parse_time_to_seconds "$raw_val")"
        if [[ "$secs" -ge 1 && "$secs" -le 10 ]]; then
            ok_vals+=("${raw_val}")
        else
            bad_vals+=("${raw_val}")
        fi
    done <<< "$lines"

    if [[ ${#bad_vals[@]} -eq 0 && ${#ok_vals[@]} -gt 0 ]]; then
        report_ok "$id" "$title" "$profile" "send_timeout is properly configured (${ok_vals[*]})."
    else
        report_fail "$id" "$title" "$profile" \
            "Invalid send_timeout value(s) detected: ${bad_vals[*]} (must be between 1 and 10 seconds, not 0)." \
            "$remediation"
    fi
}

check_2_5_1() {
    local id="2.5.1"
    local title="Ensure server_tokens directive is set to 'off' (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Disable version disclosure globally by adding 'server_tokens off;' to the 'http' block in ${NGINX_CONF_FILE}:
   http {
       server_tokens off;
   }"

    local off_lines=""
    off_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*server_tokens[[:space:]]+off[[:space:]]*;' || true)"
    local on_lines=""
    on_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*server_tokens[[:space:]]+on[[:space:]]*;' || true)"

    if [[ -n "$off_lines" && -z "$on_lines" ]]; then
        report_ok "$id" "$title" "$profile" "'server_tokens off;' is configured and no 'server_tokens on;' override exists."
    else
        report_fail "$id" "$title" "$profile" \
            "'server_tokens off;' is missing or overridden by 'server_tokens on;'." \
            "$remediation"
    fi
}

check_2_5_2() {
    local id="2.5.2"
    local title="Ensure default error and index.html pages do not reference NGINX (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Create custom error pages (e.g., in /var/www/html/errors/404.html and 50x.html) without any 'nginx' branding.
2. Configure custom error_page directives in your http or server blocks:
   error_page 404 /404.html;
   error_page 500 502 503 504 /50x.html;
   location = /50x.html {
       root /var/www/html/errors;
       internal;
   }
3. Remove or replace default index.html and 50x.html files in /usr/share/nginx/html or /var/www/html that mention 'nginx'."

    local err_pages=""
    err_pages="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*error_page[[:space:]]+' || true)"

    local branded_files=()
    local search_dirs=("/usr/share/nginx/html" "/var/www/html")
    while IFS= read -r rdir; do
        [[ -n "$rdir" && -d "$rdir" ]] && search_dirs+=("$rdir")
    done < <(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "root" {gsub(/;/, "", $2); print $2}' | sort -u)

    local d
    for d in "${search_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                if grep -qi "nginx" "$f" 2>/dev/null; then
                    branded_files+=("$f")
                fi
            done < <(find "$d" -maxdepth 2 -type f \( -name "*.html" -o -name "*.htm" \) 2>/dev/null)
        fi
    done

    if [[ -n "$err_pages" && ${#branded_files[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "Custom error_page directives are configured and no HTML files referencing 'nginx' were found."
    else
        local msg=""
        [[ -z "$err_pages" ]] && msg+="No custom 'error_page' directives found in configuration. "
        [[ ${#branded_files[@]} -gt 0 ]] && msg+="Default HTML/error pages containing 'nginx' branding found: ${branded_files[*]}."
        report_fail "$id" "$title" "$profile" "$msg" "$remediation"
    fi
}

check_2_5_3() {
    local id="2.5.3"
    local title="Ensure hidden file serving is disabled (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Add a location block to deny access to hidden dot-files inside each server block (or via a shared snippet):
   # Optional: Allow Let's Encrypt ACME challenge before the deny rule
   location ^~ /.well-known/acme-challenge/ {
       allow all;
       default_type \"text/plain\";
   }
   # Deny access to all other hidden files
   location ~ /\\. {
       deny all;
       return 404;
   }"

    local dot_loc=""
    dot_loc="$(echo "$NGINX_ACTIVE_CONF" | grep -E 'location[[:space:]]+~[[:space:]]*(/\\\.|\^/\\\.|\\\.)' || true)"
    if [[ -n "$dot_loc" ]]; then
        report_ok "$id" "$title" "$profile" "Hidden file protection rule ('location ~ /\\.') is present in configuration."
    else
        report_fail "$id" "$title" "$profile" \
            "No 'location ~ /\\.' block denying hidden dot-file access was found in the loaded configuration." \
            "$remediation"
    fi
}

check_2_5_4() {
    local id="2.5.4"
    local title="Ensure the NGINX reverse proxy does not enable information disclosure (Manual)"
    local profile="Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Add the following directives to your http, server, or proxied location block to strip backend headers:
   proxy_hide_header X-Powered-By;
   proxy_hide_header Server;
2. If using FastCGI (e.g., PHP-FPM), also add:
   fastcgi_hide_header X-Powered-By;"

    local hide_xpb=""
    hide_xpb="$(echo "$NGINX_ACTIVE_CONF" | grep -Ei '^[[:space:]]*(proxy|fastcgi)_hide_header[[:space:]]+X-Powered-By[[:space:]]*;' || true)"
    local hide_srv=""
    hide_srv="$(echo "$NGINX_ACTIVE_CONF" | grep -Ei '^[[:space:]]*(proxy|fastcgi)_hide_header[[:space:]]+Server[[:space:]]*;' || true)"

    if [[ -n "$hide_xpb" && -n "$hide_srv" ]]; then
        report_ok "$id" "$title" "$profile" "Directives to hide both 'X-Powered-By' and 'Server' headers are configured."
    else
        local missing=()
        [[ -z "$hide_xpb" ]] && missing+=("proxy_hide_header X-Powered-By;")
        [[ -z "$hide_srv" ]] && missing+=("proxy_hide_header Server;")
        report_fail "$id" "$title" "$profile" \
            "Missing reverse proxy header hiding directive(s): ${missing[*]}." \
            "$remediation"
    fi
}

# ==============================================================================
# SECTION 3: LOGGING
# ==============================================================================

check_3_1() {
    local id="3.1"
    local title="Ensure detailed logging is enabled (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Define a detailed log_format (preferably JSON) in the 'http' block of ${NGINX_CONF_FILE}:
   log_format main_access_json escape=json '{'
       '\"timestamp\": \"\$time_iso8601\",'
       '\"remote_addr\": \"\$remote_addr\",'
       '\"remote_user\": \"\$remote_user\",'
       '\"server_name\": \"\$server_name\",'
       '\"request_method\": \"\$request_method\",'
       '\"request_uri\": \"\$request_uri\",'
       '\"status\": \$status,'
       '\"body_bytes_sent\": \$body_bytes_sent,'
       '\"http_referer\": \"\$http_referer\",'
       '\"http_user_agent\": \"\$http_user_agent\",'
       '\"x_forwarded_for\": \"\$http_x_forwarded_for\",'
       '\"request_id\": \"\$request_id\"'
   '}';
2. Apply the detailed format to your access_log directive:
   access_log /var/log/nginx/access.json main_access_json;"

    local has_log_format=""
    has_log_format="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*log_format[[:space:]]+' || true)"
    if [[ -z "$has_log_format" ]]; then
        report_fail "$id" "$title" "$profile" \
            "No custom 'log_format' directive is defined in the active NGINX configuration." \
            "$remediation"
        return
    fi

    # Verify critical fields across active configuration
    local missing_vars=()
    echo "$NGINX_ACTIVE_CONF" | grep -qE '\$time_iso8601|\$time_local' || missing_vars+=("\$time_iso8601/\$time_local")
    echo "$NGINX_ACTIVE_CONF" | grep -q '\$remote_addr' || missing_vars+=("\$remote_addr")
    echo "$NGINX_ACTIVE_CONF" | grep -q '\$remote_user' || missing_vars+=("\$remote_user")
    echo "$NGINX_ACTIVE_CONF" | grep -qE '\$request|\$request_uri' || missing_vars+=("\$request/\$request_uri")
    echo "$NGINX_ACTIVE_CONF" | grep -q '\$status' || missing_vars+=("\$status")
    echo "$NGINX_ACTIVE_CONF" | grep -q '\$http_user_agent' || missing_vars+=("\$http_user_agent")
    echo "$NGINX_ACTIVE_CONF" | grep -q '\$http_x_forwarded_for' || missing_vars+=("\$http_x_forwarded_for")

    if [[ ${#missing_vars[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "Detailed custom log_format with all required forensic variables is configured."
    else
        report_fail "$id" "$title" "$profile" \
            "Custom log_format is missing required forensic variables: ${missing_vars[*]}." \
            "$remediation"
    fi
}

check_3_2() {
    local id="3.2"
    local title="Ensure access logging is enabled (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Enable access_log in the 'http' and 'server' blocks pointing to a valid local file path:
   access_log /var/log/nginx/access.json main_access_json;
2. Ensure 'access_log off;' is not applied globally in the 'http' block or in 'server' blocks handling business logic."

    local access_lines=""
    access_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*access_log[[:space:]]+' || true)"
    local access_off=""
    access_off="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*access_log[[:space:]]+off[[:space:]]*;' || true)"

    if [[ -z "$access_lines" ]]; then
        report_fail "$id" "$title" "$profile" \
            "No explicit 'access_log' directive was found in the configuration." \
            "$remediation"
        return
    fi

    local valid_dest=""
    valid_dest="$(echo "$access_lines" | grep -vE 'access_log[[:space:]]+off' || true)"

    if [[ -n "$valid_dest" && -z "$access_off" ]]; then
        report_ok "$id" "$title" "$profile" "Access logging is enabled and no 'access_log off;' directives were found."
    elif [[ -n "$valid_dest" && -n "$access_off" ]]; then
        report_fail "$id" "$title" "$profile" \
            "Found 'access_log off;' in configuration. Verify it is strictly limited to non-critical assets (e.g., /favicon.ico) and not applied globally." \
            "$remediation"
    else
        report_fail "$id" "$title" "$profile" \
            "Access logging is disabled ('access_log off;')." \
            "$remediation"
    fi
}

check_3_3() {
    local id="3.3"
    local title="Ensure error logging is enabled and set to the info logging level (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Configure the 'error_log' directive in the main context of ${NGINX_CONF_FILE} with level 'info' or 'notice':
   error_log /var/log/nginx/error.log info;"

    local err_lines=""
    err_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*error_log[[:space:]]+' || true)"
    if [[ -z "$err_lines" ]]; then
        report_fail "$id" "$title" "$profile" \
            "No explicit 'error_log' directive found (defaults to level 'error', which misses info/notice events)." \
            "$remediation"
        return
    fi

    if echo "$err_lines" | grep -qE '/dev/null|[[:space:]]+(crit|alert|emerg)[[:space:]]*;'; then
        report_fail "$id" "$title" "$profile" \
            "error_log points to /dev/null or uses an overly restrictive severity level (crit, alert, emerg): $(echo "$err_lines" | tr '\n' ' ')" \
            "$remediation"
        return
    fi

    if echo "$err_lines" | grep -qE '^[[:space:]]*error_log[[:space:]]+[^[:space:];]+[[:space:]]+(info|notice|debug)[[:space:]]*;'; then
        report_ok "$id" "$title" "$profile" "error_log is enabled and set to an appropriate verbosity level ($(echo "$err_lines" | tr '\n' ' '))."
    else
        report_fail "$id" "$title" "$profile" \
            "error_log is present ($(echo "$err_lines" | tr '\n' ' ')), but severity level is not set to 'info' or 'notice'." \
            "$remediation"
    fi
}

check_3_4() {
    local id="3.4"
    local title="Ensure proxies pass source IP information (Manual)"
    local profile="Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Configure NGINX to forward client IP headers in your server or proxied location blocks:
   proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
   proxy_set_header X-Real-IP \$remote_addr;
   proxy_set_header X-Forwarded-Proto \$scheme;"

    local xff=""
    xff="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*proxy_set_header[[:space:]]+X-Forwarded-For[[:space:]]+(\$proxy_add_x_forwarded_for|\$remote_addr)[[:space:]]*;' || true)"
    local xrip=""
    xrip="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*proxy_set_header[[:space:]]+X-Real-IP[[:space:]]+\$remote_addr[[:space:]]*;' || true)"

    if [[ -n "$xff" && -n "$xrip" ]]; then
        report_ok "$id" "$title" "$profile" "Both 'X-Forwarded-For' and 'X-Real-IP' proxy headers are properly configured."
    else
        local missing=()
        [[ -z "$xff" ]] && missing+=("proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;")
        [[ -z "$xrip" ]] && missing+=("proxy_set_header X-Real-IP \$remote_addr;")
        report_fail "$id" "$title" "$profile" \
            "Missing source IP forwarding header(s): ${missing[*]}." \
            "$remediation"
    fi
}

# ==============================================================================
# SECTION 4: ENCRYPTION
# ==============================================================================

check_4_1_1() {
    local id="4.1.1"
    local title="Ensure HTTP is redirected to HTTPS (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Configure your HTTP (port 80) server block to redirect all traffic to HTTPS:
   server {
       listen 80;
       server_name example.com;
       return 301 https://\$host\$request_uri;
   }"

    local redirect_line=""
    redirect_line="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*(return[[:space:]]+30[1278][[:space:]]+https://|rewrite[[:space:]]+.*https://.*(permanent|redirect))' || true)"

    if [[ -n "$redirect_line" ]]; then
        report_ok "$id" "$title" "$profile" "HTTP to HTTPS redirection rule found ($(echo "$redirect_line" | head -n1 | sed 's/^[[:space:]]*//'))."
    else
        report_fail "$id" "$title" "$profile" \
            "No 'return 301 https://\$host\$request_uri;' (or equivalent HTTPS redirect) found in configuration." \
            "$remediation"
    fi
}

check_4_1_2() {
    local id="4.1.2"
    local title="Ensure a trusted certificate and trust chain is installed (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Generate a 4096-bit RSA key and CSR:
   openssl req -new -newkey rsa:4096 -keyout nginx.key -out nginx.csr
2. Obtain a signed certificate and intermediate CA trust chain (.pem) from a trusted CA.
3. Configure ssl_certificate and ssl_certificate_key in your HTTPS server block:
   ssl_certificate /etc/nginx/cert.pem;
   ssl_certificate_key /etc/nginx/nginx.key;"

    local cert_paths=()
    while IFS= read -r cpath; do
        [[ -n "$cpath" ]] && cert_paths+=("$cpath")
    done < <(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "ssl_certificate" {gsub(/;/, "", $2); print $2}' | sort -u)

    local key_paths=()
    while IFS= read -r kpath; do
        [[ -n "$kpath" ]] && key_paths+=("$kpath")
    done < <(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "ssl_certificate_key" {gsub(/;/, "", $2); print $2}' | sort -u)

    if [[ ${#cert_paths[@]} -eq 0 || ${#key_paths[@]} -eq 0 ]]; then
        report_fail "$id" "$title" "$profile" \
            "Missing 'ssl_certificate' or 'ssl_certificate_key' directives in NGINX configuration." \
            "$remediation"
        return
    fi

    local issues=()
    local c
    for c in "${cert_paths[@]}"; do
        if [[ "$c" != /* ]]; then
            c="${NGINX_CONF_DIR%/}/$c"
        fi
        if [[ ! -r "$c" ]]; then
            issues+=("Certificate file '${c}' does not exist or is not readable.")
        else
            local cert_blocks=0
            cert_blocks="$(grep -c "BEGIN CERTIFICATE" "$c" 2>/dev/null || echo 0)"
            if [[ "$cert_blocks" -lt 1 ]]; then
                issues+=("Certificate file '${c}' does not contain a valid PEM certificate.")
            elif [[ "$cert_blocks" -lt 2 ]]; then
                issues+=("Certificate file '${c}' contains only ${cert_blocks} certificate block (full intermediate trust chain requires >=2 blocks).")
            fi
        fi
    done

    if [[ ${#issues[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "SSL certificate and trust chain files (${cert_paths[*]}) are installed and contain valid certificate chains."
    else
        report_fail "$id" "$title" "$profile" "${issues[*]}" "$remediation"
    fi
}

check_4_1_3() {
    local id="4.1.3"
    local title="Ensure private key permissions are restricted (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Restrict permissions on all private key files to 400 (read-only for root owner):
   find ${NGINX_CONF_DIR}/ -name '*.key' -exec chown root:root {} +
   find ${NGINX_CONF_DIR}/ -name '*.key' -exec chmod 400 {} +"

    local key_files=()
    if [[ -d "$NGINX_CONF_DIR" ]]; then
        while IFS= read -r kf; do
            [[ -n "$kf" ]] && key_files+=("$kf")
        done < <(find "$NGINX_CONF_DIR" -type f -name "*.key" 2>/dev/null)
    fi

    while IFS= read -r cfg_key; do
        [[ -z "$cfg_key" ]] && continue
        if [[ "$cfg_key" != /* ]]; then
            cfg_key="${NGINX_CONF_DIR%/}/$cfg_key"
        fi
        if [[ ! " ${key_files[*]:-} " =~ " ${cfg_key} " ]]; then
            key_files+=("$cfg_key")
        fi
    done < <(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "ssl_certificate_key" || $1 == "proxy_ssl_certificate_key" {gsub(/;/, "", $2); print $2}' | sort -u)

    if [[ ${#key_files[@]} -eq 0 ]]; then
        report_fail "$id" "$title" "$profile" \
            "No private key files (*.key or ssl_certificate_key) were found to verify permissions." \
            "$remediation"
        return
    fi

    local bad_keys=()
    local checked_keys=()
    local k
    for k in "${key_files[@]}"; do
        [[ ! -e "$k" ]] && { bad_keys+=("${k} (missing)"); continue; }
        local perms=""
        perms="$(stat -Lc "%a" "$k" 2>/dev/null || true)"
        local loose=""
        loose="$(find -L "$k" -perm /377 2>/dev/null || true)"
        if [[ -n "$loose" ]]; then
            bad_keys+=("${k} (mode ${perms}, expected 400)")
        else
            checked_keys+=("${k} (${perms})")
        fi
    done

    if [[ ${#bad_keys[@]} -eq 0 && ${#checked_keys[@]} -gt 0 ]]; then
        report_ok "$id" "$title" "$profile" "All private key files have restricted permissions (<=400): ${checked_keys[*]}."
    else
        report_fail "$id" "$title" "$profile" \
            "Private key files with overly permissive modes or missing: ${bad_keys[*]}." \
            "$remediation"
    fi
}

check_4_1_4() {
    local id="4.1.4"
    local title="Ensure only modern TLS protocols are used (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Configure NGINX to exclusively use TLSv1.3 in your http or server blocks:
   ssl_protocols TLSv1.3;
2. If NGINX acts as a reverse proxy over HTTPS, also set in your location block:
   proxy_ssl_protocols TLSv1.3;"

    local proto_lines=""
    proto_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*(ssl_protocols|proxy_ssl_protocols)[[:space:]]+' || true)"
    if [[ -z "$proto_lines" ]]; then
        report_fail "$id" "$title" "$profile" \
            "No 'ssl_protocols' directive is configured (NGINX defaults allow legacy TLSv1.0, TLSv1.1, and TLSv1.2)." \
            "$remediation"
        return
    fi

    local legacy_found=""
    legacy_found="$(echo "$proto_lines" | grep -Ei 'SSLv2|SSLv3|TLSv1([[:space:];]|$)|TLSv1\.1|TLSv1\.2' || true)"
    local tls13_found=""
    tls13_found="$(echo "$proto_lines" | grep -E 'TLSv1\.3' || true)"

    if [[ -n "$tls13_found" && -z "$legacy_found" ]]; then
        report_ok "$id" "$title" "$profile" "Only modern TLS protocol (TLSv1.3) is enabled."
    else
        report_fail "$id" "$title" "$profile" \
            "Legacy or weak TLS protocols are enabled or TLSv1.3 is missing: $(echo "$proto_lines" | tr '\n' ' ')." \
            "$remediation"
    fi
}

check_4_1_5() {
    local id="4.1.5"
    local title="Disable weak ciphers (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Exclusively enable TLSv1.3 (which mandates strong AEAD ciphers and removes all legacy weak ciphers):
   ssl_protocols TLSv1.3;
2. Set ssl_prefer_server_ciphers to off for TLS 1.3 performance:
   ssl_prefer_server_ciphers off;
3. Remove legacy weak cipher suites from any 'ssl_ciphers' or 'proxy_ssl_ciphers' directives."

    local proto_lines=""
    proto_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*ssl_protocols[[:space:]]+' || true)"
    local legacy_proto=""
    legacy_proto="$(echo "$proto_lines" | grep -Ei 'SSLv2|SSLv3|TLSv1([[:space:];]|$)|TLSv1\.1|TLSv1\.2' || true)"
    local tls13_proto=""
    tls13_proto="$(echo "$proto_lines" | grep -E 'TLSv1\.3' || true)"

    local prefer_on=""
    prefer_on="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*ssl_prefer_server_ciphers[[:space:]]+on[[:space:]]*;' || true)"

    if [[ -n "$tls13_proto" && -z "$legacy_proto" && -z "$prefer_on" ]]; then
        report_ok "$id" "$title" "$profile" "Exclusive TLSv1.3 configuration is active (mandating strong AEAD ciphers) and ssl_prefer_server_ciphers is not set to 'on'."
    else
        local msg=""
        [[ -z "$tls13_proto" || -n "$legacy_proto" ]] && msg+="TLSv1.3 is not exclusively enforced (required by CIS v3.0.0 to eliminate weak ciphers). "
        [[ -n "$prefer_on" ]] && msg+="'ssl_prefer_server_ciphers on;' is present (should be 'off' for TLS 1.3)."
        report_fail "$id" "$title" "$profile" "$msg" "$remediation"
    fi
}

check_4_1_6() {
    local id="4.1.6"
    local title="Ensure awareness of TLS 1.3 new Diffie-Hellman parameters (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Ensure 'ssl_protocols TLSv1.3;' is set exclusively (Control 4.1.4).
2. Remove any obsolete 'ssl_dhparam' directives from your NGINX configuration, as TLS 1.3 uses standardized ECDHE/FFDHE groups."

    local proto_lines=""
    proto_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*ssl_protocols[[:space:]]+' || true)"
    local legacy_proto=""
    legacy_proto="$(echo "$proto_lines" | grep -Ei 'SSLv2|SSLv3|TLSv1([[:space:];]|$)|TLSv1\.1|TLSv1\.2' || true)"
    local tls13_proto=""
    tls13_proto="$(echo "$proto_lines" | grep -E 'TLSv1\.3' || true)"
    local dhparam_line=""
    dhparam_line="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*ssl_dhparam[[:space:]]+' || true)"

    if [[ -n "$tls13_proto" && -z "$legacy_proto" && -z "$dhparam_line" ]]; then
        report_ok "$id" "$title" "$profile" "TLSv1.3 is used exclusively and obsolete 'ssl_dhparam' directive is not present."
    else
        local msg=""
        [[ -z "$tls13_proto" || -n "$legacy_proto" ]] && msg+="Configuration does not exclusively use TLSv1.3. "
        [[ -n "$dhparam_line" ]] && msg+="Obsolete 'ssl_dhparam' directive found (${dhparam_line})."
        report_fail "$id" "$title" "$profile" "$msg" "$remediation"
    fi
}

check_4_1_7() {
    local id="4.1.7"
    local title="Ensure Online Certificate Status Protocol (OCSP) stapling is enabled (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Configure all four required OCSP stapling directives in your http or server block:
   ssl_stapling on;
   ssl_stapling_verify on;
   ssl_trusted_certificate /etc/nginx/ssl/full_chain.pem;
   resolver 8.8.8.8 1.1.1.1 valid=300s;"

    local stapling_on=""
    stapling_on="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*ssl_stapling[[:space:]]+on[[:space:]]*;' || true)"
    local stapling_verify=""
    stapling_verify="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*ssl_stapling_verify[[:space:]]+on[[:space:]]*;' || true)"
    local trusted_cert=""
    trusted_cert="$(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "ssl_trusted_certificate" {gsub(/;/, "", $2); print $2; exit}')"
    local resolver_cfg=""
    resolver_cfg="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*resolver[[:space:]]+' || true)"

    local missing=()
    [[ -z "$stapling_on" ]] && missing+=("ssl_stapling on;")
    [[ -z "$stapling_verify" ]] && missing+=("ssl_stapling_verify on;")
    if [[ -z "$trusted_cert" ]]; then
        missing+=("ssl_trusted_certificate <path>;")
    else
        local tc_path="$trusted_cert"
        [[ "$tc_path" != /* ]] && tc_path="${NGINX_CONF_DIR%/}/$tc_path"
        [[ ! -f "$tc_path" ]] && missing+=("ssl_trusted_certificate file '${tc_path}' does not exist")
    fi
    [[ -z "$resolver_cfg" ]] && missing+=("resolver <DNS_IP>;")

    if [[ ${#missing[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "OCSP stapling is fully configured (ssl_stapling, ssl_stapling_verify, ssl_trusted_certificate, and resolver)."
    else
        report_fail "$id" "$title" "$profile" \
            "Missing or invalid OCSP stapling configuration: ${missing[*]}." \
            "$remediation"
    fi
}

check_4_1_8() {
    local id="4.1.8"
    local title="Ensure HTTP Strict Transport Security (HSTS) is enabled (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Add the Strict-Transport-Security header to your HTTPS server block (with max-age >= 31536000, includeSubDomains, and always):
   add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\" always;"

    local hsts_lines=""
    hsts_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -Ei '^[[:space:]]*add_header[[:space:]]+["'\'']?Strict-Transport-Security["'\'']?' || true)"
    if [[ -z "$hsts_lines" ]]; then
        report_fail "$id" "$title" "$profile" \
            "No 'Strict-Transport-Security' header is configured." \
            "$remediation"
        return
    fi

    local max_age=""
    max_age="$(echo "$hsts_lines" | grep -oEi 'max-age=[0-9]+' | head -n1 | cut -d= -f2 || echo 0)"
    local has_subdomains=""
    has_subdomains="$(echo "$hsts_lines" | grep -i 'includeSubDomains' || true)"
    local has_always=""
    has_always="$(echo "$hsts_lines" | grep -E '[[:space:]]+always[[:space:]]*;' || true)"

    local issues=()
    if [[ -z "$max_age" || "$max_age" -lt 31536000 ]]; then
        issues+=("max-age is ${max_age:-missing} (must be at least 31536000 seconds / 1 year; 63072000 recommended)")
    fi
    [[ -z "$has_subdomains" ]] && issues+=("missing 'includeSubDomains' directive")
    [[ -z "$has_always" ]] && issues+=("missing 'always' parameter at the end of add_header")

    if [[ ${#issues[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "HSTS is enabled with max-age=${max_age}, includeSubDomains, and 'always'."
    else
        report_fail "$id" "$title" "$profile" \
            "HSTS policy is incomplete: ${issues[*]}." \
            "$remediation"
    fi
}

check_4_1_9() {
    local id="4.1.9"
    local title="Ensure upstream server traffic is authenticated with a client certificate (Manual)"
    local profile="Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Generate and sign a client certificate for your NGINX proxy using your internal CA.
2. Configure NGINX to present its client certificate to upstream servers in your proxied location block:
   proxy_ssl_certificate /etc/nginx/ssl/nginx-client.crt;
   proxy_ssl_certificate_key /etc/nginx/ssl/nginx-client.key;"

    local p_cert=""
    p_cert="$(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "proxy_ssl_certificate" {gsub(/;/, "", $2); print $2; exit}')"
    local p_key=""
    p_key="$(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "proxy_ssl_certificate_key" {gsub(/;/, "", $2); print $2; exit}')"

    local missing=()
    if [[ -z "$p_cert" ]]; then
        missing+=("proxy_ssl_certificate")
    else
        local cp="$p_cert"
        [[ "$cp" != /* ]] && cp="${NGINX_CONF_DIR%/}/$cp"
        [[ ! -f "$cp" ]] && missing+=("proxy_ssl_certificate file '${cp}' does not exist")
    fi

    if [[ -z "$p_key" ]]; then
        missing+=("proxy_ssl_certificate_key")
    else
        local kp="$p_key"
        [[ "$kp" != /* ]] && kp="${NGINX_CONF_DIR%/}/$kp"
        [[ ! -f "$kp" ]] && missing+=("proxy_ssl_certificate_key file '${kp}' does not exist")
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "Upstream mTLS client certificate (${p_cert}) and key (${p_key}) are configured."
    else
        report_fail "$id" "$title" "$profile" \
            "Missing or invalid upstream mTLS client certificate configuration: ${missing[*]}." \
            "$remediation"
    fi
}

check_4_1_10() {
    local id="4.1.10"
    local title="Ensure the upstream traffic server certificate is trusted (Manual)"
    local profile="Level 2 - Proxy, Level 2 - Loadbalancer"
    local remediation="1. Place the CA certificate that signed your upstream server's certificate in a secure directory (e.g., /etc/nginx/ssl/upstream_ca.crt).
2. Add the following three directives to your proxied location block:
   proxy_ssl_verify on;
   proxy_ssl_trusted_certificate /etc/nginx/ssl/upstream_ca.crt;
   proxy_ssl_name your-upstream-hostname.com;"

    local p_verify=""
    p_verify="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*proxy_ssl_verify[[:space:]]+on[[:space:]]*;' || true)"
    local p_trusted=""
    p_trusted="$(echo "$NGINX_ACTIVE_CONF" | awk '$1 == "proxy_ssl_trusted_certificate" {gsub(/;/, "", $2); print $2; exit}')"
    local p_name=""
    p_name="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*proxy_ssl_name[[:space:]]+' || true)"

    local missing=()
    [[ -z "$p_verify" ]] && missing+=("proxy_ssl_verify on;")
    if [[ -z "$p_trusted" ]]; then
        missing+=("proxy_ssl_trusted_certificate <path>;")
    else
        local tp="$p_trusted"
        [[ "$tp" != /* ]] && tp="${NGINX_CONF_DIR%/}/$tp"
        [[ ! -f "$tp" ]] && missing+=("proxy_ssl_trusted_certificate file '${tp}' does not exist")
    fi
    [[ -z "$p_name" ]] && missing+=("proxy_ssl_name <upstream-hostname>;")

    if [[ ${#missing[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "Upstream server certificate verification (proxy_ssl_verify, proxy_ssl_trusted_certificate, proxy_ssl_name) is configured."
    else
        report_fail "$id" "$title" "$profile" \
            "Missing upstream certificate trust directive(s): ${missing[*]}." \
            "$remediation"
    fi
}

check_4_1_11() {
    local id="4.1.11"
    local title="Ensure Secure Session Resumption is Enabled (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Ensure 'ssl_session_tickets' is NOT set to 'off' in your TLS 1.3 configuration.
2. Remove 'ssl_session_tickets off;' from your configuration files or explicitly set:
   ssl_session_tickets on;"

    if [[ -z "$NGINX_ACTIVE_CONF" ]]; then
        report_fail "$id" "$title" "$profile" \
            "NGINX configuration could not be read to verify 'ssl_session_tickets'." \
            "$remediation"
        return
    fi

    local tickets_off=""
    tickets_off="$(echo "$NGINX_ACTIVE_CONF" | grep -Ei '^[[:space:]]*ssl_session_tickets[[:space:]]+off[[:space:]]*;' || true)"

    if [[ -z "$tickets_off" ]]; then
        report_ok "$id" "$title" "$profile" "Secure session resumption (ssl_session_tickets) is enabled."
    else
        report_fail "$id" "$title" "$profile" \
            "Found 'ssl_session_tickets off;' in configuration, which disables TLS 1.3 PSK session resumption." \
            "$remediation"
    fi
}

check_4_1_12() {
    local id="4.1.12"
    local title="Ensure HTTP/3.0 is used (Manual)"
    local profile="Level 2 - Webserver"
    local remediation="1. Ensure NGINX is compiled with '--with-http_v3_module'.
2. In your HTTPS server block, enable HTTP/2 on TCP 443, HTTP/3 (QUIC) on UDP 443, and advertise HTTP/3 via the Alt-Svc header:
   listen 443 ssl http2;
   listen [::]:443 ssl http2;
   listen 443 quic reuseport;
   listen [::]:443 quic reuseport;
   add_header Alt-Svc 'h3=\":443\"; ma=63072000';
   ssl_early_data on;
3. Allow UDP port 443 in your firewall."

    local has_v3_mod=""
    has_v3_mod="$(echo "$NGINX_V_OUTPUT" | grep -o '\-\-with-http_v3_module' || true)"
    local has_http2=""
    has_http2="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*(listen[[:space:]].*http2|http2[[:space:]]+on[[:space:]]*;)' || true)"
    local has_quic=""
    has_quic="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*listen[[:space:]].*quic' || true)"
    local has_altsvc=""
    has_altsvc="$(echo "$NGINX_ACTIVE_CONF" | grep -Ei '^[[:space:]]*add_header[[:space:]]+["'\'']?Alt-Svc["'\'']?.*h3=' || true)"

    local missing=()
    [[ -z "$has_v3_mod" ]] && missing+=("NGINX binary is not compiled with '--with-http_v3_module'")
    [[ -z "$has_http2" ]] && missing+=("TCP HTTP/2 listener ('listen 443 ssl http2;' or 'http2 on;')")
    [[ -z "$has_quic" ]] && missing+=("UDP QUIC listener ('listen 443 quic reuseport;')")
    [[ -z "$has_altsvc" ]] && missing+=("Alt-Svc header advertising h3 ('add_header Alt-Svc ...')")

    if [[ ${#missing[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "HTTP/3 (QUIC) module, UDP QUIC listener, HTTP/2 listener, and Alt-Svc header are all enabled."
    else
        report_fail "$id" "$title" "$profile" \
            "HTTP/3.0 configuration is incomplete: ${missing[*]}." \
            "$remediation"
    fi
}

# ==============================================================================
# SECTION 5: REQUEST FILTERING AND RESTRICTIONS
# ==============================================================================

check_5_1_1() {
    local id="5.1.1"
    local title="Ensure allow and deny filters limit access to specific IP addresses (Manual)"
    local profile="Level 2 - Webserver, Level 2 - Proxy, Level 2 - Loadbalancer"
    local remediation="1. Protect sensitive locations (or the server) with explicit IP allow-lists followed by 'deny all;':
   location /admin_login/ {
       allow 192.168.1.100;
       allow 10.20.30.0/24;
       deny all;
   }"

    local allow_rules=""
    allow_rules="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*allow[[:space:]]+[^[:space:];]+' | grep -vE 'allow[[:space:]]+all' || true)"
    local deny_all=""
    deny_all="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*deny[[:space:]]+all[[:space:]]*;' || true)"

    if [[ -n "$allow_rules" && -n "$deny_all" ]]; then
        report_ok "$id" "$title" "$profile" "IP-based 'allow' and 'deny all;' access control rules are configured."
    else
        local missing=()
        [[ -z "$allow_rules" ]] && missing+=("explicit 'allow <IP/CIDR>;' directives")
        [[ -z "$deny_all" ]] && missing+=("'deny all;' default-deny directive")
        report_fail "$id" "$title" "$profile" \
            "Missing IP access control directives: ${missing[*]}." \
            "$remediation"
    fi
}

check_5_1_2() {
    local id="5.1.2"
    local title="Ensure only approved HTTP methods are allowed (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Restrict allowed HTTP methods in your location blocks using 'limit_except' (Method 1 - Preferred):
   location / {
       limit_except GET HEAD POST {
           deny all;
       }
   }
2. Or use an 'if (\$request_method)' check in your server/location block (Method 2):
   if (\$request_method !~ ^(GET|HEAD|POST)\$) {
       return 444;
   }"

    local method_filter=""
    method_filter="$(echo "$NGINX_ACTIVE_CONF" | grep -E '(limit_except[[:space:]]+|\$request_method)' || true)"

    if [[ -n "$method_filter" ]]; then
        report_ok "$id" "$title" "$profile" "HTTP method filtering ('limit_except' or '\$request_method') is configured."
    else
        report_fail "$id" "$title" "$profile" \
            "No HTTP method restriction ('limit_except' or '\$request_method' check) was found in the configuration." \
            "$remediation"
    fi
}

check_5_2_1() {
    local id="5.2.1"
    local title="Ensure timeout values for reading the client header and body are set correctly (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Set reasonably low global timeout values (e.g., 10s-15s, overriding the 60s default) in your 'http' block:
   http {
       client_header_timeout 15s;
       client_body_timeout 15s;
       send_timeout 10s;
   }
2. If specific endpoints require longer upload times, override 'client_body_timeout' only inside that specific 'location' block."

    local ch_lines=""
    ch_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*client_header_timeout[[:space:]]+' || true)"
    local cb_lines=""
    cb_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*client_body_timeout[[:space:]]+' || true)"
    local st_lines=""
    st_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*send_timeout[[:space:]]+' || true)"

    local issues=()
    if [[ -z "$ch_lines" ]]; then
        issues+=("'client_header_timeout' is not explicitly set (defaults to 60s)")
    else
        local ch_val
        ch_val="$(echo "$ch_lines" | head -n1 | awk '{print $2}')"
        local ch_sec
        ch_sec="$(parse_time_to_seconds "$ch_val")"
        if [[ "$ch_sec" -le 0 || "$ch_sec" -ge 60 ]]; then
            issues+=("client_header_timeout (${ch_val//;/}) should be set below the 60s default (e.g., 10s-20s)")
        fi
    fi

    if [[ -z "$cb_lines" ]]; then
        issues+=("'client_body_timeout' is not explicitly set (defaults to 60s)")
    else
        local cb_val
        cb_val="$(echo "$cb_lines" | head -n1 | awk '{print $2}')"
        local cb_sec
        cb_sec="$(parse_time_to_seconds "$cb_val")"
        if [[ "$cb_sec" -le 0 || "$cb_sec" -ge 60 ]]; then
            issues+=("global client_body_timeout (${cb_val//;/}) should be set below the 60s default (e.g., 10s-20s)")
        fi
    fi

    if [[ -z "$st_lines" ]]; then
        issues+=("'send_timeout' is not explicitly set (defaults to 60s)")
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "Client header, body, and send timeout directives are explicitly set to non-default low values."
    else
        report_fail "$id" "$title" "$profile" "${issues[*]}." "$remediation"
    fi
}

check_5_2_2() {
    local id="5.2.2"
    local title="Ensure the maximum request body size is set correctly (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Explicitly define a restrictive global 'client_max_body_size' in the 'http' block of ${NGINX_CONF_FILE}:
   http {
       client_max_body_size 2M;
   }
2. Override with a larger limit only inside specific 'location' blocks that handle large uploads."

    local body_size_lines=""
    body_size_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*client_max_body_size[[:space:]]+' || true)"
    if [[ -z "$body_size_lines" ]]; then
        report_fail "$id" "$title" "$profile" \
            "'client_max_body_size' is not explicitly configured in the NGINX configuration." \
            "$remediation"
        return
    fi

    local zero_size=""
    zero_size="$(echo "$body_size_lines" | grep -E '^[[:space:]]*client_max_body_size[[:space:]]+0[mMkKgG]?[[:space:]]*;' || true)"
    if [[ -n "$zero_size" ]]; then
        report_fail "$id" "$title" "$profile" \
            "'client_max_body_size 0;' is configured, which disables request body size checking completely." \
            "$remediation"
    else
        report_ok "$id" "$title" "$profile" "client_max_body_size is explicitly configured ($(echo "$body_size_lines" | tr '\n' ' '))."
    fi
}

check_5_2_3() {
    local id="5.2.3"
    local title="Ensure the maximum buffer size for URIs is defined (Manual)"
    local profile="Level 1 - Webserver, Level 1 - Proxy, Level 1 - Loadbalancer"
    local remediation="1. Rely on the secure NGINX default ('large_client_header_buffers 4 8k;') unless a specific documented requirement exists.
2. Remove any undocumented or overly restrictive 'large_client_header_buffers' directives (such as '2 1k') from ${NGINX_CONF_FILE}."

    if [[ -z "$NGINX_ACTIVE_CONF" ]]; then
        report_fail "$id" "$title" "$profile" \
            "NGINX configuration could not be read to verify 'large_client_header_buffers'." \
            "$remediation"
        return
    fi

    local buf_lines=""
    buf_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*large_client_header_buffers[[:space:]]+' || true)"

    if [[ -z "$buf_lines" ]]; then
        report_ok "$id" "$title" "$profile" "No custom override found; NGINX is using the compliant default 'large_client_header_buffers 4 8k;'."
    elif echo "$buf_lines" | grep -qE '^[[:space:]]*large_client_header_buffers[[:space:]]+4[[:space:]]+8[kK][[:space:]]*;'; then
        report_ok "$id" "$title" "$profile" "'large_client_header_buffers 4 8k;' is explicitly configured."
    else
        report_fail "$id" "$title" "$profile" \
            "Non-default 'large_client_header_buffers' value detected (${buf_lines}). Verify whether this deviation from '4 8k' is documented and intentional." \
            "$remediation"
    fi
}

check_5_2_4() {
    local id="5.2.4"
    local title="Ensure the number of connections per IP address is limited (Manual)"
    local profile="Level 2 - Webserver, Level 2 - Proxy, Level 2 - Loadbalancer"
    local remediation="1. Define a shared memory connection zone in the 'http' block:
   limit_conn_zone \$binary_remote_addr zone=per_ip:10m;
2. Apply a connection limit per IP in your 'server' or 'location' block:
   limit_conn per_ip 20;"

    local conn_zone=""
    conn_zone="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*limit_conn_zone[[:space:]]+' || true)"
    local conn_limit=""
    conn_limit="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*limit_conn[[:space:]]+' || true)"

    if [[ -n "$conn_zone" && -n "$conn_limit" ]]; then
        report_ok "$id" "$title" "$profile" "Both 'limit_conn_zone' and 'limit_conn' directives are configured."
    else
        local missing=()
        [[ -z "$conn_zone" ]] && missing+=("limit_conn_zone")
        [[ -z "$conn_limit" ]] && missing+=("limit_conn")
        report_fail "$id" "$title" "$profile" \
            "Missing connection limiting directive(s): ${missing[*]}." \
            "$remediation"
    fi
}

check_5_2_5() {
    local id="5.2.5"
    local title="Ensure rate limits by IP address are set (Manual)"
    local profile="Level 2 - Webserver, Level 2 - Proxy, Level 2 - Loadbalancer"
    local remediation="1. Define a shared memory rate-limiting zone in the 'http' block:
   limit_req_zone \$binary_remote_addr zone=login_limit:10m rate=1r/s;
2. Apply 'limit_req' to specific, sensitive location blocks (e.g., /login or /api/authenticate):
   location /login {
       limit_req zone=login_limit burst=5 nodelay;
   }"

    local req_zone=""
    req_zone="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*limit_req_zone[[:space:]]+' || true)"
    local req_limit=""
    req_limit="$(echo "$NGINX_ACTIVE_CONF" | grep -E '^[[:space:]]*limit_req[[:space:]]+' || true)"

    if [[ -n "$req_zone" && -n "$req_limit" ]]; then
        report_ok "$id" "$title" "$profile" "Both 'limit_req_zone' and 'limit_req' directives are configured."
    else
        local missing=()
        [[ -z "$req_zone" ]] && missing+=("limit_req_zone")
        [[ -z "$req_limit" ]] && missing+=("limit_req")
        report_fail "$id" "$title" "$profile" \
            "Missing request rate-limiting directive(s): ${missing[*]}." \
            "$remediation"
    fi
}

check_5_3_1() {
    local id="5.3.1"
    local title="Ensure X-Content-Type-Options header is configured and enabled (Manual)"
    local profile="Level 1 - Webserver"
    local remediation="1. Add the X-Content-Type-Options header with the 'always' parameter to your server or http block:
   add_header X-Content-Type-Options \"nosniff\" always;"

    local xcto_line=""
    xcto_line="$(echo "$NGINX_ACTIVE_CONF" | grep -Ei '^[[:space:]]*add_header[[:space:]]+["'\'']?X-Content-Type-Options["'\'']?[[:space:]]+["'\'']?nosniff["'\'']?[[:space:]]+always[[:space:]]*;' || true)"

    if [[ -n "$xcto_line" ]]; then
        report_ok "$id" "$title" "$profile" "'add_header X-Content-Type-Options \"nosniff\" always;' is properly configured."
    else
        report_fail "$id" "$title" "$profile" \
            "The 'X-Content-Type-Options \"nosniff\" always;' header directive is missing or lacks the 'always' parameter." \
            "$remediation"
    fi
}

check_5_3_2() {
    local id="5.3.2"
    local title="Ensure that Content Security Policy (CSP) is enabled and configured properly (Manual)"
    local profile="Level 2 - Webserver"
    local remediation="1. Add a robust Content-Security-Policy header (including default-src, frame-ancestors, no unsafe-inline/unsafe-eval, and 'always') to your server block:
   add_header Content-Security-Policy \"default-src 'self'; frame-ancestors 'self'; form-action 'self';\" always;"

    local csp_lines=""
    csp_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -Ei '^[[:space:]]*add_header[[:space:]]+["'\'']?Content-Security-Policy["'\'']?[[:space:]]+' || true)"
    if [[ -z "$csp_lines" ]]; then
        report_fail "$id" "$title" "$profile" \
            "No enforced 'Content-Security-Policy' header directive was found." \
            "$remediation"
        return
    fi

    local issues=()
    echo "$csp_lines" | grep -qi 'default-src' || issues+=("missing 'default-src' directive")
    echo "$csp_lines" | grep -qi 'frame-ancestors' || issues+=("missing 'frame-ancestors' directive (Clickjacking defense)")
    echo "$csp_lines" | grep -qiE 'unsafe-inline|unsafe-eval' && issues+=("policy contains 'unsafe-inline' or 'unsafe-eval'")
    echo "$csp_lines" | grep -qE '[[:space:]]+always[[:space:]]*;' || issues+=("missing 'always' parameter")

    if [[ ${#issues[@]} -eq 0 ]]; then
        report_ok "$id" "$title" "$profile" "Content-Security-Policy is enabled with default-src, frame-ancestors, 'always', and no unsafe directives."
    else
        report_fail "$id" "$title" "$profile" \
            "Content-Security-Policy configuration issues: ${issues[*]}." \
            "$remediation"
    fi
}

check_5_3_3() {
    local id="5.3.3"
    local title="Ensure the Referrer Policy is enabled and configured properly (Manual)"
    local profile="Level 2 - Webserver"
    local remediation="1. Add the Referrer-Policy header with 'strict-origin-when-cross-origin' (or 'no-referrer') and the 'always' parameter to your server or http block:
   add_header Referrer-Policy \"strict-origin-when-cross-origin\" always;"

    local ref_lines=""
    ref_lines="$(echo "$NGINX_ACTIVE_CONF" | grep -Ei '^[[:space:]]*add_header[[:space:]]+["'\'']?Referrer-Policy["'\'']?[[:space:]]+' || true)"
    if [[ -z "$ref_lines" ]]; then
        report_fail "$id" "$title" "$profile" \
            "No 'Referrer-Policy' header directive was found." \
            "$remediation"
        return
    fi

    local has_secure_val=""
    has_secure_val="$(echo "$ref_lines" | grep -Ei 'strict-origin-when-cross-origin|no-referrer|same-origin|strict-origin' || true)"
    local has_unsafe=""
    has_unsafe="$(echo "$ref_lines" | grep -Ei 'unsafe-url' || true)"
    local has_always=""
    has_always="$(echo "$ref_lines" | grep -E '[[:space:]]+always[[:space:]]*;' || true)"

    if [[ -n "$has_secure_val" && -z "$has_unsafe" && -n "$has_always" ]]; then
        report_ok "$id" "$title" "$profile" "Referrer-Policy header is properly configured with a secure policy and 'always' parameter."
    else
        local issues=()
        [[ -z "$has_secure_val" || -n "$has_unsafe" ]] && issues+=("policy value is not set to 'strict-origin-when-cross-origin' or 'no-referrer'")
        [[ -z "$has_always" ]] && issues+=("missing 'always' parameter")
        report_fail "$id" "$title" "$profile" \
            "Referrer-Policy configuration issues: ${issues[*]}." \
            "$remediation"
    fi
}


# ==============================================================================
# SECTION RUNNERS & SUMMARY SCORECARD
# ==============================================================================
run_section_1() {
    print_section_header "1" "Initial Setup" || return 0
    check_1_1_1
    check_1_2_1
    check_1_2_2
}

run_section_2() {
    print_section_header "2" "Basic Configuration" || return 0
    check_2_1_1
    check_2_2_1
    check_2_2_2
    check_2_2_3
    check_2_3_1
    check_2_3_2
    check_2_3_3
    check_2_4_1
    check_2_4_2
    check_2_4_3
    check_2_4_4
    check_2_5_1
    check_2_5_2
    check_2_5_3
    check_2_5_4
}

run_section_3() {
    print_section_header "3" "Logging" || return 0
    check_3_1
    check_3_2
    check_3_3
    check_3_4
}

run_section_4() {
    print_section_header "4" "Encryption (TLS / SSL Configuration)" || return 0
    check_4_1_1
    check_4_1_2
    check_4_1_3
    check_4_1_4
    check_4_1_5
    check_4_1_6
    check_4_1_7
    check_4_1_8
    check_4_1_9
    check_4_1_10
    check_4_1_11
    check_4_1_12
}

run_section_5() {
    print_section_header "5" "Request Filtering and Restrictions" || return 0
    check_5_1_1
    check_5_1_2
    check_5_2_1
    check_5_2_2
    check_5_2_3
    check_5_2_4
    check_5_2_5
    check_5_3_1
    check_5_3_2
    check_5_3_3
}

run_section_6() {
    print_section_header "6" "Mandatory Access Control" || return 0
    echo -e "${C_BLUE}[INFO]${C_RESET}   ${C_BOLD}6.0 - Section 6 Mandatory Access Control (Reserved)${C_RESET} ${C_DIM}[Informational]${C_RESET}"
    echo -e "         ${C_DIM}Details: Intentionally reserved in CIS NGINX Benchmark v3.0.0. Refer to your OS CIS Benchmark for PAM/MAC (SELinux/AppArmor) and Section 5 for network access controls.${C_RESET}"
}

print_summary() {
    echo -e "\n${C_BG_BLUE} [SUMMARY] CIS NGINX Benchmark v3.0.0 AUDIT REPORT ${C_RESET}"
    echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
    printf "  %-36s | %7s | %7s | %7s | %7s | %7s\n" "Section" "OK" "FAIL" "MANUAL" "SKIP" "Total"
    echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
    local s_names=(
        ""
        "1. Initial Setup"
        "2. Basic Configuration"
        "3. Logging"
        "4. Encryption (TLS / SSL)"
        "5. Request Filtering & Restrictions"
        "6. Mandatory Access Control"
    )
    local s
    for s in 1 2 3 4 5 6; do
        local ok="${SEC_OK[$s]:-0}"
        local fl="${SEC_FAIL[$s]:-0}"
        local mn="${SEC_MANUAL[$s]:-0}"
        local sk="${SEC_SKIP[$s]:-0}"
        local tot=$(( ok + fl + mn + sk ))
        [[ "$tot" -eq 0 ]] && ! is_section_selected "$s" && continue
        printf "  %-36s | %7d | %7d | %7d | %7d | %7d\n" "${s_names[$s]}" "$ok" "$fl" "$mn" "$sk" "$tot"
    done
    echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
    echo -e "  ${C_BOLD}Total Checks Executed:${C_RESET}  ${TOTAL_CHECKS}"
    echo -e "  ${C_GREEN}${C_BOLD}[OK] Compliant:${C_RESET}         ${COUNT_OK}"
    echo -e "  ${C_RED}${C_BOLD}[FAIL] Non-Compliant:${C_RESET}   ${COUNT_FAIL}"
    echo -e "  ${C_YELLOW}${C_BOLD}[MANUAL] Site Review:${C_RESET}   ${COUNT_MANUAL}"
    echo -e "  ${C_MAGENTA}${C_BOLD}[SKIP] Skipped:${C_RESET}         ${COUNT_SKIP}"
    if [[ "$TOTAL_CHECKS" -gt 0 ]]; then
        local pct=$(( (COUNT_OK * 100) / TOTAL_CHECKS ))
        echo -e "  ${C_CYAN}${C_BOLD}Automated Pass Rate:${C_RESET}    ${pct}% (${COUNT_OK}/${TOTAL_CHECKS})\n"
    fi
}

main() {
    setup_colors_and_init
    discover_nginx
    print_warning
    run_section_1
    run_section_2
    run_section_3
    run_section_4
    run_section_5
    run_section_6
    print_summary
}

main "$@"
