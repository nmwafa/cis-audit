#!/usr/bin/env bash
# ==============================================================================
# CIS Apache HTTP Server 2.4 Benchmark v2.4.0 - Standalone Security Audit Script
# Style:       Standalone / Agentless (LinPEAS / LinEnum Inspired)
# Benchmark:   CIS Apache HTTP Server 2.4 Benchmark v2.4.0 (08-31-2026)
# Coverage:    All 81 Recommendations (Sections 1 through 12, Level 1 & Level 2)
# Repository:  https://github.com/nmwafa/cis-audit
# ==============================================================================

set -u

BENCHMARK_NAME="CIS Apache HTTP Server 2.4 Benchmark v2.4.0"
BENCHMARK_CONTROLS="81 Controls (Sections 1-12)"
SCRIPT_NAME="$(basename "$0")"

# ------------------------------------------------------------------------------
# CLI Options & Defaults
# ------------------------------------------------------------------------------
PROFILE_LEVEL="all"      # 1, 2, or all
TARGET_SECTION="all"     # 1..12 or all
CUSTOM_PREFIX=""
CUSTOM_CONF=""
CUSTOM_BIN=""
CUSTOM_DOCROOT=""
OUTPUT_FILE=""
USE_COLOR=1
FORCE_COLOR="${FORCE_COLOR:-0}"
QUIET_OK=0

usage() {
    cat << 'EOF'
Usage: ./cis_apache_2.4_audit.sh [OPTIONS]

Standalone, zero-install Bash script to audit Apache HTTP Server 2.4
against all recommendations in the CIS Apache HTTP Server 2.4 Benchmark v2.4.0.

Options:
  -l, --level <1|2|all>      Filter by CIS Profile Level (default: all)
  -s, --section <1..12|all>  Audit only a specific section (1-12) (default: all)
  -p, --prefix DIR           Specify Apache ServerRoot / prefix directory
  -c, --config FILE          Specify main Apache configuration file (httpd.conf / apache2.conf)
  -b, --binary PATH          Specify Apache binary path (httpd / apache2)
  -d, --docroot DIR          Specify Apache DocumentRoot directory
  -o, --output <file>        Save full audit report to a file
  -q, --quiet-ok             Hide [OK] results and only show findings/remediations
  -n, --no-color             Disable ANSI color codes in output
      --color                Force ANSI color output even when piped
  -h, --help                 Display this help message and exit
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
        -p|--prefix)
            CUSTOM_PREFIX="${2:-}"
            shift 2
            ;;
        -c|--config)
            CUSTOM_CONF="${2:-}"
            shift 2
            ;;
        -b|--binary)
            CUSTOM_BIN="${2:-}"
            shift 2
            ;;
        -d|--docroot)
            CUSTOM_DOCROOT="${2:-}"
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

declare -A SEC_OK=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0 [8]=0 [9]=0 [10]=0 [11]=0 [12]=0)
declare -A SEC_FAIL=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0 [8]=0 [9]=0 [10]=0 [11]=0 [12]=0)
declare -A SEC_MANUAL=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0 [8]=0 [9]=0 [10]=0 [11]=0 [12]=0)
declare -A SEC_SKIP=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0 [8]=0 [9]=0 [10]=0 [11]=0 [12]=0)

setup_colors_and_init() {
    PROFILE_LEVEL="$(normalize_profile_filter "$PROFILE_LEVEL")"
    setup_colors
    if [[ -n "$OUTPUT_FILE" ]]; then
        exec > >(tee "$OUTPUT_FILE") 2>&1
    fi
}

# Parse embedded "(Automated|Manual) [Level 1|2]" from Apache check titles
parse_apache_title_meta() {
    local raw="$1"
    AP_CLEAN_TITLE="$raw"
    AP_LEVEL="L1"
    AP_TYPE="Automated"

    if [[ "$raw" =~ \[Level[[:space:]]*2\] ]]; then
        AP_LEVEL="L2"
    elif [[ "$raw" =~ \[Level[[:space:]]*1\] ]]; then
        AP_LEVEL="L1"
    fi

    if [[ "$raw" =~ \(Manual\) ]]; then
        AP_TYPE="Manual"
    elif [[ "$raw" =~ \(Automated\) ]]; then
        AP_TYPE="Automated"
    fi

    # Strip trailing "(Automated|Manual) [Level X]" from display title
    AP_CLEAN_TITLE="$(echo "$raw" | sed -E 's/[[:space:]]*\((Automated|Manual)\)[[:space:]]*\[[^]]+\][[:space:]]*$//')"
}

pass_check() {
    local id="$1"
    local title="$2"
    local details="${3:-}"
    parse_apache_title_meta "$title"
    report_result "$id" "$AP_CLEAN_TITLE" "$AP_LEVEL" "$AP_TYPE" "OK" "$details" ""
}

fail_check() {
    local id="$1"
    local title="$2"
    local finding="$3"
    local remediation="$4"
    parse_apache_title_meta "$title"
    report_result "$id" "$AP_CLEAN_TITLE" "$AP_LEVEL" "$AP_TYPE" "FAIL" "$finding" "$remediation"
}

manual_check() {
    local id="$1"
    local title="$2"
    local finding="$3"
    local remediation="$4"
    parse_apache_title_meta "$title"
    report_result "$id" "$AP_CLEAN_TITLE" "$AP_LEVEL" "$AP_TYPE" "MANUAL" "$finding" "$remediation"
}

