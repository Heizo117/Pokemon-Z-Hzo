$filePath = 'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\Data\Scripts.rxdata'
if (Test-Path $filePath) {
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    $patterns = @('Nuzlocke', 'Experto', 'Heroico', 'reglas', 'dificultad', 'modalidad')
    foreach ($p in $patterns) {
        $matches = [regex]::Matches($text, ".{0,150}$p.{0,150}")
        if ($matches.Count -gt 0) {
            Write-Output "--- Pattern: $p ---"
            foreach ($m in $matches) {
                Write-Output $m.Value
                Write-Output "---"
            }
        }
    }
} else {
    Write-Output "File not found"
}
