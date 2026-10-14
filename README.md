# CIS Benchmark Security Audit Suite (`cis-audit`)

Standalone, zero-install, read-only Bash security auditing suite and interactive CLI launcher covering **549 CIS Benchmark controls** across Ubuntu Linux 26.04 LTS, MariaDB 10.6, Apache HTTP Server 2.4, and NGINX 3.0.0.

## Quick Start (Run Directly from GitHub)

Run the interactive, color-coded CLI launcher directly on any target Linux host using `curl`:

```
curl -sL https://github.com/nmwafa/cis-audit/raw/main/main.sh | sudo bash

```

Or using the GitHub raw content endpoint directly:

```
curl -s https://raw.githubusercontent.com/nmwafa/cis-audit/main/main.sh | sudo bash

```

To bypass the interactive menu and run a specific benchmark or section list directly from the command line, pass `--target` and `--section` via `bash -s --`:

```
# Run CIS Ubuntu Linux 26.04 LTS Audit (all sections by default)
curl -sL https://github.com/nmwafa/cis-audit/raw/main/main.sh | sudo bash -s -- --target 1

# Run CIS Ubuntu Linux 26.04 LTS Audit on Sections 1, 3, and 5 only
curl -sL https://github.com/nmwafa/cis-audit/raw/main/main.sh | sudo bash -s -- --target 1 --section 1,3,5

# Run CIS MariaDB 10.6 Audit with custom DB user and interactive password prompt
curl -sL https://github.com/nmwafa/cis-audit/raw/main/main.sh | sudo bash -s -- --target 2 --db-user root --ask-pass

# Run CIS Apache 2.4 Audit on Sections 7-8 in Quiet-OK mode
curl -sL https://github.com/nmwafa/cis-audit/raw/main/main.sh | sudo bash -s -- --target 3 --section 7-8 --quiet-ok

# Run CIS NGINX 3.0.0 Audit with custom authorized ports
curl -sL https://github.com/nmwafa/cis-audit/raw/main/main.sh | sudo bash -s -- --target 4 --nginx-ports 80,443,8443

```

## Two-Step Interactive Launcher Flow (`main.sh`)

1. **Main Menu on Startup**: Displays only the available CIS Benchmark audit programs (`[1]`–`[5]`) along with live host service detection badges (`[DETECTED]`, `[CONFIG FOUND]`, or `[NOT INSTALLED]`).

2. **Per-Audit Section List & Options**: When you select an audit code (`1`–`4`), the launcher displays the **full numbered list of CIS Benchmark sections** for that audit program with `[SELECTED]` indicators, followed by the options specific to that audit program. Profile Level is set to `all` (Level 1 & Level 2) by default.

3. **Flexible Section Selection & Default Execution**:

   * **Press `[Enter]` (or `r`)**: Immediately runs all sections (`all`) with default settings and no custom option changes.

   * **Enter section numbers directly**: Type a single section (`3`), a comma-separated list (`1,3,5`), a range (`2-4`), or `all` to choose which sections to run, then press `[Enter]` to start the audit.

   * **Customize options via letter keys**: Use `[s]`, `[q]`, `[o]`, `[c]` (plus target-specific keys) only when you want to override a default setting.

| **Audit Code** | **Audit Program** | **Displayed Sections (\[1\]–\[N\] or all)** | **Audit-Specific Option Keys** | 
|---|---|---|---|
| `[1]` | `cis_ubuntu_26.04_audit.sh` | `1` Initial Setup · `2` Services · `3` Network · `4` Host Based Firewall · `5` Access Control · `6` Logging and Auditing · `7` System Maintenance | `[s]` Section(s), `[q]` Quiet-OK, `[o]` Output File, `[c]` Color | 
| `[2]` | `cis_mariadb_10.6_audit.sh` | `1` OS Level Config · `2` Installation and Planning · `3` File Permissions · `4` General · `5` MariaDB Permissions · `6` Auditing and Logging · `7` Authentication · `8` Network · `9` Replication | `[s]`, `[q]`, `[o]`, `[c]` plus `[u]` User, `[w]` Ask-Pass, `[p]` Password, `[h]` Host, `[P]` Port, `[S]` Socket, `[f]` Defaults File, `[C]` Config File, `[A]` Admin Users, `[R]` Repl Users, `[B]` Backup Dirs | 
| `[3]` | `cis_apache_2.4_audit.sh` | `1` Planning/Install · `2` Minimize Modules · `3` Principles/Perms · `4` Access Control · `5` Minimize Features · `6` Operations/Logging · `7` SSL/TLS · `8` Info Leakage · `9` DoS Mitigations · `10` Request Limits · `11` SELinux · `12` AppArmor | `[s]`, `[q]`, `[o]`, `[c]` plus `[p]` ServerRoot Prefix, `[f]` Main Config File, `[B]` Apache Binary, `[D]` DocumentRoot | 
| `[4]` | `cis_nginx_benchmark_v3.0.0.sh` | `1` Initial Setup · `2` Basic Configuration · `3` Logging · `4` Encryption (TLS/SSL) · `5` Request Filtering and Restrictions · `6` Mandatory Access Control | `[s]`, `[q]`, `[o]`, `[c]` plus `[f]` NGINX Config Dir, `[B]` NGINX Binary, `[p]` Authorized Ports | 
| `[5]` | Full CIS Audit Suite (All 4) | All sections across all 4 benchmarks (549 Controls) | `[q]` Quiet-OK, `[o]` Output File, `[c]` Color | 

## Standardized Code Structure & Output Formatting

All four CIS audit scripts share a unified architecture and visual output:

* **Unified Header Banner**: Displays an ASCII art title, benchmark metadata, host OS/kernel telemetry, current user UID, active section filter (`Profile Level: all`), auto-discovered target binaries/config paths, and a non-root privilege warning when `UID != 0`.

* **Unified Section & Subsection Formatting**: Uses `[SECTION N]` banners and `[+]` subsection dividers encapsulated in `run_section_1` through `run_section_N` functions, supporting single sections (`-s 3`), comma-separated lists (`-s 1,3,5`), and ranges (`-s 2-4`).

* **Unified Control Status Badges**:

  * `[OK]` (Green): Control is compliant with CIS Benchmark criteria.

  * `[FAIL]` (Red): Control is non-compliant; displays the exact `Finding` and step-by-step `Remediation` commands.

  * `[MANUAL]` (Yellow): Control requires site-specific policy verification; displays observed state and verification steps.

  * `[SKIP]` (Magenta): Control requires live service/database connectivity not currently available.

* **Unified Per-Section Summary Scorecard**: Outputs a section-by-section breakdown table (`OK`, `FAIL`, `MANUAL`, `SKIP`, `Total`) for all executed sections along with overall totals and the automated compliance pass rate percentage.

---

> Build with: Gemini 4 Argon