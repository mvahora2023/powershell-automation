<#
.SYNOPSIS
    Performs a real-time Windows security posture assessment and returns a
    structured status report.

.DESCRIPTION
    Checks four security dimensions:
      1. PowerShell Execution Policy scope (restrictive vs. permissive)
      2. Failed login count from EventID 4625 in the last 24 hours
      3. Running services with suspicious naming patterns
      4. Recent PowerShell ScriptBlock log entries (EventID 4104, last 1 hour)

    Returns a PSCustomObject with individual check results and an overall
    status rating (Clean / Warning / Alert).

    Output can be used directly in the console or piped to ConvertTo-Json
    for SIEM or log ingestion.

.PARAMETER LookbackHours
    How many hours back to query for failed logon events.
    Default: 24

.PARAMETER FailedLoginWarningThreshold
    Number of EventID 4625 failures in the lookback window that triggers
    a Warning. Default: 10

.PARAMETER FailedLoginAlertThreshold
    Number of EventID 4625 failures in the lookback window that triggers
    an Alert. Default: 50

.PARAMETER ScriptBlockLookbackMinutes
    How many minutes back to query for EventID 4104 ScriptBlock log entries.
    Default: 60

.EXAMPLE
    .\Get-SecurityStatus.ps1
    # Runs with default parameters, outputs report to console.

.EXAMPLE
    .\Get-SecurityStatus.ps1 -LookbackHours 48 -FailedLoginAlertThreshold 100
    # Checks last 48 hours of failed logins, alert threshold at 100.

.EXAMPLE
    .\Get-SecurityStatus.ps1 | ConvertTo-Json -Depth 5
    # Output as JSON for SIEM or log pipeline ingestion.

.NOTES
    Author:  Mahmadarsh Vahora
    Version: 1.0
    Requires: Windows PowerShell 5.1+ or PowerShell 7+
    Requires: Run as Administrator for full Security Event Log access.
              Script will degrade gracefully if run without admin rights.
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateRange(1, 168)]
    [int] $LookbackHours = 24,

    [Parameter()]
    [ValidateRange(1, 10000)]
    [int] $FailedLoginWarningThreshold = 10,

    [Parameter()]
    [ValidateRange(1, 10000)]
    [int] $FailedLoginAlertThreshold = 50,

    [Parameter()]
    [ValidateRange(1, 1440)]
    [int] $ScriptBlockLookbackMinutes = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'


# ---------------------------------------------------------------------------
# Helper: Status Severity Calculation
# ---------------------------------------------------------------------------

function Get-OverallStatus {
    param ([string[]] $CheckStatuses)
    if ($CheckStatuses -contains 'Alert')   { return 'Alert' }
    if ($CheckStatuses -contains 'Warning') { return 'Warning' }
    return 'Clean'
}


# ---------------------------------------------------------------------------
# Check 1: PowerShell Execution Policy Scope
# ---------------------------------------------------------------------------

function Get-ExecutionPolicyCheck {
    <#
    .DESCRIPTION
        Evaluates the effective execution policy at each scope.
        An unrestricted or bypass policy at CurrentUser or Process scope
        may indicate a threat actor has set a permissive policy to run
        unsigned scripts without modifying the machine-level policy.
    #>
    $result = [PSCustomObject]@{
        CheckName      = 'ExecutionPolicyScope'
        Status         = 'Clean'
        Details        = $null
        Recommendation = $null
    }

    try {
        $policies = Get-ExecutionPolicy -List

        $effectiveScope = $null
        $permissiveScopes = @()

        foreach ($entry in $policies) {
            $permissive = $entry.ExecutionPolicy -in @('Unrestricted', 'Bypass', 'RemoteSigned')
            if ($permissive -and $entry.ExecutionPolicy -ne 'Undefined') {
                $permissiveScopes += "$($entry.Scope)=$($entry.ExecutionPolicy)"
            }
            # Track which scope is setting the effective policy
            if ($null -eq $effectiveScope -and $entry.ExecutionPolicy -ne 'Undefined') {
                $effectiveScope = "$($entry.Scope)=$($entry.ExecutionPolicy)"
            }
        }

        $currentUserPolicy = ($policies | Where-Object { $_.Scope -eq 'CurrentUser' }).ExecutionPolicy
        $processPolicy     = ($policies | Where-Object { $_.Scope -eq 'Process' }).ExecutionPolicy

        $result.Details = [PSCustomObject]@{
            EffectiveScope       = $effectiveScope
            CurrentUserPolicy    = [string]$currentUserPolicy
            ProcessPolicy        = [string]$processPolicy
            PermissiveScopesFound = $permissiveScopes
        }

        # Permissive policy at CurrentUser or Process scope is a warning signal
        # (attacker technique: Set-ExecutionPolicy -Scope CurrentUser Bypass)
        if ($currentUserPolicy -in @('Bypass', 'Unrestricted') -or
            $processPolicy     -in @('Bypass', 'Unrestricted')) {
            $result.Status         = 'Warning'
            $result.Recommendation = 'Permissive execution policy detected at CurrentUser or Process scope. ' +
                                     'Verify this was set intentionally. Review recent PowerShell activity.'
        }
        else {
            $result.Recommendation = 'Execution policy scope appears appropriately restricted.'
        }
    }
    catch {
        $result.Status  = 'Warning'
        $result.Details = "Failed to query execution policy: $_"
    }

    return $result
}


