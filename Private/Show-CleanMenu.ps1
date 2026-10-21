function Show-CleanMenu {
    while ($true) {
        Clear-Host
        Write-Host '=============================================='
        Write-Host '  Clean Storage'
        Write-Host '=============================================='
        Write-Host '  1. Run storage cleanup (background task, C: drive)'
        Write-Host '  2. View latest cleanup log (last 50 lines)'
        Write-Host '  3. Follow cleanup log live'
        Write-Host '  B. Back'
        Write-Host ' '
        $sel = (Read-Host 'Select an option').Trim()
        switch -Regex ($sel) {
            '^1$' {
                Register-CleanupTask
                if (Get-ScheduledTask -TaskName 'Start-ServerCleanup' -ErrorAction SilentlyContinue) {
                    $f = (Read-Host 'Follow the log live now? (Y/N)').Trim()
                    if ($f -match '^[Yy]') { Show-CleanupLog -Tail 50 -Wait }
                }
                Wait-ForKey
            }
            '^2$' { Show-CleanupLog -Tail 50; Wait-ForKey }
            '^3$' { Show-CleanupLog -Tail 50 -Wait; Wait-ForKey }
            '^[Bb]$'  { return }
            default   { Write-Host ' Invalid selection.'; Start-Sleep -Seconds 1 }
        }
    }
}