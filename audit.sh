#!/usr/bin/env bash
# ==============================================================================
# CIS Benchmark Security Audit Suite - Interactive CLI Launcher (audit.sh)
# Benchmarks:  Ubuntu 26.04 LTS | Ubuntu 24.04 LTS | MariaDB 10.6 | Apache 2.4 | NGINX 3.0.0
# Repository:  https://github.com/nmwafa/cis-audit
#
# Quick Start (Direct Execution from GitHub):
#   curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash
#   curl -s https://raw.githubusercontent.com/nmwafa/cis-audit/main/audit.sh | sudo bash
# ==============================================================================

set -u

REPO_OWNER="${CIS_AUDIT_REPO_OWNER:-nmwafa}"
REPO_NAME="${CIS_AUDIT_REPO_NAME:-cis-audit}"
REPO_BRANCH="${CIS_AUDIT_REPO_BRANCH:-main}"
REPO_BASE_URL="${CIS_AUDIT_REPO_URL:-https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}}"

# Determine local script directory if audit.sh is executed from a local file
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Standardized Audit Script Filenames
SCRIPT_UBUNTU="cis_ubuntu_26.04.sh"
SCRIPT_UBUNTU_2404="cis_ubuntu_24.04.sh"
SCRIPT_MARIADB="cis_mariadb_10.6.sh"
SCRIPT_APACHE="cis_apache_2.4.sh"
SCRIPT_NGINX="cis_nginx_v3.0.0.sh"

SEP_LINE="===================================================================================================="
DIV_LINE="----------------------------------------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# CLI Baseline Defaults (All Profile Levels & All Sections Included by Default)
# ------------------------------------------------------------------------------
CLI_PROFILE_LEVEL="all"
PROFILE_LEVEL="all"
TARGET_SECTION="all"
CLI_OUTPUT_FILE=""
CLI_QUIET_OK=0
CLI_USE_COLOR=1
CLI_FORCE_COLOR="${FORCE_COLOR:-1}"
RUN_ONCE=0
CLI_TARGET=""
EXTRA_ARGS=()

# CLI-supplied service-specific defaults (empty = unmodified default behavior)
CLI_MDB_USER=""
CLI_MDB_PASS=""
CLI_MDB_ASK_PASS=0
CLI_MDB_HOST=""
CLI_MDB_PORT=""
CLI_MDB_SOCKET=""
CLI_MDB_DEFAULTS_FILE=""
CLI_MDB_CONFIG=""
CLI_MDB_ADMIN_USERS=""
CLI_MDB_REPL_USERS=""
CLI_MDB_BACKUP_DIRS=""

CLI_APACHE_PREFIX=""
CLI_APACHE_CONFIG=""
CLI_APACHE_BINARY=""
CLI_APACHE_DOCROOT=""

CLI_NGINX_CONFIG_DIR=""
CLI_NGINX_BINARY=""
CLI_NGINX_PORTS=""

# Active session variables (initialized from CLI defaults before each audit menu)
OUTPUT_FILE=""
QUIET_OK=0
USE_COLOR=1
FORCE_COLOR=1

MDB_USER=""
MDB_PASS=""
MDB_ASK_PASS=0
MDB_HOST=""
MDB_PORT=""
MDB_SOCKET=""
MDB_DEFAULTS_FILE=""
MDB_CONFIG=""
MDB_ADMIN_USERS=""
MDB_REPL_USERS=""
MDB_BACKUP_DIRS=""

APACHE_PREFIX=""
APACHE_CONFIG=""
APACHE_BINARY=""
APACHE_DOCROOT=""

NGINX_CONFIG_DIR=""
NGINX_BINARY=""
NGINX_PORTS=""

STATUS_MSG=""

normalize_profile_level() {
    local val="${1:-all}"
    case "${val,,}" in
        1|l1|level1|"level 1") echo "1" ;;
        2|l2|level2|"level 2") echo "2" ;;
        all|a|"")              echo "all" ;;
        *)                     echo "" ;;
    esac
}

# Reset active options to default (unmodified) state so no custom changes
# are executed unless the user explicitly desires them.
reset_active_options() {
    PROFILE_LEVEL="${CLI_PROFILE_LEVEL:-all}"
    TARGET_SECTION="all"
    OUTPUT_FILE="$CLI_OUTPUT_FILE"
    QUIET_OK="$CLI_QUIET_OK"
    USE_COLOR="$CLI_USE_COLOR"
    FORCE_COLOR="$CLI_FORCE_COLOR"

    MDB_USER="$CLI_MDB_USER"
    MDB_PASS="$CLI_MDB_PASS"
    MDB_ASK_PASS="$CLI_MDB_ASK_PASS"
    MDB_HOST="$CLI_MDB_HOST"
    MDB_PORT="$CLI_MDB_PORT"
    MDB_SOCKET="$CLI_MDB_SOCKET"
    MDB_DEFAULTS_FILE="$CLI_MDB_DEFAULTS_FILE"
    MDB_CONFIG="$CLI_MDB_CONFIG"
    MDB_ADMIN_USERS="$CLI_MDB_ADMIN_USERS"
    MDB_REPL_USERS="$CLI_MDB_REPL_USERS"
    MDB_BACKUP_DIRS="$CLI_MDB_BACKUP_DIRS"

    APACHE_PREFIX="$CLI_APACHE_PREFIX"
    APACHE_CONFIG="$CLI_APACHE_CONFIG"
    APACHE_BINARY="$CLI_APACHE_BINARY"
    APACHE_DOCROOT="$CLI_APACHE_DOCROOT"

    NGINX_CONFIG_DIR="$CLI_NGINX_CONFIG_DIR"
    NGINX_BINARY="$CLI_NGINX_BINARY"
    NGINX_PORTS="$CLI_NGINX_PORTS"

    STATUS_MSG=""
    setup_colors
}

# ------------------------------------------------------------------------------
# Colors & Formatting (Standardized CIS Audit Suite Palette)
# ------------------------------------------------------------------------------
setup_colors() {
    if [[ "$USE_COLOR" -eq 0 ]]; then
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
    fi
}

clear_screen() {
    if [[ "$USE_COLOR" -eq 1 ]]; then
        if [[ -t 1 ]] && command -v clear >/dev/null 2>&1; then
            clear 2>/dev/null || printf '\033[2J\033[H'
        else
            printf '\033[2J\033[H'
        fi
    fi
}