# ---------------------------------------------------------------------------
# Check 2: Failed Login Count (EventID 4625, last N hours)
# ---------------------------------------------------------------------------

function Get-FailedLoginCheck {
    param (
        [int] $LookbackHours,
        [int] $WarningThreshold,
        [int] $AlertThreshold
    )

    $result = [PSCustomObject]@{
        CheckName      = 'FailedLogins_24h'
        Status         = 'Clean'
        Details        = $null
        Recommendation = $null
    }

    try {
        $startTime = (Get-Date).AddHours(-$LookbackHours)

        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = 4625
            StartTime = $startTime
        } -ErrorAction SilentlyContinue

        $count = if ($null -eq $events) { 0 } else { @($events).Count }

        # Summarize by source IP for context
        $topSources = @()
        if ($count -gt 0) {
            $topSources = $events |
                ForEach-Object {
                    try { $_.Properties[19].Value } catch { 'Unknown' }
                } |
                Group-Object |
                Sort-Object Count -Descending |
                Select-Object -First 5 |
                ForEach-Object { "$($_.Name) ($($_.Count) failures)" }
        }

        $result.Details = [PSCustomObject]@{
            LookbackHours    = $LookbackHours
            FailedLoginCount = $count
            WarningThreshold = $WarningThreshold
            AlertThreshold   = $AlertThreshold
            TopSourceIPs     = $topSources
        }

        if ($count -ge $AlertThreshold) {
            $result.Status         = 'Alert'
            $result.Recommendation = "$count failed logins in the last $LookbackHours hours exceeds " +
                                     "alert threshold ($AlertThreshold). Investigate for brute force activity. " +
                                     "Review source IPs and consider blocking if external."
        }
        elseif ($count -ge $WarningThreshold) {
            $result.Status         = 'Warning'
            $result.Recommendation = "$count failed logins in the last $LookbackHours hours exceeds " +
                                     "warning threshold ($WarningThreshold). Review source IPs."
        }
        else {
            $result.Recommendation = "$count failed login(s) in the last $LookbackHours hours. Within normal range."
        }
    }
    catch [System.Security.SecurityException] {
        $result.Status  = 'Warning'
        $result.Details = "Insufficient permissions to query Security Event Log. Run as Administrator."
    }
    catch {
        $result.Status  = 'Warning'
        $result.Details = "Failed to query Security Event Log: $_"
    }

    return $result
}


# ---------------------------------------------------------------------------
# Check 3: Suspicious Running Services
# ---------------------------------------------------------------------------

