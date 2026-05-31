#Requires -Version 5.1
<#
.SYNOPSIS
    Queries Windows Security Event Log for failed logon events and returns
    structured triage objects grouped by source IP address.

.DESCRIPTION
    Get-FailedLogins searches EventID 4625 (failed logon) in the Security
    event log, groups results by source IP and username, applies a configurable
    failure-count threshold, and returns PSCustomObjects with triage fields
    including a recommendation based on failure count and account spread.

    Intended for use during the first 15 minutes of a brute-force IR triage.
    Requires local administrator rights to read the Security event log.

.PARAMETER Threshold
    Minimum number of failed logons from a single source IP to include in results.
    Default: 5

.PARAMETER HoursBack
    Number of hours back to search from the current time.
    Default: 24

.PARAMETER Username
    Optional. Filter to failed logons targeting a specific username only.

.PARAMETER ExportCsv
    Optional. If specified, exports results to a CSV file at this path.

.EXAMPLE
    Get-FailedLogins

    Returns all source IPs with 5+ failed logins in the last 24 hours.

.EXAMPLE
    Get-FailedLogins -Threshold 3 -HoursBack 1

    Returns all source IPs with 3+ failed logins in the last hour.
    Useful for active incident triage.

.EXAMPLE
    Get-FailedLogins -Threshold 10 -ExportCsv "C:\IR\failed_logins_$(Get-Date -Format yyyyMMdd_HHmm).csv"

    Exports high-confidence results to a dated CSV for ticket attachment.

.NOTES
    Author:   Mahmadarsh Vahora
    Version:  1.0.0
    Requires: Administrator rights; Security audit policy must enable
              "Audit Logon Events - Failure" for EventID 4625 to appear.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateRange(1, 9999)]
    [int]$Threshold = 5,

    [Parameter()]
    [ValidateRange(1, 720)]
    [int]$HoursBack = 24,

    [Parameter()]
    [string]$Username,

    [Parameter()]
    [string]$ExportCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Recommendation {
    param(
        [int]$Count,
        [int]$UniqueUsernames,
        [string]$SourceIP
    )
    $isInternal = $SourceIP -match '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.)'
    if ($Count -ge 50 -and $UniqueUsernames -gt 5) {
        return "CRITICAL — Password spray pattern. Immediate block and investigation required."
    }
    elseif ($Count -ge 50) {
        return "HIGH — Brute force threshold exceeded. Block source IP and audit target accounts."
    }
    elseif ($Count -ge 20) {
        return "HIGH — Sustained failed login activity. Verify if legitimate; block if external."
    }
    elseif ($Count -ge 10 -and -not $isInternal) {
        return "MEDIUM — Elevated external failures. Monitor and consider block if no business justification."
    }
    elseif ($isInternal) {
        return "MEDIUM (Internal) — Internal source. Investigate misconfigured service or user error."
    }
    else {
        return "LOW — Below critical threshold. Document and monitor for escalation."
    }
}

# Verify we can read the Security log
try {
    $null = Get-WinEvent -LogName 'Security' -MaxEvents 1 -ErrorAction Stop
}
catch {
    if ($_.Exception.Message -match 'Access is denied') {
        Write-Error "Access denied reading Security event log. Run this script as Administrator."
        exit 1
    }
    elseif ($_.Exception.Message -match 'No events') {
        Write-Warning "Security event log is empty or EventID 4625 auditing is not enabled."
    }
    else {
        throw
    }
}

$StartTime = (Get-Date).AddHours(-$HoursBack)
Write-Verbose "Searching Security log from $($StartTime.ToString('yyyy-MM-dd HH:mm:ss')) to now (threshold: $Threshold failures)"

# Build XPath filter for EventID 4625 within time window — faster than FilterHashtable for large logs
$StartTimeXml = $StartTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000Z")
$XPathFilter = @"
*[System[EventID=4625] and System[TimeCreated[@SystemTime>='$StartTimeXml']]]
"@

Write-Verbose "Querying event log with XPath filter..."

try {
    $RawEvents = Get-WinEvent -LogName 'Security' -FilterXPath $XPathFilter -ErrorAction SilentlyContinue
}
catch {
    if ($_.Exception.Message -match 'No events') {
        Write-Warning "No EventID 4625 entries found in the specified time window."
        $RawEvents = @()
    }
    else {
        throw
    }
}

