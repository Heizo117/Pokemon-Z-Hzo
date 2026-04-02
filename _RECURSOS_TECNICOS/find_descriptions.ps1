$files = @(
    'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\Data\Scripts.rxdata',
    'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\Data\messages.dat'
)

$keywords = @('Normal', 'Experto', 'Nuzlocke', 'Heroico', 'Dificultad', 'Reglas')

foreach ($file in $files) {
    if (Test-Path $file) {
        Write-Output "Processing $file"
        $bytes = [System.IO.File]::ReadAllBytes($file)
        # Try both ASCII and UTF8/UTF16 as sometimes text is mixed
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        $cleanText = $text -replace '[^ -~]', ' '
        
        foreach ($k in $keywords) {
            if ($cleanText -match $k) {
                Write-Output "Matches for $k in $file"
                $matches = [regex]::Matches($cleanText, ".{0,100}$k.{0,100}")
                foreach ($m in $matches) {
                    Write-Output "---"
                    Write-Output $m.Value.Trim()
                }
            }
        }
    }
}
