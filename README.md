# CIS Benchmark Security Audit Suite

Standalone, zero-install, read-only Bash security auditing suite and interactive CLI launcher covering **882 CIS Benchmark controls** across Ubuntu Linux 26.04 LTS, Ubuntu Linux 24.04 LTS, MariaDB 10.6, Apache HTTP Server 2.4, and NGINX 3.0.0.

## Quick Start (Run Directly from GitHub)

Run the interactive CLI launcher directly on any target Linux host using `curl`:

```bash
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash
```

Or using the GitHub raw content endpoint directly:

```bash
curl -s https://raw.githubusercontent.com/nmwafa/cis-audit/main/audit.sh | sudo bash
```

To bypass the interactive menu and run a specific benchmark directly from the command line, pass `--target` via `bash -s --`:

```bash
# Run CIS Ubuntu Linux 26.04 LTS Audit (all sections by default)
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash -s -- --target 1

# Run CIS Ubuntu Linux 24.04 LTS Audit (all sections by default)
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash -s -- --target 2

# Run CIS MariaDB 10.6 Audit with custom DB user and interactive password prompt
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash -s -- --target 3 --db-user root --ask-pass

# Run CIS Apache 2.4 Audit in Quiet-OK mode
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash -s -- --target 4 --quiet-ok

# Run CIS NGINX 3.0.0 Audit with custom authorized ports
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash -s -- --target 5 --nginx-ports 80,443,8443
```

## Two-Step Interactive Launcher Flow

1. **Main Menu on Startup**: Clears the screen, displays the launcher banner, and lists the available CIS Benchmark audit programs (`[1]`–`[6]`) along with live host service detection badges (`[DETECTED]`, `[CONFIG FOUND]`, or `[NOT INSTALLED]`). Returning to the main menu automatically clears the screen and refreshes the banner.

2. **Numbered Pre-Audit Options Menu**: When you select an audit code (`1`–`6`), the launcher displays a clean, numbered list of options (`[1]`, `[2]`, `[3]`, ...) specific to that audit program. All sections and all profile levels (`all`) are included automatically.

3. **Default Execution Unless Modified**:

   * **Press `[Enter]` (or `r`)**: Immediately starts the audit across all sections with default settings and no custom option changes.

   * **Select a numbered option (`1`, `2`, `3`, ...)**: Toggle or customize only the specific option(s) you want before starting the audit, or press `[d]` to reset defaults and `[0]` / `[b]` to return to the main menu.

| **Audit Code** | **Audit Program** | **Coverage** | **Numbered Pre-Audit Options** |
| --- | --- | --- | --- |
| `[1]` | `cis_ubuntu_26.04_audit.sh` | All 7 Sections (350 Controls) | `[1]` Quiet-OK Mode · `[2]` Output File · `[3]` Color Output |
| `[2]` | `cis_ubuntu_24.04_audit.sh` | All 7 Sections (333 Controls) | `[1]` Quiet-OK Mode · `[2]` Output File · `[3]` Color Output |
| `[3]` | `cis_mariadb_10.6_audit.sh` | All 9 Sections (74 Controls) | `[1]` Quiet-OK · `[2]` Output File · `[3]` Color · `[4]` DB User · `[5]` Ask-Pass · `[6]` Password · `[7]` Host · `[8]` Port · `[9]` Socket · `[10]` Defaults File · `[11]` Config File · `[12]` Admin Users · `[13]` Repl Users · `[14]` Backup Dirs |
| `[4]` | `cis_apache_2.4_audit.sh` | All 12 Sections (81 Controls) | `[1]` Quiet-OK · `[2]` Output File · `[3]` Color · `[4]` ServerRoot Prefix · `[5]` Main Config File · `[6]` Apache Binary · `[7]` DocumentRoot |
| `[5]` | `cis_nginx_benchmark_v3.0.0.sh` | All 6 Sections (44 Controls) | `[1]` Quiet-OK · `[2]` Output File · `[3]` Color · `[4]` NGINX Config Dir · `[5]` NGINX Binary · `[6]` Authorized Ports |
| `[6]` | Full CIS Audit Suite (All 5) | All 5 Benchmarks (882 Controls) | `[1]` Quiet-OK Mode · `[2]` Output File · `[3]` Color Output |

## Standardized Code Structure & Output Formatting

All five CIS audit scripts share a unified architecture and visual output:

* **Unified Header Banner**: Displays an ASCII art title, benchmark metadata, host OS/kernel telemetry, current user UID, active profile/section scope (`all`), auto-discovered target binaries/config paths, and a non-root privilege warning when `UID != 0`.

* **Unified Section & Subsection Formatting**: Uses `[SECTION N]` banners and `[+]` subsection dividers encapsulated in `run_section_1` through `run_section_N` functions.

* **Unified Control Status Badges**:

  * `[OK]` (Green): Control is compliant with CIS Benchmark criteria.

  * `[FAIL]` (Red): Control is non-compliant; displays the exact `Finding` and step-by-step `Remediation` commands.

  * `[MANUAL]` (Yellow): Control requires site-specific policy verification; displays observed state and verification steps.

  * `[SKIP]` (Magenta): Control requires live service/database connectivity not currently available.

* **Unified Per-Section Summary Scorecard**: Outputs a section-by-section breakdown table (`OK`, `FAIL`, `MANUAL`, `SKIP`, `Total`) for all executed sections along with overall totals and the automated compliance pass rate percentage.