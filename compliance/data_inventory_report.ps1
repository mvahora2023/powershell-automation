#Requires -Version 5.1
<#
.SYNOPSIS
    Recursively inventories a directory and produces a structured compliance
    audit report as a CSV file.

.DESCRIPTION
    data_inventory_report.ps1 scans a target directory tree, collects metadata
    for every file, classifies each file by type (Document, Spreadsheet, Archive,
    Image, Script, Database, etc.), applies a configurable retention threshold
    to flag files that may need review under a data retention policy, and
    exports the results to a CSV report.

    Designed to be run as a scheduled compliance audit task. Output is
    reproducible, timestamped, and in a format suitable for attachment to
    compliance evidence packages or retention review records.

    No third-party dependencies. Requires file system read access to ScanPath.

.PARAMETER ScanPath
    Root directory to inventory. Scanned recursively.
    Default: Current user's Documents folder.

.PARAMETER OutputCsv
    Full path for the CSV report output file.
    Default: Desktop\DataInventory_<timestamp>.csv

.PARAMETER RetentionDays
    Files with LastModified older than this many days are flagged with
    RetentionFlag = "REVIEW_REQUIRED". Default: 365 (1 year).

.PARAMETER ExcludePaths
    Array of path substrings to exclude from scan (e.g., system folders, caches).
    Default: excludes common system/temp paths.

.PARAMETER MaxFileSizeKB
    Skip files larger than this threshold (to avoid scanning large archives
    or database files that are better inventoried by purpose). Default: 512000 (500 MB).

.PARAMETER IncludeHidden
    Switch. Include hidden files in the inventory. Default: excluded.

.EXAMPLE
    .\data_inventory_report.ps1

    Inventories current user Documents folder. Exports CSV to Desktop.

.EXAMPLE
    .\data_inventory_report.ps1 -ScanPath "D:\CompanyFiles" -OutputCsv "C:\Audits\inventory_2025.csv" -RetentionDays 730

    Inventories D:\CompanyFiles with a 2-year retention threshold.
    Exports to specified path.

.EXAMPLE
    .\data_inventory_report.ps1 -ScanPath "C:\Projects" -RetentionDays 180 -IncludeHidden

    Scans Projects folder including hidden files; flags anything older than 6 months.

.NOTES
    Author:   Mahmadarsh Vahora
    Version:  1.0.0
    Output Fields:
        FileName, FilePath, Extension, Category, SizeKB, LastModified,
        CreatedDate, AgeInDays, Owner, RetentionFlag, RetentionNote
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Container)) {
            throw "ScanPath '$_' does not exist or is not a directory."
        }
        return $true
    })]
    [string]$ScanPath = [Environment]::GetFolderPath('MyDocuments'),

    [Parameter()]
    [string]$OutputCsv,

    [Parameter()]
    [ValidateRange(1, 36500)]
    [int]$RetentionDays = 365,

    [Parameter()]
    [string[]]$ExcludePaths = @(
        '\AppData\Local\Temp',
        '\AppData\Local\Microsoft\Windows\',
        '\.git\',
        '\node_modules\',
        '\__pycache__\',
        '\.vs\',
        '\bin\Debug\',
        '\bin\Release\'
    ),

    [Parameter()]
    [ValidateRange(1, 10485760)]   # 1 KB to 10 GB
    [long]$MaxFileSizeKB = 512000,

    [Parameter()]
    [switch]$IncludeHidden
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'   # Continue on individual file errors; don't halt entire scan