if (-not $RawEvents -or $RawEvents.Count -eq 0) {
    Write-Output "No failed logon events found. Either the log is clear or Failure auditing is not enabled."
    return
}

Write-Verbose "Processing $($RawEvents.Count) raw failed logon events..."

# Parse each event into a structured object
$ParsedEvents = foreach ($Event in $RawEvents) {
    try {
        $Xml = [xml]$Event.ToXml()
        $Data = $Xml.Event.EventData.Data

        $SourceAddress = ($Data | Where-Object { $_.Name -eq 'IpAddress' }).'#text'
        $TargetUser    = ($Data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
        $LogonType     = ($Data | Where-Object { $_.Name -eq 'LogonType' }).'#text'
        $SubStatus     = ($Data | Where-Object { $_.Name -eq 'SubStatus' }).'#text'
        $WorkStation   = ($Data | Where-Object { $_.Name -eq 'WorkstationName' }).'#text'

        # Skip machine accounts and null/localhost sources
        if ($TargetUser -match '\$$' -or
            $SourceAddress -in @('-', $null, '::1', '127.0.0.1', '') -or
            $TargetUser -in @('-', $null, '')) {
            continue
        }

        # Apply username filter if specified
        if ($Username -and $TargetUser -notlike "*$Username*") {
            continue
        }

        [PSCustomObject]@{
            EventTime    = $Event.TimeCreated
            SourceIP     = $SourceAddress
            Username     = $TargetUser
            LogonType    = $LogonType
            SubStatus    = $SubStatus
            WorkStation  = $WorkStation
            ComputerName = $Event.MachineName
        }
    }
    catch {
        Write-Verbose "Failed to parse event ID $($Event.RecordId): $_"
        continue
    }
}

if (-not $ParsedEvents) {
    Write-Output "No parseable failed logon events found after filtering machine accounts and null sources."
    return
}

Write-Verbose "Parsed $(@($ParsedEvents).Count) valid failed logon events. Grouping by source IP..."

# Group by source IP and aggregate
$Results = $ParsedEvents |
    Group-Object -Property SourceIP |
    Where-Object { $_.Count -ge $Threshold } |
    ForEach-Object {
        $Group       = $_.Group
        $UniqueUsers = ($Group | Select-Object -ExpandProperty Username -Unique)
        $FirstSeen   = ($Group | Sort-Object EventTime | Select-Object -First 1).EventTime
        $LastSeen    = ($Group | Sort-Object EventTime | Select-Object -Last 1).EventTime

        [PSCustomObject]@{
            SourceIP       = $_.Name
            Count          = $_.Count
            UniqueUsernames = @($UniqueUsers).Count
            Usernames      = ($UniqueUsers -join ', ')
            FirstSeen      = $FirstSeen.ToString('yyyy-MM-dd HH:mm:ss')
            LastSeen       = $LastSeen.ToString('yyyy-MM-dd HH:mm:ss')
            SpanMinutes    = [math]::Round(($LastSeen - $FirstSeen).TotalMinutes, 1)
            Recommendation = Get-Recommendation -Count $_.Count -UniqueUsernames @($UniqueUsers).Count -SourceIP $_.Name
        }
    } |
    Sort-Object -Property Count -Descending

if (-not $Results) {
    Write-Output "No source IPs met the threshold of $Threshold failed logins. Environment appears clean for the specified window."
    return
}

# Output results
Write-Output "`n=== Failed Login Triage Report ==="
Write-Output "Time Window : Last $HoursBack hour(s) from $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "Threshold   : $Threshold+ failures"
Write-Output "Results     : $(@($Results).Count) source IP(s) flagged"
Write-Output "=================================="

$Results | Format-Table -AutoSize -Property SourceIP, Count, UniqueUsernames, Usernames, FirstSeen, LastSeen, SpanMinutes

Write-Output "`n=== Recommendations ==="
foreach ($r in $Results) {
    Write-Output "$($r.SourceIP) ($($r.Count) failures): $($r.Recommendation)"
}

# Export if requested
if ($ExportCsv) {
    try {
        $Results | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
        Write-Output "`nExported $(@($Results).Count) results to: $ExportCsv"
    }
    catch {
        Write-Warning "Failed to export CSV: $_"
    }
}

# Return structured objects for pipeline use
return $Results
