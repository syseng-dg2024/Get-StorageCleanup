function Register-CleanupTask {
    $TaskName = 'Start-ServerCleanup'
    if (-not (Test-IsAdmin)) {
        Write-Host 'ERROR: Run PowerShell as Administrator to start a cleanup.' -ForegroundColor Red
        return
    }
    $days = $script:Config.DaysToDelete
    Write-Host ' '
    Write-Host "This will delete temp/system files older than $days days, compress IIS logs,"
    Write-Host 'run DISM component cleanup, clear caches and empty the Recycle Bin.'
    Write-Host 'It runs in the background as SYSTEM and the task removes itself when done.'
    Write-Host ' '
    $c = Read-Host 'Type YES to start (anything else cancels)'
    if ($c -cne 'YES') { Write-Host 'Cancelled.'; return }

    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    $psd1 = Join-Path (Get-Module Get-StorageCleanup).ModuleBase 'Get-StorageCleanup.psd1'
    $cmd  = "Import-Module '$psd1' -Force; Invoke-DriveCleanup -RunningAsTask"
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""
    $trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10)
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 4)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Write-Host ' '
    Write-Host "Task '$TaskName' registered. Cleanup begins in ~10 seconds." -ForegroundColor Cyan
    Write-Host "Log: $($script:Config.LogFolder)\StorageCleanup_*.log  (use 'View latest cleanup log' to monitor)" -ForegroundColor Green
}
