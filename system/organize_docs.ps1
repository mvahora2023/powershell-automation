# Organize-OneDrive-DC.ps1
# Safe copy-only organizer — no moves, no deletes
# Destination: C:\Users\makin\Organized_Docs\

$SourceRoot = 'C:\Users\makin\OneDrive'
$DestRoot   = 'C:\Users\makin\Organized_Docs'
$LogFile    = "$DestRoot\copy_log.txt"

$TargetExts = @('.pdf','.docx','.xlsx','.pptx','.txt','.md','.csv')

# Keyword -> destination subfolder (checked in order, first match wins)
$FolderMap = [ordered]@{
    'omnitech'      = 'OmniTech'
    'executive summary - omni' = 'OmniTech'
    'product catalog'= 'OmniTech'
    'omnidesign'    = 'OmniTech'
    'omni'          = 'OmniTech'
    'nist csf'      = 'Cybersecurity\NIST'
    'nist'          = 'Cybersecurity\NIST'
    'incident report'= 'Cybersecurity\Incident_Reports'
    'security incident'= 'Cybersecurity\Incident_Reports'
    'cybersecurity incident'= 'Cybersecurity\Incident_Reports'
    'security risk' = 'Cybersecurity\Risk_Assessment'
    'wireshark'     = 'Cybersecurity\Labs'
    'tcpdump'       = 'Cybersecurity\Labs'
    'network hardening'= 'Cybersecurity\Labs'
    'applying the nist'= 'Cybersecurity\Labs'
    'cysa'          = 'CompTIA\CySA+'
    'network+'      = 'CompTIA\Network+'
    'network security'= 'CompTIA\Network+'
    'networks and network'= 'CompTIA\Network+'
    'security+'     = 'CompTIA\Security+'
    'course 2 - master'= 'CompTIA\Security+'
    'course 3'      = 'CompTIA\Network+'
    'master study guide course 1'= 'Cybersecurity\Study_Guides'
    'master guide'  = 'Cybersecurity\Study_Guides'
    'study guide'   = 'Cybersecurity\Study_Guides'
    'comptia'       = 'CompTIA'
    'dccc'          = 'DCCC'
    'mvahora1@mail.dccc' = 'DCCC'
    'asu courses'   = 'DCCC\ASU_Transfer'
    'penn state courses'= 'DCCC\Transfer_Planning'
    'clep'          = 'DCCC\CLEP'
    'fbla'          = 'Other_Important_Docs\FBLA'
    'resume'        = 'Career\Resumes'
    'cover letter'  = 'Career\Cover_Letters'
    'personal statement'= 'Career\Cover_Letters'
    'budget'        = 'Finance'
    'financial model'= 'Finance'
    'dungeon'       = 'Creative\Eternal_Dao'
    'inside_'       = 'Creative\Eternal_Dao'
    'outside_'      = 'Creative\Eternal_Dao'
    'world_'        = 'Creative\Eternal_Dao'
    'world map'     = 'Creative\Eternal_Dao'
    'automation'    = 'Automation'
    'macro'         = 'Automation'
    'commands for nssm'= 'Automation'
}

function Get-DestFolder($fullPath, $ext) {
    $lower = $fullPath.ToLower()
    foreach ($key in $FolderMap.Keys) {
        if ($lower -match [regex]::Escape($key.ToLower())) {
            $sub = $FolderMap[$key]
            # Excel always goes to Spreadsheets_Excel subfolder within its category
            if ($ext -eq '.xlsx' -or $ext -eq '.csv') {
                if ($sub -match 'Finance|Cybersecurity|CompTIA|DCCC') {
                    return "$sub\Spreadsheets"
                }
                return 'Spreadsheets_Excel'
            }
            return $sub
        }
    }
    # Fallback
    if ($ext -eq '.xlsx' -or $ext -eq '.csv') { return 'Spreadsheets_Excel' }
    if ($ext -eq '.pdf')  { return 'PDFs_General' }
    if ($ext -eq '.pptx') { return 'Other_Important_Docs\Presentations' }
    return 'Other_Important_Docs'
}

# Skip these — sensitive or irrelevant
$SkipFiles = @('Microsoft Edge Passwords.csv', 'desktop.ini', 'mwf_config')

# Collect files
$allFiles = Get-ChildItem -Path $SourceRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $TargetExts -contains $_.Extension.ToLower() }

$plan = @()
foreach ($f in $allFiles) {
    if ($SkipFiles -contains $f.Name) { continue }
    $ext  = $f.Extension.ToLower()
    $sub  = Get-DestFolder $f.FullName $ext
    $dest = Join-Path $DestRoot (Join-Path $sub $f.Name)
    $plan += [PSCustomObject]@{
        File   = $f.Name
        Folder = $sub
        Source = $f.FullName
        Dest   = $dest
        KB     = [math]::Round($f.Length/1KB,1)
    }
}

# Summary by folder
Write-Output "`n===== DRY RUN SUMMARY ====="
$plan | Group-Object Folder | Sort-Object Name | ForEach-Object {
    Write-Output "  $($_.Name)  ($($_.Count) files)"
}
Write-Output "  TOTAL: $($plan.Count) files"
Write-Output "==========================="

# Execute copy
New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
"" | Out-File $LogFile -Encoding utf8

$copied = 0; $skipped = 0; $errors = 0

foreach ($item in $plan) {
    try {
        New-Item -ItemType Directory -Path (Split-Path $item.Dest) -Force | Out-Null
        if (Test-Path $item.Dest) {
            "SKIP: $($item.File) -> $($item.Folder)" | Add-Content $LogFile
            $skipped++
        } else {
            Copy-Item -Path $item.Source -Destination $item.Dest -Force
            "COPY: $($item.File) -> $($item.Folder)" | Add-Content $LogFile
            $copied++
        }
    } catch {
        "ERROR: $($item.File) -- $_" | Add-Content $LogFile
        $errors++
    }
}

Write-Output "`n===== DONE ====="
Write-Output "Copied : $copied"
Write-Output "Skipped: $skipped"
Write-Output "Errors : $errors"
Write-Output "Log    : $LogFile"