usage() {
    cat << 'EOF'
Usage: audit.sh [OPTIONS] [-- EXTRA_SCRIPT_ARGS...]

Interactive, color-coded CLI launcher for the CIS Benchmark Security Audit Suite.
Displays the main audit menu on startup. When an audit code (1-6) is selected,
the numbered options for that specific audit program are displayed, including
CIS Profile Level selection, with all sections and all profile levels included
by default so pressing [Enter] runs the full audit immediately.

Direct Execution from GitHub:
  curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash
  curl -s https://raw.githubusercontent.com/nmwafa/cis-audit/main/audit.sh | sudo bash

Universal CLI Options:
  -t, --target <1..6|name>       Run target directly (1/ubuntu-26.04, 2/ubuntu-24.04, 3/mariadb, 4/apache, 5/nginx, 6/all)
  -l, --level <1|2|all>          Filter by CIS Profile Level (1 = Level 1, 2 = Level 2, all = All Profiles [default])
  -o, --output <file>            Save full audit report to <file>
  -q, --quiet-ok                 Hide [OK] results and display only FAIL/MANUAL/SKIP findings
  -n, --no-color                 Disable ANSI color output
      --color                    Force ANSI color output even when piped
  -r, --repo-url <url>           Override GitHub raw base URL for remote script fetching
      --once                     Execute one audit selection and exit immediately
  -h, --help                     Show this help message and exit

MariaDB 10.6 CLI Options:
      --db-user <USER>           MariaDB username for SQL audit queries
      --db-pass <PASS>           MariaDB password (prefer --ask-pass or --defaults-file)
  -W, --ask-pass                 Prompt interactively for MariaDB password
      --db-host <HOST>           MariaDB host (default: local socket)
      --db-port <PORT>           MariaDB port (default: 3306)
      --db-socket <SOCKET>       Path to MariaDB unix socket file
      --defaults-file <FILE>     Path to MariaDB client defaults file (e.g., ~/.my.cnf)
      --db-config <FILE>         Path to primary MariaDB configuration file (e.g., /etc/mysql/mariadb.cnf)
      --admin-users <LIST>       Comma-separated authorized DB admin users (default: root,mysql,mariadb.sys)
      --repl-users <LIST>        Comma-separated authorized replication users (default: repl,replica,slave)
      --backup-dirs <LIST>       Comma-separated backup directories to inspect

Apache 2.4 CLI Options:
      --apache-prefix <DIR>      Apache ServerRoot / prefix directory
      --apache-config <FILE>     Main Apache configuration file (httpd.conf / apache2.conf)
      --apache-binary <PATH>     Apache binary path (httpd / apache2)
      --apache-docroot <DIR>     Apache DocumentRoot directory

NGINX 3.0.0 CLI Options:
      --nginx-config-dir <DIR>   NGINX configuration directory (default: /etc/nginx)
      --nginx-binary <PATH>      NGINX binary path (default: auto-detected)
      --nginx-ports <LIST>       Comma-separated list of authorized listen ports (default: 80,443)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--target) CLI_TARGET="${2:-}"; RUN_ONCE=1; shift 2 ;;
            -l|--level|--profile)
                local norm_lvl
                norm_lvl="$(normalize_profile_level "${2:-all}")"
                if [[ -z "$norm_lvl" ]]; then
                    echo "Invalid profile level: '${2:-}'. Expected 1, 2, or all." >&2
                    exit 1
                fi
                CLI_PROFILE_LEVEL="$norm_lvl"
                shift 2
                ;;
            -o|--output) CLI_OUTPUT_FILE="${2:-}"; shift 2 ;;
            -q|--quiet-ok) CLI_QUIET_OK=1; shift ;;
            -n|--no-color) CLI_USE_COLOR=0; CLI_FORCE_COLOR=0; shift ;;
            --color) CLI_USE_COLOR=1; CLI_FORCE_COLOR=1; shift ;;
            -r|--repo-url) REPO_BASE_URL="${2%/}"; shift 2 ;;
            --once) RUN_ONCE=1; shift ;;
            # MariaDB options
            --db-user) CLI_MDB_USER="${2:-}"; shift 2 ;;
            --db-pass) CLI_MDB_PASS="${2:-}"; shift 2 ;;
            -W|--ask-pass) CLI_MDB_ASK_PASS=1; shift ;;
            --db-host) CLI_MDB_HOST="${2:-}"; shift 2 ;;
            --db-port) CLI_MDB_PORT="${2:-}"; shift 2 ;;
            --db-socket) CLI_MDB_SOCKET="${2:-}"; shift 2 ;;
            --defaults-file) CLI_MDB_DEFAULTS_FILE="${2:-}"; shift 2 ;;
            --db-config) CLI_MDB_CONFIG="${2:-}"; shift 2 ;;
            --admin-users) CLI_MDB_ADMIN_USERS="${2:-}"; shift 2 ;;
            --repl-users) CLI_MDB_REPL_USERS="${2:-}"; shift 2 ;;
            --backup-dirs) CLI_MDB_BACKUP_DIRS="${2:-}"; shift 2 ;;
            # Apache options
            --apache-prefix) CLI_APACHE_PREFIX="${2:-}"; shift 2 ;;
            --apache-config) CLI_APACHE_CONFIG="${2:-}"; shift 2 ;;
            --apache-binary) CLI_APACHE_BINARY="${2:-}"; shift 2 ;;
            --apache-docroot) CLI_APACHE_DOCROOT="${2:-}"; shift 2 ;;
            # NGINX options
            --nginx-config-dir) CLI_NGINX_CONFIG_DIR="${2:-}"; shift 2 ;;
            --nginx-binary) CLI_NGINX_BINARY="${2:-}"; shift 2 ;;
            --nginx-ports) CLI_NGINX_PORTS="${2:-}"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            --) shift; EXTRA_ARGS+=("$@"); break ;;
            *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Pipe-Safe Terminal Input Helpers (Supports `curl -s ... | bash`)
# ------------------------------------------------------------------------------
has_tty() {
    ( : < /dev/tty ) 2>/dev/null
}

prompt_input() {
    local prompt_str="$1"
    local var_name="$2"
    local secret="${3:-0}"
    local input_val=""

    local read_flags=(-r)
    [[ "$secret" -eq 1 ]] && read_flags+=(-s)

    if [[ -t 0 ]]; then
        printf "%s" "$prompt_str"
        IFS= read "${read_flags[@]}" input_val || return 1
        [[ "$secret" -eq 1 ]] && echo ""
    elif has_tty; then
        printf "%s" "$prompt_str" > /dev/tty
        IFS= read "${read_flags[@]}" input_val < /dev/tty || return 1
        [[ "$secret" -eq 1 ]] && echo "" > /dev/tty
    elif [[ -t 1 ]]; then
        printf "%s" "$prompt_str"
        IFS= read "${read_flags[@]}" input_val <&1 || return 1
        [[ "$secret" -eq 1 ]] && echo ""
    elif [[ -t 2 ]]; then
        printf "%s" "$prompt_str" >&2
        IFS= read "${read_flags[@]}" input_val <&2 || return 1
        [[ "$secret" -eq 1 ]] && echo "" >&2
    else
        printf "%s" "$prompt_str"
        IFS= read "${read_flags[@]}" input_val || return 1
        [[ "$secret" -eq 1 ]] && echo ""
    fi
    printf -v "$var_name" "%s" "$input_val"
    return 0
}

run_with_tty() {
    if [[ -t 0 ]]; then
        "$@"
    elif has_tty; then
        "$@" < /dev/tty
    elif [[ -t 1 ]]; then
        "$@" <&1
    elif [[ -t 2 ]]; then
        "$@" <&2
    else
        "$@"
    fi
}

