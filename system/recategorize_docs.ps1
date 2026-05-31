# Recategorize-OtherDocs.ps1
# Moves misrouted files from Other_Important_Docs into correct subfolders
# Within Organized_Docs only — no touching OneDrive originals

$Base = 'C:\Users\makin\Organized_Docs'
$Src  = "$Base\Other_Important_Docs"
$Log  = "$Base\recategorize_log.txt"
"" | Out-File $Log -Encoding utf8

function Move-Doc($fileName, $destSub) {
    $source = Join-Path $Src $fileName
    $destDir = Join-Path $Base $destSub
    $dest   = Join-Path $destDir $fileName
    if (-not (Test-Path $source)) {
        "MISSING: $fileName" | Add-Content $Log; return
    }
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Move-Item -Path $source -Destination $dest -Force
    "MOVED: $fileName -> $destSub" | Add-Content $Log
}

# ── OMNITECH (misrouted) ─────────────────────────────────────
$omnitech = @(
    'FULL PRODUCT REQUIREMENTS DOCUMENT (PRD) SET.docx',
    'GO-TO-MARKET (GTM) PLAYBOOKS.docx',
    'MANUFACTURING & SUPPLY CHAIN PLAYBOOK.docx',
    'ORGANIZATIONAL BLUEPRINT.docx',
    'ROADMAP VISUALIZATIONS.docx',
    'SCRIPTS (Professional + Friendly).docx',
    'SECURITY, PRIVACY & COMPLIANCE FRAMEWORK.docx',
    'TECHNICAL ARCHITECTURE WHITEPAPERS.docx'
)
foreach ($f in $omnitech) { Move-Doc $f 'OmniTech' }

# ── CAREER (misrouted) ───────────────────────────────────────
Move-Doc 'Arsh_Vahora_CoverLetter_Seneca.docx'      'Career\Cover_Letters'
Move-Doc 'Arsh_Vahora_PersonalStatement_Seneca.docx' 'Career\Cover_Letters'

# ── CYBERSECURITY STUDY GUIDES (misrouted) ───────────────────
Move-Doc '⭐ COURSE 2 — MASTER SUMMARY (MODULES 1–4).docx' 'Cybersecurity\Study_Guides'

# ── HIGH SCHOOL ──────────────────────────────────────────────
$highschool = @(
    'Civil War.docx',
    'F451 part 2 summary.docx',
    'Timed Writing.docx',
    'Isotope Activity.docx',
    'Color Lab Activity.docx',
    'Isotope and Atomic Particle Practice.docx',
    'Isotopes … Relative Abundance and Atomic Mass.docx',
    'Light and Energy Practice Problems.docx',
    'COM101 - Summary Assignment.docx',
    'Homework 1.docx',
    'Homework 3.docx',
    'Assignment 4.docx',
    'Final Exam Essay.docx',
    'Reflection on Self as Writer.docx',
    'Generative Outline.docx',
    'T-tests, Z-tests, Chi-Sqaures.docx',
    'Early Computing and the Analytical Engine.docx',
    'Mahmadarsh Vahora - La semaine 11 Activité 1 Le vocabulaire 1C Le Mariage - 4986406.docx',
    'Mahmadarsh Vahora - La semaine 12 Activité 2 Les questions de comprehensio - 4986406.docx',
    'Mahmadarsh Vahora - La semaine 2 Activité 1 Bridging 3 to 4 present tense - 4986406.docx',
    'Mahmadarsh Vahora - Understanding your Brain - 4986406.docx',
    'Mahmadarsh Vahora - Vocab elodie va assister a un mariage - 4986406.docx',
    'Mahmadarsh Vahora - Wed 113 Light Notes - 4986406.docx',
    '2021 X6 M50i.docx',
    'Courses.docx'
)
foreach ($f in $highschool) { Move-Doc $f 'High_School' }

# ── PERSONAL ─────────────────────────────────────────────────
$personal = @(
    'Healthy Body.docx',
    'Cooking at Home.docx',
    'Quotes.docx',
    "Men's mental health skit (Tanjiro & Zuko).docx",
    'The Other Izuku.docx',
    'Mist Notes.docx',
    '2D.docx',
    'Agent Identity.docx',
    'Name_ Cassidy Hamada.docx',
    'OPEN IT.docx',
    'message 5.txt',
    'Seerah.docx',
    'Seerah_ Early Meccan Period.docx',
    'Seerah_Late Mecan Period.docx',
    'To-do Watch.docx'
)
foreach ($f in $personal) { Move-Doc $f 'Personal' }

# ── IMPORT REPORTS ───────────────────────────────────────────
$reports = @(
    'mahvahora@gmail.com - Google Drive - Report.txt',
    'mmv20227@gmail.com - Google Drive - Report.txt',
    'mvahora2023@gmail.com - Dropbox - Report.txt',
    'Sarif71@icloud.com - Google Drive - Report.txt',
    't12m92finish@gmail.com - Google Drive - Report.txt'
)
foreach ($f in $reports) { Move-Doc $f 'Import_Reports' }

# ── UNTITLED DOCS ────────────────────────────────────────────
$untitled = @(
    'Untitled document.docx',
    'Untitled document (1).docx',
    'Untitled document (2).docx',
    'Untitled document (3).docx',
    'Untitled document (4).docx',
    'Untitled document (5).docx',
    'Untitled document (6).docx',
    'Untitled document (7).docx'
)
foreach ($f in $untitled) { Move-Doc $f 'Untitled_Docs' }

# ── SUMMARY ──────────────────────────────────────────────────
$moved   = (Select-String -Path $Log -Pattern '^MOVED').Count
$missing = (Select-String -Path $Log -Pattern '^MISSING').Count

Write-Output "`n===== RECATEGORIZATION DONE ====="
Write-Output "Moved  : $moved files"
Write-Output "Missing: $missing files"
Write-Output "Log    : $Log"
