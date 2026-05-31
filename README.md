# PowerShell Automation

A collection of Windows PowerShell automation scripts for system administration, security incident response, and compliance auditing. All scripts are idempotent, use structured output, and follow production scripting practices.

## Contents

```
system/
  organize_docs.ps1         — Sort Documents folder into structured category directories by type
  scan_onedrive.ps1         — Audit OneDrive contents: inventory files by type, size, location
  PostReset_Bootstrap.ps1   — Post-reset recovery automation: restore tools, settings, config
  recategorize_docs.ps1     — Reclassify misplaced documents into correct categories
  subcategorize_other.ps1   — Secondary pass for uncategorized file types

security/
  Get-FailedLogins.ps1      — Query Event Log (4625) for failed logins, threshold analysis, CSV export
  Block-SourceIP.ps1        — Add Windows Firewall block rule with ShouldProcess safety and logging
  Get-SecurityStatus.ps1    — Windows security posture report: execution policy, failed logins, suspicious services

compliance/
  data_inventory_report.ps1 — Recursive file inventory with category classification and retention flagging (CSV output)
```

## Design Principles

- **Idempotent**: Safe to run multiple times — converges to target state without side effects
- **Structured output**: `PSCustomObject` pipeline output, `Export-Csv` for auditability
- **ShouldProcess**: Destructive operations support `-WhatIf` and `-Confirm`
- **Error handling**: Precondition checks before acting on file system or network resources
- **No hardcoded paths**: Uses `$env:USERPROFILE`, `$env:SystemRoot`, parameter blocks

## Requirements

- Windows PowerShell 5.1+
- `Get-FailedLogins.ps1` and `Get-SecurityStatus.ps1` require running as Administrator for Event Log access
- `Block-SourceIP.ps1` requires Administrator for Windows Firewall rule creation

---

*Technologies: Windows PowerShell 5.1+, Windows Event Log, Windows Firewall, Task Scheduler*
