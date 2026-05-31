#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Adds a Windows Firewall inbound block rule for a specified source IP address.

.DESCRIPTION
    Block-SourceIP creates a named Windows Firewall rule to block all inbound
    traffic from the specified IP address or CIDR range. The rule is named with
    a timestamp and incident reference for auditability. All actions are logged
    to the Application event log and an optional log file.

    Supports -WhatIf for safe rehearsal before execution. Uses ShouldProcess
    so it integrates naturally with -Confirm for interactive use.

    Run Get-FailedLogins.ps1 first to identify candidate IPs, then pipe the
    SourceIP field into this script for a streamlined containment workflow.

.PARAMETER IPAddress
    The IPv4 address or CIDR range to block (e.g., "192.168.1.100" or "10.0.5.0/24").

.PARAMETER IncidentRef
    Optional. Incident reference number or ticket ID to embed in the rule name
    and log entry (e.g., "INC-2025-0042"). Defaults to "IR-<timestamp>".

.PARAMETER RuleName
    Optional. Custom display name prefix for the firewall rule. Defaults to
    "SafeOps-Block".

.PARAMETER LogFile
    Optional. Path to a log file for appending the block action record.
    If not specified, logs only to the Windows Application event log.

.PARAMETER NoEventLog
    Switch. Suppress writing to Windows Application event log (use LogFile instead).

.EXAMPLE
    Block-SourceIP -IPAddress "203.0.113.45"

    Blocks inbound traffic from 203.0.113.45. Prompts for confirmation.

.EXAMPLE
    Block-SourceIP -IPAddress "203.0.113.45" -WhatIf

    Shows what would happen without making any changes. Always run this first
    in production.

.EXAMPLE
    Block-SourceIP -IPAddress "203.0.113.45" -IncidentRef "INC-2025-0042" -Confirm:$false

    Blocks the IP and tags the firewall rule with the incident reference.
    Skips confirmation prompt (use only in scripted workflows).

.EXAMPLE
    Get-FailedLogins -Threshold 50 | ForEach-Object {
        Block-SourceIP -IPAddress $_.SourceIP -IncidentRef "INC-2025-0042" -WhatIf
    }

    Pipeline integration: dry-run blocking all IPs returned by Get-FailedLogins
    above threshold 50. Remove -WhatIf to execute.

.NOTES
    Author:   Mahmadarsh Vahora
    Version:  1.0.0
    Requires: Administrator rights; NetSecurity module (built into Windows 8+/Server 2012+)

    WARNING: Blocking an IP in Windows Firewall only affects this host.
    For network-level blocking, escalate to network team or perimeter firewall.
    This script does NOT modify perimeter/edge firewall rules.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
    [ValidateScript({
        # Accept single IPv4 address or CIDR notation
        if ($_ -match '^(\d{1,3}\.){3}\d{1,3}(\/\d{1,2})?$') {
            $parts = $_.Split('/')[0].Split('.')
            foreach ($part in $parts) {
                if ([int]$part -gt 255) {
                    throw "Invalid IP address octet: $part"
                }
            }
            if ($_ -match '\/(\d+)$') {
                $prefix = [int]$Matches[1]
                if ($prefix -lt 0 -or $prefix -gt 32) {
                    throw "Invalid CIDR prefix length: $prefix. Must be 0-32."
                }
            }
            return $true
        }
        throw "Invalid IPv4 address or CIDR range: '$_'. Expected format: '192.168.1.100' or '192.168.1.0/24'"
    })]
    [Alias('SourceIP', 'IP')]
    [string]$IPAddress,

    [Parameter()]
    [ValidateLength(1, 50)]
    [string]$IncidentRef,

    [Parameter()]
    [string]$RuleName = 'SafeOps-Block',

    [Parameter()]
    [string]$LogFile,

    [Parameter()]
    [switch]$NoEventLog
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Ensure NetSecurity module is available
    if (-not (Get-Module -ListAvailable -Name NetSecurity)) {
        throw "NetSecurity module not found. This script requires Windows 8 / Server 2012 or later."
    }
    Import-Module NetSecurity -ErrorAction Stop

    # Register event source if not already present
    if (-not $NoEventLog) {
        try {
            if (-not [System.Diagnostics.EventLog]::SourceExists('SafeOps')) {
                New-EventLog -LogName Application -Source 'SafeOps' -ErrorAction Stop
                Write-Verbose "Registered 'SafeOps' event source in Application log."
            }
        }
        catch {
            Write-Warning "Could not register event log source 'SafeOps': $_. Event log entries will be skipped."
            $NoEventLog = $true
        }
    }

    # Internal logging helper
    function Write-BlockLog {
        param(
            [string]$Message,
            [string]$Outcome,
            [string]$TargetIP,
            [int]$EventId = 9010
        )
        $Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $LogLine = "[$Timestamp] Actor=$env:USERDOMAIN\$env:USERNAME Action=Block-SourceIP Target=$TargetIP Outcome=$Outcome Severity=$(if ($Outcome -eq 'BLOCKED') { 'WARN' } else { 'ERROR' }) Message=$Message"

        Write-Verbose $LogLine

        if ($LogFile) {
            try {
                Add-Content -Path $LogFile -Value $LogLine -Encoding UTF8
            }
            catch {
                Write-Warning "Failed to write to log file '$LogFile': $_"
            }
        }

        if (-not $NoEventLog) {
            try {
                $EntryType = if ($Outcome -eq 'BLOCKED') { 'Warning' } else { 'Error' }
                Write-EventLog -LogName Application -Source 'SafeOps' -EventId $EventId -EntryType $EntryType -Message $LogLine
            }
            catch {
                Write-Verbose "Event log write failed: $_"
            }
        }
    }
}