function Get-SuspiciousServicesCheck {
    <#
    .DESCRIPTION
        Checks running services against patterns associated with common
        remote access tools, malware, and attacker tooling.
        This is a heuristic check — false positives are possible.
        Any match should be manually verified before action.
    #>
    $result = [PSCustomObject]@{
        CheckName      = 'SuspiciousServices'
        Status         = 'Clean'
        Details        = $null
        Recommendation = $null
    }

    # Patterns associated with known malware, RATs, and attacker tools
    # Intentionally broad to catch obfuscated variants; verify all matches manually
    $suspiciousPatterns = @(
        'nc\.exe',        # netcat
        'ncat',           # ncat (nmap suite)
        'mimikatz',       # credential dumping tool
        'psexec',         # Sysinternals (also used by attackers for lateral movement)
        'cobaltstrike',   # C2 framework
        'meterpreter',    # Metasploit payload
        'empire',         # PowerShell Empire C2
        'beacon',         # CobaltStrike beacon
        'rat_',           # generic RAT naming
        '_rat$',          # generic RAT naming
        'keylog',         # keylogger pattern
        'svchost32',      # fake svchost (real one is svchost.exe, not svchost32)
        'svch0st',        # svchost typosquat
        'lsass32',        # fake lsass
        'taskhostw32'     # fake taskhost
    )

    try {
        $runningServices = Get-Service | Where-Object { $_.Status -eq 'Running' }

        $matches = $runningServices | Where-Object {
            $serviceName = $_.Name.ToLower()
            $displayName = $_.DisplayName.ToLower()
            $hit = $false
            foreach ($pattern in $suspiciousPatterns) {
                if ($serviceName -match $pattern -or $displayName -match $pattern) {
                    $hit = $true
                    break
                }
            }
            $hit
        }

        $matchList = @($matches | Select-Object Name, DisplayName, Status)

        $result.Details = [PSCustomObject]@{
            RunningServiceCount    = @($runningServices).Count
            SuspiciousMatchCount   = $matchList.Count
            SuspiciousMatches      = $matchList
            PatternsChecked        = $suspiciousPatterns.Count
        }

        if ($matchList.Count -gt 0) {
            $result.Status         = 'Alert'
            $result.Recommendation = "$($matchList.Count) running service(s) match suspicious patterns. " +
                                     "Manually verify each match. False positives are possible. " +
                                     "If confirmed malicious: stop the service, prevent restart, investigate."
        }
        else {
            $result.Recommendation = "No running services matched suspicious patterns."
        }
    }
    catch {
        $result.Status  = 'Warning'
        $result.Details = "Failed to enumerate running services: $_"
    }

    return $result
}


# ---------------------------------------------------------------------------
# Check 4: Recent PowerShell ScriptBlock Log Entries (EventID 4104)
# ---------------------------------------------------------------------------

function Get-ScriptBlockLogCheck {
    param ([int] $LookbackMinutes)

    $result = [PSCustomObject]@{
        CheckName      = 'ScriptBlockLog_1h'
        Status         = 'Clean'
        Details        = $null
        Recommendation = $null
    }

    try {
        $startTime = (Get-Date).AddMinutes(-$LookbackMinutes)

        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-PowerShell/Operational'
            Id        = 4104
            StartTime = $startTime
        } -ErrorAction SilentlyContinue

        $count = if ($null -eq $events) { 0 } else { @($events).Count }

        # Check for high-risk patterns in script block content
        $highRiskPatterns = @(
            'FromBase64String',
            'Invoke-Expression',
            '\bIEX\b',
            '-EncodedCommand',
            'DownloadString',
            'Net\.WebClient',
            'Invoke-Mimikatz',
            'ShellCode',
            '-WindowStyle Hidden',
            '-NonInteractive.*Bypass'
        )

        $highRiskHits = @()
        if ($count -gt 0) {
            foreach ($event in $events) {
                $scriptContent = try { $event.Properties[2].Value } catch { '' }
                foreach ($pattern in $highRiskPatterns) {
                    if ($scriptContent -match $pattern) {
                        $highRiskHits += [PSCustomObject]@{
                            TimeCreated = $event.TimeCreated
                            Pattern     = $pattern
                            Preview     = ($scriptContent -replace '[\r\n]+', ' ').Substring(
                                0, [Math]::Min(100, $scriptContent.Length)
                            )
                        }
                        break  # one hit per event is enough
                    }
                }
            }
        }

        $loggingEnabled = $count -gt 0 -or $null -ne (
            Get-WinEvent -ListLog 'Microsoft-Windows-PowerShell/Operational' -ErrorAction SilentlyContinue
        )

        $result.Details = [PSCustomObject]@{
            LookbackMinutes       = $LookbackMinutes
            ScriptBlockEventCount = $count
            HighRiskPatternHits   = $highRiskHits.Count
            HighRiskEvents        = $highRiskHits
            ScriptBlockLoggingEnabled = $loggingEnabled
        }

        if ($highRiskHits.Count -gt 0) {
            $result.Status         = 'Alert'
            $result.Recommendation = "$($highRiskHits.Count) ScriptBlock log event(s) contain high-risk " +
                                     "patterns (obfuscation, download cradles, etc.). Review immediately."
        }
        elseif ($count -gt 100) {
            $result.Status         = 'Warning'
            $result.Recommendation = "$count ScriptBlock events in the last $LookbackMinutes minutes is " +
                                     "unusually high. Review for automation or scripting anomalies."
        }
        elseif (-not $loggingEnabled) {
            $result.Status         = 'Warning'
            $result.Recommendation = "PowerShell ScriptBlock logging may not be enabled. " +
                                     "Enable via Group Policy: Computer Config > Windows Settings > " +
                                     "Administrative Templates > Windows Components > Windows PowerShell."
        }
        else {
            $result.Recommendation = "$count ScriptBlock event(s) in the last $LookbackMinutes minutes. No high-risk patterns found."
        }
    }
    catch [System.Security.SecurityException] {
        $result.Status  = 'Warning'
        $result.Details = "Insufficient permissions to query PowerShell Operational log."
    }
    catch {
        $result.Status  = 'Warning'
        $result.Details = "Failed to query PowerShell ScriptBlock log: $_"
    }

    return $result
}


