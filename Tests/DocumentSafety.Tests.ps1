#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path $PSScriptRoot -Parent
    $organizer = Join-Path $repo 'system\organize_docs.ps1'
    $recategorize = Join-Path $repo 'system\recategorize_docs.ps1'
}
Describe 'Safe file organization' {
    BeforeEach {
        $root=Join-Path ([System.IO.Path]::GetTempPath()) ('safeops-test-'+[guid]::NewGuid())
        $src=Join-Path $root 'OneDrive'
        $dst=Join-Path $root 'Organized_Docs'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'example.txt') -Value 'original'
    }
    AfterEach { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    It 'organizer is dry-run without Apply' {
        & $organizer -SourceRoot $src -DestRoot $dst | Out-Null
        Test-Path -LiteralPath $dst | Should -BeFalse
    }
    It 'organizer copies with explicit Apply and no overwrite' {
        $destFile=Join-Path $dst 'Other_Important_Docs\example.txt'
        & $organizer -SourceRoot $src -DestRoot $dst -Apply -Confirm:$false | Out-Null
        (Get-Content -LiteralPath $destFile -Raw).Trim() | Should -Be 'original'
        (Get-Content -LiteralPath (Join-Path $src 'example.txt') -Raw).Trim() | Should -Be 'original'
        Set-Content -LiteralPath $destFile -Value 'newer-destination'
        & $organizer -SourceRoot $src -DestRoot $dst -Apply -Confirm:$false | Out-Null
        (Get-Content -LiteralPath $destFile -Raw).Trim() | Should -Be 'newer-destination'
    }
}
Describe 'Safe recategorization' {
    BeforeEach {
        $root=Join-Path ([System.IO.Path]::GetTempPath()) ('safeops-recat-'+[guid]::NewGuid())
        $base=Join-Path $root 'Organized_Docs'
        $sourceFolder=Join-Path $base 'Other_Important_Docs'
        New-Item -ItemType Directory -Path $sourceFolder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sourceFolder 'example.txt') -Value 'original'
        $csv=Join-Path $root 'mapping.csv'
        "SourceName,DestinationFolder"+[Environment]::NewLine+"example.txt,Work/Projects" | Set-Content -LiteralPath $csv
    }
    AfterEach { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    It 'does nothing without Apply' {
        & $recategorize -BaseRoot $base -MappingCsv $csv | Out-Null
        Test-Path -LiteralPath (Join-Path $sourceFolder 'example.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $base 'Work\Projects\example.txt') | Should -BeFalse
    }
    It 'moves only after Apply' {
        & $recategorize -BaseRoot $base -MappingCsv $csv -Apply -Confirm:$false | Out-Null
        Test-Path -LiteralPath (Join-Path $sourceFolder 'example.txt') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $base 'Work\Projects\example.txt') -Raw).Trim() | Should -Be 'original'
    }
    It 'preserves existing destination files' {
        $target=Join-Path $base 'Work\Projects\example.txt'
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        Set-Content -LiteralPath $target -Value 'keep-me'
        & $recategorize -BaseRoot $base -MappingCsv $csv -Apply -Confirm:$false | Out-Null
        (Get-Content -LiteralPath $target -Raw).Trim() | Should -Be 'keep-me'
        Test-Path -LiteralPath (Join-Path $sourceFolder 'example.txt') | Should -BeTrue
    }
    It 'rejects traversal attempts' {
        "SourceName,DestinationFolder"+[Environment]::NewLine+"example.txt,../outside" | Set-Content -LiteralPath $csv
        { & $recategorize -BaseRoot $base -MappingCsv $csv -Apply -Confirm:$false } | Should -Throw
    }
}