process {
    $Timestamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
    $IncRef       = if ($IncidentRef) { $IncidentRef } else { "IR-$Timestamp" }
    $FullRuleName = "$RuleName-$IPAddress-$IncRef"
    $Description  = "Blocked by SafeOps IR Toolkit. Incident: $IncRef. Actor: $env:USERDOMAIN\$env:USERNAME. Time: $Timestamp."

    # Check if a blocking rule for this IP already exists
    $ExistingRule = Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*$IPAddress*" -and $_.Action -eq 'Block' -and $_.Direction -eq 'Inbound' } |
        Select-Object -First 1

    if ($ExistingRule) {
        Write-Warning "A firewall block rule for $IPAddress already exists: '$($ExistingRule.DisplayName)'"
        Write-Warning "Skipping duplicate rule creation. To update, remove the existing rule first with: Remove-NetFirewallRule -DisplayName '$($ExistingRule.DisplayName)'"
        return
    }

    $ShouldProcessMessage = "Create Windows Firewall inbound block rule for IP: $IPAddress (Rule: '$FullRuleName')"
    $ShouldProcessTarget  = $IPAddress

    if ($PSCmdlet.ShouldProcess($ShouldProcessTarget, $ShouldProcessMessage)) {
        try {
            Write-Verbose "Creating firewall rule: $FullRuleName"

            $NewRule = New-NetFirewallRule `
                -DisplayName   $FullRuleName `
                -Description   $Description `
                -Direction     Inbound `
                -Action        Block `
                -RemoteAddress $IPAddress `
                -Protocol      Any `
                -Profile       Any `
                -Enabled       True `
                -ErrorAction   Stop

            Write-BlockLog -Message "Firewall block rule created successfully." -Outcome 'BLOCKED' -TargetIP $IPAddress

            Write-Output "`n[BLOCKED] $IPAddress"
            Write-Output "  Rule Name  : $FullRuleName"
            Write-Output "  Incident   : $IncRef"
            Write-Output "  Rule ID    : $($NewRule.InstanceID)"
            Write-Output "  Time       : $Timestamp"
            Write-Output "  Actor      : $env:USERDOMAIN\$env:USERNAME"
            Write-Output ""
            Write-Output "  Verify rule active: Get-NetFirewallRule -DisplayName '$FullRuleName'"
            Write-Output "  Remove rule:        Remove-NetFirewallRule -DisplayName '$FullRuleName'"
            Write-Output ""
            Write-Output "  NOTE: This blocks inbound traffic on this host only."
            Write-Output "        Escalate to network team for perimeter-level blocking."

            return [PSCustomObject]@{
                IPAddress  = $IPAddress
                RuleName   = $FullRuleName
                IncidentRef = $IncRef
                Timestamp  = $Timestamp
                Actor      = "$env:USERDOMAIN\$env:USERNAME"
                RuleID     = $NewRule.InstanceID
                Status     = 'Blocked'
            }
        }
        catch {
            Write-BlockLog -Message "Failed to create firewall rule: $_" -Outcome 'ERROR' -TargetIP $IPAddress -EventId 9011
            Write-Error "Failed to create firewall block rule for $IPAddress`: $_"
        }
    }
    else {
        Write-Output "[SKIPPED - WhatIf or Confirm=No] Would have created firewall block rule for: $IPAddress"
        Write-Output "  Rule would be named: $FullRuleName"
        Write-Output "  To execute: Block-SourceIP -IPAddress '$IPAddress' -IncidentRef '$IncRef' -Confirm:`$false"
    }
}
