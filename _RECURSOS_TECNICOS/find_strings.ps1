$filePath = 'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\Data\Scripts.rxdata'
if (Test-Path $filePath) {
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    # Simple strings-like filter: alphanumeric and basic punctuation
    $cleanText = $text -replace '[^a-zA-Z0-9 .,!?#$%-]', ' '
    
    $keywords = @('Nuzlocke', 'Experto', 'Heroico', 'Normal', 'Challenge', 'Level', 'Difficulty')
    foreach ($k in $keywords) {
        if ($cleanText -match $k) {
            $matches = [regex]::Matches($cleanText, ".{0,100}$k.{0,100}")
            Write-Output "--- $k ---"
            foreach ($m in $matches) {
                Write-Output $m.Value.Trim()
            }
        }
    }
}
