# powershell-automation

![License](https://img.shields.io/github/license/mvahora2023/powershell-automation)
![Last Commit](https://img.shields.io/github/last-commit/mvahora2023/powershell-automation)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)

Windows PowerShell automation scripts for system administration, security incident response, and compliance auditing.

**Safety update (Nov 2026):** `system/organize_docs.ps1` and `system/recategorize_docs.ps1` now preview changes by default and require `-Apply` before copying or moving files. Paths are user-configurable, and recategorization never overwrites an existing file. Use your own private CSV mapping instead of placing personal filenames in the public repository.

Example: `powershell -File system/organize_docs.ps1 -SourceRoot "$env:USERPROFILE\\OneDrive"`

After reviewing the preview: `powershell -File system/organize_docs.ps1 -Apply`

Recategorization example: `powershell -File system/recategorize_docs.ps1 -MappingCsv C:\\Local\\mapping.csv -Apply -Confirm`
 The scripts illustrate repeatable administration workflows, structured reporting, and safeguards where appropriate. Review each script's parameters and side effects before running; do not assume every operation is idempotent or production-validated.

---

## Contents

### `system/` — Windows System Administration

| Script | Purpose |
|---|---|
| `organize_docs.ps1` | Sort a Documents folder into structured category directories by file type |
| `scan_onedrive.ps1` | Audit cloud storage contents — inventory files by type, size, and location |
| `PostReset_Bootstrap.ps1` | Post-reset recovery automation — restore tools, settings, and configuration |
| `recategorize_docs.ps1` | Reclassify misplaced documents into correct category directories |
| `subcategorize_other.ps1` | Secondary-pass sorting for uncategorized file types |

### `security/` — Incident Response & Security Posture

| Script | Purpose |
|---|---|
| `Get-FailedLogins.ps1` | Query Event Log (ID 4625) for failed login attempts — threshold analysis, CSV export |
| `Block-SourceIP.ps1` | Add a Windows Firewall inbound block rule with `-WhatIf` safety and structured logging |
| `Get-SecurityStatus.ps1` | Windows security posture report — execution policy, recent failures, suspicious services |

### `compliance/` — Auditing & Governance

| Script | Purpose |
|---|---|
| `data_inventory_report.ps1` | Recursive file inventory — classifies by extension, flags retention age, exports CSV |

---

## Design Principles

**Idempotent** — Safe to run multiple times. Scripts converge the system to a target state without creating duplicates or errors on repeat execution.

**Structured output** — All scripts return `PSCustomObject` pipeline output. Results are pipeable to `Export-Csv`, `ConvertTo-Json`, `Where-Object`, or any downstream tool.

**ShouldProcess** — `Block-SourceIP.ps1` and any destructive operations support `-WhatIf` and `-Confirm` for safe preview before execution.

**No hardcoded paths** — Scripts use `$env:USERPROFILE`, `$env:SystemRoot`, and parameter blocks. No machine-specific values.

---

## Requirements

- **Windows PowerShell 5.1+** (all scripts)
- **Administrator privileges** required for:
  - `Get-FailedLogins.ps1` — Event Log access
  - `Block-SourceIP.ps1` — Windows Firewall rule creation
  - `Get-SecurityStatus.ps1` — Full Event Log and service inspection

---

## Quick Start

```powershell
# Audit failed login attempts in the last 24 hours
.\security\Get-FailedLogins.ps1 -HoursBack 24 -Threshold 5

# Preview a firewall block before applying it
.\security\Block-SourceIP.ps1 -IPAddress "192.168.1.100" -WhatIf

# Run a file inventory on a folder and export CSV
.\compliance\data_inventory_report.ps1 -RootPath "C:\Users\Public\Documents" -OutputPath ".\inventory.csv"

# Organize Documents folder
.\system\organize_docs.ps1 -SourcePath "$env:USERPROFILE\Documents"
```

---

## License

[MIT](LICENSE) — see the LICENSE file for details.

## Interactive project dashboard (November 2026)

- **[Open this project's public interactive explorer](https://arsh-project-lab.vercel.app/powershell-automation/index.html)**
- **[Run the standalone HTML locally](dashboard/index.html)** (no account or service required)
- **[Open the complete public Project Lab](https://arsh-project-lab.vercel.app/)**

Inspect script purposes, safety labels, and source files; the site does not execute scripts. Source-linked sample data is embedded for offline inspection. Search, group filters and CSV export work locally; checklist review marks (where available) are browser-local only. The page is not a live backend, and changes in this repository will require a separate Vercel deployment until a Git integration is enabled. [Dashboard validation source](tests/dashboard_ui.test.mjs).

## Data modes and privacy (November 2026)

- **Default:** The existing dashboard or portfolio view displays labeled synthetic or authored demonstration material. The GitHub profile index is the exception: it lists **actual public repositories** and uses separate synthetic UI tests, not invented projects.
- **Public references:** Open the project's dashboard and choose a verified public source. Records load only when you click **Load public references**; source provenance and retrieval information appear alongside the results. Public references never overwrite fictional KPIs, audit findings, or simulated incident results.
- **Local data:** Disabled for the public web interface. No local files, personal accounts, Windows logs, connected devices, or private GitHub repositories are imported. Other command-line utilities in this repository remain separate from the public web interface.
- **Source policy:** See [source manifest](data/source-manifest.json). Public fetches may be limited by third-party availability, rate limits, and browser security restrictions; the synthetic view works without them.
- **Safety:** Do not publish personal documents, tokens, passwords, real user-directory paths, or identifying log records. Existing Git history may retain older versions; replacing a current file does not erase history.
