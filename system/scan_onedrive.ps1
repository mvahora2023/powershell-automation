#Requires -Version 5.1
<#
.SYNOPSIS
  Lists document metadata from an explicitly selected folder.
.NOTES
  Read-only. Output stays in the invoking PowerShell session.
  Do not publish inventory results without checking for personal filenames.
#>
[CmdletBinding()]
param([string]$Root = (Join-Path $env:USERPROFILE 'OneDrive'))
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Folder not found: $Root"
}
Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction Stop |
    Where-Object { $_.Extension -match '^\.(pdf|docx|xlsx|pptx|txt|md|csv)$' } |
    Select-Object @{N='File';E={$_.Name}}, @{N='SizeKB';E={[math]::Round($_.Length/1KB,1)}} |
    Sort-Object File
