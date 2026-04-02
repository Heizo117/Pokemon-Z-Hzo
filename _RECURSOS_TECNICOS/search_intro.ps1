$files = @(
    'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\Data\Scripts.rxdata',
    'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\Data\CommonEvents.rxdata',
    'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\Data\messages.dat'
)

$keywords = @('Normal', 'Experto', 'Nuzlocke', 'Heroico', 'reglas', 'dificultad', 'modalidad')

foreach ($f in $files) {
    if (Test-Path $f) {
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        $clean = $text -replace '[^ -~]', ' '
        
        Write-Output "--- Search in $f ---"
        foreach ($k in $keywords) {
            $matches = [regex]::Matches($clean, ".{0,150}$k.{0,150}")
            foreach ($m in $matches) {
                Write-Output "MATCH ($k): $($m.Value.Trim())"
                Write-Output "---"
            }
        }
    }
}
