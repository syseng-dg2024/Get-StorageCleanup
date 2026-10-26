function Invoke-DirSWithTimeout {
    # Runs 'cmd /c dir /s /a' on a path, returns the byte total, kills it if it exceeds the timeout.
    param([string]$Path, [int]$TimeoutSec = 300)
    $tmp = Join-Path $env:TEMP "gsc_dir_$PID`_$(Get-Random).tmp"
    $p = Start-Process cmd.exe -ArgumentList "/c dir /s /a `"$Path`" 2>nul > `"$tmp`"" -PassThru -NoNewWindow -WindowStyle Hidden
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Write-AnalyzeLog "  TIMEOUT: scan of '$Path' exceeded $TimeoutSec sec - folder size may be incomplete."
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return [long]0
    }
    $bytes = [long]0
    foreach ($line in (Get-Content $tmp -ErrorAction SilentlyContinue)) {
        if ($line -match 'File\(s\)\s+([\d,]+)\s+bytes') { $bytes = [long]($Matches[1] -replace ',','') }
    }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $bytes
}