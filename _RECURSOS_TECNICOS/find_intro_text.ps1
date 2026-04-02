$filePath = 'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\Data\Scripts.rxdata'
if (Test-Path $filePath) {
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    # Filter for mostly printable characters with context
    $cleanText = $text -replace '[^ -~áéíóúÁÉÍÓÚñÑ]', ' '
    
    $keywords = @('Experto', 'Nuzlocke', 'Heroico', 'Normal', 'dificultad', 'modalidad', 'reglas')
    foreach ($k in $keywords) {
        if ($cleanText -match $k) {
            Write-Output "--- Found: $k ---"
            $matches = [regex]::Matches($cleanText, ".{0,200}$k.{0,200}")
            foreach ($m in $matches) {
                Write-Output $m.Value.Trim()
                Write-Output "---"
            }
        }
    }
}
