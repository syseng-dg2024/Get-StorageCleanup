function Measure-FolderSize {
    # Measures a folder with robocopy /L (list-only). /XJ skips junctions, so
    # junction loops cannot hang the scan. Kills the process if it exceeds the timeout.
    param([string]$Path, [int]$TimeoutSec = 300)
    $p = Start-Process robocopy.exe -ArgumentList "`"$Path`" NULL /L /E /BYTES /XJ /NFL /NDL /NJH /NP" -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\gsc_rc_$PID.out" -RedirectStandardError "$env:TEMP\gsc_rc_$PID.err"
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Write-AnalyzeLog "  TIMEOUT: scan of '$Path' exceeded $TimeoutSec sec - folder size may be incomplete."
        Remove-Item "$env:TEMP\gsc_rc_$PID.out","$env:TEMP\gsc_rc_$PID.err" -Force -ErrorAction SilentlyContinue
        return [long]0
    }
    $bytes = [long]0
    foreach ($line in (Get-Content "$env:TEMP\gsc_rc_$PID.out" -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*Bytes\s*:\s*([\d\s]+)') { $bytes = [long]($Matches[1] -replace '\s','') }
    }
    Remove-Item "$env:TEMP\gsc_rc_$PID.out","$env:TEMP\gsc_rc_$PID.err" -Force -ErrorAction SilentlyContinue
    return $bytes
}