# ------------------------------------------------------------------------------
# Host Service Detection & Startup Menu
# ------------------------------------------------------------------------------
detect_host_services() {
    local os_id="" os_ver=""
    if [[ -r /etc/os-release ]]; then
        os_id="$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | xargs)"
        os_ver="$(grep '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | xargs)"
    fi

    if [[ "${os_id,,}" == "ubuntu" && "$os_ver" == "26.04"* ]]; then
        BADGE_UBUNTU_2604="${C_GREEN}[DETECTED]${C_RESET}"
        BADGE_UBUNTU_2404="${C_CYAN}[UBUNTU OS]${C_RESET}"
    elif [[ "${os_id,,}" == "ubuntu" && "$os_ver" == "24.04"* ]]; then
        BADGE_UBUNTU_2604="${C_CYAN}[UBUNTU OS]${C_RESET}"
        BADGE_UBUNTU_2404="${C_GREEN}[DETECTED]${C_RESET}"
    elif [[ "${os_id,,}" =~ (ubuntu|debian) ]]; then
        BADGE_UBUNTU_2604="${C_GREEN}[DETECTED]${C_RESET}"
        BADGE_UBUNTU_2404="${C_GREEN}[DETECTED]${C_RESET}"
    else
        BADGE_UBUNTU_2604="${C_YELLOW}[LINUX OS]${C_RESET}"
        BADGE_UBUNTU_2404="${C_YELLOW}[LINUX OS]${C_RESET}"
    fi

    if command -v mariadbd >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1 || command -v mysqld >/dev/null 2>&1; then
        BADGE_MARIADB="${C_GREEN}[DETECTED]${C_RESET}"
    elif [[ -d /etc/mysql || -f /etc/my.cnf ]]; then
        BADGE_MARIADB="${C_CYAN}[CONFIG FOUND]${C_RESET}"
    else
        BADGE_MARIADB="${C_DIM}[NOT INSTALLED]${C_RESET}"
    fi

    if command -v apache2 >/dev/null 2>&1 || command -v httpd >/dev/null 2>&1; then
        BADGE_APACHE="${C_GREEN}[DETECTED]${C_RESET}"
    elif [[ -d /etc/apache2 || -d /etc/httpd ]]; then
        BADGE_APACHE="${C_CYAN}[CONFIG FOUND]${C_RESET}"
    else
        BADGE_APACHE="${C_DIM}[NOT INSTALLED]${C_RESET}"
    fi

    if command -v nginx >/dev/null 2>&1 || [[ -x /usr/sbin/nginx ]]; then
        BADGE_NGINX="${C_GREEN}[DETECTED]${C_RESET}"
    elif [[ -d /etc/nginx ]]; then
        BADGE_NGINX="${C_CYAN}[CONFIG FOUND]${C_RESET}"
    else
        BADGE_NGINX="${C_DIM}[NOT INSTALLED]${C_RESET}"
    fi

    if [[ -n "$SCRIPT_DIR" && ( -f "${SCRIPT_DIR}/${SCRIPT_UBUNTU}" || -f "${SCRIPT_DIR}/${SCRIPT_UBUNTU_2404}" ) ]]; then
        EXEC_SOURCE="Local Directory (${SCRIPT_DIR})"
    else
        EXEC_SOURCE="GitHub Remote Stream (${REPO_BASE_URL})"
    fi
}

print_launcher_banner() {
    detect_host_services
    echo -e "${C_CYAN}${C_BOLD}"
    cat << 'BANNER'
     _______________    ___             ___ __     _____       _ __     
    / ____/  _/ ___/   /   | __  ______/ (_) /_   / ___/__  __(_) /____ 
   / /    / / \__ \   / /| |/ / / / __  / / __/   \__ \/ / / / / __/ _ \
  / /____/ / ___/ /  / ___ / /_/ / /_/ / / /_    ___/ / /_/ / / /_/  __/
  \____/___//____/  /_/  |_\__,_/\__,_/_/\__/   /____/\__,_/_/\__/\___/ 
                                                                      
BANNER
    echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
    echo -e "  ${C_BOLD}Hostname:${C_RESET}       $(hostname 2>/dev/null || echo 'unknown')"
    echo -e "  ${C_BOLD}OS Release:${C_RESET}     $(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -sr)"
    echo -e "  ${C_BOLD}Kernel:${C_RESET}         $(uname -r 2>/dev/null || echo 'unknown') ($(uname -m 2>/dev/null || echo 'unknown'))"
    echo -e "  ${C_BOLD}Current User:${C_RESET}   $(id -un 2>/dev/null || echo 'unknown') (UID: $(id -u 2>/dev/null || echo '?'))"
    echo -e "  ${C_BOLD}Audit Date:${C_RESET}     $(date -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)"
    echo -e "  ${C_BOLD}Script Source:${C_RESET}  ${EXEC_SOURCE}"
    if [[ "$(id -u 2>/dev/null || echo 1)" -ne 0 ]]; then
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        echo -e "  ${C_YELLOW}[!] WARNING: Running as non-root user. Re-run with 'sudo' for full audit visibility.${C_RESET}"
    fi
    echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
}

print_main_menu() {
    echo -e "\n${C_BG_BLUE} [MAIN MENU] SELECT A CIS BENCHMARK AUDIT PROGRAM ${C_RESET}"
    echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
    printf "  ${C_CYAN}${C_BOLD}[1]${C_RESET} %-46s ${C_DIM}%-16s${C_RESET} %b\n" \
        "CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0" "(350 Controls)" "$BADGE_UBUNTU_2604"
    printf "  ${C_CYAN}${C_BOLD}[2]${C_RESET} %-46s ${C_DIM}%-16s${C_RESET} %b\n" \
        "CIS Ubuntu Linux 24.04 LTS Benchmark v2.0.0" "(333 Controls)" "$BADGE_UBUNTU_2404"
    printf "  ${C_CYAN}${C_BOLD}[3]${C_RESET} %-46s ${C_DIM}%-16s${C_RESET} %b\n" \
        "CIS MariaDB 10.6 Benchmark v1.1.0" "( 74 Controls)" "$BADGE_MARIADB"
    printf "  ${C_CYAN}${C_BOLD}[4]${C_RESET} %-46s ${C_DIM}%-16s${C_RESET} %b\n" \
        "CIS Apache HTTP Server 2.4 Benchmark v2.4.0" "( 81 Controls)" "$BADGE_APACHE"
    printf "  ${C_CYAN}${C_BOLD}[5]${C_RESET} %-46s ${C_DIM}%-16s${C_RESET} %b\n" \
        "CIS NGINX Benchmark v3.0.0" "( 44 Controls)" "$BADGE_NGINX"
    printf "  ${C_GREEN}${C_BOLD}[6]${C_RESET} ${C_BOLD}%-46s${C_RESET} ${C_DIM}%-16s${C_RESET} ${C_MAGENTA}[FULL SUITE]${C_RESET}\n" \
        "Run All 5 CIS Benchmark Audits Sequentially" "(882 Controls)"
    echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
    echo -e "  ${C_RED}${C_BOLD}[0]${C_RESET} Exit CIS Audit Launcher"
    echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
}

# ------------------------------------------------------------------------------
# Common Numbered Option Helpers ([1] Profile, [2] Quiet-OK, [3] Output, [4] Color)
# ------------------------------------------------------------------------------
format_common_labels() {
    case "${PROFILE_LEVEL:-all}" in
        1)
            PROFILE_DISP="${C_CYAN}${C_BOLD}Level 1 Only${C_RESET} (L1 - Base Security Profile)"
            ;;
        2)
            PROFILE_DISP="${C_YELLOW}${C_BOLD}Level 2${C_RESET} (L2 - Extended Security Profile)"
            ;;
        *)
            PROFILE_DISP="${C_GREEN}${C_BOLD}all${C_RESET} (default: Level 1 & Level 2)"
            ;;
    esac

    if [[ "$QUIET_OK" -eq 1 ]]; then
        QUIET_DISP="${C_YELLOW}${C_BOLD}ON${C_RESET} (Hide [OK], show FAIL/MANUAL/SKIP only)"
    else
        QUIET_DISP="OFF (default: show all checks)"
    fi

    if [[ "$USE_COLOR" -eq 1 ]]; then
        COLOR_DISP="ON (default: ANSI colors enabled)"
    else
        COLOR_DISP="${C_DIM}OFF (Plain text output)${C_RESET}"
    fi

    OUT_DISP="${OUTPUT_FILE:-none (default: terminal stdout only)}"
}