#region Category Classification
$CategoryMap = @{
    # Documents
    '.doc'    = 'Document'
    '.docx'   = 'Document'
    '.docm'   = 'Document'
    '.odt'    = 'Document'
    '.rtf'    = 'Document'
    '.txt'    = 'Document'
    '.pdf'    = 'Document'
    '.md'     = 'Document'
    '.rst'    = 'Document'
    # Spreadsheets
    '.xls'    = 'Spreadsheet'
    '.xlsx'   = 'Spreadsheet'
    '.xlsm'   = 'Spreadsheet'
    '.csv'    = 'Spreadsheet'
    '.ods'    = 'Spreadsheet'
    # Presentations
    '.ppt'    = 'Presentation'
    '.pptx'   = 'Presentation'
    '.pptm'   = 'Presentation'
    '.odp'    = 'Presentation'
    # Archives / Compressed
    '.zip'    = 'Archive'
    '.rar'    = 'Archive'
    '.7z'     = 'Archive'
    '.tar'    = 'Archive'
    '.gz'     = 'Archive'
    '.bz2'    = 'Archive'
    '.cab'    = 'Archive'
    # Images
    '.jpg'    = 'Image'
    '.jpeg'   = 'Image'
    '.png'    = 'Image'
    '.gif'    = 'Image'
    '.bmp'    = 'Image'
    '.svg'    = 'Image'
    '.tiff'   = 'Image'
    '.ico'    = 'Image'
    '.webp'   = 'Image'
    # Scripts / Code
    '.ps1'    = 'Script'
    '.psm1'   = 'Script'
    '.psd1'   = 'Script'
    '.py'     = 'Script'
    '.js'     = 'Script'
    '.ts'     = 'Script'
    '.sh'     = 'Script'
    '.bat'    = 'Script'
    '.cmd'    = 'Script'
    '.vbs'    = 'Script'
    '.rb'     = 'Script'
    '.go'     = 'Script'
    # Data / Database
    '.db'     = 'Database'
    '.sqlite' = 'Database'
    '.mdb'    = 'Database'
    '.accdb'  = 'Database'
    '.sql'    = 'Database'
    '.bak'    = 'Database'
    '.json'   = 'DataFile'
    '.xml'    = 'DataFile'
    '.yaml'   = 'DataFile'
    '.yml'    = 'DataFile'
    '.toml'   = 'DataFile'
    '.ini'    = 'DataFile'
    '.conf'   = 'DataFile'
    '.config' = 'DataFile'
    # Email
    '.pst'    = 'Email'
    '.ost'    = 'Email'
    '.msg'    = 'Email'
    '.eml'    = 'Email'
    # Media
    '.mp3'    = 'Audio'
    '.wav'    = 'Audio'
    '.mp4'    = 'Video'
    '.avi'    = 'Video'
    '.mkv'    = 'Video'
    '.mov'    = 'Video'
    # Executables
    '.exe'    = 'Executable'
    '.dll'    = 'Executable'
    '.msi'    = 'Executable'
}

function Get-FileCategory {
    param([string]$Extension)
    $ext = $Extension.ToLower()
    if ($CategoryMap.ContainsKey($ext)) {
        return $CategoryMap[$ext]
    }
    return 'Other'
}
#endregion

#region Retention Assessment
function Get-RetentionAssessment {
    param(
        [int]$AgeInDays,
        [int]$ThresholdDays,
        [string]$Category
    )

    # High-priority categories that should always be flagged if old
    $HighPriorityCategories = @('Document', 'Spreadsheet', 'Database', 'Email', 'DataFile')

    if ($AgeInDays -gt ($ThresholdDays * 2)) {
        return @{
            Flag = 'REVIEW_REQUIRED'
            Note = "File age ($AgeInDays days) exceeds $($ThresholdDays * 2)-day threshold (2x retention period). Priority review recommended."
        }
    }
    elseif ($AgeInDays -gt $ThresholdDays -and $Category -in $HighPriorityCategories) {
        return @{
            Flag = 'REVIEW_REQUIRED'
            Note = "File age ($AgeInDays days) exceeds ${ThresholdDays}-day retention threshold for $Category files."
        }
    }
    elseif ($AgeInDays -gt $ThresholdDays) {
        return @{
            Flag = 'AGED'
            Note = "File age ($AgeInDays days) exceeds threshold but category '$Category' is lower priority."
        }
    }
    else {
        return @{
            Flag = 'CURRENT'
            Note = "Within retention period ($AgeInDays / $ThresholdDays days)."
        }
    }
}
#endregion

# Set default output path if not provided
if (-not $OutputCsv) {
    $Desktop = [Environment]::GetFolderPath('Desktop')
    $Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $OutputCsv = Join-Path $Desktop "DataInventory_$Timestamp.csv"
}

# Validate output directory exists
$OutputDir = Split-Path $OutputCsv -Parent
if (-not (Test-Path $OutputDir)) {
    Write-Error "Output directory '$OutputDir' does not exist. Create it first or specify a different -OutputCsv path."
    exit 1
}

Write-Output ""
Write-Output "=== Data Inventory Compliance Audit ==="
Write-Output "Scan Path    : $ScanPath"
Write-Output "Retention    : $RetentionDays days"
Write-Output "Output CSV   : $OutputCsv"
Write-Output "Include Hidden: $($IncludeHidden.IsPresent)"
Write-Output "Scan started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "========================================"

