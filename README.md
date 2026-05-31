# powershell-automation

![License](https://img.shields.io/github/license/mvahora2023/powershell-automation)
![Last Commit](https://img.shields.io/github/last-commit/mvahora2023/powershell-automation)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)

Windows PowerShell automation scripts for system administration, security incident response, and compliance auditing. All scripts are idempotent, produce structured output, and follow production scripting practices.

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