prompt_profile_selection() {
    echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
    echo -e "  ${C_YELLOW}${C_BOLD}Select CIS Profile:${C_RESET} ${C_CYAN}[1]${C_RESET} Level 1 Only   ${C_CYAN}[2]${C_RESET} Level 2   ${C_CYAN}[all]${C_RESET} All Profiles (default)"
    local p_val=""
    prompt_input "  Enter Profile Level [1, 2, or all (Enter for all)]: " p_val || return 1
    p_val="$(echo "$p_val" | xargs)"
    local norm
    norm="$(normalize_profile_level "$p_val")"
    if [[ -z "$norm" ]]; then
        STATUS_MSG="${C_RED}[!] Invalid profile '${p_val}'. Choose '1' (Level 1), '2' (Level 2), or 'all'.${C_RESET}"
    else
        PROFILE_LEVEL="$norm"
        STATUS_MSG="${C_GREEN}[*] CIS Profile Level set to '${PROFILE_LEVEL}'.${C_RESET}"
    fi
    return 0
}

handle_common_option_number() {
    local key="$1"
    case "$key" in
        1)
            prompt_profile_selection || return 1
            return 0
            ;;
        2)
            if [[ "$QUIET_OK" -eq 0 ]]; then
                QUIET_OK=1
                STATUS_MSG="${C_GREEN}[*] Quiet-OK enabled ([OK] checks will be hidden).${C_RESET}"
            else
                QUIET_OK=0
                STATUS_MSG="${C_GREEN}[*] Quiet-OK disabled (all checks will be shown).${C_RESET}"
            fi
            return 0
            ;;
        3)
            local val=""
            prompt_input "  Enter Output Report File Path (leave blank for none/stdout only): " val || return 1
            OUTPUT_FILE="$(echo "$val" | xargs)"
            STATUS_MSG="${C_GREEN}[*] Output report file set to: ${OUTPUT_FILE:-none (stdout only)}.${C_RESET}"
            return 0
            ;;
        4)
            if [[ "$USE_COLOR" -eq 1 ]]; then
                USE_COLOR=0
                FORCE_COLOR=0
                setup_colors
                STATUS_MSG="[*] ANSI color output disabled."
            else
                USE_COLOR=1
                FORCE_COLOR=1
                setup_colors
                STATUS_MSG="${C_GREEN}[*] ANSI color output enabled.${C_RESET}"
            fi
            return 0
            ;;
    esac
    return 2
}

print_status_notice() {
    if [[ -n "$STATUS_MSG" ]]; then
        echo -e "  ${STATUS_MSG}"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        STATUS_MSG=""
    fi
}

# ------------------------------------------------------------------------------
# Per-Audit Numbered Option Menus (Displayed Only After Audit Code Is Selected)
# ------------------------------------------------------------------------------

# Audit Code 1: CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0
menu_audit_ubuntu_2604() {
    reset_active_options
    while true; do
        clear_screen
        print_launcher_banner
        format_common_labels
        echo -e "\n${C_BG_BLUE} [AUDIT CODE 1] CIS UBUNTU LINUX 26.04 LTS v1.0.0 - AUDIT OPTIONS ${C_RESET}"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
        echo -e "  ${C_DIM}Press [Enter] to run immediately with defaults, or select an option below.${C_RESET}"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        echo -e "  ${C_YELLOW}${C_BOLD}Ubuntu 26.04 Audit Options:${C_RESET}"
        printf "    ${C_CYAN}${C_BOLD}[1]${C_RESET} %-35s : %b\n" "Profile Level (-l, --level)" "$PROFILE_DISP"
        printf "    ${C_CYAN}${C_BOLD}[2]${C_RESET} %-35s : %b\n" "Quiet-OK Mode (-q, --quiet-ok)" "$QUIET_DISP"
        printf "    ${C_CYAN}${C_BOLD}[3]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Output File (-o, --output)" "$OUT_DISP"
        printf "    ${C_CYAN}${C_BOLD}[4]${C_RESET} %-35s : %b\n" "Color Output (-n, --no-color)" "$COLOR_DISP"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        print_status_notice
        echo -e "  ${C_GREEN}${C_BOLD}[Enter / r]${C_RESET} Start Ubuntu 26.04 Audit Now   ${C_YELLOW}${C_BOLD}[d]${C_RESET} Reset Defaults   ${C_RED}${C_BOLD}[0 / b]${C_RESET} Back"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"

        local sub=""
        prompt_input "${C_BOLD}${C_CYAN}Press [Enter] to start audit, or select option [1-4, d, 0]: ${C_RESET}" sub || return 1
        sub="$(echo "$sub" | xargs)"

        if [[ -z "$sub" || "${sub,,}" == "r" || "${sub,,}" == "run" ]]; then
            execute_audit_script "ubuntu" "$SCRIPT_UBUNTU" "CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0"
            return 0
        elif [[ "$sub" == "0" || "${sub,,}" == "b" || "${sub,,}" == "back" ]]; then
            return 2
        elif [[ "${sub,,}" == "d" || "${sub,,}" == "reset" ]]; then
            reset_active_options
            STATUS_MSG="${C_GREEN}[*] Reset to default settings.${C_RESET}"
        else
            handle_common_option_number "$sub"
            local rc=$?
            [[ "$rc" -eq 1 ]] && return 1
            if [[ "$rc" -eq 2 ]]; then
                STATUS_MSG="${C_RED}[!] Invalid option '${sub}'. Select [1-4], [d] to reset, [0] to go back, or press [Enter] to run.${C_RESET}"
            fi
        fi
    done
}

# Audit Code 2: CIS Ubuntu Linux 24.04 LTS Benchmark v2.0.0
menu_audit_ubuntu_2404() {
    reset_active_options
    while true; do
        clear_screen
        print_launcher_banner
        format_common_labels
        echo -e "\n${C_BG_BLUE} [AUDIT CODE 2] CIS UBUNTU LINUX 24.04 LTS v2.0.0 - AUDIT OPTIONS ${C_RESET}"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
        echo -e "  ${C_DIM}Press [Enter] to run immediately with defaults, or select an option below.${C_RESET}"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        echo -e "  ${C_YELLOW}${C_BOLD}Ubuntu 24.04 Audit Options:${C_RESET}"
        printf "    ${C_CYAN}${C_BOLD}[1]${C_RESET} %-35s : %b\n" "Profile Level (-l, --level)" "$PROFILE_DISP"
        printf "    ${C_CYAN}${C_BOLD}[2]${C_RESET} %-35s : %b\n" "Quiet-OK Mode (-q, --quiet-ok)" "$QUIET_DISP"
        printf "    ${C_CYAN}${C_BOLD}[3]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Output File (-o, --output)" "$OUT_DISP"
        printf "    ${C_CYAN}${C_BOLD}[4]${C_RESET} %-35s : %b\n" "Color Output (-n, --no-color)" "$COLOR_DISP"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        print_status_notice
        echo -e "  ${C_GREEN}${C_BOLD}[Enter / r]${C_RESET} Start Ubuntu 24.04 Audit Now   ${C_YELLOW}${C_BOLD}[d]${C_RESET} Reset Defaults   ${C_RED}${C_BOLD}[0 / b]${C_RESET} Back"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"

        local sub=""
        prompt_input "${C_BOLD}${C_CYAN}Press [Enter] to start audit, or select option [1-4, d, 0]: ${C_RESET}" sub || return 1
        sub="$(echo "$sub" | xargs)"

        if [[ -z "$sub" || "${sub,,}" == "r" || "${sub,,}" == "run" ]]; then
            execute_audit_script "ubuntu2404" "$SCRIPT_UBUNTU_2404" "CIS Ubuntu Linux 24.04 LTS Benchmark v2.0.0"
            return 0
        elif [[ "$sub" == "0" || "${sub,,}" == "b" || "${sub,,}" == "back" ]]; then
            return 2
        elif [[ "${sub,,}" == "d" || "${sub,,}" == "reset" ]]; then
            reset_active_options
            STATUS_MSG="${C_GREEN}[*] Reset to default settings.${C_RESET}"
        else
            handle_common_option_number "$sub"
            local rc=$?
            [[ "$rc" -eq 1 ]] && return 1
            if [[ "$rc" -eq 2 ]]; then
                STATUS_MSG="${C_RED}[!] Invalid option '${sub}'. Select [1-4], [d] to reset, [0] to go back, or press [Enter] to run.${C_RESET}"
            fi
        fi
    done
}

