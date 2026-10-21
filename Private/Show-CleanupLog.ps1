function Show-CleanupLog {
    param(
        [int]$Tail = 50,
        [switch]$Wait
    )
    $TaskName = 'Start-ServerCleanup'
    $pattern  = Join-Path $script:Config.LogFolder 'StorageCleanup_*.log'
    $current  = $null
    $shown    = 0

    if ($Wait) { Write-Host " Following cleanup log. Press Q to stop (cleanup keeps running)." -ForegroundColor Cyan; Write-Host ' ' }

    while ($true) {
        # Check task state BEFORE reading so the final lines are never missed
        $taskActive = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)

        $log = Get-ChildItem $pattern -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if ($log) {
            if ($current -ne $log.FullName) {
                $current = $log.FullName
                $shown   = 0
                Write-Host " Log: $current" -ForegroundColor Green; Write-Host ' '
            }
            $lines = @(Get-Content $current -ErrorAction SilentlyContinue)
            if ($shown -eq 0 -and $lines.Count -gt $Tail) { $shown = $lines.Count - $Tail }
            for ($i = $shown; $i -lt $lines.Count; $i++) { Write-Host $lines[$i] }
            $shown = $lines.Count
        }
        elseif (-not $Wait) {
            Write-Host ' No cleanup logs found.'
            return
        }

        if (-not $Wait) { return }

        if (-not $taskActive -and $log) {
            Write-Host ' '; Write-Host ' Cleanup task has finished.' -ForegroundColor Green
            return
        }

        # Q to quit (wrapped for hosts without a console)
        try {
            if ($Host.UI.RawUI.KeyAvailable) {
                $k = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                if ($k.Character -eq 'q' -or $k.Character -eq 'Q') { return }
            }
        } catch { }

        Start-Sleep -Seconds 2
    }
}