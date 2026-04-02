$text = Get-Content 'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\all_data_text.txt' -Raw
$keywords = @('Normal', 'Experto', 'Nuzlocke', 'Heroico')
foreach ($k in $keywords) {
    if ($text -match $k) {
        Write-Output "--- $k ---"
        $matches = [regex]::Matches($text, ".{0,300}$k.{0,300}")
        foreach ($m in $matches) {
            $context = $m.Value.Trim()
            # Only output if it contains at least two of the keywords (likely a menu or comparison)
            $count = 0
            foreach ($k2 in $keywords) {
                if ($context -match $k2) { $count++ }
            }
            if ($count -ge 2) {
                Write-Output $context
                Write-Output "---"
            }
        }
    }
}