# ---------------------------------------------------------------------------
# Main — Run All Checks and Assemble Report
# ---------------------------------------------------------------------------

$reportTime = Get-Date

Write-Verbose "Starting Windows Security Status assessment at $reportTime"

$check1 = Get-ExecutionPolicyCheck
$check2 = Get-FailedLoginCheck -LookbackHours $LookbackHours `
                                -WarningThreshold $FailedLoginWarningThreshold `
                                -AlertThreshold   $FailedLoginAlertThreshold
$check3 = Get-SuspiciousServicesCheck
$check4 = Get-ScriptBlockLogCheck -LookbackMinutes $ScriptBlockLookbackMinutes

$allStatuses    = @($check1.Status, $check2.Status, $check3.Status, $check4.Status)
$overallStatus  = Get-OverallStatus -CheckStatuses $allStatuses

$report = [PSCustomObject]@{
    ReportTime     = $reportTime.ToString('yyyy-MM-ddTHH:mm:ss')
    ComputerName   = $env:COMPUTERNAME
    RunAsUser      = $env:USERNAME
    OverallStatus  = $overallStatus
    Checks         = [PSCustomObject]@{
        ExecutionPolicyScope = $check1
        FailedLogins         = $check2
        SuspiciousServices   = $check3
        ScriptBlockLog       = $check4
    }
}

# ---------------------------------------------------------------------------
# Console Output
# ---------------------------------------------------------------------------

$statusColor = switch ($overallStatus) {
    'Alert'   { 'Red' }
    'Warning' { 'Yellow' }
    default   { 'Green' }
}

Write-Host "`n===== Windows Security Status Report =====" -ForegroundColor Cyan
Write-Host "  Computer   : $($report.ComputerName)"
Write-Host "  User       : $($report.RunAsUser)"
Write-Host "  Time       : $($report.ReportTime)"
Write-Host ("  Status     : {0}" -f $report.OverallStatus) -ForegroundColor $statusColor
Write-Host ""

foreach ($checkName in @('ExecutionPolicyScope', 'FailedLogins', 'SuspiciousServices', 'ScriptBlockLog')) {
    $check = $report.Checks.$checkName
    $checkColor = switch ($check.Status) {
        'Alert'   { 'Red' }
        'Warning' { 'Yellow' }
        default   { 'Green' }
    }
    Write-Host ("  [{0,-8}] {1}" -f $check.Status, $check.CheckName) -ForegroundColor $checkColor
    if ($check.Recommendation) {
        Write-Host ("            {0}" -f $check.Recommendation) -ForegroundColor DarkGray
    }
}

Write-Host "`n==========================================" -ForegroundColor Cyan

# Return the structured report object for pipeline use
return $report
