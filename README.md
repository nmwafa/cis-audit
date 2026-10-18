# CIS Benchmark Security Audit Suite

Standalone, zero-install, read-only Bash security auditing suite and interactive CLI launcher covering **882 CIS Benchmark controls** across Ubuntu Linux 26.04 LTS, Ubuntu Linux 24.04 LTS, MariaDB 10.6, Apache HTTP Server 2.4, and NGINX 3.0.0.

## Quick Start (Run Directly from GitHub)

Run the interactive launcher on a Linux host with `curl` and Bash:

```bash
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash
```

Or use the GitHub raw content endpoint:

```bash
curl -s https://raw.githubusercontent.com/nmwafa/cis-audit/main/audit.sh | sudo bash
```

The launcher fetches the selected audit script from the repository when needed. To run a benchmark directly without the interactive menu, pass `--target`:

```bash
# Ubuntu Linux 26.04 LTS
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash -s -- --target 1

# Ubuntu Linux 24.04 LTS, Level 1 profile only
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash -s -- --target 2 --level 1

# MariaDB 10.6; prompt securely for the database password
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash -s -- --target 3 --db-user root --ask-pass

# Apache HTTP Server 2.4; save the report to a file
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash -s -- --target 4 --output apache-audit.txt

# NGINX; specify authorized listen ports
curl -sL https://github.com/nmwafa/cis-audit/raw/main/audit.sh | sudo bash -s -- --target 5 --nginx-ports 80,443,8443
```

Run `audit.sh --help` for the full command-line option list. When piping the launcher from `curl`, append arguments after `bash -s --`.

## Interactive Launcher

1. **Main menu:** The launcher lists audit selections `[1]`–`[6]` and displays host service detection badges (`[DETECTED]`, `[CONFIG FOUND]`, or `[NOT INSTALLED]`). Returning to the menu refreshes its display and detection results.
2. **Pre-audit options:** After choosing an audit, the launcher lets you set its profile level and applicable output, display, and target-specific settings. By default, it audits all sections and all profile levels.
3. **Run or customize:** Press **Enter** (or `r`) to start with the current settings, or choose a numbered option to modify them. Use `[d]` to reset to defaults and `[0]` or `[b]` to return to the main menu.

| Audit code | Audit program | Coverage | Pre-audit options |
| --- | --- | --- | --- |
| `[1]` | Ubuntu Linux 26.04 LTS (`cis_ubuntu_26.04.sh`) | 7 sections, 350 controls | `[1]` Profile Level · `[2]` Quiet-OK · `[3]` Output File · `[4]` Color |
| `[2]` | Ubuntu Linux 24.04 LTS (`cis_ubuntu_24.04.sh`) | 7 sections, 333 controls | `[1]` Profile Level · `[2]` Quiet-OK · `[3]` Output File · `[4]` Color |
| `[3]` | MariaDB 10.6 (`cis_mariadb_10.6.sh`) | 9 sections, 74 controls | `[1]` Profile Level · `[2]` Quiet-OK · `[3]` Output File · `[4]` Color · `[5]` DB User · `[6]` Ask-Pass · `[7]` Password · `[8]` Host · `[9]` Port · `[10]` Socket · `[11]` Defaults File · `[12]` Config File · `[13]` Admin Users · `[14]` Replication Users · `[15]` Backup Directories |
| `[4]` | Apache HTTP Server 2.4 (`cis_apache_2.4.sh`) | 12 sections, 81 controls | `[1]` Profile Level · `[2]` Quiet-OK · `[3]` Output File · `[4]` Color · `[5]` ServerRoot Prefix · `[6]` Main Config File · `[7]` Apache Binary · `[8]` DocumentRoot |
| `[5]` | NGINX 3.0.0 (`cis_nginx_v3.0.0.sh`) | 6 sections, 44 controls | `[1]` Profile Level · `[2]` Quiet-OK · `[3]` Output File · `[4]` Color · `[5]` NGINX Config Directory · `[6]` NGINX Binary · `[7]` Authorized Ports |
| `[6]` | Full CIS Audit Suite (all five benchmarks) | 882 controls | `[1]` Profile Level · `[2]` Quiet-OK · `[3]` Output File · `[4]` Color |

## Command-Line Options

Common launcher options:

| Option | Description |
| --- | --- |
| `-t, --target <1..6\|name>` | Run one target directly. Names include `ubuntu-26.04`, `ubuntu-24.04`, `mariadb`, `apache`, `nginx`, and `all`. |
| `-l, --level <1\|2\|all>` | Select a CIS profile level. Defaults to `all`. |
| `-o, --output <file>` | Save the full audit report to a file. |
| `-q, --quiet-ok` | Hide compliant `[OK]` results; show findings requiring attention. |
| `-n, --no-color` / `--color` | Disable ANSI colors, or force them even when output is piped. |
| `--once` | Execute one audit selection and exit. |
| `-h, --help` | Display help and exit. |

Target-specific options configure MariaDB credentials and connection, Apache paths, or NGINX paths and authorized ports. Use `--ask-pass` or `--defaults-file` rather than placing a database password directly in a command where it may be exposed in shell history or process listings. For example:

```bash
sudo bash audit.sh --target mariadb --db-user root --ask-pass
sudo bash audit.sh --target mariadb --db-user audit --defaults-file /root/.my.cnf
sudo bash audit.sh --target apache --apache-config /etc/apache2/apache2.conf
sudo bash audit.sh --target nginx --nginx-config-dir /etc/nginx --nginx-ports 80,443
```

## Benchmarks

| Platform | Benchmark version | Controls |
| --- | --- | ---: |
| Ubuntu Linux 26.04 LTS | v1.0.0 | 350 |
| Ubuntu Linux 24.04 LTS | v2.0.0 | 333 |
| MariaDB 10.6 | v1.1.0 | 74 |
| Apache HTTP Server 2.4 | v2.4.0 | 81 |
| NGINX | v3.0.0 | 44 |

## Audit Output

The audit scripts share a consistent output format:

* **Header:** Benchmark metadata, host OS and kernel, current user UID, selected profile and section scope, discovered target paths, and a warning when run without root privileges.
* **Sections:** `[SECTION N]` banners and `[+]` subsection dividers.
* **Control status:**
  * `[OK]` — compliant with the control criteria.
  * `[FAIL]` — non-compliant; includes the finding and remediation guidance.
  * `[MANUAL]` — requires site-specific verification; includes observed state and verification steps.
  * `[SKIP]` — could not be evaluated, commonly because required live service or database connectivity is unavailable.
* **Summary:** Per-section counts (`OK`, `FAIL`, `MANUAL`, `SKIP`, and total), overall totals, and an automated compliance pass rate.

These scripts report audit findings; they do not apply remediation changes.
