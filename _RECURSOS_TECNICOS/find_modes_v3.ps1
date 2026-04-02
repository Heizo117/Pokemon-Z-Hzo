$text = Get-Content 'c:\Users\heizo\Downloads\POKEMON Z V2.15\Pokemon Z V2.15\all_data_text.txt' -Raw
$keywords = @('Normal', 'Experto', 'Nuzlocke', 'Heroico', 'Elija')
# Look for blocks of 1000 characters that mention at least 2 of these
$pattern = ".{0,1000}"
$regex = [regex]::new("(?i)(Normal|Experto|Nuzlocke|Heroico|Elija)")
$matches = $regex.Matches($text)

$foundBlocks = @()

foreach ($m in $matches) {
    $start = [Math]::Max(0, $m.Index - 500)
    $len = [Math]::Min(1000, $text.Length - $start)
    $block = $text.Substring($start, $len)
    
    $count = 0
    foreach ($k in $keywords) {
        if ($block -match $k) { $count++ }
    }
    
    if ($count -ge 3) {
        $foundBlocks += $block.Trim()
    }
}

$foundBlocks | Select-Object -Unique | ForEach-Object {
    Write-Output "--- Potential Mode Definition Block ---"
    Write-Output $_
    Write-Output "---"
}