# Audit Code 3: CIS MariaDB 10.6 Benchmark v1.1.0
menu_audit_mariadb() {
    reset_active_options
    while true; do
        clear_screen
        print_launcher_banner
        format_common_labels
        local ask_disp="OFF (default)"
        [[ "$MDB_ASK_PASS" -eq 1 ]] && ask_disp="${C_YELLOW}${C_BOLD}ON${C_RESET} (Prompt interactively for password)"
        local pass_disp="not set (default)"
        [[ -n "$MDB_PASS" ]] && pass_disp="******** (set)"

        echo -e "\n${C_BG_BLUE} [AUDIT CODE 3] CIS MARIADB 10.6 BENCHMARK v1.1.0 - AUDIT OPTIONS ${C_RESET}"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
        echo -e "  ${C_DIM}Press [Enter] to run immediately with defaults, or select an option below.${C_RESET}"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        echo -e "  ${C_YELLOW}${C_BOLD}General Audit Options:${C_RESET}"
        printf "    ${C_CYAN}${C_BOLD}[ 1]${C_RESET} %-35s : %b\n" "Profile Level (-l, --level)" "$PROFILE_DISP"
        printf "    ${C_CYAN}${C_BOLD}[ 2]${C_RESET} %-35s : %b\n" "Quiet-OK Mode (-q, --quiet-ok)" "$QUIET_DISP"
        printf "    ${C_CYAN}${C_BOLD}[ 3]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Output File (-o, --output)" "$OUT_DISP"
        printf "    ${C_CYAN}${C_BOLD}[ 4]${C_RESET} %-35s : %b\n" "Color Output (-n, --no-color)" "$COLOR_DISP"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        echo -e "  ${C_YELLOW}${C_BOLD}MariaDB 10.6 Connection & Policy Options:${C_RESET}"
        printf "    ${C_CYAN}${C_BOLD}[ 5]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "DB Username (-u, --user)" "${MDB_USER:-default (auto / current user)}"
        printf "    ${C_CYAN}${C_BOLD}[ 6]${C_RESET} %-35s : %b\n" "Ask Password (-W, --ask-pass)" "$ask_disp"
        printf "    ${C_CYAN}${C_BOLD}[ 7]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "DB Password (-p, --password)" "$pass_disp"
        printf "    ${C_CYAN}${C_BOLD}[ 8]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "DB Host (-H, --host)" "${MDB_HOST:-default (local socket)}"
        printf "    ${C_CYAN}${C_BOLD}[ 9]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "DB Port (-P, --port)" "${MDB_PORT:-default (3306)}"
        printf "    ${C_CYAN}${C_BOLD}[10]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Unix Socket (-S, --socket)" "${MDB_SOCKET:-default (auto-detect)}"
        printf "    ${C_CYAN}${C_BOLD}[11]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Defaults File (-d, --defaults-file)" "${MDB_DEFAULTS_FILE:-none (default)}"
        printf "    ${C_CYAN}${C_BOLD}[12]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Config File (-c, --config)" "${MDB_CONFIG:-default (auto-detect)}"
        printf "    ${C_CYAN}${C_BOLD}[13]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Admin Users (-a, --admin-users)" "${MDB_ADMIN_USERS:-root,mysql,mariadb.sys (default)}"
        printf "    ${C_CYAN}${C_BOLD}[14]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Repl Users (-r, --repl-users)" "${MDB_REPL_USERS:-repl,replica,slave (default)}"
        printf "    ${C_CYAN}${C_BOLD}[15]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Backup Dirs (-b, --backup-dirs)" "${MDB_BACKUP_DIRS:-default standard backup paths}"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        print_status_notice
        echo -e "  ${C_GREEN}${C_BOLD}[Enter / r]${C_RESET} Start MariaDB 10.6 Audit Now   ${C_YELLOW}${C_BOLD}[d]${C_RESET} Reset Defaults   ${C_RED}${C_BOLD}[0 / b]${C_RESET} Back"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"

        local sub=""
        prompt_input "${C_BOLD}${C_CYAN}Press [Enter] to start audit, or select option [1-15, d, 0]: ${C_RESET}" sub || return 1
        sub="$(echo "$sub" | xargs)"

        if [[ -z "$sub" || "${sub,,}" == "r" || "${sub,,}" == "run" ]]; then
            execute_audit_script "mariadb" "$SCRIPT_MARIADB" "CIS MariaDB 10.6 Benchmark v1.1.0"
            return 0
        elif [[ "$sub" == "0" || "${sub,,}" == "b" || "${sub,,}" == "back" ]]; then
            return 2
        elif [[ "${sub,,}" == "d" || "${sub,,}" == "reset" ]]; then
            reset_active_options
            STATUS_MSG="${C_GREEN}[*] Reset to default settings.${C_RESET}"
        else
            case "$sub" in
                5) prompt_input "  Enter MariaDB Username (leave blank for default): " MDB_USER || return 1 ;;
                6)
                    if [[ "$MDB_ASK_PASS" -eq 0 ]]; then MDB_ASK_PASS=1; else MDB_ASK_PASS=0; fi
                    ;;
                7) prompt_input "  Enter MariaDB Password (input hidden, leave blank for default): " MDB_PASS 1 || return 1 ;;
                8) prompt_input "  Enter MariaDB Host (leave blank for default local socket): " MDB_HOST || return 1 ;;
                9) prompt_input "  Enter MariaDB Port (leave blank for default 3306): " MDB_PORT || return 1 ;;
                10) prompt_input "  Enter MariaDB Unix Socket Path (leave blank for default): " MDB_SOCKET || return 1 ;;
                11) prompt_input "  Enter Client Defaults File Path (e.g. /root/.my.cnf, blank for none): " MDB_DEFAULTS_FILE || return 1 ;;
                12) prompt_input "  Enter Primary MariaDB Config File Path (leave blank for auto-detect): " MDB_CONFIG || return 1 ;;
                13) prompt_input "  Enter Authorized Admin Users (leave blank for default root,mysql,mariadb.sys): " MDB_ADMIN_USERS || return 1 ;;
                14) prompt_input "  Enter Authorized Replication Users (leave blank for default repl,replica,slave): " MDB_REPL_USERS || return 1 ;;
                15) prompt_input "  Enter Backup Directories List (leave blank for default paths): " MDB_BACKUP_DIRS || return 1 ;;
                *)
                    handle_common_option_number "$sub"
                    local rc=$?
                    [[ "$rc" -eq 1 ]] && return 1
                    if [[ "$rc" -eq 2 ]]; then
                        STATUS_MSG="${C_RED}[!] Invalid option '${sub}'. Select [1-15], [d] to reset, [0] to go back, or press [Enter] to run.${C_RESET}"
                    fi
                    ;;
            esac
        fi
    done
}