print_banner() {
    echo -e "${C_CYAN}${C_BOLD}"
    cat << 'BANNER'
   ____ ___ ____       _                     _            ____    _  _   
  / ___|_ _/ ___|     / \   _ __   __ _  ___| |__   ___  |___ \  | || |  
 | |    | |\___ \    / _ \ | '_ \ / _` |/ __| '_ \ / _ \   __) | | || |_ 
 | |___ | | ___) |  / ___ \| |_) | (_| | (__| | | |  __/  / __/ _|__   _|
  \____|___|____/  /_/   \_\ .__/ \__,_|\___|_| |_|\___| |_____(_)  |_|  
                           |_|                                           
BANNER
    echo -e "${C_BLUE}====================================================================================${C_RESET}"
    echo -e "  ${C_BOLD}Benchmark:${C_RESET}      ${BENCHMARK_NAME} (08-31-2026)"
    echo -e "  ${C_BOLD}Hostname:${C_RESET}       $(hostname 2>/dev/null || echo 'unknown')"
    echo -e "  ${C_BOLD}OS Release:${C_RESET}     $(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -sr)"
    echo -e "  ${C_BOLD}Kernel:${C_RESET}         $(uname -r 2>/dev/null || echo 'unknown') ($(uname -m 2>/dev/null || echo 'unknown'))"
    echo -e "  ${C_BOLD}Current User:${C_RESET}   $(id -un 2>/dev/null || echo 'unknown') (UID: $(id -u 2>/dev/null || echo '?'))"
    echo -e "  ${C_BOLD}Audit Date:${C_RESET}     $(date -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)"
    echo -e "  ${C_BOLD}Section Filter:${C_RESET} ${TARGET_SECTION} (Profile Level: ${PROFILE_LEVEL})"
    echo -e "  ${C_BOLD}Apache Binary:${C_RESET}  ${HTTPD_BIN:-Not Found}"
    echo -e "  ${C_BOLD}ServerRoot:${C_RESET}     ${APACHE_PREFIX}"
    echo -e "  ${C_BOLD}Main Config:${C_RESET}    ${HTTPD_CONF}"
    echo -e "  ${C_BOLD}DocumentRoot:${C_RESET}   ${DOCROOT}"
    echo -e "  ${C_BOLD}Apache User:${C_RESET}    ${APACHE_USER:-Not Set} / ${APACHE_GROUP:-Not Set} (${#CONF_FILES[@]} config file(s))"
    if [[ "$(id -u 2>/dev/null || echo 1)" -ne 0 ]]; then
        echo -e "  ${C_YELLOW}[!] WARNING: Script is not running as root (UID 0). Some file permission, process, or password lock checks may have limited visibility.${C_RESET}"
    fi
    echo -e "${C_BLUE}====================================================================================${C_RESET}"
}

detect_apache_env() {
    # 1. Detect Apache binary
    HTTPD_BIN=""
    if [[ -n "$CUSTOM_BIN" && -x "$CUSTOM_BIN" ]]; then
        HTTPD_BIN="$CUSTOM_BIN"
    else
        for candidate in \
            "$(command -v httpd 2>/dev/null || true)" \
            "$(command -v apache2 2>/dev/null || true)" \
            "/usr/sbin/httpd" \
            "/usr/sbin/apache2" \
            "/usr/local/apache2/bin/httpd" \
            "/opt/apache2/bin/httpd"; do
            if [[ -n "$candidate" && -x "$candidate" ]]; then
                HTTPD_BIN="$candidate"
                break
            fi
        done
    fi

    # 2. Detect Apachectl binary
    APACHECTL_BIN=""
    for candidate in \
        "$(command -v apachectl 2>/dev/null || true)" \
        "$(command -v apache2ctl 2>/dev/null || true)" \
        "/usr/sbin/apachectl" \
        "/usr/sbin/apache2ctl" \
        "/usr/local/apache2/bin/apachectl"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            APACHECTL_BIN="$candidate"
            break
        fi
    done

    # 3. Detect APACHE_PREFIX (ServerRoot)
    APACHE_PREFIX=""
    if [[ -n "$CUSTOM_PREFIX" ]]; then
        APACHE_PREFIX="$CUSTOM_PREFIX"
    elif [[ -n "$HTTPD_BIN" ]]; then
        local httproot
        httproot=$("$HTTPD_BIN" -V 2>/dev/null | awk -F'"' '/HTTPD_ROOT=/ {print $2}' || true)
        if [[ -n "$httproot" && -d "$httproot" ]]; then
            APACHE_PREFIX="$httproot"
        fi
    fi

    if [[ -z "$APACHE_PREFIX" ]]; then
        for dir in "/etc/httpd" "/etc/apache2" "/usr/local/apache2" "/opt/apache2"; do
            if [[ -d "$dir" ]]; then
                APACHE_PREFIX="$dir"
                break
            fi
        done
    fi
    APACHE_PREFIX="${APACHE_PREFIX:-/etc/httpd}"

    # 4. Detect Main Configuration File
    HTTPD_CONF=""
    if [[ -n "$CUSTOM_CONF" ]]; then
        HTTPD_CONF="$CUSTOM_CONF"
    else
        if [[ -n "$HTTPD_BIN" ]]; then
            local rel_conf
            rel_conf=$("$HTTPD_BIN" -V 2>/dev/null | awk -F'"' '/SERVER_CONFIG_FILE=/ {print $2}' || true)
            if [[ -n "$rel_conf" ]]; then
                if [[ "$rel_conf" = /* && -f "$rel_conf" ]]; then
                    HTTPD_CONF="$rel_conf"
                elif [[ -f "$APACHE_PREFIX/$rel_conf" ]]; then
                    HTTPD_CONF="$APACHE_PREFIX/$rel_conf"
                fi
            fi
        fi
        if [[ -z "$HTTPD_CONF" ]]; then
            for cf in \
                "$APACHE_PREFIX/conf/httpd.conf" \
                "$APACHE_PREFIX/httpd.conf" \
                "$APACHE_PREFIX/apache2.conf" \
                "/etc/httpd/conf/httpd.conf" \
                "/etc/apache2/apache2.conf" \
                "/usr/local/apache2/conf/httpd.conf"; do
                if [[ -f "$cf" ]]; then
                    HTTPD_CONF="$cf"
                    break
                fi
            done
        fi
    fi
    HTTPD_CONF="${HTTPD_CONF:-$APACHE_PREFIX/conf/httpd.conf}"

    # 5. Gather all configuration files in Apache directories
    CONF_FILES=()
    if [[ -d "$APACHE_PREFIX" ]]; then
        while IFS= read -r -d '' f; do
            CONF_FILES+=("$f")
        done < <(find "$APACHE_PREFIX" -type f \( -name "*.conf" -o -name "envvars" \) \
            ! -path "*/mods-available/*" ! -path "*/sites-available/*" ! -path "*/conf-available/*" -print0 2>/dev/null || true)
        # Also include symlinks in *-enabled directories
        while IFS= read -r -d '' f; do
            CONF_FILES+=("$f")
        done < <(find "$APACHE_PREFIX" -type l -name "*.conf" \
            \( -path "*/mods-enabled/*" -o -path "*/sites-enabled/*" -o -path "*/conf-enabled/*" \) -print0 2>/dev/null || true)
    fi
    if [[ ${#CONF_FILES[@]} -eq 0 && -f "$HTTPD_CONF" ]]; then
        CONF_FILES=("$HTTPD_CONF")
    fi

    # 6. Cache loaded modules
    LOADED_MODULES=""
    MODULES_CMD_OK=0
    if [[ -n "$HTTPD_BIN" ]]; then
        LOADED_MODULES=$("$HTTPD_BIN" -M 2>&1 || true)
        if [[ -n "$LOADED_MODULES" ]] && ! echo "$LOADED_MODULES" | grep -qiE "error|failed"; then
            MODULES_CMD_OK=1
        fi
    fi
    if [[ $MODULES_CMD_OK -eq 0 && -n "$APACHECTL_BIN" ]]; then
        LOADED_MODULES=$("$APACHECTL_BIN" -M 2>&1 || true)
        if [[ -n "$LOADED_MODULES" ]] && ! echo "$LOADED_MODULES" | grep -qiE "error|failed"; then
            MODULES_CMD_OK=1
        fi
    fi
    # Fallback: parse LoadModule from config files if binary cannot run (e.g. non-root or not installed)
    if [[ $MODULES_CMD_OK -eq 0 && ${#CONF_FILES[@]} -gt 0 ]]; then
        LOADED_MODULES=$(grep -Eh "^\s*LoadModule\s+" "${CONF_FILES[@]}" 2>/dev/null | awk '{print " " $2 " (shared)"}' || true)
    fi

    # 7. Detect DocumentRoot
    DOCROOT=""
    if [[ -n "$CUSTOM_DOCROOT" ]]; then
        DOCROOT="$CUSTOM_DOCROOT"
    elif [[ ${#CONF_FILES[@]} -gt 0 ]]; then
        DOCROOT=$(grep -Ehi "^\s*DocumentRoot\s+" "${CONF_FILES[@]}" 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '"'\''' || true)
    fi
    if [[ -z "$DOCROOT" ]]; then
        if [[ -d "$APACHE_PREFIX/htdocs" ]]; then
            DOCROOT="$APACHE_PREFIX/htdocs"
        elif [[ -d "/var/www/html" ]]; then
            DOCROOT="/var/www/html"
        else
            DOCROOT="$APACHE_PREFIX/htdocs"
        fi
    fi

    # 8. Detect Configured Apache User & Group
    APACHE_USER=""
    APACHE_GROUP=""
    if [[ ${#CONF_FILES[@]} -gt 0 ]]; then
        APACHE_USER=$(grep -Ehi "^\s*User\s+" "${CONF_FILES[@]}" 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '"'\''' || true)
        APACHE_GROUP=$(grep -Ehi "^\s*Group\s+" "${CONF_FILES[@]}" 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '"'\''' || true)
        # Resolve Debian/Ubuntu envvars if ${APACHE_RUN_USER} is used
        if [[ "$APACHE_USER" == *"\${APACHE_RUN_USER}"* || "$APACHE_USER" == *"\$APACHE_RUN_USER"* ]]; then
            if [[ -f "$APACHE_PREFIX/envvars" ]]; then
                APACHE_USER=$(awk -F= '/^\s*export\s+APACHE_RUN_USER=/ {print $2}' "$APACHE_PREFIX/envvars" | tr -d '"'\'' ' || true)
            fi
        fi
        if [[ "$APACHE_GROUP" == *"\${APACHE_RUN_GROUP}"* || "$APACHE_GROUP" == *"\$APACHE_RUN_GROUP"* ]]; then
            if [[ -f "$APACHE_PREFIX/envvars" ]]; then
                APACHE_GROUP=$(awk -F= '/^\s*export\s+APACHE_RUN_GROUP=/ {print $2}' "$APACHE_PREFIX/envvars" | tr -d '"'\'' ' || true)
            fi
        fi
    fi
}

# Helper to search active (non-commented) directives across all config files
get_active_directives() {
    local pattern="$1"
    if [[ ${#CONF_FILES[@]} -gt 0 ]]; then
        grep -Ehi "$pattern" "${CONF_FILES[@]}" 2>/dev/null | sed 's/#.*//' | sed '/^[[:space:]]*$/d' || true
    fi
}

# Helper to extract <Directory ...> or <Location ...> blocks across all config files
get_config_stream() {
    if [[ ${#CONF_FILES[@]} -gt 0 ]]; then
        cat "${CONF_FILES[@]}" 2>/dev/null | sed 's/^[[:space:]]*#.*//' | sed '/^[[:space:]]*$/d' || true
    fi
}

# ==============================================================================
# SECTION 1: Planning and Installation
# ==============================================================================
run_section_1() {
    print_section_header "1" "Planning and Installation" || return 0

# 1.1 Ensure the Pre-Installation Planning Checklist Has Been Implemented (Manual)
manual_check "1.1" "Ensure the Pre-Installation Planning Checklist Has Been Implemented (Manual) [Level 1]" \
    "Pre-installation planning requires organizational policy and architecture review." \
    "Review and implement the following items as appropriate:
1. Review and implement company security policies as they relate to web security.
2. Implement a secure network infrastructure controlling access to/from the web server via firewalls, routers, and switches.
3. Harden the underlying OS (minimize listening services, apply patches, follow OS CIS Benchmark).
4. Implement central log monitoring processes.
5. Implement a disk space monitoring process and log rotation mechanism.
6. Educate developers, architects, and testers on secure application development (OWASP/WASC) and integrate security into SDLC.
7. Ensure WHOIS domain registration does not reveal sensitive personnel info (POC names, phone numbers, email addresses matching system usernames).
8. Secure DNS servers per the CIS BIND DNS Benchmark.
9. Implement a Network Intrusion Detection System (NIDS) to monitor attacks against the web server."

# 1.2 Ensure the Server Is Not a Multi-Use System (Manual)
 check_1_2() {
    local unwanted_services=("named" "bind9" "postfix" "sendmail" "exim4" "mysqld" "mariadb" "postgresql" " slapd" "smb" "nmb" "nfs-server" "vsftpd" "proftpd" "cups" "avahi-daemon" "dhcpd")
    local enabled_list=""
    if command -v systemctl >/dev/null 2>&1; then
        enabled_list=$(systemctl list-unit-files --state=enabled 2>/dev/null | awk '/\.service/ {print $1}' || true)
    elif command -v chkconfig >/dev/null 2>&1; then
        enabled_list=$(chkconfig --list 2>/dev/null | grep -E ":on" | awk '{print $1}' || true)
    fi

    local found_unwanted=()
    for svc in "${unwanted_services[@]}"; do
        if echo "$enabled_list" | grep -qiE "^${svc}(\.service)?$"; then
            found_unwanted+=("$svc")
        fi
    done

    if [[ ${#found_unwanted[@]} -gt 0 ]]; then
        fail_check "1.2" "Ensure the Server Is Not a Multi-Use System (Manual) [Level 1]" \
            "Detected non-web primary services enabled on this host: ${found_unwanted[*]}" \
            "Audit enabled services with:
  systemctl list-unit-files --state enabled
Disable or uninstall unnecessary services (such as mail, DNS, database, or file sharing) so the server functions solely as a web server:
  systemctl disable --now <servicename>
  # Or on older Red Hat systems:
  chkconfig <servicename> off"
    else
        manual_check "1.2" "Ensure the Server Is Not a Multi-Use System (Manual) [Level 1]" \
            "No common mail/DNS/DB/file-sharing services detected as enabled, but manual review of all enabled services against business needs is required." \
            "Review all enabled services and disable any not required for the web server:
  systemctl list-unit-files --state enabled
  chkconfig <servicename> off  # or: systemctl disable --now <servicename>"
    fi
}
check_1_2

# 1.3 Ensure Apache Is Installed From the Appropriate Binaries (Manual)
check_1_3() {
    local pkg_found=""
    if command -v rpm >/dev/null 2>&1; then
        pkg_found=$(rpm -qa 2>/dev/null | grep -E "^(httpd|apache2)-[0-9]" || true)
    fi
    if [[ -z "$pkg_found" ]] && command -v dpkg >/dev/null 2>&1; then
        pkg_found=$(dpkg -l 2>/dev/null | awk '/^ii/ && ($2=="apache2" || $2=="httpd") {print $2 " " $3}' || true)
    fi

    if [[ -n "$pkg_found" ]]; then
        pass_check "1.3" "Ensure Apache Is Installed From the Appropriate Binaries (Manual) [Level 1]" \
            "Apache is installed via vendor package: $(echo "$pkg_found" | tr '\n' ' ')"
    elif [[ -n "$HTTPD_BIN" ]]; then
        manual_check "1.3" "Ensure Apache Is Installed From the Appropriate Binaries (Manual) [Level 1]" \
            "Apache binary found at $HTTPD_BIN, but vendor package was not detected via rpm/dpkg (possibly source build)." \
            "Ensure Apache is installed from vendor-supplied binaries (e.g., 'yum install httpd' or 'apt-get install apache2') or a verified source build following https://httpd.apache.org/docs/2.4/install.html."
    else
        fail_check "1.3" "Ensure Apache Is Installed From the Appropriate Binaries (Manual) [Level 1]" \
            "Apache HTTP Server binary was not found on the system." \
            "Install Apache from your OS vendor's package repository:
  # Red Hat / CentOS / Rocky / AlmaLinux:
  yum install httpd
  # Debian / Ubuntu:
  apt-get install apache2
Or compile from verified official source at https://httpd.apache.org/docs/2.4/install.html"
    fi
}
check_1_3
}

# ==============================================================================
# SECTION 2: Minimize Apache Modules
# ==============================================================================
run_section_2() {
    print_section_header "2" "Minimize Apache Modules" || return 0

# 2.1 Ensure Only Necessary Authentication and Authorization Modules Are Enabled (Manual)
check_2_1() {
    local auth_mods ldap_mods
    auth_mods=$(echo "$LOADED_MODULES" | grep -E "auth._" | awk '{print $1}' | tr '\n' ' ' || true)
    ldap_mods=$(echo "$LOADED_MODULES" | grep -E "ldap" | awk '{print $1}' | tr '\n' ' ' || true)
    manual_check "2.1" "Ensure Only Necessary Authentication and Authorization Modules Are Enabled (Manual) [Level 1]" \
        "Loaded auth* modules: [${auth_mods:-none}] | Loaded LDAP modules: [${ldap_mods:-none}]" \
        "Audit loaded authentication/authorization and LDAP modules:
  httpd -M | egrep 'auth._'
  httpd -M | egrep 'ldap'
Disable any unnecessary modules by commenting out or removing their 'LoadModule' directive in httpd.conf (or module config files), or disabling them at compile time (--disable-<module>)."
}
check_2_1

# 2.2 Ensure the Log Config Module Is Enabled (Automated)
check_2_2() {
    if echo "$LOADED_MODULES" | grep -q "log_config_module"; then
        pass_check "2.2" "Ensure the Log Config Module Is Enabled (Automated) [Level 1]" \
            "log_config_module is loaded."
    else
        fail_check "2.2" "Ensure the Log Config Module Is Enabled (Automated) [Level 1]" \
            "log_config_module is NOT loaded." \
            "Enable the log_config module:
  - For source builds: run './configure' without '--disable-log-config'.
  - For dynamically loaded modules, add or uncomment in httpd.conf:
    LoadModule log_config_module modules/mod_log_config.so"
    fi
}
check_2_2

# 2.3 Ensure the WebDAV Modules Are Disabled (Automated)
check_2_3() {
    local dav_mods
    dav_mods=$(echo "$LOADED_MODULES" | grep -i "dav" | awk '{print $1}' | tr '\n' ' ' || true)
    if [[ -z "$dav_mods" ]]; then
        pass_check "2.3" "Ensure the WebDAV Modules Are Disabled (Automated) [Level 1]" \
            "No WebDAV (dav_*) modules are loaded."
    else
        fail_check "2.3" "Ensure the WebDAV Modules Are Disabled (Automated) [Level 1]" \
            "WebDAV modules are enabled: $dav_mods" \
            "Disable WebDAV modules:
  1. For source builds: run './configure' without including mod_dav and mod_dav_fs in --enable-modules.
  2. For dynamically loaded modules: comment out or remove from httpd.conf:
     ##LoadModule dav_module modules/mod_dav.so
     ##LoadModule dav_fs_module modules/mod_dav_fs.so"
    fi
}
check_2_3

# 2.4 Ensure the Status Module Is Disabled (Automated)
check_2_4() {
    if ! echo "$LOADED_MODULES" | grep -qE "status_module"; then
        pass_check "2.4" "Ensure the Status Module Is Disabled (Automated) [Level 1]" \
            "status_module is disabled."
    else
        fail_check "2.4" "Ensure the Status Module Is Disabled (Automated) [Level 1]" \
            "status_module is currently loaded." \
            "Disable the mod_status module:
  1. For source builds: run './configure --disable-status'.
  2. For dynamically loaded modules: comment out or remove from httpd.conf:
     ##LoadModule status_module modules/mod_status.so"
    fi
}
check_2_4

# 2.5 Ensure the Autoindex Module Is Disabled (Automated)
check_2_5() {
    if ! echo "$LOADED_MODULES" | grep -q "autoindex_module"; then
        pass_check "2.5" "Ensure the Autoindex Module Is Disabled (Automated) [Level 1]" \
            "autoindex_module is disabled."
    else
        fail_check "2.5" "Ensure the Autoindex Module Is Disabled (Automated) [Level 1]" \
            "autoindex_module is currently loaded." \
            "Disable the mod_autoindex module:
  1. For source builds: run './configure --disable-autoindex'.
  2. For dynamically loaded modules: comment out or remove from httpd.conf:
     ##LoadModule autoindex_module modules/mod_autoindex.so"
    fi
}
check_2_5

# 2.6 Ensure the Proxy Modules Are Disabled if not in use (Automated)
check_2_6() {
    local proxy_mods
    proxy_mods=$(echo "$LOADED_MODULES" | grep "proxy_" | awk '{print $1}' | tr '\n' ' ' || true)
    if [[ -z "$proxy_mods" ]]; then
        pass_check "2.6" "Ensure the Proxy Modules Are Disabled if not in use (Automated) [Level 1]" \
            "No proxy_* modules are loaded."
    else
        fail_check "2.6" "Ensure the Proxy Modules Are Disabled if not in use (Automated) [Level 1]" \
            "Proxy modules are currently loaded: $proxy_mods" \
            "Disable all proxy modules if not required:
  1. For source builds: run './configure' without mod_proxy in --enable-modules.
  2. For dynamically loaded modules: comment out or remove all proxy LoadModule directives from httpd.conf:
     ##LoadModule proxy_module modules/mod_proxy.so
     ##LoadModule proxy_connect_module modules/mod_proxy_connect.so
     ##LoadModule proxy_ftp_module modules/mod_proxy_ftp.so
     ##LoadModule proxy_http_module modules/mod_proxy_http.so
     ##LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so
     ##LoadModule proxy_scgi_module modules/mod_proxy_scgi.so
     ##LoadModule proxy_ajp_module modules/mod_proxy_ajp.so
     ##LoadModule proxy_balancer_module modules/mod_proxy_balancer.so
     ##LoadModule proxy_express_module modules/mod_proxy_express.so
     ##LoadModule proxy_wstunnel_module modules/mod_proxy_wstunnel.so
     ##LoadModule proxy_fdpass_module modules/mod_proxy_fdpass.so"
    fi
}
check_2_6

# 2.7 Ensure the User Directories Module Is Disabled (Automated)
check_2_7() {
    if ! echo "$LOADED_MODULES" | grep -q "userdir_module"; then
        pass_check "2.7" "Ensure the User Directories Module Is Disabled (Automated) [Level 1]" \
            "userdir_module is disabled."
    else
        fail_check "2.7" "Ensure the User Directories Module Is Disabled (Automated) [Level 1]" \
            "userdir_module is currently loaded." \
            "Disable the user directories module:
  1. For source builds: run './configure --disable-userdir'.
  2. For dynamically loaded modules: comment out or remove from httpd.conf:
     ##LoadModule userdir_module modules/mod_userdir.so"
    fi
}
check_2_7

# 2.8 Ensure the Info Module Is Disabled (Automated)
check_2_8() {
    if ! echo "$LOADED_MODULES" | grep -qE "info_module"; then
        pass_check "2.8" "Ensure the Info Module Is Disabled (Automated) [Level 1]" \
            "info_module is disabled."
    else
        fail_check "2.8" "Ensure the Info Module Is Disabled (Automated) [Level 1]" \
            "info_module is currently loaded." \
            "Disable the mod_info module:
  1. For source builds: run './configure' without mod_info in --enable-modules.
  2. For dynamically loaded modules: comment out or remove from httpd.conf:
     ##LoadModule info_module modules/mod_info.so"
    fi
}
check_2_8

# 2.9 Ensure the Basic and Digest Authentication Modules are Disabled (Automated)
check_2_9() {
    local basic_digest
    basic_digest=$(echo "$LOADED_MODULES" | grep -E "auth_basic_module|auth_digest_module" | awk '{print $1}' | tr '\n' ' ' || true)
    if [[ -z "$basic_digest" ]]; then
        pass_check "2.9" "Ensure the Basic and Digest Authentication Modules are Disabled (Automated) [Level 1]" \
            "Neither auth_basic_module nor auth_digest_module is loaded."
    else
        fail_check "2.9" "Ensure the Basic and Digest Authentication Modules are Disabled (Automated) [Level 1]" \
            "Basic/Digest authentication module(s) loaded: $basic_digest" \
            "Disable HTTP Basic and Digest authentication modules:
  1. For source builds: run './configure' without mod_auth_basic and mod_auth_digest in --enable-modules.
  2. For dynamically loaded modules: comment out or remove from httpd.conf:
     ##LoadModule auth_basic_module modules/mod_auth_basic.so
     ##LoadModule auth_digest_module modules/mod_auth_digest.so"
    fi
}
check_2_9
}

# ==============================================================================
# SECTION 3: Principles, Permissions, and Ownership
# ==============================================================================
run_section_3() {
    print_section_header "3" "Principles, Permissions, and Ownership" || return 0

# 3.1 Ensure the Apache Web Server Runs As a Non-Root User (Automated)
check_3_1() {
    local issues=()
    if [[ -z "$APACHE_USER" || -z "$APACHE_GROUP" ]]; then
        issues+=("User and/or Group directive is missing or commented out in Apache configuration.")
    else
        if [[ "$APACHE_USER" == "root" || "$APACHE_USER" == "nobody" || "$APACHE_USER" == "daemon" ]]; then
            issues+=("Configured Apache User '$APACHE_USER' is root or default shared account (nobody/daemon).")
        fi
        if [[ "$APACHE_GROUP" == "root" || "$APACHE_GROUP" == "nobody" || "$APACHE_GROUP" == "daemon" ]]; then
            issues+=("Configured Apache Group '$APACHE_GROUP' is root or default shared group (nobody/daemon).")
        fi

        local uid_min=1000
        if [[ -f /etc/login.defs ]]; then
            local login_uid_min
            login_uid_min=$(awk '/^\s*UID_MIN\s+/ {print $2}' /etc/login.defs 2>/dev/null | head -n 1 || true)
            [[ -n "$login_uid_min" ]] && uid_min="$login_uid_min"
        fi

        if id "$APACHE_USER" >/dev/null 2>&1; then
            local apache_uid
            apache_uid=$(id -u "$APACHE_USER" 2>/dev/null || echo 9999)
            if [[ "$apache_uid" -ge "$uid_min" || "$apache_uid" -eq 0 ]]; then
                issues+=("Apache user '$APACHE_USER' UID ($apache_uid) is not a valid system account (< UID_MIN $uid_min and > 0).")
            fi
        else
            issues+=("Configured Apache user '$APACHE_USER' does not exist on the system.")
        fi

        # Check running worker processes if Apache is running
        local running_workers
        running_workers=$(ps axu 2>/dev/null | grep -E "[h]ttpd|[a]pache2" | grep -v '^root' | awk '{print $1}' | sort -u | tr '\n' ' ' || true)
        if [[ -n "$running_workers" && "$running_workers" != "${APACHE_USER} " ]]; then
            issues+=("Running httpd/apache2 worker processes user(s) ($running_workers) do not match configured User ($APACHE_USER).")
        fi
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        pass_check "3.1" "Ensure the Apache Web Server Runs As a Non-Root User (Automated) [Level 1]" \
            "Apache is configured to run as dedicated system account '$APACHE_USER:$APACHE_GROUP'."
    else
        fail_check "3.1" "Ensure the Apache Web Server Runs As a Non-Root User (Automated) [Level 1]" \
            "$(printf '%s ' "${issues[@]}")" \
            "1. Create a unique system account and group for Apache if they do not exist:
   groupadd -r apache
   useradd apache -r -g apache -d /var/www -s /sbin/nologin
2. Configure User and Group in httpd.conf:
   User apache
   Group apache"
    fi
}
check_3_1

# 3.2 Ensure the Apache User Account Has an Invalid Shell (Automated)
check_3_2() {
    local target_user="${APACHE_USER:-apache}"
    local passwd_entry
    passwd_entry=$(grep -E "^${target_user}:" /etc/passwd 2>/dev/null || true)
    if [[ -z "$passwd_entry" ]]; then
        fail_check "3.2" "Ensure the Apache User Account Has an Invalid Shell (Automated) [Level 1]" \
            "Apache user account '$target_user' was not found in /etc/passwd." \
            "Ensure the Apache user exists and change its login shell to /sbin/nologin or /dev/null:
  chsh -s /sbin/nologin apache"
    else
        local user_shell
        user_shell=$(echo "$passwd_entry" | awk -F: '{print $7}')
        if [[ "$user_shell" == "/sbin/nologin" || "$user_shell" == "/usr/sbin/nologin" || "$user_shell" == "/dev/null" || "$user_shell" == "/bin/false" ]]; then
            pass_check "3.2" "Ensure the Apache User Account Has an Invalid Shell (Automated) [Level 1]" \
                "User '$target_user' has invalid shell: $user_shell"
        else
            fail_check "3.2" "Ensure the Apache User Account Has an Invalid Shell (Automated) [Level 1]" \
                "User '$target_user' has login shell '$user_shell' in /etc/passwd." \
                "Change the '$target_user' account to use /sbin/nologin or /dev/null:
  chsh -s /sbin/nologin $target_user"
        fi
    fi
}
check_3_2

# 3.3 Ensure the Apache User Account Is Locked (Automated)
check_3_3() {
    local target_user="${APACHE_USER:-apache}"
    if ! id "$target_user" >/dev/null 2>&1; then
        fail_check "3.3" "Ensure the Apache User Account Is Locked (Automated) [Level 1]" \
            "Apache user '$target_user' does not exist." \
            "Use the passwd command to lock the Apache account:
  passwd -l apache"
        return
    fi

    local status_out=""
    status_out=$(passwd -S "$target_user" 2>/dev/null || true)
    local shadow_field=""
    if [[ -r /etc/shadow ]]; then
        shadow_field=$(awk -F: -v u="$target_user" '$1==u {print $2}' /etc/shadow 2>/dev/null || true)
    fi

    if echo "$status_out" | awk '{print $2}' | grep -qE "^(LK|L)$" || [[ "$shadow_field" == "!"* || "$shadow_field" == "*"* ]]; then
        pass_check "3.3" "Ensure the Apache User Account Is Locked (Automated) [Level 1]" \
            "Account '$target_user' is locked (${status_out:-verified via /etc/shadow})."
    else
        fail_check "3.3" "Ensure the Apache User Account Is Locked (Automated) [Level 1]" \
            "Account '$target_user' password is not locked (passwd -S output: '${status_out:-unavailable/insufficient permissions}')." \
            "Lock the Apache user account using the passwd command:
  passwd -l $target_user"
    fi
}
check_3_3

# 3.4 Ensure Apache Directories and Files Are Owned By Root (Automated)
check_3_4() {
    if [[ ! -d "$APACHE_PREFIX" ]]; then
        fail_check "3.4" "Ensure Apache Directories and Files Are Owned By Root (Automated) [Level 1]" \
            "Apache directory '$APACHE_PREFIX' does not exist." \
            "Set ownership on the \$APACHE_PREFIX directories:
  chown -R root $APACHE_PREFIX"
        return
    fi

    local non_root_files
    non_root_files=$(find "$APACHE_PREFIX" \! -user root -print 2>/dev/null | head -n 5 || true)
    if [[ -z "$non_root_files" ]]; then
        pass_check "3.4" "Ensure Apache Directories and Files Are Owned By Root (Automated) [Level 1]" \
            "All files and directories in $APACHE_PREFIX are owned by root."
    else
        fail_check "3.4" "Ensure Apache Directories and Files Are Owned By Root (Automated) [Level 1]" \
            "Found files/directories in $APACHE_PREFIX not owned by root (sample: $(echo "$non_root_files" | tr '\n' ' '))." \
            "Set root ownership on the \$APACHE_PREFIX directories:
  chown -R root $APACHE_PREFIX"
    fi
}
check_3_4

# 3.5 Ensure the Group Is Set Correctly on Apache Directories and Files (Automated)
check_3_5() {
    if [[ ! -d "$APACHE_PREFIX" ]]; then
        fail_check "3.5" "Ensure the Group Is Set Correctly on Apache Directories and Files (Automated) [Level 1]" \
            "Apache directory '$APACHE_PREFIX' does not exist." \
            "Set root group ownership on the \$APACHE_PREFIX directories:
  chgrp -R root $APACHE_PREFIX"
        return
    fi

    local non_root_grp
    non_root_grp=$(find "$APACHE_PREFIX" -path "$APACHE_PREFIX/htdocs" -prune -o \! -group root -print 2>/dev/null | head -n 5 || true)
    if [[ -z "$non_root_grp" ]]; then
        pass_check "3.5" "Ensure the Group Is Set Correctly on Apache Directories and Files (Automated) [Level 1]" \
            "All files and directories in $APACHE_PREFIX (excluding htdocs) have group 'root'."
    else
        fail_check "3.5" "Ensure the Group Is Set Correctly on Apache Directories and Files (Automated) [Level 1]" \
            "Found files/directories in $APACHE_PREFIX (outside htdocs) with group other than root (sample: $(echo "$non_root_grp" | tr '\n' ' '))." \
            "Set group ownership to root on the \$APACHE_PREFIX directories:
  chgrp -R root $APACHE_PREFIX"
    fi
}
check_3_5

# 3.6 Ensure Other Write Access on Apache Directories and Files Is Restricted (Manual)
check_3_6() {
    if [[ ! -d "$APACHE_PREFIX" ]]; then
        fail_check "3.6" "Ensure Other Write Access on Apache Directories and Files Is Restricted (Manual) [Level 1]" \
            "Apache directory '$APACHE_PREFIX' does not exist." \
            "Remove other write access on the \$APACHE_PREFIX directories:
  chmod -R o-w $APACHE_PREFIX"
        return
    fi

    local other_writable
    other_writable=$(find -L "$APACHE_PREFIX" \! -type l -perm /o=w -print 2>/dev/null | head -n 5 || true)
    if [[ -z "$other_writable" ]]; then
        pass_check "3.6" "Ensure Other Write Access on Apache Directories and Files Is Restricted (Manual) [Level 1]" \
            "No files or directories in $APACHE_PREFIX have other write (o+w) access."
    else
        fail_check "3.6" "Ensure Other Write Access on Apache Directories and Files Is Restricted (Manual) [Level 1]" \
            "Found world-writable files/directories in $APACHE_PREFIX (sample: $(echo "$other_writable" | tr '\n' ' '))." \
            "Remove other write access on the \$APACHE_PREFIX directories:
  chmod -R o-w $APACHE_PREFIX"
    fi
}
check_3_6

# 3.7 Ensure the Core Dump Directory Is Secured (Manual)
check_3_7() {
    local coredump_dir
    coredump_dir=$(get_active_directives "^\s*CoreDumpDirectory\s+" | tail -n 1 | awk '{print $2}' | tr -d '"'\''' || true)
    if [[ -z "$coredump_dir" ]]; then
        pass_check "3.7" "Ensure the Core Dump Directory Is Secured (Manual) [Level 1]" \
            "CoreDumpDirectory directive is not enabled in Apache configuration."
        return
    fi

    [[ "$coredump_dir" != /* ]] && coredump_dir="$APACHE_PREFIX/$coredump_dir"
    local issues=()
    if [[ "$coredump_dir" == "$DOCROOT"* ]]; then
        issues+=("CoreDumpDirectory ($coredump_dir) is inside DocumentRoot ($DOCROOT).")
    fi
    if [[ -d "$coredump_dir" ]]; then
        local owner group mode
        owner=$(stat -c '%U' "$coredump_dir" 2>/dev/null || echo "")
        group=$(stat -c '%G' "$coredump_dir" 2>/dev/null || echo "")
        mode=$(stat -c '%A' "$coredump_dir" 2>/dev/null || echo "")
        [[ "$owner" != "root" ]] && issues+=("Owner of $coredump_dir is '$owner' (expected 'root').")
        [[ -n "$APACHE_GROUP" && "$group" != "$APACHE_GROUP" && "$group" != "root" ]] && issues+=("Group of $coredump_dir is '$group' (expected '$APACHE_GROUP').")
        if [[ "${mode:7:3}" != "---" ]]; then
            issues+=("Other users have permissions (${mode:7:3}) on $coredump_dir (expected no rwx for other).")
        fi
    else
        issues+=("Configured CoreDumpDirectory '$coredump_dir' does not exist.")
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        pass_check "3.7" "Ensure the Core Dump Directory Is Secured (Manual) [Level 1]" \
            "CoreDumpDirectory '$coredump_dir' meets ownership, group, and permission requirements."
    else
        fail_check "3.7" "Ensure the Core Dump Directory Is Secured (Manual) [Level 1]" \
            "$(printf '%s ' "${issues[@]}")" \
            "Either remove the CoreDumpDirectory directive from Apache configuration files or ensure the directory meets these requirements:
  1. Must not be within the Apache DocumentRoot ($DOCROOT).
  2. Must be owned by root and have group ownership of the Apache group:
     chown root:${APACHE_GROUP:-apache} $coredump_dir
  3. Must have no read-write-search access permission for other users:
     chmod o-rwx $coredump_dir"
    fi
}
check_3_7

# 3.8 Ensure the Lock File Is Secured (Manual)
check_3_8() {
    local mutex_lines
    mutex_lines=$(get_active_directives "^\s*Mutex\s+" || true)
    local bad_mutex=""
    if [[ -n "$mutex_lines" ]]; then
        bad_mutex=$(echo "$mutex_lines" | grep -Ei "\b(fcntl|flock|file)\b" || true)
    fi

    if [[ -z "$bad_mutex" ]]; then
        pass_check "3.8" "Ensure the Lock File Is Secured (Manual) [Level 1]" \
            "No file-based Mutex mechanism (fcntl, flock, or file) is configured."
    else
        fail_check "3.8" "Ensure the Lock File Is Secured (Manual) [Level 1]" \
            "File-based Mutex directive detected: $(echo "$bad_mutex" | tr '\n' ' ')" \
            "Prefer semaphore/default Mutex mechanism or secure the lock file directory:
  1. Ensure the lock file directory is NOT within the Apache DocumentRoot.
  2. Change ownership and group of the lock file directory to root:root:
     chown root:root <lock_dir>
  3. Restrict permissions so the directory is only writable by root (chmod go-w <lock_dir>).
  4. Ensure the lock file directory is on a locally mounted hard drive rather than NFS."
    fi
}
check_3_8

# 3.9 Ensure the Pid File Is Secured (Manual)
check_3_9() {
    local pidfile
    pidfile=$(get_active_directives "^\s*PidFile\s+" | tail -n 1 | awk '{print $2}' | tr -d '"'\''' || true)
    if [[ -z "$pidfile" ]]; then
        pidfile="logs/httpd.pid"
    fi
    # Resolve envvar if Debian/Ubuntu ${APACHE_PID_FILE}
    if [[ "$pidfile" == *"\${APACHE_PID_FILE}"* || "$pidfile" == *"\$APACHE_PID_FILE"* ]]; then
        if [[ -f "$APACHE_PREFIX/envvars" ]]; then
            pidfile=$(awk -F= '/^\s*export\s+APACHE_PID_FILE=/ {print $2}' "$APACHE_PREFIX/envvars" | tr -d '"'\'' ' || true)
        fi
        pidfile="${pidfile:-/var/run/apache2/apache2.pid}"
    fi
    [[ "$pidfile" != /* ]] && pidfile="$APACHE_PREFIX/$pidfile"
    local piddir
    piddir=$(dirname "$pidfile")
    [[ -L "$piddir" ]] && piddir=$(readlink -f "$piddir" 2>/dev/null || echo "$piddir")

    local issues=()
    if [[ "$piddir" == "$DOCROOT"* ]]; then
        issues+=("PidFile directory ($piddir) is inside DocumentRoot ($DOCROOT).")
    fi
    if [[ -d "$piddir" ]]; then
        local owner group
        owner=$(stat -c '%U' "$piddir" 2>/dev/null || echo "")
        group=$(stat -c '%G' "$piddir" 2>/dev/null || echo "")
        [[ "$owner" != "root" ]] && issues+=("PidFile directory '$piddir' owner is '$owner' (expected 'root').")
        [[ "$group" != "root" ]] && issues+=("PidFile directory '$piddir' group is '$group' (expected 'root').")
        if [[ -n $(find -L "$piddir" -maxdepth 0 -perm /g=w,o=w 2>/dev/null || true) ]]; then
            issues+=("PidFile directory '$piddir' is writable by group or other.")
        fi
    else
        issues+=("PidFile directory '$piddir' does not exist.")
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        pass_check "3.9" "Ensure the Pid File Is Secured (Manual) [Level 1]" \
            "PidFile directory '$piddir' is outside DocumentRoot, owned by root:root, and not writable by others."
    else
        fail_check "3.9" "Ensure the Pid File Is Secured (Manual) [Level 1]" \
            "$(printf '%s ' "${issues[@]}")" \
            "Secure the PidFile directory ($piddir):
  1. Ensure PidFile is not in a directory within the Apache DocumentRoot.
  2. Set ownership and group to root:root:
     chown root:root $piddir
  3. Set permissions so the directory is only writable by root:
     chmod go-w $piddir"
    fi
}
check_3_9

# 3.10 Ensure the ScoreBoard File Is Secured (Manual)
check_3_10() {
    local sbfile
    sbfile=$(get_active_directives "^\s*ScoreBoardFile\s+" | tail -n 1 | awk '{print $2}' | tr -d '"'\''' || true)
    if [[ -z "$sbfile" ]]; then
        pass_check "3.10" "Ensure the ScoreBoard File Is Secured (Manual) [Level 1]" \
            "ScoreBoardFile directive is not specified (shared memory used by default)."
        return
    fi

    [[ "$sbfile" != /* ]] && sbfile="$APACHE_PREFIX/$sbfile"
    local sbdir
    sbdir=$(dirname "$sbfile")
    [[ -L "$sbdir" ]] && sbdir=$(readlink -f "$sbdir" 2>/dev/null || echo "$sbdir")

    local issues=()
    if [[ "$sbdir" == "$DOCROOT"* ]]; then
        issues+=("ScoreBoardFile directory ($sbdir) is inside DocumentRoot ($DOCROOT).")
    fi
    if [[ -d "$sbdir" ]]; then
        local owner group fstype
        owner=$(stat -c '%U' "$sbdir" 2>/dev/null || echo "")
        group=$(stat -c '%G' "$sbdir" 2>/dev/null || echo "")
        fstype=$(df -T "$sbdir" 2>/dev/null | awk 'NR==2 {print $2}' || echo "")
        [[ "$owner" != "root" ]] && issues+=("ScoreBoardFile directory '$sbdir' owner is '$owner' (expected 'root').")
        [[ "$group" != "root" ]] && issues+=("ScoreBoardFile directory '$sbdir' group is '$group' (expected 'root').")
        if [[ -n $(find -L "$sbdir" -maxdepth 0 -perm /g=w,o=w 2>/dev/null || true) ]]; then
            issues+=("ScoreBoardFile directory '$sbdir' is writable by group or other.")
        fi
        [[ "$fstype" == *"nfs"* ]] && issues+=("ScoreBoardFile directory '$sbdir' is on an NFS filesystem ($fstype).")
    else
        issues+=("ScoreBoardFile directory '$sbdir' does not exist.")
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        pass_check "3.10" "Ensure the ScoreBoard File Is Secured (Manual) [Level 1]" \
            "ScoreBoardFile directory '$sbdir' is properly secured."
    else
        fail_check "3.10" "Ensure the ScoreBoard File Is Secured (Manual) [Level 1]" \
            "$(printf '%s ' "${issues[@]}")" \
            "Either remove ScoreBoardFile or secure its directory ($sbdir):
  1. Ensure ScoreBoardFile is not within the Apache DocumentRoot.
  2. Set ownership and group to root:root:
     chown root:root $sbdir
  3. Restrict write permissions to root only:
     chmod go-w $sbdir
  4. Ensure the directory is on a locally mounted hard drive rather than NFS."
    fi
}
check_3_10

# 3.11 Ensure Group Write Access for the Apache Directories and Files Is Properly Restricted (Manual)
check_3_11() {
    if [[ ! -d "$APACHE_PREFIX" ]]; then
        fail_check "3.11" "Ensure Group Write Access for the Apache Directories and Files Is Properly Restricted (Manual) [Level 1]" \
            "Apache directory '$APACHE_PREFIX' does not exist." \
            "Remove group write access on \$APACHE_PREFIX directories:
  find -L $APACHE_PREFIX ! -type l -perm /g=w -exec chmod g-w {} +"
        return
    fi

    local grp_writable
    grp_writable=$(find -L "$APACHE_PREFIX" -path "$DOCROOT" -prune -o \! -type l -perm /g=w -print 2>/dev/null | head -n 5 || true)
    if [[ -z "$grp_writable" ]]; then
        pass_check "3.11" "Ensure Group Write Access for the Apache Directories and Files Is Properly Restricted (Manual) [Level 1]" \
            "No files or directories in $APACHE_PREFIX (outside DocumentRoot) have group write access."
    else
        fail_check "3.11" "Ensure Group Write Access for the Apache Directories and Files Is Properly Restricted (Manual) [Level 1]" \
            "Found group-writable files/directories in $APACHE_PREFIX (sample: $(echo "$grp_writable" | tr '\n' ' '))." \
            "Remove group write access on the \$APACHE_PREFIX directories:
  find -L $APACHE_PREFIX ! -type l -perm /g=w -exec chmod g-w {} +"
    fi
}
check_3_11

# 3.12 Ensure Group Write Access for the Document Root Directories and Files Is Properly Restricted (Manual)
check_3_12() {
    local grp="${APACHE_GROUP:-apache}"
    if [[ ! -d "$DOCROOT" ]]; then
        fail_check "3.12" "Ensure Group Write Access for the Document Root Directories and Files Is Properly Restricted (Manual) [Level 1]" \
            "DocumentRoot '$DOCROOT' does not exist." \
            "Ensure DocumentRoot exists and remove group write access for the Apache group ($grp):
  find -L $DOCROOT -group $grp -perm /g=w -print | xargs chmod g-w"
        return
    fi

    local docroot_grp_w=""
    if grep -qE "^${grp}:" /etc/group 2>/dev/null; then
        docroot_grp_w=$(find -L "$DOCROOT" -group "$grp" -perm /g=w -print 2>/dev/null | head -n 5 || true)
    fi

    if [[ -z "$docroot_grp_w" ]]; then
        pass_check "3.12" "Ensure Group Write Access for the Document Root Directories and Files Is Properly Restricted (Manual) [Level 1]" \
            "No files or directories in DocumentRoot ($DOCROOT) are writable by the Apache group ($grp)."
    else
        fail_check "3.12" "Ensure Group Write Access for the Document Root Directories and Files Is Properly Restricted (Manual) [Level 1]" \
            "Found files/directories in $DOCROOT writable by Apache group '$grp' (sample: $(echo "$docroot_grp_w" | tr '\n' ' '))." \
            "Remove group write access on \$DOCROOT directories and files with the Apache group:
  GRP=\$(grep '^Group' $HTTPD_CONF | cut -d' ' -f2)
  find -L $DOCROOT -group \$GRP -perm /g=w -print | xargs chmod g-w"
    fi
}
check_3_12

# 3.13 Ensure Access to Special Purpose Application Writable Directories is Properly Restricted (Manual)
manual_check "3.13" "Ensure Access to Special Purpose Application Writable Directories is Properly Restricted (Manual) [Level 1]" \
    "Requires manual verification of any application-specific writable directories (e.g., PHP sessions, file upload directories)." \
    "For each application writable directory (\$WR_DIR), verify and enforce:
1. Single Purpose Directory: Confirm the directory serves only a single purpose.
2. Outside DocumentRoot: Move the directory outside \$DOCROOT (verify with: find -L $DOCROOT -inum \$(stat -c '%i' \$WR_DIR)).
3. Owned by root or an Administrator Account:
   chown root \$WR_DIR
4. Not writable by Other (find \$WR_DIR/ -perm /o=w -ls):
   chmod o-w \$WR_DIR"
}

# ==============================================================================
# SECTION 4: Apache Access Control
# ==============================================================================
run_section_4() {
    print_section_header "4" "Apache Access Control" || return 0

# Helper to extract <Directory /> block contents
get_os_root_dir_block() {
    get_config_stream | awk '
        BEGIN { IGNORECASE=1; in_block=0 }
        /^[[:space:]]*<Directory[[:space:]]+"?\/"?[[:space:]]*>/ { in_block=1; next }
        in_block && /^[[:space:]]*<\/Directory>/ { in_block=0; print "---BLOCK_END---"; next }
        in_block { print }
    '
}

# 4.1 Ensure Access to OS Root Directory Is Denied By Default (Automated)
check_4_1() {
    local block
    block=$(get_os_root_dir_block)
    if [[ -z "$block" ]]; then
        fail_check "4.1" "Ensure Access to OS Root Directory Is Denied By Default (Automated) [Level 1]" \
            "No root <Directory /> element was found in the Apache configuration." \
            "Add a root <Directory /> block in httpd.conf denying access by default:
  <Directory />
      Require all denied
  </Directory>"
        return
    fi

    local req_denied req_other allow_dir deny_dir order_dir
    req_denied=$(echo "$block" | grep -Eic "^\s*Require\s+all\s+denied\s*$" || true)
    req_other=$(echo "$block" | grep -Eiv "^\s*Require\s+all\s+denied\s*$" | grep -Eic "^\s*Require\s+" || true)
    allow_dir=$(echo "$block" | grep -Eic "^\s*Allow\s+" || true)
    deny_dir=$(echo "$block" | grep -Eic "^\s*Deny\s+" || true)
    order_dir=$(echo "$block" | grep -Eic "^\s*Order\s+deny,\s*allow\s*$" || true)
    local deny_all
    deny_all=$(echo "$block" | grep -Eic "^\s*Deny\s+from\s+all\s*$" || true)

    if [[ "$req_denied" -eq 1 && "$req_other" -eq 0 && "$allow_dir" -eq 0 && "$deny_dir" -eq 0 ]]; then
        pass_check "4.1" "Ensure Access to OS Root Directory Is Denied By Default (Automated) [Level 1]" \
            "Root <Directory /> has 'Require all denied' with no conflicting Allow/Deny directives."
    elif [[ "$order_dir" -eq 1 && "$deny_all" -eq 1 && "$allow_dir" -eq 0 && "$req_denied" -eq 0 && "$req_other" -eq 0 ]]; then
        pass_check "4.1" "Ensure Access to OS Root Directory Is Denied By Default (Automated) [Level 1]" \
            "Root <Directory /> uses 'Order deny,allow' and 'Deny from all' with no Allow/Require directives."
    else
        fail_check "4.1" "Ensure Access to OS Root Directory Is Denied By Default (Automated) [Level 1]" \
            "Root <Directory /> element does not strictly enforce 'Require all denied' (or deprecated Order/Deny equivalent)." \
            "Configure the root <Directory /> element in httpd.conf as follows and remove any Deny/Allow directives:
  <Directory />
      Require all denied
  </Directory>"
    fi
}
check_4_1

# 4.2 Ensure Appropriate Access to Web Content Is Allowed (Manual)
check_4_2() {
    local deprecated_allow
    deprecated_allow=$(get_active_directives "^\s*(Order|Allow|Deny)\s+" || true)
    if [[ -n "$deprecated_allow" ]]; then
        fail_check "4.2" "Ensure Appropriate Access to Web Content Is Allowed (Manual) [Level 1]" \
            "Deprecated Order/Allow/Deny directives found in configuration." \
            "Replace deprecated Order/Allow/Deny directives with appropriate Apache 2.4 'Require' directives in <Directory> and <Location> blocks:
  <Directory \"$DOCROOT\">
      Require all granted
  </Directory>"
    else
        manual_check "4.2" "Ensure Appropriate Access to Web Content Is Allowed (Manual) [Level 1]" \
            "No deprecated Order/Allow/Deny directives detected. Manual review of <Directory> and <Location> 'Require' values is needed to confirm business appropriateness." \
            "Review all <Directory> and <Location> elements in httpd.conf and included files:
  perl -ne 'print if /^ *<Directory */i .. /<\/Directory/i' $HTTPD_CONF
  perl -ne 'print if /^ *<Location */i .. /<\/Location/i' $HTTPD_CONF
Ensure each block uses appropriate 'Require' directives (e.g., 'Require all granted', 'Require local', 'Require ip ...', or 'Require valid-user') and does not mix Order/Deny/Allow with Require."
    fi
}
check_4_2

# 4.3 Ensure OverRide Is Disabled for the OS Root Directory (Automated)
check_4_3() {
    local block
    block=$(get_os_root_dir_block)
    if [[ -z "$block" ]]; then
        fail_check "4.3" "Ensure OverRide Is Disabled for the OS Root Directory (Automated) [Level 1]" \
            "No root <Directory /> element was found in the Apache configuration." \
            "Add 'AllowOverride None' to the root <Directory /> element in httpd.conf:
  <Directory />
      AllowOverride None
  </Directory>"
        return
    fi

    local ao_none ao_other aolist
    ao_none=$(echo "$block" | grep -Eic "^\s*AllowOverride\s+None\s*$" || true)
    ao_other=$(echo "$block" | grep -Eiv "^\s*AllowOverride\s+None\s*$" | grep -Eic "^\s*AllowOverride\s+" || true)
    aolist=$(echo "$block" | grep -Eic "^\s*AllowOverrideList\s+" || true)

    if [[ "$ao_none" -eq 1 && "$ao_other" -eq 0 && "$aolist" -eq 0 ]]; then
        pass_check "4.3" "Ensure OverRide Is Disabled for the OS Root Directory (Automated) [Level 1]" \
            "Root <Directory /> has 'AllowOverride None' and no AllowOverrideList directives."
    else
        fail_check "4.3" "Ensure OverRide Is Disabled for the OS Root Directory (Automated) [Level 1]" \
            "Root <Directory /> does not have a single 'AllowOverride None' or contains AllowOverrideList." \
            "In httpd.conf within <Directory />, remove any AllowOverrideList directives and set:
  <Directory />
      AllowOverride None
  </Directory>"
    fi
}
check_4_3

# 4.4 Ensure OverRide Is Disabled for All Directories (Automated)
check_4_4() {
    local bad_ao aolist
    bad_ao=$(get_active_directives "^\s*AllowOverride\s+" | grep -Eiv "^\s*AllowOverride\s+None\s*$" || true)
    aolist=$(get_active_directives "^\s*AllowOverrideList\s+" || true)

    if [[ -z "$bad_ao" && -z "$aolist" ]]; then
        pass_check "4.4" "Ensure OverRide Is Disabled for All Directories (Automated) [Level 1]" \
            "All AllowOverride directives are set to 'None' and no AllowOverrideList directives are present."
    else
        fail_check "4.4" "Ensure OverRide Is Disabled for All Directories (Automated) [Level 1]" \
            "Non-compliant AllowOverride / AllowOverrideList directives found: $(echo "$bad_ao $aolist" | tr '\n' ' ')" \
            "1. Search all Apache configuration files for AllowOverride directives and set their value to None:
   AllowOverride None
2. Remove any AllowOverrideList directives found."
    fi
}
check_4_4
}

# ==============================================================================
# SECTION 5: Minimize Features, Content and Options
# ==============================================================================
run_section_5() {
    print_section_header "5" "Minimize Features, Content and Options" || return 0

# 5.1 Ensure Options for the OS Root Directory Are Restricted (Automated)
check_5_1() {
    local block
    block=$(get_os_root_dir_block)
    if [[ -z "$block" ]]; then
        fail_check "5.1" "Ensure Options for the OS Root Directory Are Restricted (Automated) [Level 1]" \
            "No root <Directory /> element was found in the Apache configuration." \
            "In httpd.conf within <Directory />, set Options to None:
  <Directory />
      Options None
  </Directory>"
        return
    fi

    local opt_none opt_other
    opt_none=$(echo "$block" | grep -Eic "^\s*Options\s+None\s*$" || true)
    opt_other=$(echo "$block" | grep -Eiv "^\s*Options\s+None\s*$" | grep -Eic "^\s*Options\s+" || true)

    if [[ "$opt_none" -eq 1 && "$opt_other" -eq 0 ]]; then
        pass_check "5.1" "Ensure Options for the OS Root Directory Are Restricted (Automated) [Level 1]" \
            "Root <Directory /> has 'Options None'."
    else
        fail_check "5.1" "Ensure Options for the OS Root Directory Are Restricted (Automated) [Level 1]" \
            "Root <Directory /> does not have a single 'Options None' directive." \
            "In httpd.conf within <Directory />, add or modify the Options directive to None:
  <Directory />
      Options None
  </Directory>"
    fi
}
check_5_1

# 5.2 Ensure Options for the Web Root Directory Are Restricted (Automated)
check_5_2() {
    local docroot_block
    docroot_block=$(get_config_stream | awk -v dr="$DOCROOT" '
        BEGIN { IGNORECASE=1; in_block=0 }
        /^[[:space:]]*<Directory[[:space:]]+/ {
            line=$0
            gsub(/["'\''>]/, "", line)
            sub(/^[[:space:]]*<Directory[[:space:]]+/, "", line)
            sub(/[[:space:]]*$/, "", line)
            sub(/\/$/, "", line)
            target=dr
            sub(/\/$/, "", target)
            if (tolower(line) == tolower(target)) { in_block=1; next }
        }
        in_block && /^[[:space:]]*<\/Directory>/ { in_block=0; next }
        in_block { print }
    ')

    if [[ -z "$docroot_block" ]]; then
        fail_check "5.2" "Ensure Options for the Web Root Directory Are Restricted (Automated) [Level 2]" \
            "No <Directory \"$DOCROOT\"> block was found in the Apache configuration." \
            "In httpd.conf, ensure the DocumentRoot <Directory \"$DOCROOT\"> block has 'Options None' (or 'Options Multiviews' if required):
  <Directory \"$DOCROOT\">
      Options None
  </Directory>"
        return
    fi

    local opt_valid opt_invalid
    opt_valid=$(echo "$docroot_block" | grep -Eic "^\s*Options\s+(None|Multiviews)\s*$" || true)
    opt_invalid=$(echo "$docroot_block" | grep -Eiv "^\s*Options\s+(None|Multiviews)\s*$" | grep -Eic "^\s*Options\s+" || true)

    if [[ "$opt_valid" -eq 1 && "$opt_invalid" -eq 0 ]]; then
        pass_check "5.2" "Ensure Options for the Web Root Directory Are Restricted (Automated) [Level 2]" \
            "DocumentRoot <Directory \"$DOCROOT\"> has compliant Options (None or Multiviews)."
    else
        fail_check "5.2" "Ensure Options for the Web Root Directory Are Restricted (Automated) [Level 2]" \
            "DocumentRoot <Directory \"$DOCROOT\"> has non-compliant or missing Options directive." \
            "In httpd.conf within <Directory \"$DOCROOT\">, set Options to None (or Multiviews if needed):
  <Directory \"$DOCROOT\">
      Options None
  </Directory>"
    fi
}
check_5_2

# 5.3 Ensure Options for Other Directories Are Minimized (Automated)
check_5_3() {
    local inc_opts
    # Match Options enabling 'Includes' (but allow IncludesNOEXEC or -Includes)
    inc_opts=$(get_active_directives "^\s*Options\s+" | grep -Ei "\+?\bIncludes\b" | grep -Eiv "\-Includes\b" || true)
    if [[ -z "$inc_opts" ]]; then
        pass_check "5.3" "Ensure Options for Other Directories Are Minimized (Automated) [Level 2]" \
            "No <Directory> Options directives enable 'Includes'."
    else
        fail_check "5.3" "Ensure Options for Other Directories Are Minimized (Automated) [Level 2]" \
            "Found Options directive(s) enabling 'Includes': $(echo "$inc_opts" | tr '\n' ' ')" \
            "Search all <Directory> blocks in Apache configuration files and modify any Options directive so it does NOT enable 'Includes' (use 'Options None' or 'IncludesNOEXEC' if server-side includes without exec are required)."
    fi
}
check_5_3

# 5.4 Ensure Default HTML Content Is Removed (Manual)
check_5_4() {
    local issues=()
    if [[ -f "$DOCROOT/index.html" ]]; then
        if grep -qi "It works!" "$DOCROOT/index.html" 2>/dev/null; then
            issues+=("Default 'It works!' index.html exists at $DOCROOT/index.html.")
        fi
    fi
    if [[ -f "$APACHE_PREFIX/conf.d/welcome.conf" ]]; then
        if grep -Ev "^\s*#" "$APACHE_PREFIX/conf.d/welcome.conf" 2>/dev/null | grep -qE "<LocationMatch|ErrorDocument"; then
            issues+=("Active welcome page configuration found in $APACHE_PREFIX/conf.d/welcome.conf.")
        fi
    fi
    if [[ -n $(get_active_directives "^\s*Include.*httpd-manual\.conf|Alias\s+/manual" || true) ]]; then
        issues+=("Apache User Manual configuration is active.")
    fi
    if [[ -n $(get_active_directives "^\s*SetHandler\s+(server-status|server-info|perl-script)" || true) ]]; then
        issues+=("Handler configuration (server-status, server-info, or perl-status) is active.")
    fi
    if [[ -n $(get_active_directives "^\s*Include\s+conf/extra/proxy-html\.conf" || true) ]]; then
        issues+=("Default Include conf/extra/proxy-html.conf is not commented out.")
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        pass_check "5.4" "Ensure Default HTML Content Is Removed (Manual) [Level 1]" \
            "No default welcome page, manual, status/info handlers, or default 'It works!' page detected."
    else
        fail_check "5.4" "Ensure Default HTML Content Is Removed (Manual) [Level 1]" \
            "$(printf '%s ' "${issues[@]}")" \
            "Remove or comment out default HTML content and handlers:
  1. Remove default index.html ('It works!') or comment out lines in welcome.conf.
  2. Remove Apache user manual ('yum erase httpd-manual') and comment out '#Include conf/extra/httpd-manual.conf'.
  3. Comment out or remove <Location /server-status>, <Location /server-info>, and <Location /perl-status> sections.
  4. Comment out '#Include conf/extra/proxy-html.conf' in httpd.conf if not required."
    fi
}
check_5_4

# Helper to find configured cgi-bin directories
get_cgibin_dirs() {
    local dirs=()
    [[ -d "$APACHE_PREFIX/cgi-bin" ]] && dirs+=("$APACHE_PREFIX/cgi-bin")
    [[ -d "/var/www/cgi-bin" ]] && dirs+=("/var/www/cgi-bin")
    [[ -d "/usr/lib/cgi-bin" ]] && dirs+=("/usr/lib/cgi-bin")
    while IFS= read -r dir; do
        dir=$(echo "$dir" | tr -d '"'\''' | sed 's/\/$//')
        [[ -n "$dir" && -d "$dir" ]] && dirs+=("$dir")
    done < <(get_active_directives "^\s*ScriptAlias(Match)?\s+" | awk '{print $3}' || true)
    printf '%s\n' "${dirs[@]}" | sort -u
}

# 5.5 Ensure the Default CGI Content printenv Script Is Removed (Manual)
check_5_5() {
    local found_printenv=()
    while IFS= read -r cdir; do
        [[ -z "$cdir" ]] && continue
        for f in "$cdir"/printenv*; do
            [[ -e "$f" ]] && found_printenv+=("$f")
        done
    done < <(get_cgibin_dirs)

    if [[ ${#found_printenv[@]} -eq 0 ]]; then
        pass_check "5.5" "Ensure the Default CGI Content printenv Script Is Removed (Manual) [Level 2]" \
            "No default printenv CGI script found in configured cgi-bin directories."
    else
        fail_check "5.5" "Ensure the Default CGI Content printenv Script Is Removed (Manual) [Level 2]" \
            "Found printenv CGI script(s): ${found_printenv[*]}" \
            "Remove the default printenv CGI script from cgi-bin directories:
  rm -f ${found_printenv[*]}"
    fi
}
check_5_5

# 5.6 Ensure the Default CGI Content test-cgi Script Is Removed (Manual)
check_5_6() {
    local found_testcgi=()
    while IFS= read -r cdir; do
        [[ -z "$cdir" ]] && continue
        for f in "$cdir"/test-cgi*; do
            [[ -e "$f" ]] && found_testcgi+=("$f")
        done
    done < <(get_cgibin_dirs)

    if [[ ${#found_testcgi[@]} -eq 0 ]]; then
        pass_check "5.6" "Ensure the Default CGI Content test-cgi Script Is Removed (Manual) [Level 2]" \
            "No default test-cgi script found in configured cgi-bin directories."
    else
        fail_check "5.6" "Ensure the Default CGI Content test-cgi Script Is Removed (Manual) [Level 2]" \
            "Found test-cgi script(s): ${found_testcgi[*]}" \
            "Remove the default test-cgi script from cgi-bin directories:
  rm -f ${found_testcgi[*]}"
    fi
}
check_5_6

# 5.7 Ensure HTTP Request Methods Are Restricted (Manual)
check_5_7() {
    # Inspect all non-root <Directory> blocks to verify <LimitExcept GET POST OPTIONS> or AllowMethods
    local missing_blocks
    missing_blocks=$(get_config_stream | awk '
        BEGIN { IGNORECASE=1; in_dir=0; dir_name=""; has_limit=0; has_allowmethods=0; bad_dirs="" }
        /^[[:space:]]*<Directory[[:space:]]+/ {
            line=$0
            gsub(/["'\''>]/, "", line)
            sub(/^[[:space:]]*<Directory[[:space:]]+/, "", line)
            sub(/[[:space:]]*$/, "", line)
            if (line != "/") {
                in_dir=1
                dir_name=line
                has_limit=0
                has_allowmethods=0
            }
            next
        }
        in_dir && /^[[:space:]]*<LimitExcept[[:space:]]+/ {
            # Verify only GET, POST, OPTIONS, HEAD are listed
            le=$0
            sub(/^[[:space:]]*<LimitExcept[[:space:]]+/, "", le)
            sub(/>.*$/, "", le)
            n=split(le, m, /[[:space:]]+/)
            valid=1
            for (i=1; i<=n; i++) {
                if (m[i] != "" && toupper(m[i]) !~ /^(GET|POST|OPTIONS|HEAD)$/) valid=0
            }
            if (valid) has_limit=1
        }
        in_dir && /^[[:space:]]*AllowMethods[[:space:]]+/ {
            am=$0
            sub(/^[[:space:]]*AllowMethods[[:space:]]+/, "", am)
            n=split(am, m, /[[:space:]]+/)
            valid=1
            for (i=1; i<=n; i++) {
                if (m[i] != "" && toupper(m[i]) !~ /^(GET|POST|OPTIONS|HEAD)$/) valid=0
            }
            if (valid) has_allowmethods=1
        }
        in_dir && /^[[:space:]]*<\/Directory>/ {
            if (!has_limit && !has_allowmethods) {
                bad_dirs = bad_dirs dir_name " "
            }
            in_dir=0
        }
        END { print bad_dirs }
    ')

    local total_nonroot_dirs
    total_nonroot_dirs=$(get_active_directives "^\s*<Directory\s+" | grep -Eiv "^\s*<Directory\s+\"?/\"?\s*>" | wc -l || echo 0)

    if [[ "$total_nonroot_dirs" -gt 0 && -z "$missing_blocks" ]]; then
        pass_check "5.7" "Ensure HTTP Request Methods Are Restricted (Manual) [Level 2]" \
            "All non-root <Directory> blocks restrict HTTP methods to GET, POST, OPTIONS."
    else
        fail_check "5.7" "Ensure HTTP Request Methods Are Restricted (Manual) [Level 2]" \
            "Non-root <Directory> block(s) missing HTTP method restrictions: ${missing_blocks:-No non-root <Directory> blocks configured}" \
            "Within every <Directory> section other than the OS root directory (including \"$DOCROOT\" and cgi-bin), add:
  <LimitExcept GET POST OPTIONS>
      Require all denied
  </LimitExcept>
Alternatively, load mod_allowmethods and add 'AllowMethods GET POST OPTIONS' inside each <Directory> block."
    fi
}
check_5_7

# 5.8 Ensure the HTTP TRACE Method Is Disabled (Automated)
check_5_8() {
    local trace_lines trace_off_count trace_total
    trace_lines=$(get_active_directives "^\s*TraceEnable\s+" || true)
    trace_total=$(echo "$trace_lines" | sed '/^$/d' | wc -l)
    trace_off_count=$(echo "$trace_lines" | grep -Eic "^\s*TraceEnable\s+off\s*$" || true)

    if [[ "$trace_total" -eq 1 && "$trace_off_count" -eq 1 ]]; then
        pass_check "5.8" "Ensure the HTTP TRACE Method Is Disabled (Automated) [Level 1]" \
            "TraceEnable is set to 'off'."
    else
        fail_check "5.8" "Ensure the HTTP TRACE Method Is Disabled (Automated) [Level 1]" \
            "TraceEnable is either not configured or not set to a single 'TraceEnable off' directive (found $trace_total instance(s))." \
            "Add the following directive at the global server level in httpd.conf:
  TraceEnable off"
    fi
}
check_5_8

# 5.9 Ensure Old HTTP Protocol Versions Are Disallowed (Automated)
check_5_9() {
    local has_rewrite_mod has_cond has_rule
    has_rewrite_mod=$(echo "$LOADED_MODULES" | grep -c "rewrite_module" || true)
    has_cond=$(get_active_directives "^\s*RewriteCond\s+%\{THE_REQUEST\}" | grep -Eic "!.*HTTP/1\\\.1" || true)
    has_rule=$(get_active_directives "^\s*RewriteRule\s+\.\*\s+-\s+\[.*F.*\]" | wc -l || true)

    local vhost_count inherit_count
    vhost_count=$(get_active_directives "^\s*<VirtualHost\s+" | wc -l || true)
    inherit_count=$(get_active_directives "^\s*RewriteOptions\s+Inherit" | wc -l || true)

    if [[ "$has_rewrite_mod" -ge 1 && "$has_cond" -ge 1 && "$has_rule" -ge 1 && "$inherit_count" -ge "$vhost_count" ]]; then
        pass_check "5.9" "Ensure Old HTTP Protocol Versions Are Disallowed (Automated) [Level 1]" \
            "mod_rewrite is loaded and configured to disallow old HTTP protocol versions with RewriteOptions Inherit."
    else
        fail_check "5.9" "Ensure Old HTTP Protocol Versions Are Disallowed (Automated) [Level 1]" \
            "Missing mod_rewrite rule disallowing non-HTTP/1.1 (or HTTP/2.0) requests or missing 'RewriteOptions Inherit' in VirtualHosts." \
            "1. Load mod_rewrite in httpd.conf:
   LoadModule rewrite_module modules/mod_rewrite.so
2. Add the following to the global server level configuration in httpd.conf:
   RewriteEngine On
   RewriteCond %{THE_REQUEST} !(HTTP/1\.1|HTTP/2\.0)\$
   RewriteRule .* - [F]
3. Add the following inside each <VirtualHost> section:
   RewriteEngine On
   RewriteOptions Inherit"
    fi
}
check_5_9

# 5.10 Ensure Access to .ht* Files Is Restricted (Automated)
check_5_10() {
    local ht_denied
    ht_denied=$(get_config_stream | awk '
        BEGIN { IGNORECASE=1; in_fm=0; denied=0 }
        /^[[:space:]]*<FilesMatch?[[:space:]]+"?\^?\\?\.ht/ { in_fm=1; next }
        in_fm && /^[[:space:]]*(Require[[:space:]]+all[[:space:]]+denied|Deny[[:space:]]+from[[:space:]]+all)/ { denied=1 }
        in_fm && /^[[:space:]]*<\/FilesMatch?>/ { in_fm=0 }
        END { print denied }
    ')

    if [[ "$ht_denied" -eq 1 ]]; then
        pass_check "5.10" "Ensure Access to .ht* Files Is Restricted (Automated) [Level 1]" \
            "Access to .ht* files is restricted via <FilesMatch \"^\.ht\">."
    else
        fail_check "5.10" "Ensure Access to .ht* Files Is Restricted (Automated) [Level 1]" \
            "No active <FilesMatch \"^\.ht\"> block with 'Require all denied' was found." \
            "Add or modify the following lines at the server configuration level in httpd.conf:
  <FilesMatch \"^\.ht\">
      Require all denied
  </FilesMatch>"
    fi
}
check_5_10

# 5.11 Ensure Access to .git Files Is Restricted (Manual)
check_5_11() {
    local git_restricted
    git_restricted=$(get_config_stream | awk '
        BEGIN { IGNORECASE=1; in_fm=0; in_dm=0; fm_ok=0; dm_ok=0 }
        /^[[:space:]]*<FilesMatch[[:space:]]+.*\\\.git/ { in_fm=1; next }
        in_fm && /^[[:space:]]*(Require[[:space:]]+all[[:space:]]+denied|Deny[[:space:]]+from[[:space:]]+all)/ { fm_ok=1 }
        in_fm && /^[[:space:]]*<\/FilesMatch>/ { in_fm=0 }
        /^[[:space:]]*<DirectoryMatch[[:space:]]+.*\\\.git/ { in_dm=1; next }
        in_dm && /^[[:space:]]*(Require[[:space:]]+all[[:space:]]+denied|Deny[[:space:]]+from[[:space:]]+all)/ { dm_ok=1 }
        in_dm && /^[[:space:]]*<\/DirectoryMatch>/ { in_dm=0 }
        END { if (fm_ok && dm_ok) print 1; else if (fm_ok) print 2; else print 0 }
    ')

    if [[ "$git_restricted" -eq 1 ]]; then
        pass_check "5.11" "Ensure Access to .git Files Is Restricted (Manual) [Level 1]" \
            "Both <FilesMatch \"/\.git\"> and <DirectoryMatch \"/\.git\"> deny access."
    else
        fail_check "5.11" "Ensure Access to .git Files Is Restricted (Manual) [Level 1]" \
            "Missing <FilesMatch \"/\.git\"> and/or <DirectoryMatch \"/\.git\"> with 'Require all denied'." \
            "Add the following lines at the server configuration level in httpd.conf:
  <FilesMatch \"/\.git\">
      Require all denied
  </FilesMatch>
  <DirectoryMatch \"/\.git\">
      Require all denied
  </DirectoryMatch>"
    fi
}
check_5_11

# 5.12 Ensure Access to .svn Files Is Restricted (Manual)
check_5_12() {
    local svn_restricted
    svn_restricted=$(get_config_stream | awk '
        BEGIN { IGNORECASE=1; in_fm=0; fm_ok=0 }
        /^[[:space:]]*<(FilesMatch|DirectoryMatch)[[:space:]]+.*\\\.svn/ { in_fm=1; next }
        in_fm && /^[[:space:]]*(Require[[:space:]]+all[[:space:]]+denied|Deny[[:space:]]+from[[:space:]]+all)/ { fm_ok=1 }
        in_fm && /^[[:space:]]*<\/(FilesMatch|DirectoryMatch)>/ { in_fm=0 }
        END { print fm_ok }
    ')

    if [[ "$svn_restricted" -eq 1 ]]; then
        pass_check "5.12" "Ensure Access to .svn Files Is Restricted (Manual) [Level 1]" \
            "Access to .svn files is restricted via <FilesMatch \"/\.svn\">."
    else
        fail_check "5.12" "Ensure Access to .svn Files Is Restricted (Manual) [Level 1]" \
            "Missing <FilesMatch \"/\.svn\"> with 'Require all denied' in Apache configuration." \
            "Add the following lines at the server configuration level in httpd.conf:
  <FilesMatch \"/\.svn\">
      Require all denied
  </FilesMatch>"
    fi
}
check_5_12

# 5.13 Ensure Access to Inappropriate File Extensions Is Restricted (Manual)
check_5_13() {
    local ext_whitelist
    ext_whitelist=$(get_config_stream | awk '
        BEGIN { IGNORECASE=1; in_deny_all=0; in_allow_ext=0; deny_ok=0; allow_ok=0 }
        /^[[:space:]]*<FilesMatch[[:space:]]+"?\^\.\*\$"?>/ { in_deny_all=1; next }
        in_deny_all && /^[[:space:]]*Require[[:space:]]+all[[:space:]]+denied/ { deny_ok=1 }
        in_deny_all && /^[[:space:]]*<\/FilesMatch>/ { in_deny_all=0 }
        /^[[:space:]]*<FilesMatch[[:space:]]+"?\^\.\*\\\.\(/ { in_allow_ext=1; next }
        in_allow_ext && /^[[:space:]]*Require[[:space:]]+all[[:space:]]+granted/ { allow_ok=1 }
        in_allow_ext && /^[[:space:]]*<\/FilesMatch>/ { in_allow_ext=0 }
        END { if (deny_ok && allow_ok) print 1; else print 0 }
    ')

    if [[ "$ext_whitelist" -eq 1 ]]; then
        pass_check "5.13" "Ensure Access to Inappropriate File Extensions Is Restricted (Manual) [Level 2]" \
            "Default-deny FilesMatch and approved file extension allowlist FilesMatch are configured."
    else
        fail_check "5.13" "Ensure Access to Inappropriate File Extensions Is Restricted (Manual) [Level 2]" \
            "Missing default-deny <FilesMatch \"^.*\$\"> and/or approved extension allowlist <FilesMatch> block." \
            "1. Review existing file extensions in DocumentRoot:
   find $DOCROOT -type f -name '*.*' | awk -F. '{print \$NF}' | sort -u
2. Add a default-deny FilesMatch block followed by an approved extension allowlist in httpd.conf:
   # Block all files by default, unless specifically allowed.
   <FilesMatch \"^.*\$\">
       Require all denied
   </FilesMatch>
   # Allow files with specifically approved file extensions:
   <FilesMatch \"^.*\.(css|html?|js|pdf|txt|xml|xsl|gif|ico|jpe?g|png)\$\">
       Require all granted
   </FilesMatch>"
    fi
}
check_5_13

# 5.14 Ensure IP Address Based Requests Are Disallowed (Automated)
check_5_14() {
    local host_cond
    host_cond=$(get_active_directives "^\s*RewriteCond\s+%\{HTTP_HOST\}\s+!" || true)
    if [[ -n "$host_cond" ]]; then
        pass_check "5.14" "Ensure IP Address Based Requests Are Disallowed (Automated) [Level 2]" \
            "RewriteCond on %{HTTP_HOST} is configured to disallow IP-based requests."
    else
        fail_check "5.14" "Ensure IP Address Based Requests Are Disallowed (Automated) [Level 2]" \
            "No RewriteCond checking %{HTTP_HOST} against the expected hostname was found." \
            "Enable mod_rewrite and add the following to httpd.conf (replace www.example.com with your hostname):
  RewriteEngine On
  RewriteCond %{HTTP_HOST} !^www\.example\.com [NC]
  RewriteCond %{REQUEST_URI} !^/error [NC]
  RewriteRule ^.(.*) - [L,F]"
    fi
}
check_5_14

# 5.15 Ensure the IP Addresses for Listening for Requests Are Specified (Automated)
check_5_15() {
    local listen_lines
    listen_lines=$(get_active_directives "^\s*Listen\s+" || true)
    if [[ -z "$listen_lines" ]]; then
        fail_check "5.15" "Ensure the IP Addresses for Listening for Requests Are Specified (Automated) [Level 2]" \
            "No active Listen directives were found in the Apache configuration." \
            "Configure explicit IP addresses and ports in Listen directives (e.g. 'Listen 10.1.2.3:80')."
        return
    fi

    local bad_listen=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local arg
        arg=$(echo "$line" | awk '{print $2}')
        if [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^0\.0\.0\.0: ]] || [[ "$arg" =~ ^\[::(ffff:0\.0\.0\.0)?\]: ]]; then
            bad_listen+=("$arg")
        fi
    done <<< "$listen_lines"

    if [[ ${#bad_listen[@]} -eq 0 ]]; then
        pass_check "5.15" "Ensure the IP Addresses for Listening for Requests Are Specified (Automated) [Level 2]" \
            "All Listen directives specify explicit non-zero IP addresses."
    else
        fail_check "5.15" "Ensure the IP Addresses for Listening for Requests Are Specified (Automated) [Level 2]" \
            "Found Listen directive(s) without an explicit IP or bound to all-zeros: ${bad_listen[*]}" \
            "Modify all Listen directives in httpd.conf to specify explicit IP addresses rather than port-only or 0.0.0.0/[::]:
  Listen 10.1.2.3:80"
    fi
}
check_5_15

# 5.16 Ensure Browser Framing Is Restricted (Automated)
check_5_16() {
    local csp_fa xfo
    csp_fa=$(get_active_directives "^\s*Header\s+always\s+(set|append)\s+['\"]?Content-Security-Policy" | grep -Ei "frame-ancestors\s+'?(none|self)'?" || true)
    xfo=$(get_active_directives "^\s*Header\s+always\s+(set|append)\s+['\"]?X-Frame-Options['\"]?\s+['\"]?(DENY|SAMEORIGIN)['\"]?" || true)

    if [[ -n "$csp_fa" || -n "$xfo" ]]; then
        pass_check "5.16" "Ensure Browser Framing Is Restricted (Automated) [Level 2]" \
            "Browser framing restriction header (Content-Security-Policy frame-ancestors or X-Frame-Options) is configured."
    else
        fail_check "5.16" "Ensure Browser Framing Is Restricted (Automated) [Level 2]" \
            "Neither Content-Security-Policy (frame-ancestors 'none'/'self') nor X-Frame-Options (DENY/SAMEORIGIN) with 'always' condition was found." \
            "Add the following directive to httpd.conf (requires mod_headers):
  Header always append Content-Security-Policy \"frame-ancestors 'self'\"
Or alternatively:
  Header always set X-Frame-Options SAMEORIGIN"
    fi
}
check_5_16

# 5.17 Ensure HTTP Header Referrer-Policy is set appropriately (Manual)
check_5_17() {
    local ref_pol
    ref_pol=$(get_active_directives "^\s*Header\s+(always\s+)?(set|append)\s+['\"]?Referrer-Policy" || true)
    if [[ -n "$ref_pol" ]]; then
        pass_check "5.17" "Ensure HTTP Header Referrer-Policy is set appropriately (Manual) [Level 2]" \
            "Referrer-Policy header is configured: $(echo "$ref_pol" | tr '\n' ' ')"
    else
        fail_check "5.17" "Ensure HTTP Header Referrer-Policy is set appropriately (Manual) [Level 2]" \
            "No Header directive configuring Referrer-Policy was found." \
            "Add or modify the Referrer-Policy Header directive in httpd.conf:
  Header set Referrer-Policy \"strict-origin-when-cross-origin\"
(Adjust the policy value to match your application's requirements, such as 'no-referrer', 'same-origin', or 'strict-origin-when-cross-origin')."
    fi
}
check_5_17

# 5.18 Ensure HTTP Header Permissions-Policy is set appropriately (Manual)
check_5_18() {
    local perm_pol
    perm_pol=$(get_active_directives "^\s*Header\s+(always\s+)?(set|append)\s+['\"]?Permissions-Policy" || true)
    if [[ -n "$perm_pol" ]]; then
        pass_check "5.18" "Ensure HTTP Header Permissions-Policy is set appropriately (Manual) [Level 2]" \
            "Permissions-Policy header is configured: $(echo "$perm_pol" | tr '\n' ' ')"
    else
        fail_check "5.18" "Ensure HTTP Header Permissions-Policy is set appropriately (Manual) [Level 2]" \
            "No Header directive configuring Permissions-Policy was found." \
            "Add or modify the Permissions-Policy Header directive in httpd.conf to restrict browser features as needed:
  Header set Permissions-Policy \"geolocation=(), microphone=(), camera=()\""
    fi
}
check_5_18
}

# ==============================================================================
# SECTION 6: Operations - Logging, Monitoring and Maintenance
# ==============================================================================
run_section_6() {
    print_section_header "6" "Operations - Logging, Monitoring and Maintenance" || return 0

# 6.1 Ensure the Error Log Filename and Severity Level Are Configured Correctly (Automated)
check_6_1() {
    local loglevel errorlog
    loglevel=$(get_active_directives "^\s*LogLevel\s+" | tail -n 1 || true)
    errorlog=$(get_active_directives "^\s*ErrorLog\s+" | tail -n 1 || true)

    local issues=()
    if [[ -z "$errorlog" ]]; then
        issues+=("ErrorLog directive is not configured.")
    fi
    if [[ -z "$loglevel" ]]; then
        issues+=("LogLevel directive is not configured.")
    else
        # Compliant values: 'info', 'debug', or '<notice|info|debug> core:info' / 'core:debug'
        local ll_val
        ll_val=$(echo "$loglevel" | sed -E 's/^[[:space:]]*LogLevel[[:space:]]+//I')
        if [[ "$ll_val" =~ ^(info|debug)$ ]] || { [[ "$ll_val" =~ ^(notice|info|debug)[[:space:]] ]] && [[ "$ll_val" =~ core:(info|debug) ]]; }; then
            :
        else
            issues+=("LogLevel '$ll_val' does not set core module to 'info' (or lower) and other modules to 'notice' (or lower).")
        fi
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        pass_check "6.1" "Ensure the Error Log Filename and Severity Level Are Configured Correctly (Automated) [Level 1]" \
            "ErrorLog and LogLevel ('$loglevel') are properly configured."
    else
        fail_check "6.1" "Ensure the Error Log Filename and Severity Level Are Configured Correctly (Automated) [Level 1]" \
            "$(printf '%s ' "${issues[@]}")" \
            "Configure LogLevel and ErrorLog in httpd.conf (and VirtualHosts as needed):
  LogLevel notice core:info
  ErrorLog \"logs/error_log\""
    fi
}
check_6_1

# 6.2 Ensure a Syslog Facility Is Configured for Error Logging (Manual)
check_6_2() {
    local syslog_err
    syslog_err=$(get_active_directives "^\s*ErrorLog\s+['\"]?syslog:" || true)
    if [[ -n "$syslog_err" ]]; then
        pass_check "6.2" "Ensure a Syslog Facility Is Configured for Error Logging (Manual) [Level 2]" \
            "ErrorLog is configured to use syslog: $(echo "$syslog_err" | tr '\n' ' ')"
    else
        fail_check "6.2" "Ensure a Syslog Facility Is Configured for Error Logging (Manual) [Level 2]" \
            "ErrorLog is not configured to send logs to a syslog facility (e.g., syslog:local1)." \
            "Configure ErrorLog in httpd.conf to send logs to syslog:
  ErrorLog \"syslog:local1\""
    fi
}
check_6_2

# 6.3 Ensure the Server Access Log Is Configured Correctly (Manual)
check_6_3() {
    local customlogs
    customlogs=$(get_active_directives "^\s*CustomLog\s+" || true)
    if [[ -z "$customlogs" ]]; then
        fail_check "6.3" "Ensure the Server Access Log Is Configured Correctly (Manual) [Level 1]" \
            "No active CustomLog directive was found in the Apache configuration." \
            "Configure LogFormat and CustomLog in httpd.conf:
  LogFormat \"%h %l %u %t \\\"%r\\\" %>s %b \\\"%{Referer}i\\\" \\\"%{User-agent}i\\\"\" combined
  CustomLog log/access_log combined"
        return
    fi

    # Check if CustomLog uses 'combined' and combined LogFormat has all required tokens
    local required_tokens=("%h" "%l" "%u" "%t" "%r" "%>s" "%b" "%{Referer}i" "%{User-agent}i")
    local logformats
    logformats=$(get_active_directives "^\s*LogFormat\s+" || true)
    local missing_tokens=()
    for tok in "${required_tokens[@]}"; do
        if ! echo "$logformats $customlogs" | grep -Fqi "$tok"; then
            missing_tokens+=("$tok")
        fi
    done

    # Also ensure CustomLog does not only use 'common'
    local uses_common
    uses_common=$(echo "$customlogs" | grep -Eic "\s+common\s*$" || true)

    if [[ ${#missing_tokens[@]} -eq 0 && "$uses_common" -eq 0 ]]; then
        pass_check "6.3" "Ensure the Server Access Log Is Configured Correctly (Manual) [Level 1]" \
            "CustomLog is configured with all required CIS format tokens."
    else
        fail_check "6.3" "Ensure the Server Access Log Is Configured Correctly (Manual) [Level 1]" \
            "CustomLog either uses 'common' format or is missing required tokens (${missing_tokens[*]:-none})." \
            "1. Ensure the combined LogFormat in httpd.conf includes all required tokens:
   LogFormat \"%h %l %u %t \\\"%r\\\" %>s %b \\\"%{Referer}i\\\" \\\"%{User-agent}i\\\"\" combined
2. Configure CustomLog to use the combined format:
   CustomLog log/access_log combined"
    fi
}
check_6_3

# 6.4 Ensure Log Storage and Rotation Is Configured Correctly (Manual)
check_6_4() {
    local lr_files=()
    [[ -f /etc/logrotate.conf ]] && lr_files+=("/etc/logrotate.conf")
    [[ -f /etc/logrotate.d/httpd ]] && lr_files+=("/etc/logrotate.d/httpd")
    [[ -f /etc/logrotate.d/apache2 ]] && lr_files+=("/etc/logrotate.d/apache2")

    local piped_rotatelogs
    piped_rotatelogs=$(get_active_directives "^\s*(CustomLog|ErrorLog)\s+.*rotatelogs" || true)

    if [[ -f /etc/logrotate.d/httpd || -f /etc/logrotate.d/apache2 ]]; then
        local rot_val
        rot_val=$(grep -Ehi "^\s*rotate\s+[0-9]+" "${lr_files[@]}" 2>/dev/null | tail -n 1 | awk '{print $2}' || echo 0)
        if [[ "${rot_val:-0}" -ge 13 ]]; then
            pass_check "6.4" "Ensure Log Storage and Rotation Is Configured Correctly (Manual) [Level 1]" \
                "Logrotate is configured for Apache and retains $rot_val rotations (>= 13 weeks)."
        else
            fail_check "6.4" "Ensure Log Storage and Rotation Is Configured Correctly (Manual) [Level 1]" \
                "Logrotate retention count is '${rot_val:-unset}' (recommended: at least 13 weeks / 3 months)." \
                "Update /etc/logrotate.d/httpd (or /etc/logrotate.d/apache2 or /etc/logrotate.conf) to retain at least 13 weeks of logs:
  weekly
  rotate 13"
        fi
    elif [[ -n "$piped_rotatelogs" ]]; then
        manual_check "6.4" "Ensure Log Storage and Rotation Is Configured Correctly (Manual) [Level 1]" \
            "Piped logging via rotatelogs is configured; verify retention scripts keep at least 13 weeks / 3 months of logs." \
            "Ensure rotatelogs interval and log retention scripts preserve at least 3 months (13 weeks) of log files."
    else
        fail_check "6.4" "Ensure Log Storage and Rotation Is Configured Correctly (Manual) [Level 1]" \
            "Neither /etc/logrotate.d/httpd (/etc/logrotate.d/apache2) nor piped rotatelogs was found." \
            "Configure /etc/logrotate.d/httpd (or /etc/logrotate.d/apache2) to rotate Apache logs weekly and keep at least 13 weeks of backlogs:
  /var/log/httpd/*log {
      weekly
      rotate 13
      missingok
      notifempty
      sharedscripts
      postrotate
          /bin/kill -HUP \`cat /var/run/httpd.pid 2>/dev/null\` 2> /dev/null || true
      endscript
  }"
    fi
}
check_6_4

# 6.5 Ensure Applicable Patches Are Applied (Manual)
check_6_5() {
    local ver_out="Unknown"
    if [[ -n "$HTTPD_BIN" ]]; then
        ver_out=$("$HTTPD_BIN" -v 2>/dev/null | tr '\n' ' ' || echo "Unknown")
    fi
    manual_check "6.5" "Ensure Applicable Patches Are Applied (Manual) [Level 1]" \
        "Detected Apache version: $ver_out. Verify that all security patches released more than 1 month ago are applied." \
        "Check https://httpd.apache.org/security/vulnerabilities_24.html or your OS vendor's package manager (e.g., 'yum check-update httpd' or 'apt-get -s upgrade apache2') and apply available security patches within 1 month of release."
}
check_6_5

# 6.6 Ensure ModSecurity Is Installed and Enabled (Automated)
check_6_6() {
    if echo "$LOADED_MODULES" | grep -q "security2_module"; then
        pass_check "6.6" "Ensure ModSecurity Is Installed and Enabled (Automated) [Level 2]" \
            "security2_module (ModSecurity) is loaded."
    else
        fail_check "6.6" "Ensure ModSecurity Is Installed and Enabled (Automated) [Level 2]" \
            "security2_module (ModSecurity) is NOT loaded." \
            "1. Install the ModSecurity module via OS package manager (e.g., 'yum install mod_security' or 'apt-get install libapache2-mod-security2') or from source.
2. Ensure the LoadModule directive is present in the Apache configuration:
   LoadModule security2_module modules/mod_security2.so"
    fi
}
check_6_6
}

# ==============================================================================
# SECTION 7: SSL/TLS Configuration
# ==============================================================================
run_section_7() {
    print_section_header "7" "SSL/TLS Configuration" || return 0

# 7.1 Ensure mod_ssl and/or mod_nss Is Installed (Automated)
check_7_1() {
    local ssl_mod
    ssl_mod=$(echo "$LOADED_MODULES" | grep -E "ssl_module|nss_module" | awk '{print $1}' | tr '\n' ' ' || true)
    if [[ -n "$ssl_mod" ]]; then
        pass_check "7.1" "Ensure mod_ssl and/or mod_nss Is Installed (Automated) [Level 1]" \
            "SSL/TLS module loaded: $ssl_mod"
    else
        fail_check "7.1" "Ensure mod_ssl and/or mod_nss Is Installed (Automated) [Level 1]" \
            "Neither ssl_module nor nss_module is loaded in Apache." \
            "Install and enable mod_ssl (or mod_nss):
  - For OS packages: 'yum install mod_ssl' or 'a2enmod ssl'
  - For source builds: './configure --with-included-apr --with-ssl=\$OPENSSL_DIR --enable-ssl'"
    fi
}
check_7_1

# 7.2 Ensure a Valid Trusted Certificate Is Installed (Manual)
check_7_2() {
    local cert_files
    cert_files=$(get_active_directives "^\s*SSLCertificateFile\s+" | awk '{print $2}' | tr -d '"'\''' | sort -u || true)
    if [[ -z "$cert_files" ]]; then
        fail_check "7.2" "Ensure a Valid Trusted Certificate Is Installed (Manual) [Level 1]" \
            "No SSLCertificateFile directive is configured in Apache." \
            "Generate a CSR and install a valid X.509 certificate signed by a trusted CA, then configure in mod_ssl configuration:
  SSLCertificateFile /etc/ssl/certs/example.com.crt
  SSLCertificateKeyFile /etc/ssl/private/example.com.key
  SSLCertificateChainFile /etc/ssl/certs/server-chain.crt"
        return
    fi

    local issues=()
    while IFS= read -r cert; do
        [[ -z "$cert" ]] && continue
        [[ "$cert" != /* ]] && cert="$APACHE_PREFIX/$cert"
        if [[ ! -f "$cert" ]]; then
            issues+=("Certificate file '$cert' does not exist.")
            continue
        fi
        if command -v openssl >/dev/null 2>&1; then
            local subj iss sig_alg
            subj=$(openssl x509 -in "$cert" -noout -subject 2>/dev/null || true)
            iss=$(openssl x509 -in "$cert" -noout -issuer 2>/dev/null || true)
            sig_alg=$(openssl x509 -in "$cert" -noout -text 2>/dev/null | grep -i "Signature Algorithm" | head -n 1 || true)
            if ! openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1; then
                issues+=("Certificate '$cert' is expired.")
            fi
            if [[ -n "$subj" && "${subj#*=}" == "${iss#*=}" ]]; then
                issues+=("Certificate '$cert' appears to be self-signed ($subj).")
            fi
            if echo "$sig_alg" | grep -qiE "md5|sha1"; then
                issues+=("Certificate '$cert' uses a weak signature algorithm ($sig_alg).")
            fi
        fi
    done <<< "$cert_files"

    if [[ ${#issues[@]} -eq 0 ]]; then
        manual_check "7.2" "Ensure a Valid Trusted Certificate Is Installed (Manual) [Level 1]" \
            "Configured certificate(s) exist, are not expired, and are not self-signed. Verify full CA chain trust using 'openssl verify' or Qualys SSL Labs." \
            "Validate the server certificate against your trusted CA bundle:
  openssl verify -CAfile /etc/ssl/certs/ca-bundle.crt -purpose sslserver /etc/ssl/certs/example.com.crt"
    else
        fail_check "7.2" "Ensure a Valid Trusted Certificate Is Installed (Manual) [Level 1]" \
            "$(printf '%s ' "${issues[@]}")" \
            "Install a valid, non-expired certificate signed by a trusted Certificate Authority (using SHA-256 or stronger) and configure SSLCertificateFile, SSLCertificateKeyFile, and SSLCertificateChainFile."
    fi
}
check_7_2

# 7.3 Ensure the Server's Private Key Is Protected (Manual)
check_7_3() {
    local cert_files key_files
    cert_files=$(get_active_directives "^\s*SSLCertificateFile\s+" | awk '{print $2}' | tr -d '"'\''' | sort -u || true)
    key_files=$(get_active_directives "^\s*SSLCertificateKeyFile\s+" | awk '{print $2}' | tr -d '"'\''' | sort -u || true)

    if [[ -z "$key_files" ]]; then
        fail_check "7.3" "Ensure the Server's Private Key Is Protected (Manual) [Level 1]" \
            "No SSLCertificateKeyFile directives found in Apache configuration." \
            "Store all private keys separately from public certificates using SSLCertificateKeyFile, owned by root:root with mode 0400:
  chown root:root /etc/ssl/private/example.com.key
  chmod 0400 /etc/ssl/private/example.com.key"
        return
    fi

    local issues=()
    while IFS= read -r cf; do
        [[ -z "$cf" ]] && continue
        [[ "$cf" != /* ]] && cf="$APACHE_PREFIX/$cf"
        if [[ -f "$cf" ]] && grep -q "PRIVATE KEY---" "$cf" 2>/dev/null; then
            issues+=("Certificate file '$cf' contains an embedded PRIVATE KEY.")
        fi
    done <<< "$cert_files"

    while IFS= read -r kf; do
        [[ -z "$kf" ]] && continue
        [[ "$kf" != /* ]] && kf="$APACHE_PREFIX/$kf"
        if [[ ! -f "$kf" ]]; then
            issues+=("Private key file '$kf' does not exist.")
            continue
        fi
        local owner group perm
        owner=$(stat -c '%U' "$kf" 2>/dev/null || echo "")
        group=$(stat -c '%G' "$kf" 2>/dev/null || echo "")
        perm=$(stat -c '%04a' "$kf" 2>/dev/null || echo "")
        [[ "$owner" != "root" || "$group" != "root" ]] && issues+=("Private key '$kf' is owned by $owner:$group (expected root:root).")
        [[ "$perm" != "0400" ]] && issues+=("Private key '$kf' has permission $perm (expected 0400).")
    done <<< "$key_files"

    if [[ ${#issues[@]} -eq 0 ]]; then
        pass_check "7.3" "Ensure the Server's Private Key Is Protected (Manual) [Level 1]" \
            "Private key files are separate from certificates, owned by root:root, and have 0400 permissions."
    else
        fail_check "7.3" "Ensure the Server's Private Key Is Protected (Manual) [Level 1]" \
            "$(printf '%s ' "${issues[@]}")" \
            "1. Move any private key out of SSLCertificateFile into a separate SSLCertificateKeyFile.
2. Set ownership to root:root and permissions to 0400 on each private key file:
   chown root:root /path/to/server.key
   chmod 0400 /path/to/server.key"
    fi
}
check_7_3

# 7.4 Ensure the TLSv1.0 and TLSv1.1 Protocols are Disabled (Manual)
check_7_4() {
    local proto_lines
    proto_lines=$(get_active_directives "^\s*SSLProtocol\s+" || true)
    if [[ -z "$proto_lines" ]]; then
        fail_check "7.4" "Ensure the TLSv1.0 and TLSv1.1 Protocols are Disabled (Manual) [Level 1]" \
            "No SSLProtocol directive is configured (default enables legacy TLS protocols)." \
            "Add or modify the SSLProtocol directive in your SSL configuration to allow only TLSv1.2 and TLSv1.3:
  SSLProtocol +TLSv1.2 +TLSv1.3"
        return
    fi

    local bad_proto=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local val
        val=$(echo "$line" | sed -E 's/^[[:space:]]*SSLProtocol[[:space:]]+//I')
        # Compliant if it explicitly sets +TLSv1.2 (+TLSv1.3) or 'all -SSLv3 -TLSv1 -TLSv1.1'
        if [[ "$val" =~ ^\+?TLSv1\.2([[:space:]]+\+?TLSv1\.3)?$ ]]; then
            :
        elif echo "$val" | grep -qi "all" && echo "$val" | grep -qiE "\-TLSv1(\b|\.0)" && echo "$val" | grep -qi "\-TLSv1\.1"; then
            :
        else
            bad_proto+=("$val")
        fi
    done <<< "$proto_lines"

    if [[ ${#bad_proto[@]} -eq 0 ]]; then
        pass_check "7.4" "Ensure the TLSv1.0 and TLSv1.1 Protocols are Disabled (Manual) [Level 1]" \
            "SSLProtocol disables TLSv1.0 and TLSv1.1 and allows only TLSv1.2/TLSv1.3."
    else
        fail_check "7.4" "Ensure the TLSv1.0 and TLSv1.1 Protocols are Disabled (Manual) [Level 1]" \
            "Non-compliant SSLProtocol value(s) detected: ${bad_proto[*]}" \
            "Configure SSLProtocol in Apache SSL configuration files to allow only TLSv1.2 and TLSv1.3:
  SSLProtocol +TLSv1.2 +TLSv1.3"
    fi
}
check_7_4

# 7.5 Ensure Weak SSL/TLS Ciphers Are Disabled (Manual)
check_7_5() {
    local honor_order cipher_lines
    honor_order=$(get_active_directives "^\s*SSLHonorCipherOrder\s+On\b" || true)
    cipher_lines=$(get_active_directives "^\s*SSLCipherSuite\s+" || true)

    local issues=()
    [[ -z "$honor_order" ]] && issues+=("SSLHonorCipherOrder is not set to 'On'.")
    if [[ -z "$cipher_lines" ]]; then
        issues+=("SSLCipherSuite directive is not configured.")
    else
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            for req in "!NULL" "!SSLv2" "!RC4" "!aNULL"; do
                if ! echo "$line" | grep -Fqi "$req"; then
                    issues+=("SSLCipherSuite ('$line') does not include '$req'.")
                fi
            done
        done <<< "$cipher_lines"
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        pass_check "7.5" "Ensure Weak SSL/TLS Ciphers Are Disabled (Manual) [Level 1]" \
            "SSLHonorCipherOrder is On and SSLCipherSuite disables NULL, SSLv2, RC4, and aNULL ciphers."
    else
        fail_check "7.5" "Ensure Weak SSL/TLS Ciphers Are Disabled (Manual) [Level 1]" \
            "$(printf '%s ' "${issues[@]}")" \
            "Add or modify the following lines in the Apache server level configuration and every TLS-enabled VirtualHost:
  SSLHonorCipherOrder On
  SSLCipherSuite EECDH:EDH:!NULL:!SSLv2:!RC4:!aNULL:!3DES:!IDEA"
    fi
}
check_7_5

# 7.6 Ensure Insecure SSL Renegotiation Is Not Enabled (Manual)
check_7_6() {
    local reneg_on
    reneg_on=$(get_active_directives "^\s*SSLInsecureRenegotiation\s+" | grep -Eiv "^\s*SSLInsecureRenegotiation\s+off\s*$" || true)
    if [[ -z "$reneg_on" ]]; then
        pass_check "7.6" "Ensure Insecure SSL Renegotiation Is Not Enabled (Manual) [Level 1]" \
            "SSLInsecureRenegotiation is either not present or set to 'off'."
    else
        fail_check "7.6" "Ensure Insecure SSL Renegotiation Is Not Enabled (Manual) [Level 1]" \
            "SSLInsecureRenegotiation is enabled: $(echo "$reneg_on" | tr '\n' ' ')" \
            "Set SSLInsecureRenegotiation to off (or remove the directive) in Apache configuration files:
  SSLInsecureRenegotiation off"
    fi
}
check_7_6

# 7.7 Ensure SSL Compression is not Enabled (Manual)
check_7_7() {
    local comp_on
    comp_on=$(get_active_directives "^\s*SSLCompression\s+" | grep -Eiv "^\s*SSLCompression\s+off\s*$" || true)
    if [[ -z "$comp_on" ]]; then
        pass_check "7.7" "Ensure SSL Compression is not Enabled (Manual) [Level 1]" \
            "SSLCompression is either not present or set to 'off'."
    else
        fail_check "7.7" "Ensure SSL Compression is not Enabled (Manual) [Level 1]" \
            "SSLCompression is enabled: $(echo "$comp_on" | tr '\n' ' ')" \
            "Set SSLCompression to off in the Apache configuration files:
  SSLCompression off"
    fi
}
check_7_7

# 7.8 Ensure Medium Strength SSL/TLS Ciphers Are Disabled (Manual)
check_7_8() {
    local cipher_lines
    cipher_lines=$(get_active_directives "^\s*SSLCipherSuite\s+" || true)
    if [[ -z "$cipher_lines" ]]; then
        fail_check "7.8" "Ensure Medium Strength SSL/TLS Ciphers Are Disabled (Manual) [Level 1]" \
            "SSLCipherSuite is not configured." \
            "Add or modify SSLCipherSuite in the Apache configuration and every SSL/TLS VirtualHost to disable 3DES and IDEA:
  SSLHonorCipherOrder On
  SSLCipherSuite EECDH:EDH:!NULL:!SSLv2:!RC4:!aNULL:!3DES:!IDEA"
        return
    fi

    local issues=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        for req in "!3DES" "!IDEA"; do
            if ! echo "$line" | grep -Fqi "$req"; then
                issues+=("SSLCipherSuite ('$line') does not include '$req'.")
            fi
        done
    done <<< "$cipher_lines"

    if [[ ${#issues[@]} -eq 0 ]]; then
        pass_check "7.8" "Ensure Medium Strength SSL/TLS Ciphers Are Disabled (Manual) [Level 1]" \
            "SSLCipherSuite explicitly disables medium-strength ciphers (!3DES and !IDEA)."
    else
        fail_check "7.8" "Ensure Medium Strength SSL/TLS Ciphers Are Disabled (Manual) [Level 1]" \
            "$(printf '%s ' "${issues[@]}")" \
            "Add or modify the following lines in the Apache server level configuration and every SSL/TLS VirtualHost:
  SSLHonorCipherOrder On
  SSLCipherSuite EECDH:EDH:!NULL:!SSLv2:!RC4:!aNULL:!3DES:!IDEA"
    fi
}
check_7_8

# 7.9 Ensure All Web Content is Accessed via HTTPS (Manual)
check_7_9() {
    local https_redirect
    https_redirect=$(get_active_directives "^\s*(Redirect(\s+permanent)?\s+/\s+https://|RewriteRule\s+.*https://)" || true)
    if [[ -n "$https_redirect" ]]; then
        pass_check "7.9" "Ensure All Web Content is Accessed via HTTPS (Manual) [Level 1]" \
            "HTTP-to-HTTPS Redirect or RewriteRule is configured."
    else
        fail_check "7.9" "Ensure All Web Content is Accessed via HTTPS (Manual) [Level 1]" \
            "No HTTP-to-HTTPS Redirect or RewriteRule was found in the Apache configuration." \
            "Move web content to a TLS-enabled website and add an HTTP Redirect directive to redirect HTTP requests to HTTPS:
  Redirect permanent / https://www.example.com/"
    fi
}
check_7_9

# 7.10 Ensure OCSP Stapling Is Enabled (Manual)
check_7_10() {
    local stapling_cache stapling_on
    stapling_cache=$(get_active_directives "^\s*SSLStaplingCache\s+" || true)
    stapling_on=$(get_active_directives "^\s*SSLUseStapling\s+on\b" || true)

    if [[ -n "$stapling_cache" && -n "$stapling_on" ]]; then
        pass_check "7.10" "Ensure OCSP Stapling Is Enabled (Manual) [Level 2]" \
            "SSLUseStapling is On and SSLStaplingCache is configured."
    else
        fail_check "7.10" "Ensure OCSP Stapling Is Enabled (Manual) [Level 2]" \
            "SSLUseStapling On and/or SSLStaplingCache is missing from the Apache configuration." \
            "Configure OCSP Stapling in the Apache server level configuration and every SSL-enabled VirtualHost:
  SSLUseStapling On
  SSLStaplingCache \"shmcb:logs/ssl_staple_cache(512000)\""
    fi
}
check_7_10

# 7.11 Ensure HTTP Strict Transport Security Is Enabled (Manual)
check_7_11() {
    local hsts_line
    hsts_line=$(get_active_directives "^\s*Header\s+always\s+set\s+['\"]?Strict-Transport-Security" || true)
    if [[ -z "$hsts_line" ]]; then
        fail_check "7.11" "Ensure HTTP Strict Transport Security Is Enabled (Manual) [Level 2]" \
            "No 'Header always set Strict-Transport-Security' directive was found." \
            "Add the Strict-Transport-Security header with max-age of at least 480 seconds (e.g. 600 or more) in the server level configuration and every SSL-enabled VirtualHost:
  Header always set Strict-Transport-Security \"max-age=600\""
        return
    fi

    local max_age
    max_age=$(echo "$hsts_line" | grep -Eo "max-age=[0-9]+" | head -n 1 | cut -d= -f2 || echo 0)
    if [[ "${max_age:-0}" -ge 480 ]]; then
        pass_check "7.11" "Ensure HTTP Strict Transport Security Is Enabled (Manual) [Level 2]" \
            "Strict-Transport-Security is enabled with max-age=$max_age (>= 480)."
    else
        fail_check "7.11" "Ensure HTTP Strict Transport Security Is Enabled (Manual) [Level 2]" \
            "Strict-Transport-Security max-age (${max_age:-0}) is less than 480 seconds." \
            "Configure Strict-Transport-Security with a max-age value of at least 480 seconds (e.g., 600):
  Header always set Strict-Transport-Security \"max-age=600\""
    fi
}
check_7_11

# 7.12 Ensure Only Cipher Suites That Provide Forward Secrecy Are Enabled (Manual)
check_7_12() {
    local cipher_lines
    cipher_lines=$(get_active_directives "^\s*SSLCipherSuite\s+" || true)
    if [[ -z "$cipher_lines" ]]; then
        fail_check "7.12" "Ensure Only Cipher Suites That Provide Forward Secrecy Are Enabled (Manual) [Level 2]" \
            "SSLCipherSuite is not configured." \
            "Configure SSLCipherSuite to allow only Forward Secrecy (ECDHE/EECDH and DHE/EDH) cipher suites:
  SSLCipherSuite EECDH:EDH:!NULL:!SSLv2:!RC4:!aNULL:!3DES:!IDEA"
        return
    fi

    local issues=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local spec
        spec=$(echo "$line" | awk '{print $2}' | tr -d '"'\''')
        if command -v openssl >/dev/null 2>&1; then
            local non_fs
            non_fs=$(openssl ciphers -v "$spec" 2>/dev/null | grep -Ev "^(ECDHE-|DHE-|TLS_)" || true)
            if [[ -n "$non_fs" ]]; then
                issues+=("Cipher spec '$spec' permits non-Forward-Secrecy ciphers.")
            fi
        else
            if ! echo "$spec" | grep -Eq "^(EECDH|ECDHE|EDH|DHE)"; then
                issues+=("Cipher spec '$spec' does not start with EECDH/ECDHE/EDH/DHE.")
            fi
        fi
    done <<< "$cipher_lines"

    if [[ ${#issues[@]} -eq 0 ]]; then
        pass_check "7.12" "Ensure Only Cipher Suites That Provide Forward Secrecy Are Enabled (Manual) [Level 2]" \
            "SSLCipherSuite only permits Forward Secrecy (ECDHE/DHE) cipher suites."
    else
        fail_check "7.12" "Ensure Only Cipher Suites That Provide Forward Secrecy Are Enabled (Manual) [Level 2]" \
            "$(printf '%s ' "${issues[@]}")" \
            "Add or modify SSLCipherSuite in the Apache server level configuration and every SSL/TLS VirtualHost to require ECDHE/EECDH or DHE/EDH:
  SSLCipherSuite EECDH:EDH:!NULL:!SSLv2:!RC4:!aNULL:!3DES:!IDEA"
    fi
}
check_7_12
}

# ==============================================================================
# SECTION 8: Information Leakage
# ==============================================================================
run_section_8() {
    print_section_header "8" "Information Leakage" || return 0

# 8.1 Ensure ServerTokens is Set to 'Prod' or 'ProductOnly' (Automated)
check_8_1() {
    local st_line
    st_line=$(get_active_directives "^\s*ServerTokens\s+" | tail -n 1 || true)
    if echo "$st_line" | grep -Eiq "^\s*ServerTokens\s+(Prod|ProductOnly)\s*$"; then
        pass_check "8.1" "Ensure ServerTokens is Set to 'Prod' or 'ProductOnly' (Automated) [Level 1]" \
            "ServerTokens is set to '$(echo "$st_line" | awk '{print $2}')'."
    else
        fail_check "8.1" "Ensure ServerTokens is Set to 'Prod' or 'ProductOnly' (Automated) [Level 1]" \
            "ServerTokens is currently '${st_line:-not configured (defaults to Full)}'." \
            "Add or modify the ServerTokens directive in httpd.conf:
  ServerTokens Prod"
    fi
}
check_8_1

# 8.2 Ensure ServerSignature Is Not Enabled (Automated)
check_8_2() {
    local ss_lines ss_bad
    ss_lines=$(get_active_directives "^\s*ServerSignature\s+" || true)
    ss_bad=$(echo "$ss_lines" | grep -Eiv "^\s*ServerSignature\s+Off\s*$" || true)
    if [[ -z "$ss_bad" ]]; then
        pass_check "8.2" "Ensure ServerSignature Is Not Enabled (Automated) [Level 1]" \
            "ServerSignature is Off (or not enabled)."
    else
        fail_check "8.2" "Ensure ServerSignature Is Not Enabled (Automated) [Level 1]" \
            "ServerSignature is enabled: $(echo "$ss_bad" | tr '\n' ' ')" \
            "Add or modify the ServerSignature directive in httpd.conf:
  ServerSignature Off"
    fi
}
check_8_2

# 8.3 Ensure All Default Apache Content Is Removed (Manual)
check_8_3() {
    local icons_conf
    icons_conf=$(get_active_directives "^\s*(Include\s+.*httpd-autoindex\.conf|Alias\s+/icons/|<Directory\s+.*icons\"?>)" || true)
    if [[ -z "$icons_conf" ]]; then
        pass_check "8.3" "Ensure All Default Apache Content Is Removed (Manual) [Level 2]" \
            "No active Alias or Directory access to the Apache icons directory was found."
    else
        fail_check "8.3" "Ensure All Default Apache Content Is Removed (Manual) [Level 2]" \
            "Active Apache icons configuration detected: $(echo "$icons_conf" | tr '\n' ' ')" \
            "1. Leave 'Include conf/extra/httpd-autoindex.conf' commented out in httpd.conf.
2. Comment out any 'Alias /icons/' and '<Directory \"/var/www/icons\">' blocks in Apache configuration files."
    fi
}
check_8_3

# 8.4 Ensure ETag Response Header Fields Do Not Include Inodes (Automated)
check_8_4() {
    local etag_bad
    etag_bad=$(get_active_directives "^\s*FileETag\s+" | grep -Ei "\b(all|\+?inode)\b" | grep -Eiv "\-inode\b" || true)
    if [[ -z "$etag_bad" ]]; then
        pass_check "8.4" "Ensure ETag Response Header Fields Do Not Include Inodes (Automated) [Level 2]" \
            "FileETag is either not present or does not include 'all' or 'inode'."
    else
        fail_check "8.4" "Ensure ETag Response Header Fields Do Not Include Inodes (Automated) [Level 2]" \
            "FileETag includes inode information: $(echo "$etag_bad" | tr '\n' ' ')" \
            "Remove all instances of FileETag or set FileETag to 'None' or 'MTime Size' in the server and VirtualHost configurations:
  FileETag MTime Size"
    fi
}
check_8_4
}

# ==============================================================================
# SECTION 9: Denial of Service Mitigations
# ==============================================================================
run_section_9() {
    print_section_header "9" "Denial of Service Mitigations" || return 0

# 9.1 Ensure the TimeOut Is Set to 10 or Less (Automated)
check_9_1() {
    local to_line
    to_line=$(get_active_directives "^\s*Timeout\s+" | tail -n 1 || true)
    if [[ -z "$to_line" ]]; then
        fail_check "9.1" "Ensure the TimeOut Is Set to 10 or Less (Automated) [Level 1]" \
            "Timeout directive is not specified (defaults to 60 seconds)." \
            "Add or modify the Timeout directive in httpd.conf to 10 seconds or less:
  Timeout 10"
        return
    fi

    local to_val
    to_val=$(echo "$to_line" | awk '{print $2}')
    if [[ "$to_val" =~ ^[0-9]+$ && "$to_val" -ge 1 && "$to_val" -le 10 ]]; then
        pass_check "9.1" "Ensure the TimeOut Is Set to 10 or Less (Automated) [Level 1]" \
            "Timeout is set to $to_val seconds (between 1 and 10)."
    else
        fail_check "9.1" "Ensure the TimeOut Is Set to 10 or Less (Automated) [Level 1]" \
            "Timeout is set to '$to_val' (expected 1 to 10 seconds)." \
            "Add or modify the Timeout directive in httpd.conf to have a value of 1 to 10 seconds:
  Timeout 10"
    fi
}
check_9_1

# 9.2 Ensure KeepAlive Is Enabled (Automated)
check_9_2() {
    local ka_line
    ka_line=$(get_active_directives "^\s*KeepAlive\s+" | tail -n 1 || true)
    if [[ -z "$ka_line" ]] || echo "$ka_line" | grep -Eiq "^\s*KeepAlive\s+On\s*$"; then
        pass_check "9.2" "Ensure KeepAlive Is Enabled (Automated) [Level 1]" \
            "KeepAlive is enabled (${ka_line:-default On})."
    else
        fail_check "9.2" "Ensure KeepAlive Is Enabled (Automated) [Level 1]" \
            "KeepAlive is disabled ('$ka_line')." \
            "Add or modify the KeepAlive directive in httpd.conf to have a value of On:
  KeepAlive On"
    fi
}
check_9_2

# 9.3 Ensure MaxKeepAliveRequests is Set to a Value of 100 or Greater (Automated)
check_9_3() {
    local mkar_line
    mkar_line=$(get_active_directives "^\s*MaxKeepAliveRequests\s+" | tail -n 1 || true)
    if [[ -z "$mkar_line" ]]; then
        pass_check "9.3" "Ensure MaxKeepAliveRequests is Set to a Value of 100 or Greater (Automated) [Level 1]" \
            "MaxKeepAliveRequests is not explicitly set (defaults to 100)."
        return
    fi

    local mkar_val
    mkar_val=$(echo "$mkar_line" | awk '{print $2}')
    if [[ "$mkar_val" =~ ^[0-9]+$ && "$mkar_val" -ge 100 ]]; then
        pass_check "9.3" "Ensure MaxKeepAliveRequests is Set to a Value of 100 or Greater (Automated) [Level 1]" \
            "MaxKeepAliveRequests is set to $mkar_val (>= 100)."
    else
        fail_check "9.3" "Ensure MaxKeepAliveRequests is Set to a Value of 100 or Greater (Automated) [Level 1]" \
            "MaxKeepAliveRequests is set to '$mkar_val' (expected >= 100)." \
            "Add or modify the MaxKeepAliveRequests directive in httpd.conf to 100 or more:
  MaxKeepAliveRequests 100"
    fi
}
check_9_3

# 9.4 Ensure KeepAliveTimeout is Set to a Value of 15 or Less (Automated)
check_9_4() {
    local kat_line
    kat_line=$(get_active_directives "^\s*KeepAliveTimeout\s+" | tail -n 1 || true)
    if [[ -z "$kat_line" ]]; then
        pass_check "9.4" "Ensure KeepAliveTimeout is Set to a Value of 15 or Less (Automated) [Level 1]" \
            "KeepAliveTimeout is not explicitly set (defaults to 5 seconds, which is <= 15)."
        return
    fi

    local kat_val
    kat_val=$(echo "$kat_line" | awk '{print $2}')
    if [[ "$kat_val" =~ ^[0-9]+$ && "$kat_val" -ge 1 && "$kat_val" -le 15 ]]; then
        pass_check "9.4" "Ensure KeepAliveTimeout is Set to a Value of 15 or Less (Automated) [Level 1]" \
            "KeepAliveTimeout is set to $kat_val seconds (<= 15)."
    else
        fail_check "9.4" "Ensure KeepAliveTimeout is Set to a Value of 15 or Less (Automated) [Level 1]" \
            "KeepAliveTimeout is set to '$kat_val' (expected 15 seconds or less)." \
            "Add or modify the KeepAliveTimeout directive in httpd.conf to 15 or less:
  KeepAliveTimeout 15"
    fi
}
check_9_4

# 9.5 Ensure the Timeout Limits for Request Headers is Set to 40 or Less (Manual)
check_9_5() {
    local has_mod rrt_lines
    has_mod=$(echo "$LOADED_MODULES" | grep -c "reqtimeout_module" || true)
    rrt_lines=$(get_active_directives "^\s*RequestReadTimeout\s+" || true)

    if [[ "$has_mod" -eq 0 ]]; then
        fail_check "9.5" "Ensure the Timeout Limits for Request Headers is Set to 40 or Less (Manual) [Level 1]" \
            "reqtimeout_module (mod_reqtimeout) is not loaded." \
            "1. Load mod_reqtimeout in httpd.conf:
   LoadModule reqtimeout_module modules/mod_reqtimeout.so
2. Configure RequestReadTimeout with a maximum header timeout of 40 seconds or less:
   RequestReadTimeout header=20-40,MinRate=500 body=20,MinRate=500"
        return
    fi

    if [[ -z "$rrt_lines" ]]; then
        pass_check "9.5" "Ensure the Timeout Limits for Request Headers is Set to 40 or Less (Manual) [Level 1]" \
            "reqtimeout_module is loaded and uses default header=20-40,MinRate=500 (max 40s)."
        return
    fi

    local hdr_max
    hdr_max=$(echo "$rrt_lines" | tail -n 1 | grep -Eo "header=[0-9]+(-[0-9]+)?" | sed -E 's/header=([0-9]+-)?//' || echo 999)
    if [[ "$hdr_max" =~ ^[0-9]+$ && "$hdr_max" -le 40 && "$hdr_max" -gt 0 ]]; then
        pass_check "9.5" "Ensure the Timeout Limits for Request Headers is Set to 40 or Less (Manual) [Level 1]" \
            "RequestReadTimeout maximum header timeout is $hdr_max seconds (<= 40)."
    else
        fail_check "9.5" "Ensure the Timeout Limits for Request Headers is Set to 40 or Less (Manual) [Level 1]" \
            "RequestReadTimeout header maximum timeout ('$hdr_max') exceeds 40 seconds or is invalid." \
            "Configure RequestReadTimeout in httpd.conf with a maximum header timeout of 40 seconds or less:
  LoadModule reqtimeout_module modules/mod_reqtimeout.so
  RequestReadTimeout header=20-40,MinRate=500 body=20,MinRate=500"
    fi
}
check_9_5

# 9.6 Ensure Timeout Limits for the Request Body is Set to 20 or Less (Manual)
check_9_6() {
    local has_mod rrt_lines
    has_mod=$(echo "$LOADED_MODULES" | grep -c "reqtimeout_module" || true)
    rrt_lines=$(get_active_directives "^\s*RequestReadTimeout\s+" || true)

    if [[ "$has_mod" -eq 0 ]]; then
        fail_check "9.6" "Ensure Timeout Limits for the Request Body is Set to 20 or Less (Manual) [Level 1]" \
            "reqtimeout_module (mod_reqtimeout) is not loaded." \
            "1. Load mod_reqtimeout in httpd.conf:
   LoadModule reqtimeout_module modules/mod_reqtimeout.so
2. Configure RequestReadTimeout with a maximum body timeout of 20 seconds or less:
   RequestReadTimeout header=20-40,MinRate=500 body=20,MinRate=500"
        return
    fi

    if [[ -z "$rrt_lines" ]]; then
        pass_check "9.6" "Ensure Timeout Limits for the Request Body is Set to 20 or Less (Manual) [Level 1]" \
            "reqtimeout_module is loaded and uses default body=20,MinRate=500 (max 20s)."
        return
    fi

    local body_max
    body_max=$(echo "$rrt_lines" | tail -n 1 | grep -Eo "body=[0-9]+(-[0-9]+)?" | sed -E 's/body=([0-9]+-)?//' || echo 999)
    if [[ "$body_max" =~ ^[0-9]+$ && "$body_max" -le 20 && "$body_max" -gt 0 ]]; then
        pass_check "9.6" "Ensure Timeout Limits for the Request Body is Set to 20 or Less (Manual) [Level 1]" \
            "RequestReadTimeout maximum body timeout is $body_max seconds (<= 20)."
    else
        fail_check "9.6" "Ensure Timeout Limits for the Request Body is Set to 20 or Less (Manual) [Level 1]" \
            "RequestReadTimeout body maximum timeout ('$body_max') exceeds 20 seconds or is missing." \
            "Configure RequestReadTimeout in httpd.conf with a maximum request body timeout of 20 seconds or less:
  LoadModule reqtimeout_module modules/mod_reqtimeout.so
  RequestReadTimeout header=20-40,MinRate=500 body=20,MinRate=500"
    fi
}
check_9_6

# 9.7 2.4.0 (Manual) - Included for 100% fidelity to CIS Benchmark v2.4.0 PDF (Page 282 / Summary Table)
pass_check "9.7" "2.4.0 (Manual) [CIS v2.4.0 Benchmark Placeholder Section]" \
    "Section 9.7 in CIS Apache HTTP Server 2.4 Benchmark v2.4.0 contains no technical control specifications (document placeholder)."
}

# ==============================================================================
# SECTION 10: Request Limits
# ==============================================================================
run_section_10() {
    print_section_header "10" "Request Limits" || return 0

# 10.1 Ensure the LimitRequestLine directive is Set to 8190 or less but not 0 (Automated)
check_10_1() {
    local lrl_line
    lrl_line=$(get_active_directives "^\s*LimitRequestLine\s+" | tail -n 1 || true)
    if [[ -z "$lrl_line" ]]; then
        fail_check "10.1" "Ensure the LimitRequestLine directive is Set to 8190 or less but not 0 (Automated) [Level 2]" \
            "LimitRequestLine directive is not explicitly present in the Apache configuration." \
            "Add or modify the LimitRequestLine directive in httpd.conf to have a value of 8190 or less (but not 0):
  LimitRequestLine 8190"
        return
    fi

    local lrl_val
    lrl_val=$(echo "$lrl_line" | awk '{print $2}')
    if [[ "$lrl_val" =~ ^[0-9]+$ && "$lrl_val" -ge 1 && "$lrl_val" -le 8190 ]]; then
        pass_check "10.1" "Ensure the LimitRequestLine directive is Set to 8190 or less but not 0 (Automated) [Level 2]" \
            "LimitRequestLine is set to $lrl_val."
    else
        fail_check "10.1" "Ensure the LimitRequestLine directive is Set to 8190 or less but not 0 (Automated) [Level 2]" \
            "LimitRequestLine is set to '$lrl_val' (expected 1 to 8190)." \
            "Add or modify the LimitRequestLine directive in httpd.conf:
  LimitRequestLine 8190"
    fi
}
check_10_1

# 10.2 Ensure the LimitRequestFields Directive is Set to 100 or Less but not 0 (Automated)
check_10_2() {
    local lrf_line
    lrf_line=$(get_active_directives "^\s*LimitRequestFields\s+" | tail -n 1 || true)
    if [[ -z "$lrf_line" ]]; then
        fail_check "10.2" "Ensure the LimitRequestFields Directive is Set to 100 or Less but not 0 (Automated) [Level 2]" \
            "LimitRequestFields directive is not explicitly present in the Apache configuration." \
            "Add or modify the LimitRequestFields directive in httpd.conf to have a value of 100 or less (but not 0):
  LimitRequestFields 100"
        return
    fi

    local lrf_val
    lrf_val=$(echo "$lrf_line" | awk '{print $2}')
    if [[ "$lrf_val" =~ ^[0-9]+$ && "$lrf_val" -ge 1 && "$lrf_val" -le 100 ]]; then
        pass_check "10.2" "Ensure the LimitRequestFields Directive is Set to 100 or Less but not 0 (Automated) [Level 2]" \
            "LimitRequestFields is set to $lrf_val."
    else
        fail_check "10.2" "Ensure the LimitRequestFields Directive is Set to 100 or Less but not 0 (Automated) [Level 2]" \
            "LimitRequestFields is set to '$lrf_val' (expected 1 to 100)." \
            "Add or modify the LimitRequestFields directive in httpd.conf:
  LimitRequestFields 100"
    fi
}
check_10_2

# 10.3 Ensure the LimitRequestFieldsize Directive is Set to 8190 or Less (Automated)
check_10_3() {
    local lrfs_line
    lrfs_line=$(get_active_directives "^\s*LimitRequestFieldSize\s+" | tail -n 1 || true)
    if [[ -z "$lrfs_line" ]]; then
        fail_check "10.3" "Ensure the LimitRequestFieldsize Directive is Set to 8190 or Less (Automated) [Level 2]" \
            "LimitRequestFieldSize directive is not explicitly present in the Apache configuration." \
            "Add or modify the LimitRequestFieldSize directive in httpd.conf to have a value of 8190 or less:
  LimitRequestFieldSize 8190"
        return
    fi

    local lrfs_val
    lrfs_val=$(echo "$lrfs_line" | awk '{print $2}')
    if [[ "$lrfs_val" =~ ^[0-9]+$ && "$lrfs_val" -ge 1 && "$lrfs_val" -le 8190 ]]; then
        pass_check "10.3" "Ensure the LimitRequestFieldsize Directive is Set to 8190 or Less (Automated) [Level 2]" \
            "LimitRequestFieldSize is set to $lrfs_val."
    else
        fail_check "10.3" "Ensure the LimitRequestFieldsize Directive is Set to 8190 or Less (Automated) [Level 2]" \
            "LimitRequestFieldSize is set to '$lrfs_val' (expected <= 8190 and > 0)." \
            "Add or modify the LimitRequestFieldSize directive in httpd.conf:
  LimitRequestFieldSize 8190"
    fi
}
check_10_3

# 10.4 Ensure the LimitRequestBody Directive is Set to 102400 or Less but not 0 (Automated)
check_10_4() {
    local lrb_line
    lrb_line=$(get_active_directives "^\s*LimitRequestBody\s+" | tail -n 1 || true)
    if [[ -z "$lrb_line" ]]; then
        fail_check "10.4" "Ensure the LimitRequestBody Directive is Set to 102400 or Less but not 0 (Automated) [Level 2]" \
            "LimitRequestBody directive is not present (defaults to 0 / unlimited)." \
            "Add or modify the LimitRequestBody directive in httpd.conf to have a value of 102400 (100K) or less (but not 0):
  LimitRequestBody 102400"
        return
    fi

    local lrb_val
    lrb_val=$(echo "$lrb_line" | awk '{print $2}')
    if [[ "$lrb_val" =~ ^[0-9]+$ && "$lrb_val" -ge 1 && "$lrb_val" -le 102400 ]]; then
        pass_check "10.4" "Ensure the LimitRequestBody Directive is Set to 102400 or Less but not 0 (Automated) [Level 2]" \
            "LimitRequestBody is set to $lrb_val bytes (<= 102400 and != 0)."
    else
        fail_check "10.4" "Ensure the LimitRequestBody Directive is Set to 102400 or Less but not 0 (Automated) [Level 2]" \
            "LimitRequestBody is set to '$lrb_val' (expected 1 to 102400)." \
            "Add or modify the LimitRequestBody directive in httpd.conf:
  LimitRequestBody 102400"
    fi
}
check_10_4
}

# ==============================================================================
# SECTION 11: Enable SELinux to Restrict Apache Processes
# ==============================================================================
run_section_11() {
    print_section_header "11" "Enable SELinux to Restrict Apache Processes" || return 0

# 11.1 Ensure SELinux Is Enabled in Enforcing Mode (Automated)
check_11_1() {
    if ! command -v sestatus >/dev/null 2>&1; then
        fail_check "11.1" "Ensure SELinux Is Enabled in Enforcing Mode (Automated) [Level 2]" \
            "sestatus command not found (SELinux is not installed/enabled on this system; note: CIS recommends either SELinux or AppArmor)." \
            "If using SELinux on this platform:
  1. Edit /etc/selinux/config and set:
     SELINUX=enforcing
  2. Enforce immediately or reboot:
     setenforce 1"
        return
    fi

    local se_out cur_mode cfg_mode
    se_out=$(sestatus 2>/dev/null || true)
    cur_mode=$(echo "$se_out" | awk -F: '/Current mode:/ {gsub(/[[:space:]]/, "", $2); print tolower($2)}' || true)
    cfg_mode=$(echo "$se_out" | awk -F: '/Mode from config file:/ {gsub(/[[:space:]]/, "", $2); print tolower($2)}' || true)

    if [[ "$cur_mode" == "enforcing" && "$cfg_mode" == "enforcing" ]]; then
        pass_check "11.1" "Ensure SELinux Is Enabled in Enforcing Mode (Automated) [Level 2]" \
            "SELinux current mode and config file mode are both set to 'enforcing'."
    else
        fail_check "11.1" "Ensure SELinux Is Enabled in Enforcing Mode (Automated) [Level 2]" \
            "SELinux Current mode='${cur_mode:-disabled}', Config mode='${cfg_mode:-disabled}'." \
            "1. Edit /etc/selinux/config and set:
   SELINUX=enforcing
2. Run 'setenforce 1' (or reboot the system) for the new configuration to take effect."
    fi
}
check_11_1

# 11.2 Ensure Apache Processes Run in the httpd_t Confined Context (Manual)
check_11_2() {
    local proc_z
    proc_z=$(ps -eZ 2>/dev/null | grep -E "httpd|apache2" | grep -v "grep" || true)
    if [[ -z "$proc_z" ]]; then
        fail_check "11.2" "Ensure Apache Processes Run in the httpd_t Confined Context (Manual) [Level 2]" \
            "No running httpd/apache2 processes found or SELinux contexts unavailable." \
            "Ensure SELinux is enabled, label the Apache binaries properly, and restart Apache:
  semanage fcontext -f -- -a -t httpd_exec_t '/usr/sbin/httpd'
  semanage fcontext -f -- -a -t initrc_exec_t '/usr/sbin/apachectl'
  restorecon -v /usr/sbin/httpd /usr/sbin/httpd.* /usr/sbin/apachectl"
        return
    fi

    local unconfined_procs
    unconfined_procs=$(echo "$proc_z" | grep -v ":httpd_t:" || true)
    if [[ -z "$unconfined_procs" ]]; then
        pass_check "11.2" "Ensure Apache Processes Run in the httpd_t Confined Context (Manual) [Level 2]" \
            "All running Apache processes are confined in the httpd_t SELinux context."
    else
        fail_check "11.2" "Ensure Apache Processes Run in the httpd_t Confined Context (Manual) [Level 2]" \
            "Apache process(es) not confined to httpd_t: $(echo "$unconfined_procs" | tr '\n' ' ')" \
            "Set the SELinux file context for the Apache binaries and restore labels:
  semanage fcontext -f -- -a -t httpd_exec_t '/usr/sbin/httpd'
  semanage fcontext -f -- -a -t initrc_exec_t '/usr/sbin/apachectl'
  restorecon -v /usr/sbin/httpd /usr/sbin/httpd.* /usr/sbin/apachectl"
    fi
}
check_11_2

# 11.3 Ensure the httpd_t Type is Not in Permissive Mode (Automated)
check_11_3() {
    if ! command -v semodule >/dev/null 2>&1; then
        fail_check "11.3" "Ensure the httpd_t Type is Not in Permissive Mode (Automated) [Level 2]" \
            "semodule command not found (SELinux policy utilities not installed)." \
            "If using SELinux, verify httpd_t is not permissive ('semodule -l | grep permissive_httpd_t') and remove permissive mode if present:
  semanage permissive -d httpd_t"
        return
    fi

    local perm_httpd
    perm_httpd=$(semodule -l 2>/dev/null | grep "permissive_httpd_t" || true)
    if [[ -z "$perm_httpd" ]]; then
        pass_check "11.3" "Ensure the httpd_t Type is Not in Permissive Mode (Automated) [Level 2]" \
            "SELinux httpd_t domain is not in permissive mode."
    else
        fail_check "11.3" "Ensure the httpd_t Type is Not in Permissive Mode (Automated) [Level 2]" \
            "SELinux httpd_t domain is set to permissive mode ($perm_httpd)." \
            "Delete the customized permissive mode for httpd_t:
  semanage permissive -d httpd_t"
    fi
}
check_11_3

# 11.4 Ensure Only the Necessary SELinux Booleans are Enabled (Manual)
check_11_4() {
    if command -v getsebool >/dev/null 2>&1; then
        local enabled_bools
        enabled_bools=$(getsebool -a 2>/dev/null | grep "httpd_" | grep -- "--> on" | awk '{print $1}' | tr '\n' ' ' || true)
        manual_check "11.4" "Ensure Only the Necessary SELinux Booleans are Enabled (Manual) [Level 2]" \
            "Currently enabled httpd SELinux booleans: [${enabled_bools:-none}]" \
            "Review enabled httpd SELinux booleans ('getsebool -a | grep httpd_ | grep \"> on\"') and disable any unnecessary booleans persistently:
  setsebool -P <boolean_name> off"
    else
        manual_check "11.4" "Ensure Only the Necessary SELinux Booleans are Enabled (Manual) [Level 2]" \
            "getsebool command not found (SELinux not active)." \
            "If SELinux is used, review enabled booleans with:
  getsebool -a | grep httpd_ | grep '> on'
Disable unnecessary booleans persistently with:
  setsebool -P <boolean_name> off"
    fi
}
check_11_4
}

# ==============================================================================
# SECTION 12: Enable AppArmor to Restrict Apache Processes
# ==============================================================================
run_section_12() {
    print_section_header "12" "Enable AppArmor to Restrict Apache Processes" || return 0

# 12.1 Ensure the AppArmor Framework Is Enabled (Automated)
check_12_1() {
    if command -v aa-status >/dev/null 2>&1; then
        if aa-status --enabled 2>/dev/null; then
            pass_check "12.1" "Ensure the AppArmor Framework Is Enabled (Automated) [Level 2]" \
                "AppArmor framework is enabled."
        else
            fail_check "12.1" "Ensure the AppArmor Framework Is Enabled (Automated) [Level 2]" \
                "aa-status --enabled returned non-zero (AppArmor is not enabled)." \
                "Enable and start the AppArmor framework:
  /etc/init.d/apparmor start  # or: systemctl enable --now apparmor"
        fi
    else
        fail_check "12.1" "Ensure the AppArmor Framework Is Enabled (Automated) [Level 2]" \
            "aa-status command not found (AppArmor is not installed; note: CIS recommends either AppArmor or SELinux)." \
            "If using AppArmor on this platform:
  apt-get install apparmor libapache2-mod-apparmor
  /etc/init.d/apparmor start"
    fi
}
check_12_1

# 12.2 Ensure the Apache AppArmor Profile Is Configured Properly (Manual)
check_12_2() {
    local profile="/etc/apparmor.d/usr.sbin.apache2"
    if [[ ! -f "$profile" ]]; then
        fail_check "12.2" "Ensure the Apache AppArmor Profile Is Configured Properly (Manual) [Level 2]" \
            "AppArmor profile '$profile' was not found." \
            "Create and customize an AppArmor profile for Apache implementing least privilege:
  1. service apache2 stop
  2. aa-autodep apache2
  3. aa-complain apache2 && service apache2 start
  4. Exercise the web application and run 'aa-logprof' to refine rules.
  5. Reload profile: apparmor_parser -r /etc/apparmor.d/usr.sbin.apache2
  6. Enforce profile: aa-enforce /usr/sbin/apache2 && /etc/init.d/apparmor reload"
        return
    fi

    local wildcard_root
    wildcard_root=$(grep -Ev "^\s*#" "$profile" 2>/dev/null | grep -E "^\s*/\*\*\s+" || true)
    if [[ -n "$wildcard_root" ]]; then
        fail_check "12.2" "Ensure the Apache AppArmor Profile Is Configured Properly (Manual) [Level 2]" \
            "AppArmor profile '$profile' contains overly permissive root wildcard '/**' rule." \
            "Edit $profile to remove wildcard '/**' rules and grant read/write access only to specific required paths (e.g. /etc/apache2/** r, /var/www/html/** r, /var/log/apache2/** rw), then reload:
  apparmor_parser -r /etc/apparmor.d/usr.sbin.apache2"
    else
        manual_check "12.2" "Ensure the Apache AppArmor Profile Is Configured Properly (Manual) [Level 2]" \
            "AppArmor profile '$profile' exists and does not contain root wildcard '/**'. Review capabilities and path permissions for least privilege." \
            "Review $profile and included files in /etc/apparmor.d/apache2.d/ to verify least-privilege access rules."
    fi
}
check_12_2

# 12.3 Ensure Apache AppArmor Profile is in Enforce Mode (Automated)
check_12_3() {
    if ! command -v aa-unconfined >/dev/null 2>&1; then
        fail_check "12.3" "Ensure Apache AppArmor Profile is in Enforce Mode (Automated) [Level 2]" \
            "aa-unconfined command not found (AppArmor utilities not installed)." \
            "Install AppArmor utilities and set the Apache profile to enforce mode:
  aa-enforce apache2
  service apache2 stop && service apache2 start"
        return
    fi

    local aa_out
    aa_out=$(aa-unconfined --paranoid 2>/dev/null | grep "apache2" || true)
    if [[ -z "$aa_out" ]]; then
        fail_check "12.3" "Ensure Apache AppArmor Profile is in Enforce Mode (Automated) [Level 2]" \
            "No running apache2 processes detected by 'aa-unconfined --paranoid | grep apache2'." \
            "Set the apache2 AppArmor profile to enforce mode and restart Apache:
  aa-enforce apache2
  service apache2 stop
  service apache2 start"
    elif echo "$aa_out" | grep -q "confined by" && echo "$aa_out" | grep -q "(enforce)" && ! echo "$aa_out" | grep -qE "not confined|\(complain\)"; then
        pass_check "12.3" "Ensure Apache AppArmor Profile is in Enforce Mode (Automated) [Level 2]" \
            "All running apache2 processes are confined by AppArmor in (enforce) mode."
    else
        fail_check "12.3" "Ensure Apache AppArmor Profile is in Enforce Mode (Automated) [Level 2]" \
            "Apache processes are not confined in enforce mode: $(echo "$aa_out" | tr '\n' ' ')" \
            "Set the apache2 AppArmor profile to enforce mode and restart the service:
  aa-enforce apache2
  service apache2 stop
  service apache2 start"
    fi
}
check_12_3
}


# ==============================================================================
# MAIN EXECUTION & SUMMARY SCORECARD
# ==============================================================================
print_summary() {
    echo -e "\n${C_BG_BLUE} [SUMMARY] ${BENCHMARK_NAME^^} AUDIT REPORT ${C_RESET}"
    echo -e "${C_BLUE}====================================================================================${C_RESET}"
    printf "  %-36s | %7s | %7s | %7s | %7s | %7s\n" "Section" "OK" "FAIL" "MANUAL" "SKIP" "Total"
    echo -e "${C_DIM}------------------------------------------------------------------------------------${C_RESET}"
    local s_names=(
        ""
        "1. Planning and Installation"
        "2. Minimize Apache Modules"
        "3. Principles, Perms & Ownership"
        "4. Apache Access Control"
        "5. Minimize Features & Options"
        "6. Logging, Monitoring & Maint."
        "7. SSL/TLS Configuration"
        "8. Information Leakage"
        "9. Denial of Service Mitigations"
        "10. Request Limits"
        "11. Enable SELinux Restrictions"
        "12. Enable AppArmor Restrictions"
    )
    local s
    for s in 1 2 3 4 5 6 7 8 9 10 11 12; do
        local ok="${SEC_OK[$s]:-0}"
        local fl="${SEC_FAIL[$s]:-0}"
        local mn="${SEC_MANUAL[$s]:-0}"
        local sk="${SEC_SKIP[$s]:-0}"
        local tot=$(( ok + fl + mn + sk ))
        [[ "$tot" -eq 0 ]] && ! is_section_selected "$s" && continue
        printf "  %-36s | %7d | %7d | %7d | %7d | %7d\n" "${s_names[$s]}" "$ok" "$fl" "$mn" "$sk" "$tot"
    done
    echo -e "${C_BLUE}====================================================================================${C_RESET}"
    echo -e "  ${C_BOLD}Total Checks Executed:${C_RESET}  ${TOTAL_CHECKS}"
    echo -e "  ${C_GREEN}${C_BOLD}[OK] Compliant:${C_RESET}         ${COUNT_OK}"
    echo -e "  ${C_RED}${C_BOLD}[FAIL] Non-Compliant:${C_RESET}   ${COUNT_FAIL}"
    echo -e "  ${C_YELLOW}${C_BOLD}[MANUAL] Site Review:${C_RESET}   ${COUNT_MANUAL}"
    echo -e "  ${C_MAGENTA}${C_BOLD}[SKIP] Skipped:${C_RESET}         ${COUNT_SKIP}"
    if [[ "$TOTAL_CHECKS" -gt 0 ]]; then
        local pct=$(( (COUNT_OK * 100) / TOTAL_CHECKS ))
        echo -e "  ${C_CYAN}${C_BOLD}Automated Pass Rate:${C_RESET}    ${pct}% (${COUNT_OK}/${TOTAL_CHECKS})"
    fi
    echo -e "${C_BLUE}====================================================================================${C_RESET}"
}

main() {
    setup_colors_and_init
    detect_apache_env
    print_banner
    run_section_1
    run_section_2
    run_section_3
    run_section_4
    run_section_5
    run_section_6
    run_section_7
    run_section_8
    run_section_9
    run_section_10
    run_section_11
    run_section_12
    print_summary
}

main "$@"
