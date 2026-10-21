function Show-CleanMenu {
    while ($true) {
        Clear-Host
        Write-Host '=============================================='
        Write-Host '  Clean Storage'
        Write-Host '=============================================='
        Write-Host '  1. Run storage cleanup (background task, C: drive)'
        Write-Host '  2. View latest cleanup log'
        Write-Host '  B. Back'
        Write-Host ' '
        $sel = (Read-Host 'Select an option').Trim()
        switch -Regex ($sel) {
            '^1$' { Register-CleanupTask; Wait-ForKey }
            '^2$' {
                $log = Get-ChildItem (Join-Path $script:Config.LogFolder 'ServerCleanup_*.log') -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($log) {
                    Write-Host "Showing last 40 lines of $($log.FullName)"; Write-Host ' '
                    Get-Content $log.FullName -Tail 40
                } else { Write-Host ' No cleanup logs found.' }
                Wait-ForKey
            }
            '^[Bb]$'  { return }
            default   { Write-Host ' Invalid selection.'; Start-Sleep -Seconds 1 }
        }
    }
}
