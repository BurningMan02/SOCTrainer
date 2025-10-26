# create-100-random-files.ps1
$target = Join-Path $env:USERPROFILE 'Documents\MyFiles'
New-Item -Path $target -ItemType Directory -Force | Out-Null

# small common-English word list (feel free to extend)
$wordList = @(
'the','be','to','of','and','a','in','that','have','I','it','for','not','on','with','he','as','you','do','at',
'this','but','his','by','from','they','we','say','her','she','or','an','will','my','one','all','would','there','their',
'what','so','up','out','if','about','who','get','which','go','me','when','make','can','like','time','no','just','him',
'know','take','people','into','year','your','good','some','could','them','see','other','than','then','now','look','only',
'come','its','over','think','also','back','after','use','two','how','our','work','first','well','way','even','new','want',
'because','any','these','give','day','most','us'
)

$filesToCreate = 100
for ($i = 1; $i -le $filesToCreate; $i++) {
    $wordsCount = Get-Random -Minimum 20 -Maximum 101   # 20..100 words
    $words = -join (1..$wordsCount | ForEach-Object { $wordList | Get-Random } | ForEach-Object { $_ + ' ' })
    $fileName = "file{0:D3}.txt" -f $i
    $path = Join-Path $target $fileName

    # write file (UTF8), overwrite if exists
    Set-Content -LiteralPath $path -Value $words -Encoding UTF8

    Write-Host "Created $fileName ($wordsCount words)"
}
Write-Host "Done. Files are in: $target"
