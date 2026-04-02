$dataDir = 'Data'
$outFile = 'maps_text.txt'
$files = @('Map010.rxdata', 'Map018.rxdata', 'Map030.rxdata', 'Map045.rxdata', 'Map060.rxdata', 'Map082.rxdata', 'Map104.rxdata', 'Map114.rxdata', 'Map134.rxdata', 'Map142.rxdata', 'Map164.rxdata')

foreach ($f in $files) {
    $filePath = Join-Path -Path $dataDir -ChildPath $f
    if (Test-Path $filePath) {
        Write-Output "Processing $($f)"
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        $clean = $text -replace '[^a-zA-Z0-9 .,!?#$%-]', ' '
        Add-Content -Path $outFile -Value "--- FILE: $($f) ---"
        Add-Content -Path $outFile -Value $clean
        Add-Content -Path $outFile -Value ""
    } else {
        Write-Output "File not found: $($filePath)"
    }
}

Write-Output "Extraction complete. Output saved to $($outFile)"
