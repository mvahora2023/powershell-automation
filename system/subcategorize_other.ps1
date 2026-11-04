#Requires -Version 5.1
<#
.SYNOPSIS
  Compatibility wrapper for the safer, mapping-driven recategorization tool.
.DESCRIPTION
  This public script contains NO personal filenames or copied cloud-report names.
  To perform moves, provide a separate private CSV mapping created on your
  computer. It is not created, stored, uploaded, or committed by this project.
  By default the underlying script previews actions without modifying files.
#>
[CmdletBinding()]
param(
    [string]$BaseRoot = (Join-Path $env:USERPROFILE 'Organized_Docs'),
    [string]$MappingCsv = (Join-Path $PSScriptRoot 'recategorize_mapping.example.csv'),
    [switch]$Apply
)
$implementation=Join-Path $PSScriptRoot 'recategorize_docs.ps1'
if (-not (Test-Path -LiteralPath $implementation -PathType Leaf)) {
    throw 'Missing recategorization script in this repository.'
}
& $implementation -BaseRoot $BaseRoot -MappingCsv $MappingCsv -Apply:$Apply -Confirm:$false
