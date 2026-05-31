$Base   = 'C:\Users\makin\Organized_Docs'
$OtherD = "$Base\Other_Important_Docs"
$Log    = "$Base\subcategorize_log.txt"
"" | Out-File $Log -Encoding utf8

function Move-Doc($fileName, $destSub) {
    $src = Join-Path $OtherD $fileName
    $dir = Join-Path $Base $destSub
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $dst = Join-Path $dir $fileName
    if (Test-Path $src) {
        Move-Item -Path $src -Destination $dst -Force
        $msg = "MOVED: $fileName -> $destSub"
    } else {
        $msg = "SKIP: $fileName"
    }
    Write-Output $msg
    Add-Content $Log $msg
}

Write-Output "===== SUB-CATEGORIZING ====="

@('FULL PRODUCT REQUIREMENTS DOCUMENT (PRD) SET.docx',
  'GO-TO-MARKET (GTM) PLAYBOOKS.docx',
  'MANUFACTURING & SUPPLY CHAIN PLAYBOOK.docx',
  'ORGANIZATIONAL BLUEPRINT.docx',
  'ROADMAP VISUALIZATIONS.docx',
  'SCRIPTS (Professional + Friendly).docx',
  'SECURITY, PRIVACY & COMPLIANCE FRAMEWORK.docx',
  'TECHNICAL ARCHITECTURE WHITEPAPERS.docx'
) | ForEach-Object { Move-Doc $_ 'OmniTech' }

@('Arsh_Vahora_CoverLetter_Seneca.docx',
  'Arsh_Vahora_PersonalStatement_Seneca.docx'
) | ForEach-Object { Move-Doc $_ 'Career\Cover_Letters' }

@('Civil War.docx','F451 part 2 summary.docx','Timed Writing.docx',
  'Isotope Activity.docx','Isotope and Atomic Particle Practice.docx',
  'Color Lab Activity.docx','Light and Energy Practice Problems.docx',
  'COM101 - Summary Assignment.docx','Homework 1.docx','Homework 3.docx',
  'Assignment 4.docx','Final Exam Essay.docx','Reflection on Self as Writer.docx',
  'Generative Outline.docx','T-tests, Z-tests, Chi-Sqaures.docx',
  'Early Computing and the Analytical Engine.docx','2021 X6 M50i.docx',
  'Mahmadarsh Vahora - Understanding your Brain - 4986406.docx',
  'Mahmadarsh Vahora - Wed 113 Light Notes - 4986406.docx'
) | ForEach-Object { Move-Doc $_ 'High_School' }

Get-ChildItem -Path $OtherD -Filter 'Mahmadarsh Vahora - La semaine*' -ErrorAction SilentlyContinue | ForEach-Object { Move-Doc $_.Name 'High_School' }
Get-ChildItem -Path $OtherD -Filter 'Mahmadarsh Vahora - Vocab*' -ErrorAction SilentlyContinue | ForEach-Object { Move-Doc $_.Name 'High_School' }

@('Healthy Body.docx','Cooking at Home.docx','Quotes.docx',
  "Men's mental health skit (Tanjiro & Zuko).docx",
  'The Other Izuku.docx','Mist Notes.docx','2D.docx','Agent Identity.docx',
  'Name_ Cassidy Hamada.docx','OPEN IT.docx','message 5.txt',
  'To-do Watch.docx','Seerah.docx',
  'Seerah_ Early Meccan Period.docx','Seerah_Late Mecan Period.docx'
) | ForEach-Object { Move-Doc $_ 'Personal' }

@('mahvahora@gmail.com - Google Drive - Report.txt',
  'mmv20227@gmail.com - Google Drive - Report.txt',
  'mvahora2023@gmail.com - Dropbox - Report.txt',
  'Sarif71@icloud.com - Google Drive - Report.txt',
  't12m92finish@gmail.com - Google Drive - Report.txt'
) | ForEach-Object { Move-Doc $_ 'Import_Reports' }

@('Untitled document.docx','Untitled document (1).docx',
  'Untitled document (2).docx','Untitled document (3).docx',
  'Untitled document (4).docx','Untitled document (5).docx',
  'Untitled document (6).docx','Untitled document (7).docx'
) | ForEach-Object { Move-Doc $_ 'Untitled_Docs' }

Move-Doc 'Courses.docx' 'DCCC'

Write-Output "===== DONE ====="
