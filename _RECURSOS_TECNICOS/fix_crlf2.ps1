$text = [IO.File]::ReadAllText('preload.rb')
$text = $text -replace "`r`n", "`n"
$text = $text -replace "`n", "`r`n"
$bytes = [Text.Encoding]::UTF8.GetBytes($text)
[IO.File]::WriteAllBytes('preload.rb', $bytes)