# Audit Code 4: CIS Apache HTTP Server 2.4 Benchmark v2.4.0
menu_audit_apache() {
    reset_active_options
    while true; do
        clear_screen
        print_launcher_banner
        format_common_labels
        echo -e "\n${C_BG_BLUE} [AUDIT CODE 4] CIS APACHE HTTP SERVER 2.4 v2.4.0 - AUDIT OPTIONS ${C_RESET}"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
        echo -e "  ${C_DIM}Press [Enter] to run immediately with defaults, or select an option below.${C_RESET}"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        echo -e "  ${C_YELLOW}${C_BOLD}General Audit Options:${C_RESET}"
        printf "    ${C_CYAN}${C_BOLD}[1]${C_RESET} %-35s : %b\n" "Profile Level (-l, --level)" "$PROFILE_DISP"
        printf "    ${C_CYAN}${C_BOLD}[2]${C_RESET} %-35s : %b\n" "Quiet-OK Mode (-q, --quiet-ok)" "$QUIET_DISP"
        printf "    ${C_CYAN}${C_BOLD}[3]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Output File (-o, --output)" "$OUT_DISP"
        printf "    ${C_CYAN}${C_BOLD}[4]${C_RESET} %-35s : %b\n" "Color Output (-n, --no-color)" "$COLOR_DISP"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        echo -e "  ${C_YELLOW}${C_BOLD}Apache 2.4 Environment Options:${C_RESET}"
        printf "    ${C_CYAN}${C_BOLD}[5]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "ServerRoot Prefix (-p, --prefix)" "${APACHE_PREFIX:-default (auto-detect /etc/apache2 or /etc/httpd)}"
        printf "    ${C_CYAN}${C_BOLD}[6]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Main Config File (-c, --config)" "${APACHE_CONFIG:-default (auto-detect httpd.conf / apache2.conf)}"
        printf "    ${C_CYAN}${C_BOLD}[7]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Apache Binary (-b, --binary)" "${APACHE_BINARY:-default (auto-detect httpd / apache2)}"
        printf "    ${C_CYAN}${C_BOLD}[8]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "DocumentRoot Dir (-d, --docroot)" "${APACHE_DOCROOT:-default (auto-detect /var/www/html)}"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        print_status_notice
        echo -e "  ${C_GREEN}${C_BOLD}[Enter / r]${C_RESET} Start Apache 2.4 Audit Now     ${C_YELLOW}${C_BOLD}[d]${C_RESET} Reset Defaults   ${C_RED}${C_BOLD}[0 / b]${C_RESET} Back"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"

        local sub=""
        prompt_input "${C_BOLD}${C_CYAN}Press [Enter] to start audit, or select option [1-8, d, 0]: ${C_RESET}" sub || return 1
        sub="$(echo "$sub" | xargs)"

        if [[ -z "$sub" || "${sub,,}" == "r" || "${sub,,}" == "run" ]]; then
            execute_audit_script "apache" "$SCRIPT_APACHE" "CIS Apache HTTP Server 2.4 Benchmark v2.4.0"
            return 0
        elif [[ "$sub" == "0" || "${sub,,}" == "b" || "${sub,,}" == "back" ]]; then
            return 2
        elif [[ "${sub,,}" == "d" || "${sub,,}" == "reset" ]]; then
            reset_active_options
            STATUS_MSG="${C_GREEN}[*] Reset to default settings.${C_RESET}"
        else
            case "$sub" in
                5) prompt_input "  Enter Apache ServerRoot / Prefix directory (leave blank for default): " APACHE_PREFIX || return 1 ;;
                6) prompt_input "  Enter Main Apache Config File path (leave blank for default): " APACHE_CONFIG || return 1 ;;
                7) prompt_input "  Enter Apache Binary path (leave blank for default): " APACHE_BINARY || return 1 ;;
                8) prompt_input "  Enter Apache DocumentRoot directory (leave blank for default): " APACHE_DOCROOT || return 1 ;;
                *)
                    handle_common_option_number "$sub"
                    local rc=$?
                    [[ "$rc" -eq 1 ]] && return 1
                    if [[ "$rc" -eq 2 ]]; then
                        STATUS_MSG="${C_RED}[!] Invalid option '${sub}'. Select [1-8], [d] to reset, [0] to go back, or press [Enter] to run.${C_RESET}"
                    fi
                    ;;
            esac
        fi
    done
}

# Audit Code 5: CIS NGINX Benchmark v3.0.0
menu_audit_nginx() {
    reset_active_options
    while true; do
        clear_screen
        print_launcher_banner
        format_common_labels
        echo -e "\n${C_BG_BLUE} [AUDIT CODE 5] CIS NGINX BENCHMARK v3.0.0 - AUDIT OPTIONS ${C_RESET}"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
        echo -e "  ${C_DIM}Press [Enter] to run immediately with defaults, or select an option below.${C_RESET}"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        echo -e "  ${C_YELLOW}${C_BOLD}General Audit Options:${C_RESET}"
        printf "    ${C_CYAN}${C_BOLD}[1]${C_RESET} %-35s : %b\n" "Profile Level (-l, --level)" "$PROFILE_DISP"
        printf "    ${C_CYAN}${C_BOLD}[2]${C_RESET} %-35s : %b\n" "Quiet-OK Mode (-q, --quiet-ok)" "$QUIET_DISP"
        printf "    ${C_CYAN}${C_BOLD}[3]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Output File (-o, --output)" "$OUT_DISP"
        printf "    ${C_CYAN}${C_BOLD}[4]${C_RESET} %-35s : %b\n" "Color Output (-n, --no-color)" "$COLOR_DISP"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        echo -e "  ${C_YELLOW}${C_BOLD}NGINX 3.0.0 Environment Options:${C_RESET}"
        printf "    ${C_CYAN}${C_BOLD}[5]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Config Directory (-c, --config-dir)" "${NGINX_CONFIG_DIR:-default (auto-detect /etc/nginx)}"
        printf "    ${C_CYAN}${C_BOLD}[6]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "NGINX Binary Path (-b, --binary)" "${NGINX_BINARY:-default (auto-detect from PATH)}"
        printf "    ${C_CYAN}${C_BOLD}[7]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Authorized Ports (-p, --ports)" "${NGINX_PORTS:-80,443 (default)}"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        print_status_notice
        echo -e "  ${C_GREEN}${C_BOLD}[Enter / r]${C_RESET} Start NGINX 3.0.0 Audit Now    ${C_YELLOW}${C_BOLD}[d]${C_RESET} Reset Defaults   ${C_RED}${C_BOLD}[0 / b]${C_RESET} Back"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"

        local sub=""
        prompt_input "${C_BOLD}${C_CYAN}Press [Enter] to start audit, or select option [1-7, d, 0]: ${C_RESET}" sub || return 1
        sub="$(echo "$sub" | xargs)"

        if [[ -z "$sub" || "${sub,,}" == "r" || "${sub,,}" == "run" ]]; then
            execute_audit_script "nginx" "$SCRIPT_NGINX" "CIS NGINX Benchmark v3.0.0"
            return 0
        elif [[ "$sub" == "0" || "${sub,,}" == "b" || "${sub,,}" == "back" ]]; then
            return 2
        elif [[ "${sub,,}" == "d" || "${sub,,}" == "reset" ]]; then
            reset_active_options
            STATUS_MSG="${C_GREEN}[*] Reset to default settings.${C_RESET}"
        else
            case "$sub" in
                5) prompt_input "  Enter NGINX Config Directory (leave blank for default /etc/nginx): " NGINX_CONFIG_DIR || return 1 ;;
                6) prompt_input "  Enter NGINX Binary Path (leave blank for default): " NGINX_BINARY || return 1 ;;
                7) prompt_input "  Enter Authorized Listen Ports (leave blank for default 80,443): " NGINX_PORTS || return 1 ;;
                *)
                    handle_common_option_number "$sub"
                    local rc=$?
                    [[ "$rc" -eq 1 ]] && return 1
                    if [[ "$rc" -eq 2 ]]; then
                        STATUS_MSG="${C_RED}[!] Invalid option '${sub}'. Select [1-7], [d] to reset, [0] to go back, or press [Enter] to run.${C_RESET}"
                    fi
                    ;;
            esac
        fi
    done
}

