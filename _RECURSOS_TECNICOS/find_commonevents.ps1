$text = Get-Content 'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\all_data_text.txt' -Raw
$parts = $text -split '--- FILE: '
foreach ($p in $parts) {
    if ($p -match 'CommonEvents.rxdata') {
        # Split by multiple spaces which usually separate strings in this format
        $lines = $p -split '  +'
        foreach ($l in $lines) {
            $clean = $l.Trim()
            if ($clean -match 'Nuzlocke|Experto|Normal|Heroico|Reglas|Dificultad|Elija') {
                Write-Output $clean
            }
        }
    }
}
