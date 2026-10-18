#!/usr/bin/env bash
# ==============================================================================
# CIS MariaDB 10.6 Benchmark v1.1.0 - Standalone Security Audit Script
# Benchmark:   CIS MariaDB 10.6 Benchmark v1.1.0 (03-29-2024)
# Coverage:    All 74 Recommendations (Sections 1 through 9, Level 1 & Level 2)
# Repository:  https://github.com/nmwafa/cis-audit
# ==============================================================================

set -u

VERSION="1.1.0"
BENCHMARK_NAME="CIS MariaDB 10.6 Benchmark v1.1.0"
BENCHMARK_CONTROLS="74 Controls (Sections 1-9)"
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
HOSTNAME_VAL="$(hostname 2>/dev/null || uname -n)"

# ------------------------------------------------------------------------------
# CLI Options & Defaults
# ------------------------------------------------------------------------------
DB_USER=""
DB_PASS=""
DB_HOST=""
DB_PORT=""
DB_SOCKET=""
DEFAULTS_FILE=""
CUSTOM_CNF=""
PROFILE_LEVEL="all"        # 1, 2, or all
TARGET_SECTION="all"       # 1..9 or all
ADMIN_USERS="root,mysql,mariadb.sys"
REPL_USERS="repl,replica,slave"
BACKUP_DIRS="/var/backups,/backup,/backups,/srv/backup,/mnt/backup,/opt/backup"
OUTPUT_FILE=""
USE_COLOR=1
FORCE_COLOR="${FORCE_COLOR:-0}"
PROMPT_PASS=0
QUIET_OK=0

usage() {
    cat <<EOF
Usage: ./$SCRIPT_NAME [OPTIONS]

Standalone, zero-install Bash script to audit a MariaDB 10.6 server against
all 74 recommendations in the CIS MariaDB 10.6 Benchmark v1.1.0.

Options:
  -l, --level <1|2|all>      Filter by CIS Profile Level (default: all)
  -s, --section <1..9|all>   Audit only a specific section (1-9) (default: all)
  -u, --user USER            MariaDB username for SQL audit queries
  -p, --password PASS        MariaDB password (prefer -W or --defaults-file)
  -W, --ask-pass             Prompt interactively for MariaDB password
  -H, --host HOST            MariaDB host (default: local socket)
  -P, --port PORT            MariaDB port (default: 3306)
  -S, --socket SOCKET        Path to MariaDB unix socket file
  -d, --defaults-file FILE   Path to MariaDB client defaults file (e.g., ~/.my.cnf)
  -c, --config FILE          Path to primary MariaDB configuration file (e.g., /etc/mysql/mariadb.cnf)
  -a, --admin-users LIST     Comma-separated list of authorized DB admin users (default: root,mysql,mariadb.sys)
  -r, --repl-users LIST      Comma-separated list of authorized replication users (default: repl,replica,slave)
  -b, --backup-dirs LIST     Comma-separated list of backup directories to inspect
  -o, --output <file>        Save full audit report to a file
  -q, --quiet-ok             Hide [OK] results and only show findings/remediations
  -n, --no-color             Disable ANSI color output
      --color                Force ANSI color output even when piped
  -h, --help                 Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--level) PROFILE_LEVEL="${2:-all}"; shift 2 ;;
        -s|--section) TARGET_SECTION="${2:-all}"; shift 2 ;;
        -u|--user) DB_USER="${2:-}"; shift 2 ;;
        -p|--password) DB_PASS="${2:-}"; shift 2 ;;
        -W|--ask-pass) PROMPT_PASS=1; shift ;;
        -H|--host) DB_HOST="${2:-}"; shift 2 ;;
        -h)
            if [[ $# -ge 2 && "${2:-}" != -* ]]; then
                DB_HOST="${2:-}"
                shift 2
            else
                usage
                exit 0
            fi
            ;;
        -P|--port) DB_PORT="${2:-}"; shift 2 ;;
        -S|--socket) DB_SOCKET="${2:-}"; shift 2 ;;
        -d|--defaults-file) DEFAULTS_FILE="${2:-}"; shift 2 ;;
        -c|--config) CUSTOM_CNF="${2:-}"; shift 2 ;;
        -a|--admin-users) ADMIN_USERS="${2:-}"; shift 2 ;;
        -r|--repl-users) REPL_USERS="${2:-}"; shift 2 ;;
        -b|--backup-dirs) BACKUP_DIRS="${2:-}"; shift 2 ;;
        -o|--output) OUTPUT_FILE="${2:-}"; shift 2 ;;
        -q|--quiet-ok) QUIET_OK=1; shift ;;
        -n|--no-color) USE_COLOR=0; FORCE_COLOR=0; shift ;;
        --color) USE_COLOR=1; FORCE_COLOR=1; shift ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
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
DB_CONN_STATUS=""