# Audit Code 6: Run All 5 CIS Benchmark Audits Sequentially
menu_audit_all() {
    reset_active_options
    while true; do
        clear_screen
        print_launcher_banner
        format_common_labels
        echo -e "\n${C_BG_BLUE} [AUDIT CODE 6] FULL CIS SUITE (ALL 5 BENCHMARKS) - AUDIT OPTIONS ${C_RESET}"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"
        echo -e "  ${C_DIM}Press [Enter] to run immediately with defaults, or select an option below.${C_RESET}"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        echo -e "  ${C_YELLOW}${C_BOLD}Full Suite Audit Options:${C_RESET}"
        printf "    ${C_CYAN}${C_BOLD}[1]${C_RESET} %-35s : %b\n" "Profile Level (-l, --level)" "$PROFILE_DISP"
        printf "    ${C_CYAN}${C_BOLD}[2]${C_RESET} %-35s : %b\n" "Quiet-OK Mode (-q, --quiet-ok)" "$QUIET_DISP"
        printf "    ${C_CYAN}${C_BOLD}[3]${C_RESET} %-35s : ${C_WHITE}%s${C_RESET}\n" "Output File (-o, --output)" "$OUT_DISP"
        printf "    ${C_CYAN}${C_BOLD}[4]${C_RESET} %-35s : %b\n" "Color Output (-n, --no-color)" "$COLOR_DISP"
        echo -e "${C_DIM}${DIV_LINE}${C_RESET}"
        print_status_notice
        echo -e "  ${C_GREEN}${C_BOLD}[Enter / r]${C_RESET} Start All 5 Audits Now         ${C_YELLOW}${C_BOLD}[d]${C_RESET} Reset Defaults   ${C_RED}${C_BOLD}[0 / b]${C_RESET} Back"
        echo -e "${C_BLUE}${SEP_LINE}${C_RESET}"

        local sub=""
        prompt_input "${C_BOLD}${C_CYAN}Press [Enter] to execute all audits, or select option [1-4, d, 0]: ${C_RESET}" sub || return 1
        sub="$(echo "$sub" | xargs)"
        case "${sub,,}" in
            ""|r|run)
                execute_audit_script "ubuntu" "$SCRIPT_UBUNTU" "CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0"
                execute_audit_script "ubuntu2404" "$SCRIPT_UBUNTU_2404" "CIS Ubuntu Linux 24.04 LTS Benchmark v2.0.0"
                execute_audit_script "mariadb" "$SCRIPT_MARIADB" "CIS MariaDB 10.6 Benchmark v1.1.0"
                execute_audit_script "apache" "$SCRIPT_APACHE" "CIS Apache HTTP Server 2.4 Benchmark v2.4.0"
                execute_audit_script "nginx" "$SCRIPT_NGINX" "CIS NGINX Benchmark v3.0.0"
                return 0
                ;;
            1|2|3|4)
                handle_common_option_number "$sub" || return 1
                ;;
            d|reset)
                reset_active_options
                STATUS_MSG="${C_GREEN}[*] Options reset to default values.${C_RESET}"
                ;;
            0|b|back)
                return 2
                ;;
            *)
                STATUS_MSG="${C_RED}[!] Invalid option '${sub}'. Select [1-4], [d] to reset, [0] to go back, or press [Enter] to run.${C_RESET}"
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Argument Builder & Script Execution Engine
# ------------------------------------------------------------------------------
# All sections are always included by default; Profile Level defaults to "all"
# unless modified by the user via CLI (-l/--level) or Option [1].
build_child_args() {
    local target_key="$1"
    CHILD_ARGS=()

    if [[ "$USE_COLOR" -eq 1 ]]; then
        CHILD_ARGS+=("--color")
    else
        CHILD_ARGS+=("--no-color")
    fi

    CHILD_ARGS+=("--level" "${PROFILE_LEVEL:-all}" "--section" "all")
    [[ "$QUIET_OK" -eq 1 ]] && CHILD_ARGS+=("--quiet-ok")
    [[ -n "$OUTPUT_FILE" ]] && CHILD_ARGS+=("--output" "$OUTPUT_FILE")

    case "$target_key" in
        mariadb)
            [[ -n "$MDB_USER" ]] && CHILD_ARGS+=("--user" "$MDB_USER")
            [[ -n "$MDB_PASS" ]] && CHILD_ARGS+=("--password" "$MDB_PASS")
            [[ "$MDB_ASK_PASS" -eq 1 ]] && CHILD_ARGS+=("--ask-pass")
            [[ -n "$MDB_HOST" ]] && CHILD_ARGS+=("--host" "$MDB_HOST")
            [[ -n "$MDB_PORT" ]] && CHILD_ARGS+=("--port" "$MDB_PORT")
            [[ -n "$MDB_SOCKET" ]] && CHILD_ARGS+=("--socket" "$MDB_SOCKET")
            [[ -n "$MDB_DEFAULTS_FILE" ]] && CHILD_ARGS+=("--defaults-file" "$MDB_DEFAULTS_FILE")
            [[ -n "$MDB_CONFIG" ]] && CHILD_ARGS+=("--config" "$MDB_CONFIG")
            [[ -n "$MDB_ADMIN_USERS" ]] && CHILD_ARGS+=("--admin-users" "$MDB_ADMIN_USERS")
            [[ -n "$MDB_REPL_USERS" ]] && CHILD_ARGS+=("--repl-users" "$MDB_REPL_USERS")
            [[ -n "$MDB_BACKUP_DIRS" ]] && CHILD_ARGS+=("--backup-dirs" "$MDB_BACKUP_DIRS")
            ;;
        apache)
            [[ -n "$APACHE_PREFIX" ]] && CHILD_ARGS+=("--prefix" "$APACHE_PREFIX")
            [[ -n "$APACHE_CONFIG" ]] && CHILD_ARGS+=("--config" "$APACHE_CONFIG")
            [[ -n "$APACHE_BINARY" ]] && CHILD_ARGS+=("--binary" "$APACHE_BINARY")
            [[ -n "$APACHE_DOCROOT" ]] && CHILD_ARGS+=("--docroot" "$APACHE_DOCROOT")
            ;;
        nginx)
            [[ -n "$NGINX_CONFIG_DIR" ]] && CHILD_ARGS+=("--config-dir" "$NGINX_CONFIG_DIR")
            [[ -n "$NGINX_BINARY" ]] && CHILD_ARGS+=("--binary" "$NGINX_BINARY")
            [[ -n "$NGINX_PORTS" ]] && CHILD_ARGS+=("--ports" "$NGINX_PORTS")
            ;;
    esac

    if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
        CHILD_ARGS+=("${EXTRA_ARGS[@]}")
    fi
}

