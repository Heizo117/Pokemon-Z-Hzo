$text = [IO.File]::ReadAllText('preload.rb')
$text = $text -replace "`r`n", "`n"
$text = $text -replace "`r", "`n"
[IO.File]::WriteAllText('preload.rb', $text)