declare -A SEC_OK=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0 [8]=0 [9]=0)
declare -A SEC_FAIL=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0 [8]=0 [9]=0)
declare -A SEC_MANUAL=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0 [8]=0 [9]=0)
declare -A SEC_SKIP=([1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0 [8]=0 [9]=0)

setup_colors_and_init() {
    PROFILE_LEVEL="$(normalize_profile_filter "$PROFILE_LEVEL")"
    setup_colors
    if [[ "$PROMPT_PASS" -eq 1 ]]; then
        if ( : < /dev/tty ) 2>/dev/null; then
            read -r -s -p "Enter MariaDB password: " DB_PASS < /dev/tty
            echo ""
        else
            read -r -s -p "Enter MariaDB password: " DB_PASS
            echo ""
        fi
    fi
    if [[ -n "$OUTPUT_FILE" ]]; then
        exec > >(tee "$OUTPUT_FILE") 2>&1
    fi
}

print_warning() {
    if [[ ${#CNF_FILES[@]} -gt 0 ]]; then
        echo -e "\n${C_BOLD}Config Files:${C_RESET}   ${#CNF_FILES[@]} file(s) (${CNF_FILES[*]})"
    else
        echo -e "\n${C_BOLD}Config Files:${C_RESET}   ${C_YELLOW}None detected in standard paths (/etc/mysql, /etc/my.cnf)${C_RESET}"
    fi
    if [[ "$(id -u 2>/dev/null || echo 1)" -ne 0 ]]; then
        echo -e "\n${C_YELLOW}[!] WARNING: Script is not running as root (UID 0). Some filesystem and OS checks require root privileges for accurate results.${C_RESET}"
    fi
}

# ==============================================================================
# Environment, Configuration & Database Discovery
# ==============================================================================

SQL_CLI=""
DB_CONNECTED=0
CNF_FILES=()

discover_environment() {

    # Locate MariaDB / MySQL client binary
    if command -v mariadb >/dev/null 2>&1; then
        SQL_CLI="mariadb"
    elif command -v mysql >/dev/null 2>&1; then
        SQL_CLI="mysql"
    fi

    # Locate MariaDB Configuration files
    local candidate_dirs=("/etc/mysql" "/etc/my.cnf.d" "/usr/local/mysql/etc" "/opt/mariadb/etc")
    local candidate_files=("/etc/my.cnf" "/etc/mysql/my.cnf" "/etc/mysql/mariadb.cnf" "/usr/local/etc/my.cnf")

    if [[ -n "$CUSTOM_CNF" && -f "$CUSTOM_CNF" ]]; then
        CNF_FILES+=("$CUSTOM_CNF")
    fi

    for f in "${candidate_files[@]}"; do
        [[ -f "$f" ]] && CNF_FILES+=("$f")
    done

    for d in "${candidate_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            while IFS= read -r -d '' cf; do
                CNF_FILES+=("$cf")
            done < <(find "$d" -maxdepth 3 -type f -name "*.cnf" -print0 2>/dev/null)
        fi
    done

    # Deduplicate CNF_FILES
    if [[ ${#CNF_FILES[@]} -gt 0 ]]; then
        mapfile -t CNF_FILES < <(printf "%s\n" "${CNF_FILES[@]}" | awk '!seen[$0]++')
    fi

    # Build SQL client arguments
    SQL_ARGS=("-N" "-B" "--connect-timeout=5")
    [[ -n "$DEFAULTS_FILE" ]] && SQL_ARGS=("--defaults-file=$DEFAULTS_FILE" "${SQL_ARGS[@]}")
    [[ -n "$DB_USER" ]] && SQL_ARGS+=("-u" "$DB_USER")
    [[ -n "$DB_HOST" ]] && SQL_ARGS+=("-h" "$DB_HOST")
    [[ -n "$DB_PORT" ]] && SQL_ARGS+=("-P" "$DB_PORT")
    [[ -n "$DB_SOCKET" ]] && SQL_ARGS+=("-S" "$DB_SOCKET")

    # Test DB connection
    if [[ -n "$SQL_CLI" ]]; then
        if [[ -n "$DB_PASS" ]]; then
            if MYSQL_PWD="$DB_PASS" "$SQL_CLI" "${SQL_ARGS[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
                DB_CONNECTED=1
            fi
        else
            if "$SQL_CLI" "${SQL_ARGS[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
                DB_CONNECTED=1
            elif command -v sudo >/dev/null 2>&1 && sudo -n "$SQL_CLI" "${SQL_ARGS[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
                SQL_CLI="sudo -n $SQL_CLI"
                DB_CONNECTED=1
            fi
        fi
    fi

    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        DB_CONN_STATUS="${C_GREEN}Connected (Live SQL + OS + Config Audit Active)${C_RESET}"
    else
        DB_CONN_STATUS="${C_YELLOW}Unavailable (Offline Config & OS Heuristics Mode)${C_RESET}"
    fi
}

# Run a SQL query and return output
run_sql() {
    local query="$1"
    if [[ "$DB_CONNECTED" -ne 1 ]]; then
        return 1
    fi
    if [[ -n "$DB_PASS" ]]; then
        MYSQL_PWD="$DB_PASS" $SQL_CLI "${SQL_ARGS[@]}" -e "$query" 2>/dev/null
    else
        $SQL_CLI "${SQL_ARGS[@]}" -e "$query" 2>/dev/null
    fi
}

# Run a SQL query with vertical (\G) output
run_sql_vertical() {
    local query="$1"
    if [[ "$DB_CONNECTED" -ne 1 ]]; then
        return 1
    fi
    if [[ -n "$DB_PASS" ]]; then
        MYSQL_PWD="$DB_PASS" $SQL_CLI "${SQL_ARGS[@]}" -E -e "$query" 2>/dev/null
    else
        $SQL_CLI "${SQL_ARGS[@]}" -E -e "$query" 2>/dev/null
    fi
}

# Search configuration files for a parameter (handles both - and _ in option names)
get_cnf_value() {
    local key="$1"
    local key_regex="${key//[-_]/[-_]}"
    if [[ ${#CNF_FILES[@]} -eq 0 ]]; then
        return 1
    fi
    grep -h -E -i "^[[:space:]]*${key_regex}[[:space:]]*=" "${CNF_FILES[@]}" 2>/dev/null | tail -n 1 | sed -E 's/^[^=]+=[[:space:]]*//; s/[[:space:]]*(#.*)?$//; s/^["'\'']//; s/["'\'']$//'
}

# Check if a key exists as a standalone flag or key=value in config files
has_cnf_key() {
    local key="$1"
    local key_regex="${key//[-_]/[-_]}"
    if [[ ${#CNF_FILES[@]} -eq 0 ]]; then
        return 1
    fi
    grep -q -E -i "^[[:space:]]*${key_regex}([[:space:]]*=|[[:space:]]*$)" "${CNF_FILES[@]}" 2>/dev/null
}

# Get MariaDB Global Variable (Live SQL first, fallback to config file)
get_mariadb_var() {
    local var_name="$1"
    local val=""
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        val="$(run_sql "SELECT VARIABLE_VALUE FROM information_schema.global_variables WHERE VARIABLE_NAME = '${var_name}';")"
        if [[ -n "$val" ]]; then
            echo "$val"
            return 0
        fi
    fi
    val="$(get_cnf_value "$var_name")"
    if [[ -n "$val" ]]; then
        echo "$val"
        return 0
    fi
    return 1
}

# Convert SQL comma list ("root,mysql") into SQL IN clause ("'root','mysql'")
to_sql_in_list() {
    local csv="$1"
    echo "$csv" | awk -F',' '{for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$/,"",$i); printf "%s'\''%s'\''",(i>1?",":""),$i}}'
}

# Check numeric octal permission constraint: returns 0 if actual_octal is <= max_octal bitwise
is_perm_compliant() {
    local actual="$1"
    local max_allowed="$2"
    local a_dec=$((8#$actual))
    local m_dec=$((8#$max_allowed))
    # Any bit set in actual that is NOT set in max_allowed is a violation
    if (( (a_dec & ~m_dec) == 0 )); then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# SECTION 1: Operating System Level Configuration
# ==============================================================================

audit_section_1() {
    print_section_header "1" "Operating System Level Configuration" || return 0

    # --------------------------------------------------------------------------
    # 1.1 Place Databases on Non-System Partitions (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local datadir_val=""
    datadir_val="$(get_mariadb_var "datadir")"
    [[ -z "$datadir_val" ]] && datadir_val="/var/lib/mysql"

    if [[ -d "$datadir_val" ]]; then
        local mount_pt=""
        mount_pt="$(df -P "$datadir_val" 2>/dev/null | awk 'NR==2 {print $6}')"
        if [[ -n "$mount_pt" && "$mount_pt" != "/" && "$mount_pt" != "/var" && "$mount_pt" != "/usr" ]]; then
            report_result "1.1" "Place Databases on Non-System Partitions" 1 "Manual" "OK" \
                "datadir ($datadir_val) is mounted on non-system partition '$mount_pt'." ""
        else
            report_result "1.1" "Place Databases on Non-System Partitions" 1 "Manual" "FAIL" \
                "datadir ($datadir_val) resides on a system partition (mount point: '${mount_pt:-unknown}', which is /, /var, or /usr)." \
                "1. Backup the database.
2. Choose a non-system partition new location for MariaDB data (not /, /var, or /usr).
3. Stop mariadbd: sudo service mariadb stop
4. Copy the data: sudo cp -rp ${datadir_val} <new_location>
5. Set 'datadir = <new_location>' in the MariaDB configuration file (and update AppArmor /etc/apparmor.d/usr.sbin.mariadbd if used).
6. Start mariadbd: sudo service mariadb start"
        fi
    else
        report_result "1.1" "Place Databases on Non-System Partitions" 1 "Manual" "FAIL" \
            "datadir ($datadir_val) directory was not found on the local filesystem." \
            "1. Ensure MariaDB datadir is placed on a dedicated non-system partition (not /, /var, or /usr).
2. Configure 'datadir = <new_location>' in the MariaDB configuration file and restart MariaDB."
    fi

    # --------------------------------------------------------------------------
    # 1.2 Use Dedicated Least Privileged Account for MariaDB Daemon/Service (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local mysql_procs=""
    local root_mysqld=""
    mysql_procs="$(ps -ef 2>/dev/null | grep -E "^mysql.*$" || true)"
    root_mysqld="$(ps -ef 2>/dev/null | grep -E "^root.*(mariadbd|mysqld)" | grep -v "mysqld_safe" | grep -v "grep" || true)"

    if [[ -n "$mysql_procs" && -z "$root_mysqld" ]]; then
        report_result "1.2" "Use Dedicated Least Privileged Account for MariaDB Daemon/Service" 1 "Automated" "OK" \
            "MariaDB daemon is running under dedicated least-privileged account 'mysql'." ""
    else
        local cnf_user=""
        cnf_user="$(get_cnf_value "user" || true)"
        report_result "1.2" "Use Dedicated Least Privileged Account for MariaDB Daemon/Service" 1 "Automated" "FAIL" \
            "No running process matched '^mysql.*$' (or mariadbd is running as root). Config user='${cnf_user:-not set}'." \
            "Create a dedicated least-privileged user/group without shell access and configure MariaDB to run as 'mysql':
  sudo /usr/sbin/groupadd -g 27 -o -r mysql >/dev/null 2>&1 || :
  sudo /usr/sbin/useradd -M -N -g mysql -o -r -d /var/lib/mysql -s /bin/false -c 'MariaDB Server' -u 27 mysql >/dev/null 2>&1 || :
Ensure 'user = mysql' is set under [mysqld]/[mariadbd] in mariadb.cnf and restart the service."
    fi

    # --------------------------------------------------------------------------
    # 1.3 Disable MariaDB Command History (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local bad_hist=()
    while IFS= read -r -d '' hfile; do
        local target=""
        target="$(readlink -f "$hfile" 2>/dev/null || true)"
        if [[ "$target" != "/dev/null" ]]; then
            bad_hist+=("$hfile")
        fi
    done < <(find /home /root -name ".mysql_history" -print0 2>/dev/null)

    if [[ ${#bad_hist[@]} -eq 0 ]]; then
        report_result "1.3" "Disable MariaDB Command History" 2 "Automated" "OK" \
            "No unlinked .mysql_history files found in /home or /root." ""
    else
        report_result "1.3" "Disable MariaDB Command History" 2 "Automated" "FAIL" \
            "Found .mysql_history file(s) not symbolically linked to /dev/null: ${bad_hist[*]}" \
            "1. Remove existing .mysql_history files: rm -f /root/.mysql_history /home/*/.mysql_history
2. Prevent creation by symlinking to /dev/null for each user:
   ln -s /dev/null \$HOME/.mysql_history
   Or export MYSQL_HISTFILE=/dev/null in the shell's startup script (/etc/profile)."
    fi

    # --------------------------------------------------------------------------
    # 1.4 Verify That the MYSQL_PWD Environment Variable is Not in Use (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local pwd_procs=()
    for env_file in /proc/[0-9]*/environ; do
        [[ -r "$env_file" ]] || continue
        local pid_num="${env_file#/proc/}"
        pid_num="${pid_num%/environ}"
        [[ "$pid_num" == "$$" || "$pid_num" == "$PPID" ]] && continue
        if tr '\0' '\n' < "$env_file" 2>/dev/null | grep -q "^MYSQL_PWD="; then
            pwd_procs+=("PID:$pid_num")
        fi
    done

    if [[ ${#pwd_procs[@]} -eq 0 ]]; then
        report_result "1.4" "Verify That the MYSQL_PWD Environment Variable is Not in Use" 1 "Automated" "OK" \
            "MYSQL_PWD is not set in any running process environment (/proc/*/environ)." ""
    else
        report_result "1.4" "Verify That the MYSQL_PWD Environment Variable is Not in Use" 1 "Automated" "FAIL" \
            "MYSQL_PWD environment variable is in use by process(es): ${pwd_procs[*]}" \
            "Check which users and/or scripts are setting MYSQL_PWD and change them to use a more secure authentication method (e.g., X.509 certificate verification, unix_socket, or restricted ~/.mariadb.cnf)."
    fi

    # --------------------------------------------------------------------------
    # 1.5 Ensure Interactive Login is Disabled (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local mysql_passwd=""
    mysql_passwd="$(getent passwd mysql 2>/dev/null || true)"
    if [[ -n "$mysql_passwd" ]] && echo "$mysql_passwd" | grep -q -E "(/bin/false|/sbin/nologin|/usr/sbin/nologin)$"; then
        report_result "1.5" "Ensure Interactive Login is Disabled" 2 "Automated" "OK" \
            "mysql user shell is non-interactive (${mysql_passwd##*:})." ""
    else
        report_result "1.5" "Ensure Interactive Login is Disabled" 2 "Automated" "FAIL" \
            "mysql account either does not exist or has an interactive shell: '${mysql_passwd:-user mysql not found}'." \
            "Disable interactive login for the mysql user by running one of the following commands:
  sudo usermod -s /bin/false mysql
  # Or:
  sudo usermod -s /sbin/nologin mysql"
    fi

    # --------------------------------------------------------------------------
    # 1.6 Verify That 'MYSQL_PWD' is Not Set in Users' Profiles (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local profile_hits=""
    profile_hits="$(grep -H "MYSQL_PWD" /home/*/.bashrc /home/*/.profile /home/*/.bash_profile /root/.bashrc /root/.profile /root/.bash_profile /etc/profile /etc/bash.bashrc 2>/dev/null || true)"
    if [[ -z "$profile_hits" ]]; then
        report_result "1.6" "Verify That 'MYSQL_PWD' is Not Set in Users' Profiles" 1 "Automated" "OK" \
            "MYSQL_PWD was not found in any user shell profile scripts." ""
    else
        report_result "1.6" "Verify That 'MYSQL_PWD' is Not Set in Users' Profiles" 1 "Automated" "FAIL" \
            "MYSQL_PWD found in profile script(s): $(echo "$profile_hits" | tr '\n' ' ')" \
            "Remove MYSQL_PWD definitions from user profile scripts (.bashrc, .profile, .bash_profile) and switch to a secure credential mechanism."
    fi

    # --------------------------------------------------------------------------
    # 1.7 Ensure MariaDB is Run Under a Sandbox Environment (Manual) [Level 2]
    # --------------------------------------------------------------------------
    local chroot_val=""
    chroot_val="$(get_mariadb_var "chroot" || true)"
    local systemd_ok=0
    local systemd_info=""
    if command -v systemctl >/dev/null 2>&1; then
        systemd_info="$(systemctl status mariadb.service mysqld.service 2>/dev/null | grep -E "Main PID:" || true)"
        if [[ -n "$systemd_info" ]] && ! echo "$systemd_info" | grep -q "(root)"; then
            systemd_ok=1
        fi
    fi
    local docker_ok=0
    if [[ -f "/.dockerenv" ]] || grep -q -E "(docker|containerd|kubepods)" /proc/1/cgroup 2>/dev/null; then
        docker_ok=1
    elif command -v docker >/dev/null 2>&1 && docker ps 2>/dev/null | grep -q -i "mariadb"; then
        docker_ok=1
    fi

    if [[ ( -n "$chroot_val" && "$chroot_val" != "$datadir_val" ) || "$systemd_ok" -eq 1 || "$docker_ok" -eq 1 ]]; then
        report_result "1.7" "Ensure MariaDB is Run Under a Sandbox Environment" 2 "Manual" "OK" \
            "Sandbox environment detected (chroot='${chroot_val:-none}', systemd_isolated=${systemd_ok}, docker=${docker_ok})." ""
    else
        report_result "1.7" "Ensure MariaDB is Run Under a Sandbox Environment" 2 "Manual" "FAIL" \
            "MariaDB is not verified to run under chroot, non-root systemd service, or Docker container." \
            "Perform one of the following to run MariaDB in a sandbox environment:
- Configure chroot: Add 'chroot=<chroot_location>' to my.cnf on a non-system partition.
- Configure systemd: Create/modify /lib/systemd/system/mariadb.service with User=mysql and Group=mysql under [Service], then run:
    sudo systemctl daemon-reload && sudo systemctl enable --now mariadb.service
- Run in Docker: Use an official MariaDB container without MARIADB_ALLOW_EMPTY_ROOT_PASSWORD or plaintext password args."
    fi
}

# ==============================================================================
# SECTION 2: Installation and Planning
# ==============================================================================

audit_section_2() {
    print_section_header "2" "Installation and Planning" || return 0

    # --------------------------------------------------------------------------
    # 2.1.1 Backup Policy in Place (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local cron_backups=""
    cron_backups="$(grep -R -i -E "(mariabackup|mysqldump|mydumper|xtrabackup|mysqlbackup)" /etc/crontab /etc/cron.* /var/spool/cron 2>/dev/null || true)"
    if [[ -z "$cron_backups" ]]; then
        cron_backups="$(crontab -l 2>/dev/null | grep -i -E "(mariabackup|mysqldump|mydumper|xtrabackup)" || true)"
    fi
    if [[ -n "$cron_backups" ]]; then
        report_result "2.1.1" "Backup Policy in Place" 1 "Manual" "OK" \
            "Scheduled backup job detected in cron: $(echo "$cron_backups" | head -n 1)" ""
    else
        report_result "2.1.1" "Backup Policy in Place" 1 "Manual" "MANUAL" \
            "No automated backup schedule (mariabackup/mysqldump) was detected in crontab or /etc/cron*." \
            "Create a formal backup policy and configure an automated backup schedule (e.g., via crontab -e or systemd timers) covering all databases including 'mysql'."
    fi

    # --------------------------------------------------------------------------
    # 2.1.2 Verify Backups are Good (Manual) [Level 1]
    # --------------------------------------------------------------------------
    report_result "2.1.2" "Verify Backups are Good" 1 "Manual" "MANUAL" \
        "Requires manual verification of backup validation test reports and restoration drill logs." \
        "Implement regular backup validation checks (e.g., test restores using 'mariabackup --prepare' and verification on a staging instance) and document each check."

    # --------------------------------------------------------------------------
    # 2.1.3 Secure Backup Credentials (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local insecure_cnf=()
    for cf in "${CNF_FILES[@]}" /root/.my.cnf /root/.mariadb.cnf /home/*/.my.cnf /home/*/.mariadb.cnf; do
        [[ -f "$cf" ]] || continue
        if grep -q -E -i "^[[:space:]]*password[[:space:]]*=" "$cf" 2>/dev/null; then
            local perm=""
            perm="$(stat -c "%a" "$cf" 2>/dev/null || true)"
            if [[ -n "$perm" ]] && ! is_perm_compliant "$perm" "600"; then
                insecure_cnf+=("$cf (mode $perm)")
            fi
        fi
    done

    if [[ ${#insecure_cnf[@]} -gt 0 ]]; then
        report_result "2.1.3" "Secure Backup Credentials" 1 "Manual" "FAIL" \
            "Files containing credentials have overly permissive permissions: ${insecure_cnf[*]}" \
            "Use a dedicated least-privilege backup database user and restrict permissions on files containing passwords or SSL keys:
  chmod 600 <credential_or_key_file>
  chown <backup_user>:<backup_group> <credential_or_key_file>"
    else
        report_result "2.1.3" "Secure Backup Credentials" 1 "Manual" "MANUAL" \
            "No world/group-readable credential files found in standard paths; manually verify any custom backup scripts/certificates." \
            "Ensure the database backup user has minimal required privileges and restrict permissions (chmod 600 / 400) on all files containing backup passwords or SSL keys."
    fi

    # --------------------------------------------------------------------------
    # 2.1.4 The Backups Should be Properly Secured (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local world_readable_backups=()
    IFS=',' read -r -a bdirs <<< "$BACKUP_DIRS"
    for bd in "${bdirs[@]}"; do
        [[ -d "$bd" ]] || continue
        while IFS= read -r -d '' bf; do
            local bperm=""
            bperm="$(stat -c "%a" "$bf" 2>/dev/null || true)"
            if [[ -n "$bperm" ]] && ! is_perm_compliant "$bperm" "640"; then
                world_readable_backups+=("$bf (mode $bperm)")
            fi
        done < <(find "$bd" -maxdepth 3 -type f \( -name "*.sql*" -o -name "*.xb*" -o -name "*backup*" \) -print0 2>/dev/null)
    done

    if [[ ${#world_readable_backups[@]} -gt 0 ]]; then
        report_result "2.1.4" "The Backups Should be Properly Secured" 1 "Manual" "FAIL" \
            "Found backup files with overly permissive (world-readable) permissions: ${world_readable_backups[*]}" \
            "Encrypt backups and restrict filesystem permissions on backup files and directories:
  mariabackup --defaults-file=/home/dbadmin/my.cnf --backup --stream=xbstream | openssl enc -aes-256-cbc -k <strong_pass> > backup.xb.enc
  chmod 600 backup.xb.enc"
    else
        report_result "2.1.4" "The Backups Should be Properly Secured" 1 "Manual" "MANUAL" \
            "No world-readable backup files detected in (${BACKUP_DIRS}). Verify backup encryption, key storage, and offsite access controls." \
            "Ensure backup files are not world-readable, group ownership is mysql/backup-specific (or not group-readable), backups are encrypted (e.g., AES-256-CBC), and encryption keys are stored separately."
    fi

    # --------------------------------------------------------------------------
    # 2.1.5 Point-in-Time Recovery (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local log_bin_val=""
    local binlog_exp_val=""
    log_bin_val="$(get_mariadb_var "log_bin" || true)"
    binlog_exp_val="$(get_mariadb_var "binlog_expire_logs_seconds" || true)"

    if [[ "$log_bin_val" =~ ^(ON|1)$ ]] && [[ -n "$binlog_exp_val" && "$binlog_exp_val" != "0" ]]; then
        report_result "2.1.5" "Point-in-Time Recovery" 2 "Automated" "OK" \
            "log_bin is enabled ($log_bin_val) and binlog_expire_logs_seconds is set to $binlog_exp_val." ""
    else
        report_result "2.1.5" "Point-in-Time Recovery" 2 "Automated" "FAIL" \
            "log_bin='${log_bin_val:-OFF/unset}', binlog_expire_logs_seconds='${binlog_exp_val:-0/unset}' (must be enabled and non-zero)." \
            "1. Enable binary logging and set log expiration in mariadb.cnf under [mariadbd]:
   log_bin = /path/to/non-system-partition/mariadb-bin
   binlog_expire_logs_seconds = 604800
2. Back up binlogs to separate media and create/test a point-in-time restore procedure."
    fi

    # --------------------------------------------------------------------------
    # 2.1.6 Disaster Recovery (DR) Plan (Manual) [Level 1]
    # --------------------------------------------------------------------------
    report_result "2.1.6" "Disaster Recovery (DR) Plan" 1 "Manual" "MANUAL" \
        "Requires organizational verification of documented Disaster Recovery (DR) plan and RTO." \
        "Create and formalize a Disaster Recovery (DR) plan defining Recovery Time Objective (RTO), offsite backups, replica/Galera cluster failover capacity, and network/at-rest encryption."

    # --------------------------------------------------------------------------
    # 2.1.7 Backup of Configuration and Related Files (Manual) [Level 1]
    # --------------------------------------------------------------------------
    report_result "2.1.7" "Backup of Configuration and Related Files" 1 "Manual" "MANUAL" \
        "Requires verification that configuration, key management, audit logs, SSL certs/keys, and UDFs are included in backups." \
        "Ensure backup procedures include:
- Edited configuration files (mariadb.cnf and included files)
- Key Management and Keyring files (KMIP / file_key_management files)
- Audit Log files (if not shipped externally)
- SSL files (certificates and keys)
- User Defined Functions (UDFs) and custom source code."

    # --------------------------------------------------------------------------
    # 2.2 Dedicate the Machine Running MariaDB (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local non_db_services=""
    non_db_services="$(ps -eo comm= 2>/dev/null | grep -E "^(apache2|httpd|nginx|lighttpd|postfix|exim4|sendmail|named|vsftpd|proftpd|smbd|nmbd|cupsd|dockerd|kubelet)$" | sort -u | tr '\n' ' ' || true)"
    if [[ -n "$non_db_services" ]]; then
        report_result "2.2" "Dedicate the Machine Running MariaDB" 1 "Manual" "FAIL" \
            "Detected non-MariaDB server daemons running on this host: ${non_db_services}" \
            "Remove excess applications or services unrelated to MariaDB operation from the underlying operating system."
    else
        report_result "2.2" "Dedicate the Machine Running MariaDB" 1 "Manual" "MANUAL" \
            "No common web/mail/file-sharing daemons detected; manually review installed packages and OS roles." \
            "Verify no other server roles or unrelated applications are enabled on the host running MariaDB."
    fi

    # --------------------------------------------------------------------------
    # 2.3 Do Not Specify Passwords in the Command Line (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local cli_pass_procs=""
    local cli_pass_hist=""
    cli_pass_procs="$(ps -ef 2>/dev/null | grep -E "(mysql|mariadb|mysqldump|mariabackup|mysqladmin).*(-p[^[:space:]]+|--password=)" | grep -v "grep" || true)"
    cli_pass_hist="$(grep -H -E "(mysql|mariadb|mysqldump|mariabackup|mysqladmin)[[:space:]].*(-p[^[:space:]]+|--password=)" /root/.*history /home/*/.*history 2>/dev/null || true)"

    if [[ -z "$cli_pass_procs" && -z "$cli_pass_hist" ]]; then
        report_result "2.3" "Do Not Specify Passwords in the Command Line" 1 "Manual" "OK" \
            "No cleartext passwords found on the command line in process list or shell history files." ""
    else
        report_result "2.3" "Do Not Specify Passwords in the Command Line" 1 "Manual" "FAIL" \
            "Found command-line password usage in process list or shell history files." \
            "Do not pass passwords directly on the command line (e.g., 'mariadb -u admin -p password').
Instead, use '-p' without a password to prompt interactively, use a properly secured ~/.mariadb.cnf (chmod 600), or use ~/.mylogin.cnf."
    fi

    # --------------------------------------------------------------------------
    # 2.4 Do Not Reuse Usernames (Manual) [Level 1]
    # --------------------------------------------------------------------------
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local user_list=""
        user_list="$(run_sql "SELECT host, user, plugin, IF(plugin = 'mysql_native_password', 'WEAK SHA1', 'STRONG SHA2') AS HASHTYPE FROM mysql.user WHERE user NOT IN ('mysql.infoschema', 'mysql.session', 'mysql.sys') AND plugin NOT LIKE 'auth%' AND plugin <> 'mysql_no_login' AND LENGTH(authentication_string) > 0 ORDER BY plugin;" || true)"
        report_result "2.4" "Do Not Reuse Usernames" 1 "Manual" "MANUAL" \
            "Review database user accounts to verify each username is dedicated to a single person, system account, or application: $(echo "$user_list" | tr '\t' ':' | tr '\n' ' ')" \
            "Add or remove database user accounts so that each username is uniquely linked to a single person, application, or system service."
    else
        report_result "2.4" "Do Not Reuse Usernames" 1 "Manual" "SKIP" \
            "Database connection required to enumerate mysql.user accounts." \
            "Connect to MariaDB and ensure each user account is uniquely used for one specific application, person, or system service."
    fi

    # --------------------------------------------------------------------------
    # 2.5 Ensure Non-Default, Unique Cryptographic Material is in Use (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local datadir_val=""
    datadir_val="$(get_mariadb_var "datadir" || true)"
    [[ -z "$datadir_val" ]] && datadir_val="/var/lib/mysql"
    local ssl_cert_file=""
    ssl_cert_file="$(get_mariadb_var "ssl_cert" || true)"
    [[ -z "$ssl_cert_file" && -f "${datadir_val}/server-cert.pem" ]] && ssl_cert_file="${datadir_val}/server-cert.pem"

    if [[ -n "$ssl_cert_file" && -f "$ssl_cert_file" ]] && command -v openssl >/dev/null 2>&1; then
        local cert_subj=""
        cert_subj="$(openssl x509 -in "$ssl_cert_file" -subject -noout 2>/dev/null || true)"
        if echo "$cert_subj" | grep -q "Auto_Generated_Server_Certificate"; then
            report_result "2.5" "Ensure Non-Default, Unique Cryptographic Material is in Use" 1 "Manual" "FAIL" \
                "Server certificate ($ssl_cert_file) is a MariaDB auto-generated default certificate: $cert_subj" \
                "Generate new, unique certificates, keys, and cryptographic material for each MariaDB instance and configure ssl_ca, ssl_cert, and ssl_key in mariadb.cnf."
        else
            report_result "2.5" "Ensure Non-Default, Unique Cryptographic Material is in Use" 1 "Manual" "OK" \
                "Server certificate ($ssl_cert_file) is not auto-generated ($cert_subj). Ensure it is not shared across instances." ""
        fi
    else
        report_result "2.5" "Ensure Non-Default, Unique Cryptographic Material is in Use" 1 "Manual" "FAIL" \
            "No custom server SSL certificate (ssl_cert) was found or configured." \
            "Generate non-default, instance-unique SSL/TLS certificates and keys and configure ssl_cert, ssl_key, and ssl_ca in mariadb.cnf."
    fi

    # --------------------------------------------------------------------------
    # 2.6 Ensure 'password_lifetime' is Less Than or Equal to '365' (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local def_pw_life=""
    def_pw_life="$(get_mariadb_var "default_password_lifetime" || true)"

    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local bad_users_pw=""
        bad_users_pw="$(run_sql "WITH password_expiration_info AS (
            SELECT User, Host,
                IF(IFNULL(JSON_EXTRACT(Priv, '\$.password_lifetime'), -1) = -1,
                   @@global.default_password_lifetime,
                   JSON_EXTRACT(Priv, '\$.password_lifetime')) AS password_lifetime,
                JSON_EXTRACT(Priv, '\$.password_last_changed') AS password_last_changed
            FROM mysql.global_priv
        )
        SELECT CONCAT(User, '@', Host, '(lifetime=', password_lifetime, ')')
        FROM password_expiration_info
        WHERE password_lifetime = 0 OR password_lifetime > 365 OR password_last_changed IS NULL;" || true)"

        if [[ -n "$def_pw_life" && "$def_pw_life" -gt 0 && "$def_pw_life" -le 365 && -z "$bad_users_pw" ]]; then
            report_result "2.6" "Ensure 'password_lifetime' is Less Than or Equal to '365'" 1 "Automated" "OK" \
                "default_password_lifetime=$def_pw_life and all user accounts have password_lifetime between 1 and 365 days." ""
        else
            report_result "2.6" "Ensure 'password_lifetime' is Less Than or Equal to '365'" 1 "Automated" "FAIL" \
                "default_password_lifetime='${def_pw_life:-0}' (0 = never expires) or accounts exceed 365 days / never expire: $(echo "$bad_users_pw" | tr '\n' ' ')" \
                "Configure global password lifetime to 365 days or less:
  SET GLOBAL default_password_lifetime=365;
  (Add 'default_password_lifetime = 365' under [mariadbd] in mariadb.cnf)
And/or set per-user password expiration:
  ALTER USER '<username>'@'<host>' PASSWORD EXPIRE INTERVAL 365 DAY;"
        fi
    else
        if [[ -n "$def_pw_life" && "$def_pw_life" -gt 0 && "$def_pw_life" -le 365 ]]; then
            report_result "2.6" "Ensure 'password_lifetime' is Less Than or Equal to '365'" 1 "Automated" "OK" \
                "default_password_lifetime=$def_pw_life in configuration file." ""
        else
            report_result "2.6" "Ensure 'password_lifetime' is Less Than or Equal to '365'" 1 "Automated" "FAIL" \
                "default_password_lifetime is '${def_pw_life:-not set (defaults to 0 / never expires)}'." \
                "Set 'default_password_lifetime = 365' in mariadb.cnf and run:
  SET GLOBAL default_password_lifetime=365;
  ALTER USER '<username>'@'<host>' PASSWORD EXPIRE INTERVAL 365 DAY;"
        fi
    fi

    # --------------------------------------------------------------------------
    # 2.7 Lock Out Accounts if Not Currently in Use (Manual) [Level 2]
    # --------------------------------------------------------------------------
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local unlocked_reserved=""
        unlocked_reserved="$(run_sql "SELECT CONCAT(User, '@', Host) FROM mysql.global_priv WHERE User IN ('mysql', 'mariadb.sys') AND IFNULL(JSON_EXTRACT(Priv, '\$.account_locked'), false) <> true;" || true)"
        local all_lock_status=""
        all_lock_status="$(run_sql "SELECT CONCAT(User, '@', Host, '(locked=', IF(IFNULL(JSON_EXTRACT(Priv, '\$.account_locked'), false)=true, 'true', 'false'), ')') FROM mysql.global_priv;" | tr '\n' ' ' || true)"
        if [[ -n "$unlocked_reserved" ]]; then
            report_result "2.7" "Lock Out Accounts if Not Currently in Use" 2 "Manual" "FAIL" \
                "MariaDB reserved account(s) are not locked: $(echo "$unlocked_reserved" | tr '\n' ' '). All accounts: $all_lock_status" \
                "Lock unused and MariaDB reserved accounts using:
  ALTER USER '<username>'@'<host>' ACCOUNT LOCK;"
        else
            report_result "2.7" "Lock Out Accounts if Not Currently in Use" 2 "Manual" "MANUAL" \
                "Reserved accounts are locked. Review active accounts to ensure any unused accounts are locked: $all_lock_status" \
                "Lock any accounts not currently in use:
  ALTER USER '<username>'@'<host>' ACCOUNT LOCK;"
        fi
    else
        report_result "2.7" "Lock Out Accounts if Not Currently in Use" 2 "Manual" "SKIP" \
            "Database connection required to inspect mysql.global_priv account lock status." \
            "Review accounts via 'SELECT CONCAT(user, \"@\", host, \" => \", JSON_DETAILED(priv)) FROM mysql.global_priv;' and lock unused accounts with:
  ALTER USER '<username>'@'<host>' ACCOUNT LOCK;"
    fi

    # --------------------------------------------------------------------------
    # 2.8 Ensure Socket Peer-Credential Authentication is Used Appropriately (Manual) [Level 2]
    # --------------------------------------------------------------------------
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local unix_sock_status=""
        unix_sock_status="$(run_sql "SELECT PLUGIN_STATUS FROM INFORMATION_SCHEMA.PLUGINS WHERE PLUGIN_NAME = 'unix_socket';" || true)"
        local remote_sock_users=""
        remote_sock_users="$(run_sql "SELECT CONCAT(user, '@', host) FROM mysql.global_priv WHERE (JSON_CONTAINS(priv, '{\"plugin\":\"unix_socket\"}', '\$.auth_or') OR JSON_EXTRACT(priv, '\$.plugin') = 'unix_socket') AND host <> 'localhost';" || true)"
        local sock_users=""
        sock_users="$(run_sql "SELECT CONCAT(user, '@', host) FROM mysql.global_priv WHERE JSON_CONTAINS(priv, '{\"plugin\":\"unix_socket\"}', '\$.auth_or') OR JSON_EXTRACT(priv, '\$.plugin') = 'unix_socket';" | tr '\n' ' ' || true)"

        if [[ -n "$remote_sock_users" ]]; then
            report_result "2.8" "Ensure Socket Peer-Credential Authentication is Used Appropriately" 2 "Manual" "FAIL" \
                "Non-localhost user(s) configured with unix_socket plugin: $(echo "$remote_sock_users" | tr '\n' ' ')" \
                "Restrict unix_socket authentication strictly to authorized '@localhost' accounts, or disable the plugin in mariadb.cnf under [mysqld]:
  unix_socket=OFF"
        else
            report_result "2.8" "Ensure Socket Peer-Credential Authentication is Used Appropriately" 2 "Manual" "MANUAL" \
                "unix_socket plugin is '${unix_sock_status:-INACTIVE}'. Users with unix_socket: ${sock_users:-none}. Verify policy compliance." \
                "Ensure only authorized local users ('<user>'@'localhost') use unix_socket, or disable it in mariadb.cnf under [mysqld] if disallowed:
  unix_socket=OFF"
        fi
    else
        report_result "2.8" "Ensure Socket Peer-Credential Authentication is Used Appropriately" 2 "Manual" "SKIP" \
            "Database connection required to inspect unix_socket plugin status and accounts." \
            "Ensure unix_socket is only used by authorized '@localhost' accounts or set 'unix_socket=OFF' under [mysqld] in mariadb.cnf."
    fi

    # --------------------------------------------------------------------------
    # 2.9 Ensure MariaDB is Bound to an IP Address (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local bind_addr=""
    bind_addr="$(get_mariadb_var "bind_address" || true)"
    if [[ -n "$bind_addr" && "$bind_addr" != "*" && "$bind_addr" != "::" && "$bind_addr" != "0.0.0.0" ]]; then
        report_result "2.9" "Ensure MariaDB is Bound to an IP Address" 2 "Automated" "OK" \
            "bind_address is explicitly set to '$bind_addr'." ""
    else
        report_result "2.9" "Ensure MariaDB is Bound to an IP Address" 2 "Automated" "FAIL" \
            "bind_address is '${bind_addr:-empty/unset}' (must not be empty, '*', '::', or '0.0.0.0')." \
            "Add a specific IPv4 or IPv6 bind_address entry under [mysqld] / [mariadbd] in /etc/mysql/mariadb.conf.d/50-server.cnf (or mariadb.cnf) and restart MariaDB:
  bind_address = 127.0.0.1   # or specific interface IP e.g. 192.0.2.24"
    fi

    # --------------------------------------------------------------------------
    # 2.10 Limit Accepted Transport Layer Security (TLS) Versions (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local tls_ver=""
    tls_ver="$(get_mariadb_var "tls_version" || true)"
    if [[ -n "$tls_ver" ]] && ! echo "$tls_ver" | grep -q -E "(TLSv1(,|$)|TLSv1\.0|TLSv1\.1)"; then
        report_result "2.10" "Limit Accepted Transport Layer Security (TLS) Versions" 2 "Automated" "OK" \
            "tls_version is restricted to '$tls_ver' (TLSv1 and TLSv1.1 are disabled)." ""
    else
        report_result "2.10" "Limit Accepted Transport Layer Security (TLS) Versions" 2 "Automated" "FAIL" \
            "tls_version is '${tls_ver:-default (includes TLSv1.1)}', which allows deprecated TLS versions." \
            "Set tls_version in MariaDB configuration files under [mariadbd] to only accept TLSv1.2 and/or TLSv1.3, then restart MariaDB:
  tls_version=TLSv1.2,TLSv1.3"
    fi

    # --------------------------------------------------------------------------
    # 2.11 Require Client-Side Certificates (X.509) (Automated) [Level 2]
    # --------------------------------------------------------------------------
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local non_x509_users=""
        non_x509_users="$(run_sql "SELECT CONCAT(user, '@', host, '(ssl_type=', IF(ssl_type='', 'NONE', ssl_type), ')') FROM mysql.user WHERE user NOT IN ('mysql', 'root', 'mariadb.sys') AND ssl_type NOT IN ('X509', 'SPECIFIED');" || true)"
        if [[ -z "$non_x509_users" ]]; then
            report_result "2.11" "Require Client-Side Certificates (X.509)" 2 "Automated" "OK" \
                "All evaluated non-system database accounts require X509 client certificates." ""
        else
            report_result "2.11" "Require Client-Side Certificates (X.509)" 2 "Automated" "FAIL" \
                "Accounts not requiring X.509 client certificates: $(echo "$non_x509_users" | tr '\n' ' ')" \
                "Configure database users to require X.509 client-side certificates:
  ALTER USER '<user>'@'<host>' REQUIRE X509;"
        fi
    else
        report_result "2.11" "Require Client-Side Certificates (X.509)" 2 "Automated" "SKIP" \
            "Database connection required to query ssl_type from mysql.user." \
            "Run 'SELECT user, host, ssl_type FROM mysql.user WHERE user NOT IN (\"mysql\", \"root\", \"mariadb.sys\");' and enforce X.509 certificates:
  ALTER USER '<user>'@'<host>' REQUIRE X509;"
    fi

    # --------------------------------------------------------------------------
    # 2.12 Ensure Only Approved Ciphers are Used (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local ssl_cipher_val=""
    ssl_cipher_val="$(get_mariadb_var "ssl_cipher" || true)"
    if [[ -n "$ssl_cipher_val" ]] && ! echo "$ssl_cipher_val" | grep -q -E -i "(NULL|RC4|DES|3DES|MD5|EXP|PSK|SRP|SEED|IDEA|CAMELLIA)"; then
        report_result "2.12" "Ensure Only Approved Ciphers are Used" 2 "Automated" "OK" \
            "ssl_cipher is set to '$ssl_cipher_val'." ""
    else
        report_result "2.12" "Ensure Only Approved Ciphers are Used" 2 "Automated" "FAIL" \
            "ssl_cipher is '${ssl_cipher_val:-empty/unset}' or includes weak/unapproved ciphers." \
            "Set ssl_cipher to approved strong cipher suites in your MariaDB configuration file under [mariadbd], then restart MariaDB:
  ssl_cipher='ECDHE-ECDSA-AES128-GCM-SHA256'"
    fi
}

# ==============================================================================
# SECTION 3: File Permissions
# ==============================================================================

audit_section_3() {
    print_section_header "3" "File Permissions" || return 0

    local datadir_val=""
    datadir_val="$(get_mariadb_var "datadir" || true)"
    [[ -z "$datadir_val" ]] && datadir_val="/var/lib/mysql"

    # --------------------------------------------------------------------------
    # 3.1 Ensure 'datadir' Has Appropriate Permissions (Automated) [Level 1]
    # --------------------------------------------------------------------------
    if [[ -d "$datadir_val" ]]; then
        local dd_perm=""
        local dd_owner=""
        dd_perm="$(stat -c "%a" "$datadir_val" 2>/dev/null || true)"
        dd_owner="$(stat -c "%U:%G" "$datadir_val" 2>/dev/null || true)"
        if [[ "$dd_owner" == "mysql:mysql" ]] && is_perm_compliant "$dd_perm" "750"; then
            report_result "3.1" "Ensure 'datadir' Has Appropriate Permissions" 1 "Automated" "OK" \
                "datadir ($datadir_val) has permissions $dd_perm and owner $dd_owner." ""
        else
            report_result "3.1" "Ensure 'datadir' Has Appropriate Permissions" 1 "Automated" "FAIL" \
                "datadir ($datadir_val) has mode $dd_perm and owner $dd_owner (expected 750 or more restrictive, mysql:mysql)." \
                "Execute the following commands at a terminal prompt:
  sudo chmod 750 ${datadir_val}
  sudo chown mysql:mysql ${datadir_val}"
        fi
    else
        report_result "3.1" "Ensure 'datadir' Has Appropriate Permissions" 1 "Automated" "FAIL" \
            "datadir ($datadir_val) does not exist or is not accessible." \
            "Ensure datadir exists and set permissions:
  sudo chmod 750 <datadir>
  sudo chown mysql:mysql <datadir>"
    fi

    # --------------------------------------------------------------------------
    # 3.2 Ensure 'log_bin_basename' Files Have Appropriate Permissions (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local log_bin_base=""
    log_bin_base="$(get_mariadb_var "log_bin_basename" || true)"
    if [[ -z "$log_bin_base" ]]; then
        log_bin_base="$(get_cnf_value "log_bin" || true)"
    fi

    if [[ -n "$log_bin_base" && "$log_bin_base" != "OFF" && "$log_bin_base" != "0" ]]; then
        local bad_binlogs=()
        local binlog_dir
        binlog_dir="$(dirname "$log_bin_base")"
        local binlog_prefix
        binlog_prefix="$(basename "$log_bin_base")"
        if [[ -d "$binlog_dir" ]]; then
            while IFS= read -r -d '' bf; do
                local p o
                p="$(stat -c "%a" "$bf" 2>/dev/null || true)"
                o="$(stat -c "%U:%G" "$bf" 2>/dev/null || true)"
                if [[ "$o" != "mysql:mysql" ]] || ! is_perm_compliant "$p" "660"; then
                    bad_binlogs+=("$bf ($p $o)")
                fi
            done < <(find "$binlog_dir" -maxdepth 1 -type f -name "${binlog_prefix}*" -print0 2>/dev/null)
        fi
        if [[ ${#bad_binlogs[@]} -eq 0 ]]; then
            report_result "3.2" "Ensure 'log_bin_basename' Files Have Appropriate Permissions" 1 "Automated" "OK" \
                "All binary log files matching ${log_bin_base}.* have 660 (or stricter) permissions and mysql:mysql ownership." ""
        else
            report_result "3.2" "Ensure 'log_bin_basename' Files Have Appropriate Permissions" 1 "Automated" "FAIL" \
                "Non-compliant binary log files found: ${bad_binlogs[*]}" \
                "Execute the following commands for each binary log file:
  sudo chmod 660 ${log_bin_base}.*
  sudo chown mysql:mysql ${log_bin_base}.*"
        fi
    else
        report_result "3.2" "Ensure 'log_bin_basename' Files Have Appropriate Permissions" 1 "Automated" "OK" \
            "Binary logging (log_bin_basename) is not currently active or no non-compliant files exist (note: see 2.1.5 to enable binlogs)." ""
    fi

    # --------------------------------------------------------------------------
    # 3.3 Ensure 'log_error' Has Appropriate Permissions (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local log_err_val=""
    log_err_val="$(get_mariadb_var "log_error" || true)"
    if [[ -n "$log_err_val" && "$log_err_val" != "./stderr.err" && "$log_err_val" != "stderr" && -f "$log_err_val" ]]; then
        local le_perm le_owner
        le_perm="$(stat -c "%a" "$log_err_val" 2>/dev/null || true)"
        le_owner="$(stat -c "%U:%G" "$log_err_val" 2>/dev/null || true)"
        if [[ "$le_owner" == "mysql:mysql" ]] && is_perm_compliant "$le_perm" "600"; then
            report_result "3.3" "Ensure 'log_error' Has Appropriate Permissions" 1 "Automated" "OK" \
                "log_error ($log_err_val) has permissions $le_perm and owner $le_owner." ""
        else
            report_result "3.3" "Ensure 'log_error' Has Appropriate Permissions" 1 "Automated" "FAIL" \
                "log_error ($log_err_val) has mode $le_perm and owner $le_owner (expected 600 and mysql:mysql)." \
                "Execute the following commands for the error log file:
  sudo chmod 600 ${log_err_val}
  sudo chown mysql:mysql ${log_err_val}"
        fi
    else
        report_result "3.3" "Ensure 'log_error' Has Appropriate Permissions" 1 "Automated" "FAIL" \
            "log_error is '${log_err_val:-not configured}' or file does not exist on disk." \
            "Configure 'log_error = /var/log/mysql/mariadb.err' in mariadb.cnf and restrict permissions:
  sudo chmod 600 <log_error_file>
  sudo chown mysql:mysql <log_error_file>"
    fi

    # --------------------------------------------------------------------------
    # 3.4 Ensure 'slow_query_log' Has Appropriate Permissions (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local sq_log=""
    local sq_file=""
    sq_log="$(get_mariadb_var "slow_query_log" || echo "OFF")"
    sq_file="$(get_mariadb_var "slow_query_log_file" || true)"
    [[ -n "$sq_file" && "${sq_file:0:1}" != "/" ]] && sq_file="${datadir_val}/${sq_file}"

    if [[ "$sq_log" =~ ^(OFF|0)$ ]]; then
        if [[ -n "$sq_file" && -f "$sq_file" ]]; then
            report_result "3.4" "Ensure 'slow_query_log' Has Appropriate Permissions" 1 "Automated" "FAIL" \
                "slow_query_log is disabled ($sq_log), but old slow query log file still exists at '$sq_file'." \
                "Remove old slow query log files when slow_query_log is disabled:
  sudo rm -f ${sq_file}*"
        else
            report_result "3.4" "Ensure 'slow_query_log' Has Appropriate Permissions" 1 "Automated" "OK" \
                "slow_query_log is disabled ($sq_log) and no old slow query log file exists." ""
        fi
    else
        if [[ -n "$sq_file" && -f "$sq_file" ]]; then
            local sq_perm sq_owner
            sq_perm="$(stat -c "%a" "$sq_file" 2>/dev/null || true)"
            sq_owner="$(stat -c "%U:%G" "$sq_file" 2>/dev/null || true)"
            if [[ "$sq_owner" == "mysql:mysql" ]] && is_perm_compliant "$sq_perm" "660"; then
                report_result "3.4" "Ensure 'slow_query_log' Has Appropriate Permissions" 1 "Automated" "OK" \
                    "slow_query_log_file ($sq_file) has permissions $sq_perm and owner $sq_owner." ""
            else
                report_result "3.4" "Ensure 'slow_query_log' Has Appropriate Permissions" 1 "Automated" "FAIL" \
                    "slow_query_log_file ($sq_file) has mode $sq_perm and owner $sq_owner (expected <=660, mysql:mysql)." \
                    "Disable slow_query_log ('SET PERSIST slow_query_log = OFF;') or fix file permissions:
  sudo chmod 660 ${sq_file}
  sudo chown mysql:mysql ${sq_file}"
            fi
        else
            report_result "3.4" "Ensure 'slow_query_log' Has Appropriate Permissions" 1 "Automated" "FAIL" \
                "slow_query_log is enabled ($sq_log), but slow_query_log_file (${sq_file:-unset}) was not found." \
                "Disable slow_query_log ('SET PERSIST slow_query_log = OFF;') or ensure slow_query_log_file is owned by mysql:mysql with mode 660."
        fi
    fi

    # --------------------------------------------------------------------------
    # 3.5 Ensure 'relay_log_basename' Files Have Appropriate Permissions (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local relay_base=""
    relay_base="$(get_mariadb_var "relay_log_basename" || true)"
    if [[ -n "$relay_base" ]]; then
        local bad_relay=()
        local r_dir r_pref
        r_dir="$(dirname "$relay_base")"
        r_pref="$(basename "$relay_base")"
        if [[ -d "$r_dir" ]]; then
            while IFS= read -r -d '' rf; do
                local p o
                p="$(stat -c "%a" "$rf" 2>/dev/null || true)"
                o="$(stat -c "%U:%G" "$rf" 2>/dev/null || true)"
                if [[ "$o" != "mysql:mysql" ]] || ! is_perm_compliant "$p" "660"; then
                    bad_relay+=("$rf ($p $o)")
                fi
            done < <(find "$r_dir" -maxdepth 1 -type f -name "${r_pref}*" -print0 2>/dev/null)
        fi
        if [[ ${#bad_relay[@]} -eq 0 ]]; then
            report_result "3.5" "Ensure 'relay_log_basename' Files Have Appropriate Permissions" 1 "Automated" "OK" \
                "All relay log files (${relay_base}.*) are compliant (<=660, mysql:mysql)." ""
        else
            report_result "3.5" "Ensure 'relay_log_basename' Files Have Appropriate Permissions" 1 "Automated" "FAIL" \
                "Non-compliant relay log files found: ${bad_relay[*]}" \
                "Execute the following commands for each relay log file:
  sudo chmod 660 ${relay_base}.*
  sudo chown mysql:mysql ${relay_base}.*"
        fi
    else
        report_result "3.5" "Ensure 'relay_log_basename' Files Have Appropriate Permissions" 1 "Automated" "OK" \
            "Relay logging (relay_log_basename) is not active and no non-compliant relay log files exist." ""
    fi

    # --------------------------------------------------------------------------
    # 3.6 Ensure 'general_log_file' Has Appropriate Permissions (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local gen_log=""
    local gen_file=""
    gen_log="$(get_mariadb_var "general_log" || echo "OFF")"
    gen_file="$(get_mariadb_var "general_log_file" || true)"
    [[ -n "$gen_file" && "${gen_file:0:1}" != "/" ]] && gen_file="${datadir_val}/${gen_file}"

    if [[ "$gen_log" =~ ^(OFF|0)$ ]]; then
        if [[ -n "$gen_file" && -f "$gen_file" ]]; then
            report_result "3.6" "Ensure 'general_log_file' Has Appropriate Permissions" 1 "Automated" "FAIL" \
                "general_log is disabled ($gen_log), but old general_log_file still exists at '$gen_file'." \
                "Remove old general log files when general_log is disabled:
  sudo rm -f ${gen_file}"
        else
            report_result "3.6" "Ensure 'general_log_file' Has Appropriate Permissions" 1 "Automated" "OK" \
                "general_log is disabled ($gen_log) and no residual general_log_file exists." ""
        fi
    else
        if [[ -n "$gen_file" && -f "$gen_file" ]]; then
            local g_perm g_owner
            g_perm="$(stat -c "%a" "$gen_file" 2>/dev/null || true)"
            g_owner="$(stat -c "%U:%G" "$gen_file" 2>/dev/null || true)"
            if [[ "$g_owner" == "mysql:mysql" ]] && is_perm_compliant "$g_perm" "600"; then
                report_result "3.6" "Ensure 'general_log_file' Has Appropriate Permissions" 1 "Automated" "OK" \
                    "general_log_file ($gen_file) has permissions $g_perm and owner $g_owner." ""
            else
                report_result "3.6" "Ensure 'general_log_file' Has Appropriate Permissions" 1 "Automated" "FAIL" \
                    "general_log_file ($gen_file) has mode $g_perm and owner $g_owner (expected 600, mysql:mysql)." \
                    "Disable general_log ('SET PERSIST @@GENERAL_LOG=OFF;') or fix permissions:
  sudo chmod 600 ${gen_file}
  sudo chown mysql:mysql ${gen_file}"
            fi
        else
            report_result "3.6" "Ensure 'general_log_file' Has Appropriate Permissions" 1 "Automated" "FAIL" \
                "general_log is enabled ($gen_log), but general_log_file (${gen_file:-unset}) does not exist." \
                "Disable general_log ('SET PERSIST @@GENERAL_LOG=OFF;') or set permissions to 600 and owner mysql:mysql."
        fi
    fi

    # --------------------------------------------------------------------------
    # 3.7 Ensure SSL Key Files Have Appropriate Permissions (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local ssl_vars=("ssl_ca" "ssl_capath" "ssl_cert" "ssl_crl" "ssl_crlpath" "ssl_key")
    local ssl_found=0
    local bad_ssl_files=()

    for sv in "${ssl_vars[@]}"; do
        local sval=""
        sval="$(get_mariadb_var "$sv" || true)"
        if [[ -n "$sval" ]]; then
            ssl_found=1
            if [[ -e "$sval" ]]; then
                local sp so
                sp="$(stat -c "%a" "$sval" 2>/dev/null || true)"
                so="$(stat -c "%U:%G" "$sval" 2>/dev/null || true)"
                if [[ "$so" != "mysql:mysql" ]] || ! is_perm_compliant "$sp" "400"; then
                    bad_ssl_files+=("${sv}=${sval} (mode $sp, owner $so)")
                fi
            else
                bad_ssl_files+=("${sv}=${sval} (missing file)")
            fi
        fi
    done

    if [[ "$ssl_found" -eq 0 ]]; then
        report_result "3.7" "Ensure SSL Key Files Have Appropriate Permissions" 1 "Automated" "FAIL" \
            "No SSL key/certificate files are configured (SSL is highly recommended by CIS)." \
            "Configure SSL/TLS files in mariadb.cnf and restrict permissions on each file:
  sudo chown mysql:mysql <ssl_file>
  sudo chmod 400 <ssl_file>"
    elif [[ ${#bad_ssl_files[@]} -eq 0 ]]; then
        report_result "3.7" "Ensure SSL Key Files Have Appropriate Permissions" 1 "Automated" "OK" \
            "All configured SSL key and certificate files have mode 400 and owner mysql:mysql." ""
    else
        report_result "3.7" "Ensure SSL Key Files Have Appropriate Permissions" 1 "Automated" "FAIL" \
            "Non-compliant SSL file(s): ${bad_ssl_files[*]}" \
            "Set ownership to mysql:mysql and permissions to 400 on all SSL files:
  sudo chown mysql:mysql <ssl_file>
  sudo chmod 400 <ssl_file>"
    fi

    # --------------------------------------------------------------------------
    # 3.8 Ensure Plugin Directory Has Appropriate Permissions (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local plugin_dir_val=""
    plugin_dir_val="$(get_mariadb_var "plugin_dir" || true)"
    [[ -z "$plugin_dir_val" && -d "/usr/lib/mysql/plugin" ]] && plugin_dir_val="/usr/lib/mysql/plugin"
    [[ -z "$plugin_dir_val" && -d "/usr/lib64/mysql/plugin" ]] && plugin_dir_val="/usr/lib64/mysql/plugin"

    if [[ -n "$plugin_dir_val" && -d "$plugin_dir_val" ]]; then
        local pd_perm pd_owner
        pd_perm="$(stat -c "%a" "$plugin_dir_val" 2>/dev/null || true)"
        pd_owner="$(stat -c "%U:%G" "$plugin_dir_val" 2>/dev/null || true)"
        if [[ "$pd_owner" == "mysql:mysql" && ( "$pd_perm" == "550" || "$pd_perm" == "554" || "$pd_perm" == "500" ) ]]; then
            report_result "3.8" "Ensure Plugin Directory Has Appropriate Permissions" 1 "Automated" "OK" \
                "plugin_dir ($plugin_dir_val) has permissions $pd_perm and owner $pd_owner." ""
        else
            report_result "3.8" "Ensure Plugin Directory Has Appropriate Permissions" 1 "Automated" "FAIL" \
                "plugin_dir ($plugin_dir_val) has mode $pd_perm and owner $pd_owner (expected 550 or 554 and mysql:mysql)." \
                "Execute the following commands at a terminal prompt:
  sudo chmod 550 ${plugin_dir_val}   # (or 554)
  sudo chown mysql:mysql ${plugin_dir_val}"
        fi
    else
        report_result "3.8" "Ensure Plugin Directory Has Appropriate Permissions" 1 "Automated" "FAIL" \
            "plugin_dir (${plugin_dir_val:-unset}) could not be found." \
            "Locate plugin_dir via 'SHOW VARIABLES WHERE variable_name = \"plugin_dir\";' and run:
  sudo chmod 550 <plugin_dir>
  sudo chown mysql:mysql <plugin_dir>"
    fi

    # --------------------------------------------------------------------------
    # 3.9 Ensure 'server_audit_file_path' Has Appropriate Permissions (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local audit_path=""
    audit_path="$(get_mariadb_var "server_audit_file_path" || true)"
    if [[ -n "$audit_path" ]]; then
        [[ "${audit_path:0:1}" != "/" ]] && audit_path="${datadir_val%/}/${audit_path}"
        if [[ -f "$audit_path" ]]; then
            local ap_perm ap_owner
            ap_perm="$(stat -c "%a" "$audit_path" 2>/dev/null || true)"
            ap_owner="$(stat -c "%U:%G" "$audit_path" 2>/dev/null || true)"
            if [[ "$ap_owner" == "mysql:mysql" ]] && is_perm_compliant "$ap_perm" "660"; then
                report_result "3.9" "Ensure 'server_audit_file_path' Has Appropriate Permissions" 1 "Automated" "OK" \
                    "server_audit_file_path ($audit_path) has mode $ap_perm and owner $ap_owner." ""
            else
                report_result "3.9" "Ensure 'server_audit_file_path' Has Appropriate Permissions" 1 "Automated" "FAIL" \
                    "server_audit_file_path ($audit_path) has mode $ap_perm and owner $ap_owner (expected <=660, mysql:mysql)." \
                    "Execute the following commands:
  sudo chmod 660 ${audit_path}
  sudo chown mysql:mysql ${audit_path}"
            fi
        else
            report_result "3.9" "Ensure 'server_audit_file_path' Has Appropriate Permissions" 1 "Automated" "FAIL" \
                "server_audit_file_path is set to '$audit_path', but the file does not exist on disk." \
                "Enable server_audit logging and set permissions on the audit log file:
  sudo chmod 660 ${audit_path}
  sudo chown mysql:mysql ${audit_path}"
        fi
    else
        report_result "3.9" "Ensure 'server_audit_file_path' Has Appropriate Permissions" 1 "Automated" "FAIL" \
            "server_audit_file_path is not set (MariaDB Audit plugin is not installed/enabled)." \
            "Install and enable the server_audit plugin (see 6.4) and restrict audit log file permissions:
  sudo chmod 660 <server_audit_file_path>
  sudo chown mysql:mysql <server_audit_file_path>"
    fi

    # --------------------------------------------------------------------------
    # 3.10 Ensure File Key Management Encryption Plugin files have appropriate permissions (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local fkm_file=""
    local fkm_key=""
    fkm_file="$(get_mariadb_var "file_key_management_filename" || true)"
    fkm_key="$(get_mariadb_var "file_key_management_filekey" || true)"
    fkm_key="${fkm_key#FILE:}"

    if [[ -z "$fkm_file" && -z "$fkm_key" ]]; then
        report_result "3.10" "Ensure File Key Management Encryption Plugin files have appropriate permissions" 1 "Automated" "FAIL" \
            "File Key Management Encryption plugin files (file_key_management_filename / file_key_management_filekey) are not configured." \
            "First implement recommendation 4.9 to configure the File Key Management Encryption plugin, then set permissions on each key file:
  sudo chmod 750 <file>   # (or 640 / 600)
  sudo chown mysql:mysql <file>"
    else
        local bad_fkm=()
        for kf in "$fkm_file" "$fkm_key"; do
            [[ -z "$kf" ]] && continue
            if [[ -e "$kf" ]]; then
                local kp ko
                kp="$(stat -c "%a" "$kf" 2>/dev/null || true)"
                ko="$(stat -c "%U:%G" "$kf" 2>/dev/null || true)"
                if [[ "$ko" != "mysql:mysql" ]] || ! is_perm_compliant "$kp" "750"; then
                    bad_fkm+=("$kf (mode $kp, owner $ko)")
                fi
            else
                bad_fkm+=("$kf (file not found)")
            fi
        done
        if [[ ${#bad_fkm[@]} -eq 0 ]]; then
            report_result "3.10" "Ensure File Key Management Encryption Plugin files have appropriate permissions" 1 "Automated" "OK" \
                "File Key Management Encryption plugin files have compliant permissions (<=750) and owner mysql:mysql." ""
        else
            report_result "3.10" "Ensure File Key Management Encryption Plugin files have appropriate permissions" 1 "Automated" "FAIL" \
                "Non-compliant File Key Management file(s): ${bad_fkm[*]}" \
                "Execute the following commands for each File Key Management file:
  sudo chmod 750 <file>   # (or 640)
  sudo chown mysql:mysql <file>"
        fi
    fi
}

# ==============================================================================
# SECTION 4: General
# ==============================================================================

audit_section_4() {
    print_section_header "4" "General" || return 0

    # --------------------------------------------------------------------------
    # 4.1 Ensure the Latest Security Patches are Applied (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local mdb_ver=""
    mdb_ver="$(get_mariadb_var "version" || true)"
    if [[ -z "$mdb_ver" ]] && command -v mariadbd >/dev/null 2>&1; then
        mdb_ver="$(mariadbd --version 2>/dev/null || true)"
    fi
    report_result "4.1" "Ensure the Latest Security Patches are Applied" 1 "Manual" "MANUAL" \
        "Detected MariaDB version: '${mdb_ver:-unknown}'. Compare with latest MariaDB 10.6 security announcements and OS package updates." \
        "Install the latest security patches for your MariaDB version or upgrade to the latest release via your OS package manager (e.g., 'sudo apt update && sudo apt upgrade mariadb-server'), then restart MariaDB."

    # --------------------------------------------------------------------------
    # 4.2 Ensure Example or Test Databases are Not Installed on Production Servers (Automated) [Level 1]
    # --------------------------------------------------------------------------
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local test_dbs=""
        test_dbs="$(run_sql "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME NOT IN ('mysql','information_schema', 'sys', 'performance_schema') AND (SCHEMA_NAME = 'test' OR SCHEMA_NAME LIKE 'test\_%' OR SCHEMA_NAME IN ('sakila', 'world', 'employees', 'menagerie'));" || true)"
        if [[ -z "$test_dbs" ]]; then
            report_result "4.2" "Ensure Example or Test Databases are Not Installed on Production Servers" 1 "Automated" "OK" \
                "No example or test databases ('test', etc.) are present." ""
        else
            report_result "4.2" "Ensure Example or Test Databases are Not Installed on Production Servers" 1 "Automated" "FAIL" \
                "Example/test database(s) found: $(echo "$test_dbs" | tr '\n' ' ')" \
                "Execute the following SQL statement for each example/test database:
  DROP DATABASE <database_name>;"
        fi
    else
        local datadir_val
        datadir_val="$(get_mariadb_var "datadir" || echo "/var/lib/mysql")"
        if [[ -d "${datadir_val}/test" ]]; then
            report_result "4.2" "Ensure Example or Test Databases are Not Installed on Production Servers" 1 "Automated" "FAIL" \
                "Found '${datadir_val}/test' database directory on disk." \
                "Connect to MariaDB and drop the test database:
  DROP DATABASE test;"
        else
            report_result "4.2" "Ensure Example or Test Databases are Not Installed on Production Servers" 1 "Automated" "SKIP" \
                "Database connection required to query information_schema.SCHEMATA." \
                "Verify no test/example databases exist and drop any found using:
  DROP DATABASE <database_name>;"
        fi
    fi

    # --------------------------------------------------------------------------
    # 4.3 Ensure 'allow-suspicious-udfs' is Set to 'OFF' (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local udf_proc=""
    local udf_def=""
    udf_proc="$(ps -ef 2>/dev/null | grep -E "(mariadbd|mysqld)" | grep -- "allow-suspicious-udfs" | grep -v "allow-suspicious-udfs=OFF" | grep -v "allow-suspicious-udfs=0" | grep -v "grep" || true)"
    if command -v my_print_defaults >/dev/null 2>&1; then
        udf_def="$(my_print_defaults mysqld mariadbd 2>/dev/null | grep "allow-suspicious-udfs" | grep -v -E "=(OFF|0|FALSE)$" || true)"
    fi
    if [[ -z "$udf_def" ]] && has_cnf_key "allow-suspicious-udfs"; then
        local cnf_udf
        cnf_udf="$(get_cnf_value "allow-suspicious-udfs" || echo "ON")"
        [[ ! "$cnf_udf" =~ ^(OFF|0|FALSE)$ ]] && udf_def="allow-suspicious-udfs=$cnf_udf"
    fi

    if [[ -z "$udf_proc" && -z "$udf_def" ]]; then
        report_result "4.3" "Ensure 'allow-suspicious-udfs' is Set to 'OFF'" 2 "Automated" "OK" \
            "allow-suspicious-udfs is not enabled in startup arguments or MariaDB configuration." ""
    else
        report_result "4.3" "Ensure 'allow-suspicious-udfs' is Set to 'OFF'" 2 "Automated" "FAIL" \
            "allow-suspicious-udfs is enabled (${udf_proc} ${udf_def})." \
            "1. Remove '--allow-suspicious-udfs' from the mariadbd startup command line.
2. Remove 'allow-suspicious-udfs' (or set to OFF) in the MariaDB option file and restart MariaDB."
    fi

    # --------------------------------------------------------------------------
    # 4.4 Harden Usage for 'local_infile' on MariaDB Clients (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local local_infile_val=""
    local_infile_val="$(get_mariadb_var "local_infile" || true)"
    if [[ "$local_infile_val" =~ ^(OFF|0)$ ]]; then
        report_result "4.4" "Harden Usage for 'local_infile' on MariaDB Clients" 1 "Automated" "OK" \
            "local_infile is disabled ($local_infile_val)." ""
    else
        report_result "4.4" "Harden Usage for 'local_infile' on MariaDB Clients" 1 "Automated" "FAIL" \
            "local_infile is '${local_infile_val:-ON/unset}' (expected 0 / OFF)." \
            "1. Upgrade all MariaDB clients and connectors to 10.2.0 or higher.
2. Add the following line to the [mariadbd] section of the MariaDB configuration file and restart MariaDB:
   local-infile=0"
    fi

    # --------------------------------------------------------------------------
    # 4.5 Ensure mariadb is Not Started With 'skip-grant-tables' (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local sgt_proc=""
    local sgt_cnf=""
    sgt_proc="$(ps -ef 2>/dev/null | grep -E "(mariadbd|mysqld)" | grep -E "skip[-_]grant[-_]tables" | grep -v -E "=(FALSE|0|OFF)" | grep -v "grep" || true)"
    if has_cnf_key "skip-grant-tables"; then
        local v
        v="$(get_cnf_value "skip-grant-tables" || echo "TRUE")"
        [[ -z "$v" || ! "$v" =~ ^(FALSE|0|OFF)$ ]] && sgt_cnf="skip-grant-tables=${v:-TRUE}"
    fi

    if [[ -z "$sgt_proc" && -z "$sgt_cnf" ]]; then
        report_result "4.5" "Ensure mariadb is Not Started With 'skip-grant-tables'" 1 "Automated" "OK" \
            "skip-grant-tables is not enabled in configuration or running process." ""
    else
        report_result "4.5" "Ensure mariadb is Not Started With 'skip-grant-tables'" 1 "Automated" "FAIL" \
            "skip-grant-tables is enabled (${sgt_proc} ${sgt_cnf})." \
            "Open the MariaDB configuration file (mariadb.cnf) and set:
  skip-grant-tables = FALSE
Remove any other occurrences of skip_grant_tables or --skip-grant-tables and restart MariaDB."
    fi

    # --------------------------------------------------------------------------
    # 4.6 Ensure Symbolic Links are Disabled (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local symlink_val=""
    symlink_val="$(get_mariadb_var "have_symlink" || true)"
    if [[ -z "$symlink_val" ]]; then
        local cnf_sym
        cnf_sym="$(get_cnf_value "skip-symbolic-links" || true)"
        [[ "$cnf_sym" =~ ^(YES|1|ON)$ ]] && symlink_val="DISABLED"
    fi

    if [[ "$symlink_val" == "DISABLED" ]]; then
        report_result "4.6" "Ensure Symbolic Links are Disabled" 1 "Automated" "OK" \
            "have_symlink is DISABLED." ""
    else
        report_result "4.6" "Ensure Symbolic Links are Disabled" 1 "Automated" "FAIL" \
            "have_symlink is '${symlink_val:-ENABLED/unset}' (expected DISABLED)." \
            "Open the MariaDB configuration file (mariadb.cnf) and under the [mariadbd] section set:
  skip-symbolic-links = YES
Then restart the MariaDB service."
    fi

    # --------------------------------------------------------------------------
    # 4.7 Ensure the 'secure_file_priv' is Configured Correctly (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local sfp_val=""
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        sfp_val="$(run_sql "SELECT IFNULL(VARIABLE_VALUE, 'NULL') FROM information_schema.global_variables WHERE VARIABLE_NAME = 'secure_file_priv';" || true)"
    else
        sfp_val="$(get_cnf_value "secure_file_priv" || true)"
    fi

    local datadir_val
    datadir_val="$(get_mariadb_var "datadir" || echo "/var/lib/mysql")"

    if [[ "$sfp_val" == "NULL" ]] || [[ -n "$sfp_val" && -d "$sfp_val" && "${sfp_val#${datadir_val}}" == "$sfp_val" ]]; then
        report_result "4.7" "Ensure the 'secure_file_priv' is Configured Correctly" 1 "Automated" "OK" \
            "secure_file_priv is safely configured as '$sfp_val'." ""
    else
        report_result "4.7" "Ensure the 'secure_file_priv' is Configured Correctly" 1 "Automated" "FAIL" \
            "secure_file_priv is '${sfp_val:-empty/unrestricted}' (empty string or inside datadir is insecure)." \
            "Add the following line to the [mariadbd] section of the MariaDB configuration file and restart MariaDB:
  secure_file_priv = NULL   # (to disable LOAD DATA INFILE / SELECT INTO OUTFILE completely)
  # Or specify a dedicated, restricted directory outside datadir:
  secure_file_priv = <path_to_load_directory>"
    fi

    # --------------------------------------------------------------------------
    # 4.8 Ensure 'sql_mode' Contains 'STRICT_ALL_TABLES' (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local sql_mode_val=""
    sql_mode_val="$(get_mariadb_var "sql_mode" || true)"
    if echo "$sql_mode_val" | grep -q "STRICT_ALL_TABLES"; then
        report_result "4.8" "Ensure 'sql_mode' Contains 'STRICT_ALL_TABLES'" 2 "Automated" "OK" \
            "sql_mode contains STRICT_ALL_TABLES ($sql_mode_val)." ""
    else
        report_result "4.8" "Ensure 'sql_mode' Contains 'STRICT_ALL_TABLES'" 2 "Automated" "FAIL" \
            "sql_mode ('$sql_mode_val') does not contain STRICT_ALL_TABLES." \
            "Add STRICT_ALL_TABLES to sql_mode dynamically and in mariadb.cnf under [mariadbd]:
  SET GLOBAL sql_mode = 'STRICT_ALL_TABLES,ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';"
    fi

    # --------------------------------------------------------------------------
    # 4.9 Enable data-at-rest encryption in MariaDB (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local enc_tables=""
    local enc_log=""
    local enc_tmp_files=""
    local enc_tmp_tables=""
    local enc_binlog=""
    enc_tables="$(get_mariadb_var "innodb_encrypt_tables" || echo "OFF")"
    enc_log="$(get_mariadb_var "innodb_encrypt_log" || echo "OFF")"
    enc_tmp_files="$(get_mariadb_var "encrypt_tmp_files" || echo "OFF")"
    enc_tmp_tables="$(get_mariadb_var "innodb_encrypt_temporary_tables" || echo "OFF")"
    enc_binlog="$(get_mariadb_var "encrypt_binlog" || echo "OFF")"

    local unencrypted_ts=""
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        unencrypted_ts="$(run_sql "SELECT COUNT(*) FROM INFORMATION_SCHEMA.INNODB_TABLESPACES_ENCRYPTION WHERE ENCRYPTION_SCHEME = 0;" || echo "1")"
    fi

    if [[ "$enc_tables" =~ ^(ON|FORCE|1)$ && "$enc_log" =~ ^(ON|1)$ && "$enc_tmp_files" =~ ^(ON|1)$ && "$enc_tmp_tables" =~ ^(ON|1)$ && "$enc_binlog" =~ ^(ON|1)$ && "${unencrypted_ts:-0}" == "0" ]]; then
        report_result "4.9" "Enable data-at-rest encryption in MariaDB" 2 "Automated" "OK" \
            "Data-at-rest encryption is enabled (innodb_encrypt_tables=$enc_tables, innodb_encrypt_log=$enc_log, encrypt_binlog=$enc_binlog)." ""
    else
        report_result "4.9" "Enable data-at-rest encryption in MariaDB" 2 "Automated" "FAIL" \
            "innodb_encrypt_tables=$enc_tables, innodb_encrypt_log=$enc_log, encrypt_tmp_files=$enc_tmp_files, innodb_encrypt_temporary_tables=$enc_tmp_tables, encrypt_binlog=$enc_binlog, unencrypted_tablespaces=${unencrypted_ts:-unknown}." \
            "1. Create and encrypt a keyfile in /etc/mysql/encryption/ (chmod 640, chown mysql:mysql).
2. Configure [mariadb] in mariadb.cnf:
   plugin_load_add = file_key_management
   file_key_management_filename = /etc/mysql/encryption/keyfile.enc
   file_key_management_filekey = FILE:/etc/mysql/encryption/keyfile.key
   encrypt_binlog = ON
   innodb_encrypt_log = ON
   encrypt_tmp_files = ON
   innodb_encrypt_temporary_tables = ON
   innodb_encrypt_tables = ON
3. Restart MariaDB and encrypt existing tables:
   ALTER TABLE <table_name> ENCRYPTED=YES ENCRYPTION_KEY_ID=1;"
    fi
}

# ==============================================================================
# SECTION 5: MariaDB Permissions
# ==============================================================================

audit_section_5() {
    print_section_header "5" "MariaDB Permissions" || return 0

    local admin_in_list
    admin_in_list="$(to_sql_in_list "$ADMIN_USERS")"
    local repl_in_list
    repl_in_list="$(to_sql_in_list "${ADMIN_USERS},${REPL_USERS}")"

    if [[ "$DB_CONNECTED" -ne 1 ]]; then
        for item in \
            "5.1|Ensure Only Administrative Users Have Full Database Access|1|REVOKE <privilege> ON *.* FROM '<user>';" \
            "5.2|Ensure 'FILE' is Not Granted to Non-Administrative Users|1|REVOKE FILE ON *.* FROM '<user>';" \
            "5.3|Ensure 'PROCESS' is Not Granted to Non-Administrative Users|2|REVOKE PROCESS ON *.* FROM '<user>';" \
            "5.4|Ensure 'SUPER' is Not Granted to Non-Administrative Users|1|REVOKE SUPER ON *.* FROM '<user>';" \
            "5.5|Ensure 'SHUTDOWN' is Not Granted to Non-Administrative Users|1|REVOKE SHUTDOWN ON *.* FROM '<user>';" \
            "5.6|Ensure 'CREATE USER' is Not Granted to Non-Administrative Users|1|REVOKE CREATE USER ON *.* FROM '<user>';" \
            "5.7|Ensure 'GRANT OPTION' is Not Granted to Non-Administrative Users|1|REVOKE GRANT OPTION ON *.* FROM '<user>';" \
            "5.8|Ensure 'REPLICATION SLAVE' is Not Granted to Non-Administrative Users|1|REVOKE REPLICATION SLAVE ON *.* FROM '<user>';" \
            "5.9|Ensure DML/DDL Grants are Limited to Specific Databases and Users|1|REVOKE SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER ON <db>.* FROM '<user>'@'<host>';" \
            "5.10|Securely Define Stored Procedures and Functions DEFINER and INVOKER|1|Drop and recreate stored procedures/functions with proper DEFINER and SQL SECURITY INVOKER."; do
            IFS='|' read -r cid ctitle clvl crem <<< "$item"
            report_result "$cid" "$ctitle" "$clvl" "Manual" "SKIP" \
                "Database connection required to audit user privileges." "$crem"
        done
        return
    fi

    # --------------------------------------------------------------------------
    # 5.1 Ensure Only Administrative Users Have Full Database Access (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local non_admin_global=""
    non_admin_global="$(run_sql "SELECT DISTINCT GRANTEE FROM information_schema.user_privileges WHERE grantee NOT LIKE \"'mysql.%localhost'\" AND SUBSTRING_INDEX(TRIM(BOTH \"'\" FROM SUBSTRING_INDEX(GRANTEE, '@', 1)), \"'\", 1) NOT IN (${admin_in_list}) AND PRIVILEGE_TYPE NOT IN ('USAGE');" || true)"
    if [[ -z "$non_admin_global" ]]; then
        report_result "5.1" "Ensure Only Administrative Users Have Full Database Access" 1 "Manual" "OK" \
            "Only administrative accounts (${ADMIN_USERS}) hold global privileges in information_schema.user_privileges." ""
    else
        report_result "5.1" "Ensure Only Administrative Users Have Full Database Access" 1 "Manual" "FAIL" \
            "Non-administrative accounts with global privileges: $(echo "$non_admin_global" | tr '\n' ' ')" \
            "1. Enumerate non-administrative users resulting from:
   SELECT * FROM information_schema.user_privileges WHERE grantee NOT LIKE ('\'mysql.%localhost\'');
2. For each non-administrative user, use the REVOKE statement to remove global privileges."
    fi

    # --------------------------------------------------------------------------
    # 5.2 Ensure 'FILE' is Not Granted to Non-Administrative Users (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local priv_file=""
    priv_file="$(run_sql "SELECT GRANTEE FROM INFORMATION_SCHEMA.USER_PRIVILEGES WHERE PRIVILEGE_TYPE = 'FILE' AND TRIM(BOTH \"'\" FROM SUBSTRING_INDEX(GRANTEE, '@', 1)) NOT IN (${admin_in_list});" || true)"
    if [[ -z "$priv_file" ]]; then
        report_result "5.2" "Ensure 'FILE' is Not Granted to Non-Administrative Users" 1 "Manual" "OK" \
            "No non-administrative users have the FILE privilege." ""
    else
        report_result "5.2" "Ensure 'FILE' is Not Granted to Non-Administrative Users" 1 "Manual" "FAIL" \
            "Non-administrative grantees with FILE privilege: $(echo "$priv_file" | tr '\n' ' ')" \
            "Revoke FILE from each non-administrative user:
  REVOKE FILE ON *.* FROM '<user>'@'<host>';"
    fi

    # --------------------------------------------------------------------------
    # 5.3 Ensure 'PROCESS' is Not Granted to Non-Administrative Users (Manual) [Level 2]
    # --------------------------------------------------------------------------
    local priv_proc=""
    priv_proc="$(run_sql "SELECT GRANTEE FROM INFORMATION_SCHEMA.USER_PRIVILEGES WHERE PRIVILEGE_TYPE = 'PROCESS' AND TRIM(BOTH \"'\" FROM SUBSTRING_INDEX(GRANTEE, '@', 1)) NOT IN (${admin_in_list});" || true)"
    if [[ -z "$priv_proc" ]]; then
        report_result "5.3" "Ensure 'PROCESS' is Not Granted to Non-Administrative Users" 2 "Manual" "OK" \
            "No non-administrative users have the PROCESS privilege." ""
    else
        report_result "5.3" "Ensure 'PROCESS' is Not Granted to Non-Administrative Users" 2 "Manual" "FAIL" \
            "Non-administrative grantees with PROCESS privilege: $(echo "$priv_proc" | tr '\n' ' ')" \
            "Revoke PROCESS from each non-administrative user:
  REVOKE PROCESS ON *.* FROM '<user>'@'<host>';"
    fi

    # --------------------------------------------------------------------------
    # 5.4 Ensure 'SUPER' is Not Granted to Non-Administrative Users (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local priv_super=""
    priv_super="$(run_sql "SELECT GRANTEE FROM INFORMATION_SCHEMA.USER_PRIVILEGES WHERE PRIVILEGE_TYPE = 'SUPER' AND TRIM(BOTH \"'\" FROM SUBSTRING_INDEX(GRANTEE, '@', 1)) NOT IN (${admin_in_list});" || true)"
    if [[ -z "$priv_super" ]]; then
        report_result "5.4" "Ensure 'SUPER' is Not Granted to Non-Administrative Users" 1 "Manual" "OK" \
            "No non-administrative users have the SUPER privilege." ""
    else
        report_result "5.4" "Ensure 'SUPER' is Not Granted to Non-Administrative Users" 1 "Manual" "FAIL" \
            "Non-administrative grantees with SUPER privilege: $(echo "$priv_super" | tr '\n' ' ')" \
            "Revoke SUPER from each non-administrative user and migrate administrative accounts to granular Dynamic Privileges:
  REVOKE SUPER ON *.* FROM '<user>'@'<host>';
  GRANT BINLOG_ADMIN, SYSTEM_VARIABLES_ADMIN ON *.* TO '<admin>'@'<host>';"
    fi

    # --------------------------------------------------------------------------
    # 5.5 Ensure 'SHUTDOWN' is Not Granted to Non-Administrative Users (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local priv_shut=""
    priv_shut="$(run_sql "SELECT GRANTEE FROM INFORMATION_SCHEMA.USER_PRIVILEGES WHERE PRIVILEGE_TYPE = 'SHUTDOWN' AND TRIM(BOTH \"'\" FROM SUBSTRING_INDEX(GRANTEE, '@', 1)) NOT IN (${admin_in_list});" || true)"
    if [[ -z "$priv_shut" ]]; then
        report_result "5.5" "Ensure 'SHUTDOWN' is Not Granted to Non-Administrative Users" 1 "Manual" "OK" \
            "No non-administrative users have the SHUTDOWN privilege." ""
    else
        report_result "5.5" "Ensure 'SHUTDOWN' is Not Granted to Non-Administrative Users" 1 "Manual" "FAIL" \
            "Non-administrative grantees with SHUTDOWN privilege: $(echo "$priv_shut" | tr '\n' ' ')" \
            "Revoke SHUTDOWN from each non-administrative user:
  REVOKE SHUTDOWN ON *.* FROM '<user>'@'<host>';"
    fi

    # --------------------------------------------------------------------------
    # 5.6 Ensure 'CREATE USER' is Not Granted to Non-Administrative Users (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local priv_cu=""
    priv_cu="$(run_sql "SELECT GRANTEE FROM INFORMATION_SCHEMA.USER_PRIVILEGES WHERE PRIVILEGE_TYPE = 'CREATE USER' AND TRIM(BOTH \"'\" FROM SUBSTRING_INDEX(GRANTEE, '@', 1)) NOT IN (${admin_in_list});" || true)"
    if [[ -z "$priv_cu" ]]; then
        report_result "5.6" "Ensure 'CREATE USER' is Not Granted to Non-Administrative Users" 1 "Manual" "OK" \
            "No non-administrative users have the CREATE USER privilege." ""
    else
        report_result "5.6" "Ensure 'CREATE USER' is Not Granted to Non-Administrative Users" 1 "Manual" "FAIL" \
            "Non-administrative grantees with CREATE USER privilege: $(echo "$priv_cu" | tr '\n' ' ')" \
            "Revoke CREATE USER from each non-administrative user:
  REVOKE CREATE USER ON *.* FROM '<user>'@'<host>';"
    fi

    # --------------------------------------------------------------------------
    # 5.7 Ensure 'GRANT OPTION' is Not Granted to Non-Administrative Users (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local priv_grant=""
    priv_grant="$(run_sql "SELECT DISTINCT GRANTEE FROM INFORMATION_SCHEMA.USER_PRIVILEGES WHERE IS_GRANTABLE = 'YES' AND TRIM(BOTH \"'\" FROM SUBSTRING_INDEX(GRANTEE, '@', 1)) NOT IN (${admin_in_list});" || true)"
    if [[ -z "$priv_grant" ]]; then
        report_result "5.7" "Ensure 'GRANT OPTION' is Not Granted to Non-Administrative Users" 1 "Manual" "OK" \
            "No non-administrative users have GRANT OPTION." ""
    else
        report_result "5.7" "Ensure 'GRANT OPTION' is Not Granted to Non-Administrative Users" 1 "Manual" "FAIL" \
            "Non-administrative grantees with GRANT OPTION: $(echo "$priv_grant" | tr '\n' ' ')" \
            "Revoke GRANT OPTION from each non-administrative user:
  REVOKE GRANT OPTION ON *.* FROM '<user>'@'<host>';"
    fi

    # --------------------------------------------------------------------------
    # 5.8 Ensure 'REPLICATION SLAVE' is Not Granted to Non-Administrative Users (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local priv_repl=""
    priv_repl="$(run_sql "SELECT GRANTEE FROM INFORMATION_SCHEMA.USER_PRIVILEGES WHERE PRIVILEGE_TYPE = 'REPLICATION SLAVE' AND TRIM(BOTH \"'\" FROM SUBSTRING_INDEX(GRANTEE, '@', 1)) NOT IN (${repl_in_list});" || true)"
    if [[ -z "$priv_repl" ]]; then
        report_result "5.8" "Ensure 'REPLICATION SLAVE' is Not Granted to Non-Administrative Users" 1 "Manual" "OK" \
            "Only authorized administrative/replication accounts hold REPLICATION SLAVE." ""
    else
        report_result "5.8" "Ensure 'REPLICATION SLAVE' is Not Granted to Non-Administrative Users" 1 "Manual" "FAIL" \
            "Unauthorized grantees with REPLICATION SLAVE privilege: $(echo "$priv_repl" | tr '\n' ' ')" \
            "Revoke REPLICATION SLAVE from non-replica users:
  REVOKE REPLICATION SLAVE ON *.* FROM '<user>'@'<host>';"
    fi

    # --------------------------------------------------------------------------
    # 5.9 Ensure DML/DDL Grants are Limited to Specific Databases and Users (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local global_dml=""
    global_dml="$(run_sql "SELECT CONCAT(User, '@', Host) FROM mysql.user WHERE User NOT IN (${admin_in_list}) AND (Select_priv='Y' OR Insert_priv='Y' OR Update_priv='Y' OR Delete_priv='Y' OR Create_priv='Y' OR Drop_priv='Y' OR Alter_priv='Y');" || true)"
    local db_dml=""
    db_dml="$(run_sql "SELECT CONCAT(User, '@', Host, '->', Db) FROM mysql.db WHERE Select_priv='Y' OR Insert_priv='Y' OR Update_priv='Y' OR Delete_priv='Y' OR Create_priv='Y' OR Drop_priv='Y' OR Alter_priv='Y';" | tr '\n' ' ' || true)"

    if [[ -n "$global_dml" ]]; then
        report_result "5.9" "Ensure DML/DDL Grants are Limited to Specific Databases and Users" 1 "Manual" "FAIL" \
            "Non-administrative users have global (*.*) DML/DDL privileges: $(echo "$global_dml" | tr '\n' ' '). DB-scoped grants: ${db_dml:-none}" \
            "Revoke global DML/DDL privileges and scope grants strictly to specific databases:
  REVOKE SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER ON *.* FROM '<user>'@'<host>';
  REVOKE SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER ON <database>.* FROM '<user>'@'<host>';"
    else
        report_result "5.9" "Ensure DML/DDL Grants are Limited to Specific Databases and Users" 1 "Manual" "MANUAL" \
            "No non-admin global DML/DDL privileges found. Verify database-level grants in mysql.db are authorized: ${db_dml:-none}" \
            "Review 'SELECT User,Host,Db FROM mysql.db WHERE Select_priv=\"Y\" OR Insert_priv=\"Y\" OR Update_priv=\"Y\" OR Delete_priv=\"Y\" OR Create_priv=\"Y\" OR Drop_priv=\"Y\" OR Alter_priv=\"Y\";' and revoke any unauthorized grants."
    fi

    # --------------------------------------------------------------------------
    # 5.10 Securely Define Stored Procedures and Functions DEFINER and INVOKER (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local routines_list=""
    routines_list="$(run_sql "SELECT CONCAT(ROUTINE_SCHEMA, '.', ROUTINE_NAME, '(', ROUTINE_TYPE, ',Definer=', DEFINER, ',Security=', SECURITY_TYPE, ')') FROM information_schema.routines WHERE ROUTINE_SCHEMA NOT IN ('sys', 'mysql', 'information_schema', 'performance_schema');" || true)"
    if [[ -z "$routines_list" ]]; then
        report_result "5.10" "Securely Define Stored Procedures and Functions DEFINER and INVOKER" 1 "Manual" "OK" \
            "No custom stored procedures or functions found in non-system schemas." ""
    else
        report_result "5.10" "Ensure Stored Procedures and Functions DEFINER and INVOKER are Securely Defined" 1 "Manual" "MANUAL" \
            "Custom stored routines found; review DEFINER and SECURITY_TYPE: $(echo "$routines_list" | tr '\n' ' ')" \
            "Inspect stored procedures/functions with 'SHOW CREATE PROCEDURE <name>;' / 'SHOW CREATE FUNCTION <name>;' and recreate with SQL SECURITY INVOKER or a least-privileged DEFINER where appropriate."
    fi
}

# ==============================================================================
# SECTION 6: Auditing and Logging
# ==============================================================================

audit_section_6() {
    print_section_header "6" "Auditing and Logging" || return 0

    # --------------------------------------------------------------------------
    # 6.1 Ensure 'log_error' is configured correctly (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local log_err_val=""
    log_err_val="$(get_mariadb_var "log_error" || true)"
    if [[ -n "$log_err_val" && "$log_err_val" != "./stderr.err" && "$log_err_val" != "stderr" ]]; then
        report_result "6.1" "Ensure 'log_error' is configured correctly" 1 "Automated" "OK" \
            "log_error is configured to '$log_err_val'." ""
    else
        report_result "6.1" "Ensure 'log_error' is configured correctly" 1 "Automated" "FAIL" \
            "log_error is '${log_err_val:-./stderr.err (or empty)}'." \
            "1. Open the MariaDB configuration file (mariadb.cnf).
2. Set 'log_error = /var/log/mysql/mariadb.err' (or a dedicated log partition path) under [mariadbd] and restart MariaDB."
    fi

    # --------------------------------------------------------------------------
    # 6.2 Ensure Log Files are Stored on a Non-System Partition (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local log_bin_base=""
    log_bin_base="$(get_mariadb_var "log_bin_basename" || true)"
    [[ -z "$log_bin_base" ]] && log_bin_base="$(get_cnf_value "log_bin" || true)"

    if [[ -n "$log_bin_base" && "$log_bin_base" != "OFF" && "$log_bin_base" != "0" ]]; then
        local lb_dir lb_mount
        lb_dir="$(dirname "$log_bin_base")"
        lb_mount="$(df -P "$lb_dir" 2>/dev/null | awk 'NR==2 {print $6}')"
        if [[ -n "$lb_mount" && "$lb_mount" != "/" && "$lb_mount" != "/var" && "$lb_mount" != "/usr" ]]; then
            report_result "6.2" "Ensure Log Files are Stored on a Non-System Partition" 1 "Automated" "OK" \
                "log_bin_basename ($log_bin_base) resides on non-system partition '$lb_mount'." ""
        else
            report_result "6.2" "Ensure Log Files are Stored on a Non-System Partition" 1 "Automated" "FAIL" \
                "log_bin_basename ($log_bin_base) resides on system partition '${lb_mount:-/ or /var}'." \
                "1. Open the MariaDB configuration file (mariadb.cnf).
2. Locate the 'log_bin' entry and set it to a file path on a non-system partition (not /, /var, or /usr), then restart MariaDB."
        fi
    else
        report_result "6.2" "Ensure Log Files are Stored on a Non-System Partition" 1 "Automated" "FAIL" \
            "log_bin_basename is not configured on a non-system partition (current: '${log_bin_base:-unset}')." \
            "1. Open the MariaDB configuration file (mariadb.cnf).
2. Set 'log_bin' to a file path on a dedicated non-system partition (not /, /var, or /usr) and restart MariaDB."
    fi

    # --------------------------------------------------------------------------
    # 6.3 Ensure 'log_warnings' is Set to '2' (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local log_warn_val=""
    log_warn_val="$(get_mariadb_var "log_warnings" || true)"
    if [[ "$log_warn_val" == "2" ]]; then
        report_result "6.3" "Ensure 'log_warnings' is Set to '2'" 2 "Automated" "OK" \
            "log_warnings is set to 2." ""
    else
        report_result "6.3" "Ensure 'log_warnings' is Set to '2'" 2 "Automated" "FAIL" \
            "log_warnings is '${log_warn_val:-unset}' (expected 2)." \
            "Open the MariaDB configuration file (mariadb.cnf) and ensure the following line is present in the [mariadbd] section:
  log_warnings = 2
Or set dynamically with 'SET GLOBAL log_warnings = 2;'."
    fi

    # --------------------------------------------------------------------------
    # 6.4 Ensure Audit Logging Is Enabled (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local sa_logging=""
    local sa_events=""
    sa_logging="$(get_mariadb_var "server_audit_logging" || true)"
    sa_events="$(get_mariadb_var "server_audit_events" || true)"

    if [[ "$sa_logging" =~ ^(ON|1)$ ]] && echo "$sa_events" | grep -q -i "CONNECT"; then
        report_result "6.4" "Ensure Audit Logging Is Enabled" 2 "Automated" "OK" \
            "server_audit_logging=$sa_logging and server_audit_events='$sa_events'." ""
    else
        report_result "6.4" "Ensure Audit Logging Is Enabled" 2 "Automated" "FAIL" \
            "server_audit_logging='${sa_logging:-OFF/unset}', server_audit_events='${sa_events:-unset}'." \
            "Add the following to MariaDB's configuration file under [mariadb] and restart the instance:
  plugin_load_add = server_audit
  server_audit_logging = ON
  server_audit_events = CONNECT   # (and optionally QUERY,TABLE)"
    fi

    # --------------------------------------------------------------------------
    # 6.5 Ensure the Audit Plugin Can't be Unloaded (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local sa_load_opt=""
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        sa_load_opt="$(run_sql "SELECT LOAD_OPTION FROM information_schema.plugins WHERE PLUGIN_NAME='SERVER_AUDIT';" || true)"
    else
        sa_load_opt="$(get_cnf_value "server_audit" || true)"
    fi

    if [[ "$sa_load_opt" == "FORCE_PLUS_PERMANENT" ]]; then
        report_result "6.5" "Ensure the Audit Plugin Can't be Unloaded" 1 "Automated" "OK" \
            "SERVER_AUDIT plugin LOAD_OPTION is FORCE_PLUS_PERMANENT." ""
    else
        report_result "6.5" "Ensure the Audit Plugin Can't be Unloaded" 1 "Automated" "FAIL" \
            "SERVER_AUDIT LOAD_OPTION is '${sa_load_opt:-not installed/unset}' (expected FORCE_PLUS_PERMANENT)." \
            "Open the MariaDB configuration file (mariadb.cnf), add the following line in the [mariadbd] section, and restart MariaDB:
  server_audit=FORCE_PLUS_PERMANENT"
    fi

    # --------------------------------------------------------------------------
    # 6.6 Ensure Binary and Relay Logs are Encrypted (Automated) [Level 2]
    # --------------------------------------------------------------------------
    local enc_binlog_val=""
    enc_binlog_val="$(get_mariadb_var "encrypt_binlog" || true)"
    if [[ "$enc_binlog_val" =~ ^(ON|1)$ ]]; then
        report_result "6.6" "Ensure Binary and Relay Logs are Encrypted" 2 "Automated" "OK" \
            "encrypt_binlog is set to $enc_binlog_val." ""
    else
        report_result "6.6" "Ensure Binary and Relay Logs are Encrypted" 2 "Automated" "FAIL" \
            "encrypt_binlog is '${enc_binlog_val:-OFF}' (expected ON)." \
            "1. Ensure a Key Management Encryption plugin is installed and configured (see 4.9).
2. Add the following under [mariadb] in mariadb.cnf and restart MariaDB:
   encrypt_binlog=ON
3. Purge old unencrypted binary logs using 'PURGE BINARY LOGS' and 'RESET MASTER'."
    fi
}

# ==============================================================================
# SECTION 7: Authentication
# ==============================================================================

audit_section_7() {
    print_section_header "7" "Authentication" || return 0

    # --------------------------------------------------------------------------
    # 7.1 Disable use of the mysql_old_password plugin (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local old_pw_val=""
    local sec_auth_val=""
    old_pw_val="$(get_mariadb_var "old_passwords" || echo "OFF")"
    sec_auth_val="$(get_mariadb_var "secure_auth" || echo "ON")"

    if [[ "$old_pw_val" =~ ^(OFF|0)$ && "$sec_auth_val" =~ ^(ON|1)$ ]]; then
        report_result "7.1" "Disable use of the mysql_old_password plugin" 1 "Automated" "OK" \
            "old_passwords=$old_pw_val and secure_auth=$sec_auth_val." ""
    else
        report_result "7.1" "Disable use of the mysql_old_password plugin" 1 "Automated" "FAIL" \
            "old_passwords='$old_pw_val' (expected OFF/0), secure_auth='$sec_auth_val' (expected ON/1)." \
            "Add the following lines to the [mariadbd] section in mariadb.cnf and restart MariaDB:
  old_passwords=0
  secure_auth=ON"
    fi

    # --------------------------------------------------------------------------
    # 7.2 Ensure Passwords are Not Stored in the Global Configuration (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local global_pw_hits=""
    if [[ ${#CNF_FILES[@]} -gt 0 ]]; then
        global_pw_hits="$(grep -H -n -E -i "^[[:space:]]*password[[:space:]]*=" "${CNF_FILES[@]}" 2>/dev/null || true)"
    fi

    if [[ -z "$global_pw_hits" ]]; then
        report_result "7.2" "Ensure Passwords are Not Stored in the Global Configuration" 1 "Automated" "OK" \
            "No password parameter found in global MariaDB configuration files." ""
    else
        report_result "7.2" "Ensure Passwords are Not Stored in the Global Configuration" 1 "Automated" "FAIL" \
            "Password parameter found in global configuration file(s): $(echo "$global_pw_hits" | tr '\n' ' ')" \
            "Remove 'password' entries from all sections of the global configuration file (mariadb.cnf / my.cnf) and use a restricted user-specific ~/.mariadb.cnf file (chmod 600) instead."
    fi

    # --------------------------------------------------------------------------
    # 7.3 Ensure strong authentication is utilized for all accounts (Automated) [Level 1]
    # --------------------------------------------------------------------------
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local weak_auth_users=""
        weak_auth_users="$(run_sql "SELECT CONCAT(User, '@', host, '(plugin=', IF(plugin='', 'EMPTY', plugin), ')') FROM mysql.user WHERE (plugin IN ('mysql_native_password', 'mysql_old_password', '') AND NOT (User = 'root' AND authentication_string = 'invalid') AND NOT (User = 'mysql' AND authentication_string = 'invalid'));" || true)"
        if [[ -z "$weak_auth_users" ]]; then
            report_result "7.3" "Ensure strong authentication is utilized for all accounts" 1 "Automated" "OK" \
                "No accounts use weak authentication plugins (mysql_native_password, mysql_old_password, or empty)." ""
        else
            report_result "7.3" "Ensure strong authentication is utilized for all accounts" 1 "Automated" "FAIL" \
                "Accounts using weak authentication plugins: $(echo "$weak_auth_users" | tr '\n' ' ')" \
                "Remediate weak authentication accounts in MariaDB:
- For root:        ALTER USER 'root'@'localhost' IDENTIFIED VIA 'unix_socket';
- For mysql:       SET PASSWORD FOR 'mysql'@'localhost' = 'invalid';
- For mariadb.sys: SET PASSWORD FOR 'mariadb.sys'@'localhost' = 'invalid';
- For other users: Configure strong authentication plugins (ed25519, gssapi, pam, or unix_socket) via ALTER USER."
        fi
    else
        report_result "7.3" "Ensure strong authentication is utilized for all accounts" 1 "Automated" "SKIP" \
            "Database connection required to inspect mysql.user authentication plugins." \
            "Ensure no user accounts use 'mysql_native_password', 'mysql_old_password', or ''; use unix_socket, ed25519, pam, or gssapi."
    fi

    # --------------------------------------------------------------------------
    # 7.4 Ensure Password Complexity Policies are in Place (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local spc_status=""
    local cpc_status=""
    local spc_len=""
    local strict_pw=""
    local cpc_dict=""

    spc_len="$(get_mariadb_var "simple_password_check_minimal_length" || echo "0")"
    strict_pw="$(get_mariadb_var "strict_password_validation" || echo "OFF")"
    cpc_dict="$(get_mariadb_var "cracklib_password_check_dictionary" || true)"

    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        spc_status="$(run_sql "SELECT CONCAT(PLUGIN_STATUS, ':', LOAD_OPTION) FROM information_schema.plugins WHERE PLUGIN_NAME = 'simple_password_check';" || true)"
        cpc_status="$(run_sql "SELECT CONCAT(PLUGIN_STATUS, ':', LOAD_OPTION) FROM information_schema.plugins WHERE PLUGIN_NAME = 'cracklib_password_check';" || true)"
    else
        spc_status="$(get_cnf_value "simple_password_check" || true)"
        cpc_status="$(get_cnf_value "cracklib_password_check" || true)"
    fi

    if [[ "$spc_status" =~ FORCE_PLUS_PERMANENT && "$cpc_status" =~ FORCE_PLUS_PERMANENT && "$spc_len" -ge 14 && "$strict_pw" =~ ^(ON|1)$ && -n "$cpc_dict" ]]; then
        report_result "7.4" "Ensure Password Complexity Policies are in Place" 1 "Automated" "OK" \
            "simple_password_check ($spc_status, min_len=$spc_len), cracklib_password_check ($cpc_status, dict=$cpc_dict), strict_password_validation=$strict_pw." ""
    else
        report_result "7.4" "Ensure Password Complexity Policies are in Place" 1 "Automated" "FAIL" \
            "simple_password_check='${spc_status:-not active}' (min_length=${spc_len}), cracklib_password_check='${cpc_status:-not active}' (dict='${cpc_dict:-unset}'), strict_password_validation='${strict_pw}'." \
            "1. Install the password check plugins:
   INSTALL SONAME 'simple_password_check';
   INSTALL SONAME 'cracklib_password_check';
2. Add the following lines to MariaDB configuration files under [mariadbd]:
   plugin_load_add = simple_password_check
   simple_password_check = FORCE_PLUS_PERMANENT
   simple_password_check_minimal_length = 14
   plugin_load_add = cracklib_password_check
   cracklib_password_check = FORCE_PLUS_PERMANENT
   strict_password_validation = ON
   cracklib_password_check_dictionary = <path_to_dictionary>"
    fi

    # --------------------------------------------------------------------------
    # 7.5 Ensure No Users Have Wildcard Hostnames (Automated) [Level 1]
    # --------------------------------------------------------------------------
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local wildcard_users=""
        wildcard_users="$(run_sql "SELECT CONCAT(user, '@', host) FROM mysql.user WHERE host = '%';" || true)"
        if [[ -z "$wildcard_users" ]]; then
            report_result "7.5" "Ensure No Users Have Wildcard Hostnames" 1 "Automated" "OK" \
                "No user accounts have wildcard ('%') hostnames." ""
        else
            report_result "7.5" "Ensure No Users Have Wildcard Hostnames" 1 "Automated" "FAIL" \
                "Users with wildcard ('%') hostnames found: $(echo "$wildcard_users" | tr '\n' ' ')" \
                "Enumerate all users returned by 'SELECT user, host FROM mysql.user WHERE host = \"%\";' and either ALTER/RENAME the user's host to a specific IP/hostname or DROP the user:
  RENAME USER '<user>'@'%' TO '<user>'@'<specific_host>';
  # Or:
  DROP USER '<user>'@'%';"
        fi
    else
        report_result "7.5" "Ensure No Users Have Wildcard Hostnames" 1 "Automated" "SKIP" \
            "Database connection required to query mysql.user for wildcard hostnames." \
            "Run 'SELECT user, host FROM mysql.user WHERE host = \"%\";' and replace '%' with specific hosts or DROP the user."
    fi

    # --------------------------------------------------------------------------
    # 7.6 Ensure No Anonymous Accounts Exist (Automated) [Level 1]
    # --------------------------------------------------------------------------
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local anon_users=""
        anon_users="$(run_sql "SELECT CONCAT(\"''@'\", host, \"'\") FROM mysql.user WHERE user = '';" || true)"
        if [[ -z "$anon_users" ]]; then
            report_result "7.6" "Ensure No Anonymous Accounts Exist" 1 "Automated" "OK" \
                "No anonymous user accounts ('') exist in mysql.user." ""
        else
            report_result "7.6" "Ensure No Anonymous Accounts Exist" 1 "Automated" "FAIL" \
                "Anonymous accounts found: $(echo "$anon_users" | tr '\n' ' ')" \
                "Drop all anonymous user accounts or run 'mariadb-secure-installation':
  DROP USER ''@'<host>';"
        fi
    else
        report_result "7.6" "Ensure No Anonymous Accounts Exist" 1 "Automated" "SKIP" \
            "Database connection required to query mysql.user for anonymous accounts." \
            "Run 'SELECT user, host FROM mysql.user WHERE user = \"\";' and DROP any anonymous accounts found."
    fi
}

# ==============================================================================
# SECTION 8: Network
# ==============================================================================

audit_section_8() {
    print_section_header "8" "Network" || return 0

    # --------------------------------------------------------------------------
    # 8.1 Ensure 'require_secure_transport' is Set to 'ON' and 'have_ssl' is Set to 'YES' (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local req_sec_trans=""
    local have_ssl_val=""
    req_sec_trans="$(get_mariadb_var "require_secure_transport" || echo "OFF")"
    have_ssl_val="$(get_mariadb_var "have_ssl" || echo "DISABLED")"

    if [[ "$req_sec_trans" =~ ^(ON|1)$ && "$have_ssl_val" == "YES" ]]; then
        report_result "8.1" "Ensure 'require_secure_transport' is Set to 'ON' and 'have_ssl' is Set to 'YES'" 1 "Automated" "OK" \
            "require_secure_transport=$req_sec_trans and have_ssl=$have_ssl_val." ""
    else
        report_result "8.1" "Ensure 'require_secure_transport' is Set to 'ON' and 'have_ssl' is Set to 'YES'" 1 "Automated" "FAIL" \
            "require_secure_transport='$req_sec_trans' (expected ON/1), have_ssl='$have_ssl_val' (expected YES)." \
            "1. Configure SSL/TLS certificates (ssl_ca, ssl_cert, ssl_key) in mariadb.cnf so have_ssl reports YES.
2. Enable require_secure_transport in your MariaDB configuration file under [mariadbd] and restart MariaDB:
   require_secure_transport=ON"
    fi

    # --------------------------------------------------------------------------
    # 8.2 Ensure 'ssl_type' is Set to 'ANY', 'X509', or 'SPECIFIED' for All Remote Users (Automated) [Level 1]
    # --------------------------------------------------------------------------
    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local insecure_remote=""
        insecure_remote="$(run_sql "SELECT CONCAT(user, '@', host, '(ssl_type=', IF(ssl_type='', 'NONE', ssl_type), ')') FROM mysql.user WHERE NOT HOST IN ('::1', '127.0.0.1', 'localhost') AND ssl_type NOT IN ('ANY', 'X509', 'SPECIFIED');" || true)"
        if [[ -z "$insecure_remote" ]]; then
            report_result "8.2" "Ensure 'ssl_type' is Set to 'ANY', 'X509', or 'SPECIFIED' for All Remote Users" 1 "Automated" "OK" \
                "All remote user accounts have ssl_type set to ANY, X509, or SPECIFIED (or no remote accounts exist)." ""
        else
            report_result "8.2" "Ensure 'ssl_type' is Set to 'ANY', 'X509', or 'SPECIFIED' for All Remote Users" 1 "Automated" "FAIL" \
                "Remote user(s) without enforced SSL/TLS: $(echo "$insecure_remote" | tr '\n' ' ')" \
                "Use the ALTER USER statement to require SSL/TLS for all remote accounts:
  ALTER USER '<user>'@'<remote_host>' REQUIRE SSL;
  # Or for stronger client certificate verification:
  ALTER USER '<user>'@'<remote_host>' REQUIRE X509;"
        fi
    else
        report_result "8.2" "Ensure 'ssl_type' is Set to 'ANY', 'X509', or 'SPECIFIED' for All Remote Users" 1 "Automated" "SKIP" \
            "Database connection required to inspect ssl_type for remote users." \
            "Run 'SELECT user, host, ssl_type FROM mysql.user WHERE NOT HOST IN (\"::1\", \"127.0.0.1\", \"localhost\");' and enforce TLS with:
  ALTER USER '<user>'@'<remote_host>' REQUIRE SSL;"
    fi

    # --------------------------------------------------------------------------
    # 8.3 Set Maximum Connection Limits for Server and per User (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local max_conn=""
    local max_user_conn=""
    max_conn="$(get_mariadb_var "max_connections" || true)"
    max_user_conn="$(get_mariadb_var "max_user_connections" || true)"

    if [[ "$DB_CONNECTED" -eq 1 ]]; then
        local unlimited_users=""
        unlimited_users="$(run_sql "SELECT CONCAT(user, '@', host) FROM mysql.user WHERE user NOT LIKE 'mysql.%' AND user NOT LIKE 'root' AND max_connections = 0 AND max_user_connections = 0;" || true)"
        if [[ -n "$max_conn" && "$max_conn" -gt 0 && -n "$max_user_conn" && "$max_user_conn" -gt 0 ]]; then
            report_result "8.3" "Set Maximum Connection Limits for Server and per User" 1 "Manual" "OK" \
                "Global connection limits are active (max_connections=$max_conn, max_user_connections=$max_user_conn)." ""
        else
            report_result "8.3" "Set Maximum Connection Limits for Server and per User" 1 "Manual" "FAIL" \
                "max_connections='${max_conn:-unset}', max_user_connections='${max_user_conn:-0 (unlimited)}'. Accounts with 0 per-user limits: $(echo "$unlimited_users" | tr '\n' ' ')" \
                "Configure global connection limits in mariadb.cnf under [mariadbd] (and/or dynamically):
  SET GLOBAL max_user_connections=<desired_numeric_value>;
  SET GLOBAL max_connections=<desired_numeric_value>;
And/or set per-user limits:
  ALTER USER '<user>'@'<host>' WITH MAX_CONNECTIONS_PER_HOUR <n> MAX_USER_CONNECTIONS <m>;"
        fi
    else
        if [[ -n "$max_conn" && "$max_conn" -gt 0 && -n "$max_user_conn" && "$max_user_conn" -gt 0 ]]; then
            report_result "8.3" "Set Maximum Connection Limits for Server and per User" 1 "Manual" "OK" \
                "Configured max_connections=$max_conn and max_user_connections=$max_user_conn." ""
        else
            report_result "8.3" "Set Maximum Connection Limits for Server and per User" 1 "Manual" "FAIL" \
                "max_connections='${max_conn:-unset}', max_user_connections='${max_user_conn:-0 (unlimited)}'." \
                "Set max_connections and max_user_connections to positive numeric values in mariadb.cnf under [mariadbd]."
        fi
    fi
}

# ==============================================================================
# SECTION 9: Replication
# ==============================================================================

audit_section_9() {
    print_section_header "9" "Replication" || return 0

    if [[ "$DB_CONNECTED" -ne 1 ]]; then
        for item in \
            "9.1|Ensure Replication Traffic is Secured|1|Manual|STOP REPLICA; CHANGE MASTER TO MASTER_SSL=1; START REPLICA;" \
            "9.2|Ensure 'MASTER_SSL_VERIFY_SERVER_CERT' is enabled|1|Automated|STOP REPLICA; CHANGE MASTER TO MASTER_SSL_VERIFY_SERVER_CERT=1; START REPLICA;" \
            "9.3|Ensure 'super_priv' is Not Set to 'Y' for Replication Users|1|Automated|REVOKE SUPER ON *.* FROM '<repl_user>';" \
            "9.4|Ensure only approved ciphers are used for Replication|2|Manual|STOP REPLICA; CHANGE MASTER TO MASTER_SSL_CIPHER='ECDHE-ECDSA-AES128-GCM-SHA256'; START REPLICA;" \
            "9.5|Ensure mutual TLS is enabled|1|Manual|Configure MASTER_SSL_CERT and MASTER_SSL_KEY on REPLICA and 'ALTER USER <repl_user> REQUIRE X509;' on PRIMARY."; do
            IFS='|' read -r cid ctitle clvl ctype crem <<< "$item"
            report_result "$cid" "$ctitle" "$clvl" "$ctype" "SKIP" \
                "Database connection required to inspect replication status and replication user privileges." "$crem"
        done
        return
    fi

    local replica_status=""
    replica_status="$(run_sql_vertical "SHOW REPLICA STATUS" || run_sql_vertical "SHOW SLAVE STATUS" || true)"

    local repl_ssl_allowed=""
    local repl_verify_cert=""
    local repl_ssl_cipher=""
    local repl_ssl_cert=""
    local repl_ssl_key=""

    if [[ -n "$replica_status" ]]; then
        repl_ssl_allowed="$(echo "$replica_status" | awk -F': ' '/Master_SSL_Allowed:/ {print $2}' | head -n 1)"
        repl_verify_cert="$(echo "$replica_status" | awk -F': ' '/Master_SSL_Verify_Server_Cert:/ {print $2}' | head -n 1)"
        repl_ssl_cipher="$(echo "$replica_status" | awk -F': ' '/Master_SSL_Cipher:/ {print $2}' | head -n 1)"
        repl_ssl_cert="$(echo "$replica_status" | awk -F': ' '/Master_SSL_Cert:/ {print $2}' | head -n 1)"
        repl_ssl_key="$(echo "$replica_status" | awk -F': ' '/Master_SSL_Key:/ {print $2}' | head -n 1)"
    fi

    # --------------------------------------------------------------------------
    # 9.1 Ensure Replication Traffic is Secured (Manual) [Level 1]
    # --------------------------------------------------------------------------
    if [[ -z "$replica_status" ]]; then
        report_result "9.1" "Ensure Replication Traffic is Secured" 1 "Manual" "OK" \
            "This instance is not configured as a replication replica (SHOW REPLICA STATUS returned empty)." ""
    elif [[ "$repl_ssl_allowed" == "Yes" ]]; then
        report_result "9.1" "Ensure Replication Traffic is Secured" 1 "Manual" "OK" \
            "Replication SSL is enabled (Master_SSL_Allowed = Yes)." ""
    else
        report_result "9.1" "Ensure Replication Traffic is Secured" 1 "Manual" "FAIL" \
            "Replica is configured, but Master_SSL_Allowed is '${repl_ssl_allowed:-No}'." \
            "Secure replication traffic using SSL/TLS (or VPN / SSH Tunnel / isolated private network). On the REPLICA server(s), run:
  STOP REPLICA;
  CHANGE MASTER TO MASTER_SSL=1;
  START REPLICA;"
    fi

    # --------------------------------------------------------------------------
    # 9.2 Ensure 'MASTER_SSL_VERIFY_SERVER_CERT' is enabled (Automated) [Level 1]
    # --------------------------------------------------------------------------
    if [[ -z "$replica_status" ]]; then
        report_result "9.2" "Ensure 'MASTER_SSL_VERIFY_SERVER_CERT' is enabled" 1 "Automated" "OK" \
            "Not a replication replica (not applicable / compliant)." ""
    elif [[ "$repl_verify_cert" == "Yes" ]]; then
        report_result "9.2" "Ensure 'MASTER_SSL_VERIFY_SERVER_CERT' is enabled" 1 "Automated" "OK" \
            "Master_SSL_Verify_Server_Cert is set to Yes." ""
    else
        report_result "9.2" "Ensure 'MASTER_SSL_VERIFY_SERVER_CERT' is enabled" 1 "Automated" "FAIL" \
            "Master_SSL_Verify_Server_Cert is '${repl_verify_cert:-No}' (expected Yes)." \
            "On the REPLICA server, enable primary server certificate verification:
  STOP REPLICA;
  CHANGE MASTER TO MASTER_SSL_VERIFY_SERVER_CERT=1;
  START REPLICA;"
    fi

    # --------------------------------------------------------------------------
    # 9.3 Ensure 'super_priv' is Not Set to 'Y' for Replication Users (Automated) [Level 1]
    # --------------------------------------------------------------------------
    local admin_in_list
    admin_in_list="$(to_sql_in_list "$ADMIN_USERS")"
    local repl_only_in_list
    repl_only_in_list="$(to_sql_in_list "$REPL_USERS")"

    local repl_super_users=""
    repl_super_users="$(run_sql "SELECT CONCAT(user, '@', host) FROM mysql.user WHERE (user IN (${repl_only_in_list}) OR (Repl_slave_priv = 'Y' AND user NOT IN (${admin_in_list}))) AND Super_priv = 'Y';" || true)"
    if [[ -z "$repl_super_users" ]]; then
        report_result "9.3" "Ensure 'super_priv' is Not Set to 'Y' for Replication Users" 1 "Automated" "OK" \
            "No replication users have Super_priv = 'Y'." ""
    else
        report_result "9.3" "Ensure 'super_priv' is Not Set to 'Y' for Replication Users" 1 "Automated" "FAIL" \
            "Replication user(s) granted SUPER privilege: $(echo "$repl_super_users" | tr '\n' ' ')" \
            "Revoke SUPER privilege from each replication user:
  REVOKE SUPER ON *.* FROM '<replication_user>'@'<host>';"
    fi

    # --------------------------------------------------------------------------
    # 9.4 Ensure only approved ciphers are used for Replication (Manual) [Level 2]
    # --------------------------------------------------------------------------
    if [[ -z "$replica_status" ]]; then
        report_result "9.4" "Ensure only approved ciphers are used for Replication" 2 "Manual" "OK" \
            "Not a replication replica (not applicable / compliant)." ""
    elif [[ -n "$repl_ssl_cipher" ]] && ! echo "$repl_ssl_cipher" | grep -q -E -i "(NULL|RC4|DES|3DES|MD5|EXP|PSK|SRP)"; then
        report_result "9.4" "Ensure only approved ciphers are used for Replication" 2 "Manual" "OK" \
            "Master_SSL_Cipher is set to '$repl_ssl_cipher'." ""
    else
        report_result "9.4" "Ensure only approved ciphers are used for Replication" 2 "Manual" "FAIL" \
            "Master_SSL_Cipher is '${repl_ssl_cipher:-empty}'." \
            "On the REPLICA server, configure an approved strong cipher suite for replication:
  STOP REPLICA;
  CHANGE MASTER TO MASTER_SSL_CIPHER='ECDHE-ECDSA-AES128-GCM-SHA256';
  START REPLICA;"
    fi

    # --------------------------------------------------------------------------
    # 9.5 Ensure mutual TLS is enabled (Manual) [Level 1]
    # --------------------------------------------------------------------------
    local repl_non_x509=""
    repl_non_x509="$(run_sql "SELECT CONCAT(user, '@', host, '(ssl_type=', IF(ssl_type='', 'NONE', ssl_type), ')') FROM mysql.user WHERE (user IN (${repl_only_in_list}) OR (Repl_slave_priv = 'Y' AND user NOT IN (${admin_in_list}))) AND ssl_type <> 'X509';" || true)"

    if [[ -z "$replica_status" && -z "$repl_non_x509" ]]; then
        report_result "9.5" "Ensure mutual TLS is enabled" 1 "Manual" "OK" \
            "No replication users without X509 and instance is not an unconfigured replica." ""
    elif [[ -n "$replica_status" && ( -z "$repl_ssl_cert" || -z "$repl_ssl_key" ) ]] || [[ -n "$repl_non_x509" ]]; then
        report_result "9.5" "Ensure mutual TLS is enabled" 1 "Manual" "FAIL" \
            "Master_SSL_Cert='${repl_ssl_cert:-empty}', Master_SSL_Key='${repl_ssl_key:-empty}', Replication users without X509: ${repl_non_x509:-none}" \
            "1. On the REPLICA, configure client certificate and private key:
   STOP REPLICA;
   CHANGE MASTER TO
     MASTER_SSL_CERT='/etc/mysql/mariadb.conf.d/certificates/client-cert.pem',
     MASTER_SSL_KEY='/etc/mysql/mariadb.conf.d/certificates/client-key.pem';
   START REPLICA;
2. On the PRIMARY, require X.509 certificates for all replication users:
   ALTER USER '<replication_user>'@'<host>' REQUIRE X509;"
    else
        report_result "9.5" "Ensure mutual TLS is enabled" 1 "Manual" "OK" \
            "Mutual TLS is enabled for replication (Master_SSL_Cert=$repl_ssl_cert, Master_SSL_Key=$repl_ssl_key, replication users require X509)." ""
    fi
}


# ==============================================================================
# MAIN EXECUTION & SUMMARY SCORECARD
# ==============================================================================
run_section_1() { audit_section_1; }
run_section_2() { audit_section_2; }
run_section_3() { audit_section_3; }
run_section_4() { audit_section_4; }
run_section_5() { audit_section_5; }
run_section_6() { audit_section_6; }
run_section_7() { audit_section_7; }
run_section_8() { audit_section_8; }
run_section_9() { audit_section_9; }

print_summary() {
    echo -e "\n${C_BG_BLUE} [SUMMARY] ${BENCHMARK_NAME^^} AUDIT REPORT ${C_RESET}"
    echo -e "${C_BLUE}==========================================================================================${C_RESET}"
    printf "  %-36s | %7s | %7s | %7s | %7s | %7s\n" "Section" "OK" "FAIL" "MANUAL" "SKIP" "Total"
    echo -e "${C_DIM}------------------------------------------------------------------------------------------${C_RESET}"
    local s_names=(
        ""
        "1. OS Level Configuration"
        "2. Installation and Planning"
        "3. File Permissions"
        "4. General"
        "5. MariaDB Permissions"
        "6. Auditing and Logging"
        "7. Authentication"
        "8. Network"
        "9. Replication"
    )
    local s
    for s in 1 2 3 4 5 6 7 8 9; do
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
    discover_environment
    print_warning
    run_section_1
    run_section_2
    run_section_3
    run_section_4
    run_section_5
    run_section_6
    run_section_7
    run_section_8
    run_section_9
    print_summary
}

main "$@"
