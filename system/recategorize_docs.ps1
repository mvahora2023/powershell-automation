#Requires -Version 5.1
<#
.SYNOPSIS
  Safely recategorize documents using an explicit CSV plan.
.DESCRIPTION
  Dry-run by default. When -Apply is specified, move files from the
  Other_Important_Docs subfolder only. Never overwrite an existing file.
  CSV columns: SourceName,DestinationFolder.
  See recategorize_mapping.example.csv. Never publish private filenames.
.EXAMPLE
  .\recategorize_docs.ps1 -MappingCsv .\recategorize_mapping.example.csv
.EXAMPLE
  .\recategorize_docs.ps1 -MappingCsv C:\Local\my-mapping.csv -Apply -Confirm
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
  [string]$BaseRoot = (Join-Path $env:USERPROFILE 'Organized_Docs'),
  [string]$MappingCsv = (Join-Path $PSScriptRoot 'recategorize_mapping.example.csv'),
  [switch]$Apply
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath $MappingCsv -PathType Leaf)) {
  throw "Mapping CSV not found: $MappingCsv"
}
$base=[System.IO.Path]::GetFullPath($BaseRoot)
$src=Join-Path $base 'Other_Important_Docs'
if (-not (Test-Path -LiteralPath $src -PathType Container)) {
  throw "Source folder not found: $src"
}
$mapping=Import-Csv -LiteralPath $MappingCsv
if (-not $mapping) { Write-Output 'Mapping CSV has no rows.'; return }
$results=@()
foreach ($row in $mapping) {
  $fileName=([string]$row.SourceName).Trim()
  $sub=([string]$row.DestinationFolder).Trim()
  if ([string]::IsNullOrWhiteSpace($fileName) -or [string]::IsNullOrWhiteSpace($sub)) {
    throw 'Each row needs SourceName and DestinationFolder.'
  }
  # Restrict moves to a simple filename and a relative folder within BaseRoot.
  if ($fileName -ne [System.IO.Path]::GetFileName($fileName) -or
      [System.IO.Path]::IsPathRooted($sub) -or
      $sub -match '(^|[\\/])\.\.([\\/]|$)' -or
      $sub -match '[:*?"<>|]' -or
      $sub.StartsWith('\') -or $sub.StartsWith('/')) {
    throw "Unsafe mapping entry: $fileName -> $sub"
  }
  $source=Join-Path $src $fileName
  $destinationDir=Join-Path $base $sub
  $destination=Join-Path $destinationDir $fileName
  $status='Planned'
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    $status='Missing'
  } elseif (Test-Path -LiteralPath $destination) {
    $status='Skipped: destination exists'
  } elseif ($Apply) {
    if ($PSCmdlet.ShouldProcess($source,"Move to $destination")) {
      try {
        New-Item -ItemType Directory -Path $destinationDir -Force -ErrorAction Stop | Out-Null
        # No -Force here: never overwrite existing files.
        Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
        $status='Moved'
      } catch {
        $status='Error: '+$_.Exception.Message
      }
    } else {
      $status='Not moved'
    }
  }
  $results += [pscustomobject]@{File=$fileName;DestinationFolder=$sub;Status=$status}
}
$results | Format-Table -AutoSize
if (-not $Apply) {
  Write-Output 'PREVIEW ONLY. Review the plan, then use -Apply for actual changes.'
}
