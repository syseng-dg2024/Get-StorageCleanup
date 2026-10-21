function Invoke-DriveAnalysis {
    $Top = $script:Config.Top
    $FolderThresholdMB = $script:Config.FolderThresholdMB
    $folderBytes = [long]$FolderThresholdMB * [long]1048576

    $drive = Select-Drive
    if (-not $drive) { return }
    Start-AnalyzeReport

    $root = "$drive\"
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'"
    Write-AnalyzeLog
    Write-AnalyzeLog ("Total capacity of {0} - {1:N0} GB" -f $drive, ($disk.Size / 1GB))
    Write-AnalyzeLog ("Free space on {0} - {1:N0} GB / {2:N0} MB" -f $drive, ($disk.FreeSpace / 1GB), ($disk.FreeSpace / 1MB))

    $scan = {
        param($path)
        $map = Build-FolderMap -RootPath $path
        Write-AnalyzeLog
        $res = @(Get-TopFolders -RootPath $path -FolderMap $map -ThresholdBytes $folderBytes -Top $Top)
        if ($res.Count -eq 0) {
            Write-AnalyzeLog " No folders >= $FolderThresholdMB MB under $path."
        } else {
            $h = "Top $Top largest folders in $path (largest first):"
            Write-AnalyzeLog $h; Write-AnalyzeLog ('-' * $h.Length)
            Write-FolderResults -SortedResults $res
        }
        Write-AnalyzeLog
        Find-LargeFiles -Path $path -ThresholdMB $script:Config.FileThresholdMB -Top $script:Config.FileTop
        return ,$res
    }

    Write-AnalyzeTimestamp 'Scan started:'
    $current = & $scan $root
    Write-AnalyzeTimestamp 'Scan ended:'

    $history = @()
    while ($true) {
        Write-Host ' '
        if ($history.Count -gt 0) { $back = 'B up one level' } else { $back = 'B back to menu' }
        Write-Host "  Select a folder: 1-$($current.Count) drill in, 0 custom path, $back"
        $sel = (Read-Host 'Enter selection').Trim()

        if ($sel -match '^[Bb]$') {
            if ($history.Count -eq 0) { Write-Host "Report saved to: $($script:AnalyzeOutput)"; Wait-ForKey; return }
            $current = $history[-1]
            if ($history.Count -gt 1) { $history = $history[0..($history.Count - 2)] } else { $history = @() }
            Write-Host 'Previous level:'; Write-FolderResults -SortedResults $current
            continue
        }
        if ($sel -notmatch '^\d+$' -or [int]$sel -gt $current.Count) { Write-Host ' Invalid selection.'; continue }
        if ([int]$sel -eq 0) {
            $path = Read-Host 'Enter custom folder path'
            if (-not (Test-Path $path)) { Write-Host ' Path not found.'; continue }
        } else { $path = $current[[int]$sel - 1]['Path'] }

        Write-AnalyzeTimestamp 'Drill-down scan started:'
        $sub = & $scan $path
        if ($sub.Count -gt 0) { $history += ,$current; $current = $sub }
        Write-AnalyzeTimestamp 'Drill-down scan ended:'
    }
}
