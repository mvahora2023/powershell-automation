# ================================
#  Mahmadarsh OS v2 — Bootstrap Script
#  Run once after Windows reset
# ================================

Write-Host "Starting Mahmadarsh OS v2 bootstrap..." -ForegroundColor Cyan

# === Paths ===
$UserRoot   = "C:\Users\makin"
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
$backupScript = @"
\$source = 'C:\Users\makin\Organized'
\$destRoot = 'D:\Backups'
if (-not (Test-Path \$destRoot)) { New-Item -ItemType Directory -Path \$destRoot | Out-Null }
\$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
\$dest = Join-Path \$destRoot "Organized_\$stamp"
Copy-Item -Path \$source -Destination \$dest -Recurse -Force
"@
Set-Content -Path "$Maintenance\backup_organized.ps1" -Value $backupScript -Encoding UTF8

# Temp cleanup script
$cleanupScript = @"
Remove-Item -Path \$env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'C:\Windows\Temp\*' -Recurse -Force -ErrorAction SilentlyContinue
"@
Set-Content -Path "$Maintenance\cleanup_temp.ps1" -Value $cleanupScript -Encoding UTF8

Write-Host "[OK] Automation scripts installed."

Write-Host "`nMahmadarsh OS v2 bootstrap complete." -ForegroundColor Green
