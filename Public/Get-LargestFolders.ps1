function Get-LargestFolders {
    <#
    .SYNOPSIS
    Interactive drive analysis: reports largest folders AND largest files, with drill-down.
    #>
    [CmdletBinding()]
    param(
        [string]$OutputFile = (Join-Path (Get-Location).Path 'FindLargestFilesAndFolders.txt'),
        [int]$Top = 10,
        [int]$FolderThresholdMB = 1024,
        [int]$FileThresholdMB = 500,
        [string[]]$FileExtension,
        [switch]$SkipFiles
    )
    $script:AnalyzeOutput = $OutputFile
    $folderBytes = [long]$FolderThresholdMB * [long]1048576
    Clear-Host
    "Script launched: $(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss')  (Get-StorageCleanup v$(Get-StorageCleanupVersion))" | Out-File -Width 150 $OutputFile

    $drive = Select-Drive
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
        if (-not $SkipFiles) {
            Write-AnalyzeLog
            Find-LargeFiles -Path $path -ThresholdMB $FileThresholdMB -Top $Top -Extension $FileExtension
        }
        return ,$res
    }

    Write-AnalyzeTimestamp 'Scan started:'
    $current = & $scan $root
    Write-AnalyzeTimestamp 'Scan ended:'

    $history = @()
    while ($true) {
        Write-Host ' '
        $opt = "1-$($current.Count) drill in, 0 custom path"
        if ($history.Count -gt 0) { $opt += ', B back' }
        Write-Host "  Select a folder: $opt, Q quit"
        $sel = (Read-Host 'Enter selection').Trim()
        if ($sel -match '^[Qq]$') { Write-AnalyzeLog 'Exiting.'; Write-Host "Report saved to: $OutputFile"; return }
        if ($sel -match '^[Bb]$' -and $history.Count -gt 0) {
            $current = $history[-1]
            $history = if ($history.Count -gt 1) { $history[0..($history.Count - 2)] } else { @() }
            Write-Host 'Previous level:'; Write-FolderResults -SortedResults $current
            continue
        }
        if ($sel -notmatch '^\d+$' -or [int]$sel -gt $current.Count) { Write-Host ' Invalid selection.'; continue }
        if ([int]$sel -eq 0) { $path = Read-Host 'Enter custom folder path'; if (-not (Test-Path $path)) { Write-Host ' Path not found.'; continue } }
        else { $path = $current[[int]$sel - 1]['Path'] }

        Write-AnalyzeTimestamp 'Drill-down scan started:'
        $sub = & $scan $path
        if ($sub.Count -gt 0) { $history += ,$current; $current = $sub }
        Write-AnalyzeTimestamp 'Drill-down scan ended:'
    }
}
