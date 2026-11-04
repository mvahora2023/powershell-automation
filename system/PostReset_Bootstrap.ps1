# ================================
#  Mahmadarsh OS v2 — Bootstrap Script
#  Run once after Windows reset
# ================================

[CmdletBinding()]
param([switch]$Apply)
if (-not $Apply) {
    Write-Output 'PREVIEW ONLY. With -Apply this script may install applications, change Windows preferences, and create sample maintenance scripts.'
    Write-Output 'Inspect every step and run in a disposable test machine first. No local data is included in this GitHub repository.'
    return
}
Write-Host "Starting Windows bootstrap (approved -Apply)..." -ForegroundColor Cyan

# === Paths ===
$UserRoot   = $env:USERPROFILE
$Organized  = Join-Path $UserRoot "Organized"
$Maintenance = Join-Path $UserRoot "Maintenance"
$Logs        = Join-Path $Maintenance "Logs"
$Reports     = Join-Path $Maintenance "Reports"

# === 1. Create Organized folder structure ===
$folders = @(
    "Automation-UiPath",
    "Cybersecurity",
    "Discord-Bots",
    "Education",
    "Finance",
    "Images-Media",
    "Installers",
    "Misc",
    "OmniTech",
    "Spreadsheets"
)

if (-not (Test-Path $Organized)) {
    New-Item -ItemType Directory -Path $Organized | Out-Null
}

foreach ($f in $folders) {
    $path = Join-Path $Organized $f
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

Write-Host "[OK] Organized folder structure created."

# === 2. Create Maintenance folders ===
foreach ($p in @($Maintenance, $Logs, $Reports)) {
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p | Out-Null
    }
}

Write-Host "[OK] Maintenance folder created."

# === 3. Install core apps via winget ===
function Install-App {
    param([string]$Id, [string]$Name)
    Write-Host "[*] Installing $Name..."
    winget install --id $Id --silent --accept-package-agreements --accept-source-agreements -h 2>$null
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Install-App -Id "Microsoft.Edge" -Name "Microsoft Edge"
    Install-App -Id "Google.Chrome" -Name "Google Chrome"
    Install-App -Id "Microsoft.VisualStudioCode" -Name "VS Code"
    Install-App -Id "Discord.Discord" -Name "Discord"
    Install-App -Id "7zip.7zip" -Name "7-Zip"
} else {
    Write-Host "[WARN] winget not found. Install apps manually."
}

# === 4. Apply Windows preferences ===
# Dark mode
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
    -Name "AppsUseLightTheme" -Value 0 -Force

# Show file extensions
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "HideFileExt" -Value 0 -Force

# Show hidden files
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "Hidden" -Value 1 -Force

Write-Host "[OK] Windows preferences applied."

# === 5. Performance tuning ===
# Balanced plan + no sleep on AC
powercfg /setactive SCHEME_BALANCED
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 20

Write-Host "[OK] Performance settings applied."

# === 6. Security hardening ===
# SmartScreen ON
Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue

Write-Host "[OK] Security baseline applied."

# === 7. Install lightweight automation scripts ===

# Backup script
$backupScript = @'
param([switch]$Apply)
if (-not $Apply) { Write-Output "Preview: would copy Organized to Backups. Use -Apply to perform the copy."; return }
$source = Join-Path $env:USERPROFILE 'Organized'
$destRoot = Join-Path $env:USERPROFILE 'Backups'
if (-not (Test-Path -LiteralPath $source)) { throw "Source folder does not exist" }
if (-not (Test-Path -LiteralPath $destRoot)) { New-Item -ItemType Directory -Path $destRoot | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$dest = Join-Path $destRoot ("Organized_" + $stamp)
if (Test-Path -LiteralPath $dest) { throw "Refusing to overwrite existing destination" }
Copy-Item -LiteralPath $source -Destination $dest -Recurse -ErrorAction Stop
'@

Set-Content -Path "$Maintenance\backup_organized.ps1" -Value $backupScript -Encoding UTF8

# Temp cleanup script
$cleanupScript = @'
param([switch]$Apply)
if (-not $Apply) { Write-Output "Preview: cleanup script requires explicit -Apply."; return }
Write-Output "Review temporary folders and back up anything important before deletion."
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
'@

Set-Content -Path "$Maintenance\cleanup_temp.ps1" -Value $cleanupScript -Encoding UTF8

Write-Host "[OK] Automation scripts installed."

Write-Host "`nMahmadarsh OS v2 bootstrap complete." -ForegroundColor Green
