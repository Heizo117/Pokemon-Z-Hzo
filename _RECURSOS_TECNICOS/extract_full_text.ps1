$dataDir = 'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\Data'
$outFile = 'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\all_data_text.txt'
$files = Get-ChildItem -Path $dataDir -File

foreach ($f in $files) {
    if ($f.Extension -eq '.rxdata' -or $f.Extension -eq '.dat') {
        Write-Output "Processing $($f.Name)"
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        $clean = $text -replace '[^a-zA-Z0-9 .,!?#$%-]', ' '
        Add-Content -Path $outFile -Value "--- FILE: $($f.Name) ---"
        Add-Content -Path $outFile -Value $clean
    }
}