if ($PSCmdlet.ShouldProcess($ScanPath, "Inventory files recursively")) {

    $Now = Get-Date
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $SkippedCount = 0
    $ErrorCount   = 0
    $ProcessedCount = 0

    # Build Get-ChildItem parameters
    $GciParams = @{
        Path    = $ScanPath
        Recurse = $true
        File    = $true
        ErrorAction = 'SilentlyContinue'
    }
    if ($IncludeHidden) {
        $GciParams['Force'] = $true
    }

    Write-Verbose "Scanning directory tree..."
    $AllFiles = Get-ChildItem @GciParams

    $TotalFiles = @($AllFiles).Count
    Write-Output "Files found  : $TotalFiles (before filtering)"

    $Counter = 0
    foreach ($File in $AllFiles) {
        $Counter++
        if ($Counter % 500 -eq 0) {
            Write-Verbose "Processing file $Counter of $TotalFiles..."
        }

        # Check exclusion paths
        $IsExcluded = $false
        foreach ($ExcludePath in $ExcludePaths) {
            if ($File.FullName -like "*$ExcludePath*") {
                $IsExcluded = $true
                break
            }
        }
        if ($IsExcluded) {
            $SkippedCount++
            continue
        }

        # Skip oversized files
        $FileSizeKB = [math]::Round($File.Length / 1KB, 2)
        if ($FileSizeKB -gt $MaxFileSizeKB) {
            Write-Verbose "Skipping large file ($FileSizeKB KB): $($File.FullName)"
            $SkippedCount++
            continue
        }

        try {
            $AgeInDays   = [math]::Round(($Now - $File.LastWriteTime).TotalDays, 0)
            $Category    = Get-FileCategory -Extension $File.Extension
            $RetentionResult = Get-RetentionAssessment -AgeInDays $AgeInDays -ThresholdDays $RetentionDays -Category $Category

            # Try to get file owner (may fail on some files without sufficient rights)
            $Owner = 'Unknown'
            try {
                $Acl = Get-Acl -Path $File.FullName -ErrorAction SilentlyContinue
                if ($Acl) { $Owner = $Acl.Owner }
            }
            catch {
                $Owner = 'Access Denied'
            }

            $Record = [PSCustomObject]@{
                FileName        = $File.Name
                FilePath        = $File.FullName
                ParentDirectory = $File.DirectoryName
                Extension       = $File.Extension.ToLower()
                Category        = $Category
                SizeKB          = $FileSizeKB
                LastModified    = $File.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                CreatedDate     = $File.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
                AgeInDays       = $AgeInDays
                Owner           = $Owner
                RetentionFlag   = $RetentionResult.Flag
                RetentionNote   = $RetentionResult.Note
                ScanDate        = $Now.ToString('yyyy-MM-dd HH:mm:ss')
            }

            $Results.Add($Record)
            $ProcessedCount++
        }
        catch {
            Write-Verbose "Error processing file '$($File.FullName)': $_"
            $ErrorCount++
        }
    }

    # Export to CSV
    if ($Results.Count -gt 0) {
        try {
            $Results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
            Write-Output ""
            Write-Output "=== Audit Complete ==="
            Write-Output "Processed    : $ProcessedCount files"
            Write-Output "Skipped      : $SkippedCount files (excluded paths or oversized)"
            Write-Output "Errors       : $ErrorCount files (access denied or parse error)"
            Write-Output "Output CSV   : $OutputCsv"
        }
        catch {
            Write-Error "Failed to export CSV to '$OutputCsv': $_"
        }
    }
    else {
        Write-Output "No files found after filtering. Check ScanPath and exclusion settings."
    }

    # Summary statistics
    if ($Results.Count -gt 0) {
        Write-Output ""
        Write-Output "=== Summary by Category ==="
        $Results | Group-Object Category | Sort-Object Count -Descending |
            Select-Object Name, Count, @{N='TotalSizeMB';E={[math]::Round(($_.Group | Measure-Object SizeKB -Sum).Sum / 1024, 2)}} |
            Format-Table -AutoSize

        Write-Output "=== Retention Flags ==="
        $Results | Group-Object RetentionFlag | Sort-Object Name |
            Select-Object @{N='Flag';E={$_.Name}}, @{N='FileCount';E={$_.Count}} |
            Format-Table -AutoSize

        $ReviewCount = ($Results | Where-Object { $_.RetentionFlag -eq 'REVIEW_REQUIRED' }).Count
        if ($ReviewCount -gt 0) {
            Write-Output "ACTION REQUIRED: $ReviewCount file(s) are flagged REVIEW_REQUIRED."
            Write-Output "Filter the CSV by RetentionFlag = 'REVIEW_REQUIRED' to identify files needing retention decisions."
        }
        else {
            Write-Output "All files are within retention policy. No review required."
        }
    }

    # Return results for pipeline use
    return $Results
}
else {
    Write-Output "[WhatIf] Would have scanned: $ScanPath"
    Write-Output "[WhatIf] Would have written CSV to: $OutputCsv"
    Write-Output "[WhatIf] RetentionDays threshold: $RetentionDays"
}
