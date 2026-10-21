function Test-IsAdmin {
    $null = net session 2>&1
    return ($LASTEXITCODE -eq 0)
}