execute_audit_script() {
    local target_key="$1"
    local script_name="$2"
    local display_name="$3"

    build_child_args "$target_key"

    echo -e "\n${C_CYAN}${C_BOLD}[*] Launching ${display_name} (${script_name})...${C_RESET}"
    echo -e "${C_DIM}    Active Flags: ${CHILD_ARGS[*]}${C_RESET}"

    # 1. Check if script exists in local SCRIPT_DIR or current working directory
    local local_path=""
    if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/${script_name}" ]]; then
        local_path="${SCRIPT_DIR}/${script_name}"
    elif [[ -f "./${script_name}" ]]; then
        local_path="./${script_name}"
    fi

    if [[ -n "$local_path" ]]; then
        echo -e "${C_DIM}    Source: Local file (${local_path})${C_RESET}"
        run_with_tty bash "$local_path" "${CHILD_ARGS[@]}"
        return $?
    fi

    # 2. Otherwise download from GitHub repository into a temporary file and execute
    local candidate_urls=(
        "${REPO_BASE_URL}/${script_name}"
        "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/${script_name}"
        "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/master/${script_name}"
        "https://github.com/${REPO_OWNER}/${REPO_NAME}/raw/main/${script_name}"
    )

    local tmp_script
    tmp_script="$(mktemp "/tmp/${script_name}.XXXXXX" 2>/dev/null || echo "/tmp/${script_name}.$$")"
    local downloaded=0
    local url

    for url in "${candidate_urls[@]}"; do
        echo -e "${C_DIM}    Fetching: ${url}${C_RESET}"
        if command -v curl >/dev/null 2>&1; then
            if curl -fsSL "$url" -o "$tmp_script" 2>/dev/null && [[ -s "$tmp_script" ]] && head -n 1 "$tmp_script" | grep -q "bash"; then
                downloaded=1
                break
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -qO "$tmp_script" "$url" 2>/dev/null && [[ -s "$tmp_script" ]] && head -n 1 "$tmp_script" | grep -q "bash"; then
                downloaded=1
                break
            fi
        else
            echo -e "${C_RED}[!] Error: Neither 'curl' nor 'wget' is installed to download ${script_name}.${C_RESET}" >&2
            rm -f "$tmp_script"
            return 1
        fi
    done

    if [[ "$downloaded" -eq 0 ]]; then
        echo -e "${C_RED}[!] Failed to download ${script_name} from GitHub (${REPO_BASE_URL}/${script_name}).${C_RESET}" >&2
        echo -e "${C_YELLOW}    Ensure the repository is public and reachable, or set CIS_AUDIT_REPO_URL.${C_RESET}" >&2
        rm -f "$tmp_script"
        return 1
    fi

    chmod +x "$tmp_script" 2>/dev/null || true
    local rc=0
    run_with_tty bash "$tmp_script" "${CHILD_ARGS[@]}" || rc=$?
    rm -f "$tmp_script"
    return "$rc"
}

run_direct_target() {
    local opt="$1"
    reset_active_options
    case "${opt,,}" in
        1|ubuntu|ubuntu-26.04|ubuntu26|ubuntu2604|26.04)
            execute_audit_script "ubuntu" "$SCRIPT_UBUNTU" "CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0"
            ;;
        2|ubuntu-24.04|ubuntu24|ubuntu2404|24.04)
            execute_audit_script "ubuntu2404" "$SCRIPT_UBUNTU_2404" "CIS Ubuntu Linux 24.04 LTS Benchmark v2.0.0"
            ;;
        3|mariadb|mysql)
            execute_audit_script "mariadb" "$SCRIPT_MARIADB" "CIS MariaDB 10.6 Benchmark v1.1.0"
            ;;
        4|apache|httpd)
            execute_audit_script "apache" "$SCRIPT_APACHE" "CIS Apache HTTP Server 2.4 Benchmark v2.4.0"
            ;;
        5|nginx)
            execute_audit_script "nginx" "$SCRIPT_NGINX" "CIS NGINX Benchmark v3.0.0"
            ;;
        6|all)
            execute_audit_script "ubuntu" "$SCRIPT_UBUNTU" "CIS Ubuntu Linux 26.04 LTS Benchmark v1.0.0"
            execute_audit_script "ubuntu2404" "$SCRIPT_UBUNTU_2404" "CIS Ubuntu Linux 24.04 LTS Benchmark v2.0.0"
            execute_audit_script "mariadb" "$SCRIPT_MARIADB" "CIS MariaDB 10.6 Benchmark v1.1.0"
            execute_audit_script "apache" "$SCRIPT_APACHE" "CIS Apache HTTP Server 2.4 Benchmark v2.4.0"
            execute_audit_script "nginx" "$SCRIPT_NGINX" "CIS NGINX Benchmark v3.0.0"
            ;;
        *)
            return 2
            ;;
    esac
    return 0
}

post_audit_prompt() {
    if [[ "$RUN_ONCE" -eq 1 ]]; then
        return 1
    fi
    echo ""
    local cont=""
    if ! prompt_input "${C_BOLD}${C_YELLOW}Press [Enter] to return to the main menu, or [0/q] to exit: ${C_RESET}" cont; then
        echo ""
        return 1
    fi
    if [[ "${cont,,}" == "0" || "${cont,,}" == "q" || "${cont,,}" == "exit" ]]; then
        echo -e "${C_GREEN}[*] Exiting CIS Benchmark Security Audit Launcher.${C_RESET}"
        return 1
    fi
    return 0
}

interactive_loop() {
    reset_active_options

    while true; do
        clear_screen
        print_launcher_banner
        print_main_menu
        local choice=""
        if ! prompt_input "${C_BOLD}${C_CYAN}Select an audit code [1-6, or 0 to exit]: ${C_RESET}" choice; then
            echo ""
            break
        fi
        choice="$(echo "$choice" | xargs)"

        local menu_rc=0
        case "${choice,,}" in
            1|ubuntu|ubuntu-26.04|ubuntu26|26.04)
                menu_audit_ubuntu_2604 || menu_rc=$?
                ;;
            2|ubuntu-24.04|ubuntu24|24.04)
                menu_audit_ubuntu_2404 || menu_rc=$?
                ;;
            3|mariadb|mysql)
                menu_audit_mariadb || menu_rc=$?
                ;;
            4|apache|httpd)
                menu_audit_apache || menu_rc=$?
                ;;
            5|nginx)
                menu_audit_nginx || menu_rc=$?
                ;;
            6|all)
                menu_audit_all || menu_rc=$?
                ;;
            0|q|exit|quit)
                echo -e "${C_GREEN}[*] Exiting CIS Benchmark Security Audit Launcher.${C_RESET}"
                break
                ;;
            "")
                continue
                ;;
            *)
                echo -e "${C_RED}[!] Invalid selection '${choice}'. Please select audit code 1-6, or 0 to exit.${C_RESET}"
                sleep 1
                continue
                ;;
        esac

        if [[ "$menu_rc" -eq 1 ]]; then
            echo ""
            break
        elif [[ "$menu_rc" -eq 0 ]]; then
            post_audit_prompt || break
        fi
    done
}

main() {
    parse_args "$@"
    reset_active_options

    if [[ -n "$CLI_TARGET" ]]; then
        print_launcher_banner
        if ! run_direct_target "$CLI_TARGET"; then
            echo -e "${C_RED}[!] Unknown audit target: ${CLI_TARGET}${C_RESET}" >&2
            usage >&2
            exit 1
        fi
        exit 0
    fi

    interactive_loop
}

main "$@"