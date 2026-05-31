$files = Get-ChildItem -Path 'C:\Users\makin\OneDrive' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '\.(pdf|docx|xlsx|pptx|txt|md|csv)$' }

foreach ($f in $files) {
    $kb = [math]::Round($f.Length / 1KB, 1)
    Write-Output "$($f.FullName) | $kb KB"
}
