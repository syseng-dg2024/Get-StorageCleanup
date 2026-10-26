function Invoke-DriveCleanup {
    <#
    .SYNOPSIS
    Performs the storage cleanup. Called by the scheduled task created from the menu (Clean Storage).
    Settings come from $script:Config in Get-StorageCleanup.psm1.
    #>
    [CmdletBinding()]
    param([switch]$RunningAsTask)

    $TaskName           = 'Start-ServerCleanup'
    $DaysToDelete       = $script:Config.DaysToDelete
    $LogFolder          = $script:Config.LogFolder
    $DismTimeoutMinutes = $script:Config.DismTimeoutMinutes
    $ReportFilesOverMB  = $script:Config.CleanupLargeFileReportMB
    $SkipDism           = $false

    if (-not (Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder | Out-Null }
    $script:CleanupLogPath = Join-Path $LogFolder "StorageCleanup_$(Get-Date -Format 'MM-dd-yyyy_hhmmtt').log"
    $script:CleanupBuffer  = @()
    $Deleted = 0; $Compressed = 0
    $Cutoff = (Get-Date).AddDays(-$DaysToDelete)

    try {
        $c0 = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $TotalGB  = [double]("{0:F2}" -f ($c0.Size / 1GB))
        $BeforeGB = [double]("{0:F2}" -f ($c0.FreeSpace / 1GB))
        $BeforePct = [double]("{0:F1}" -f (($BeforeGB / $TotalGB) * 100))

        Write-CleanupLog '======================================================'
        Write-CleanupLog "CLEANUP STARTED: $(Get-Date -Format 'MM-dd-yyyy hh:mm:ss tt')  (Get-StorageCleanup v$(Get-StorageCleanupVersion))"
        Write-CleanupLog "Days threshold: $DaysToDelete (cutoff: $($Cutoff.ToString('MM-dd-yyyy hh:mm:ss tt')))"
        Write-CleanupLog "Start Free Space: $BeforeGB GB ($BeforePct% free)"
        Write-CleanupLog '======================================================'

        # [1/9] Pending reboot
        Write-CleanupLog '[1/9] Checking for pending reboots...'
        $reasons = Get-PendingReboot
        if ($reasons.Count -gt 0) {
            foreach ($r in $reasons) { Write-CleanupLog "WARNING: Pending Reboot - $r" }
            Write-CleanupLog 'WARNING: DISM may hang with a pending reboot. Proceeding anyway.'
        } else { Write-CleanupLog 'No pending reboot detected.' }

        # [2/9] DISM
        if ($SkipDism) {
            Write-CleanupLog '[2/9] DISM skipped by parameter.'
        } else {
            Write-CleanupLog '[2/9] Starting DISM Component Cleanup...'
            $so = Join-Path $LogFolder 'dism_stdout.tmp'; $se = Join-Path $LogFolder 'dism_stderr.tmp'
            $p = Start-Process 'dism.exe' -ArgumentList '/online /Cleanup-Image /StartComponentCleanup /NoRestart' -PassThru -NoNewWindow -RedirectStandardOutput $so -RedirectStandardError $se
            $TimeoutMs = $DismTimeoutMinutes * 60000; $Beat = 30000; $el = 0
            while (-not $p.HasExited -and $el -lt $TimeoutMs) {
                Start-Sleep -Milliseconds $Beat; $el += $Beat
                Write-CleanupLog ("DISM: Still running... ({0:F1} min)" -f ($el / 60000)); Clear-CleanupLogBuffer
            }
            if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; Write-CleanupLog "ERROR: DISM killed - exceeded $DismTimeoutMinutes min timeout." }
            else { Write-CleanupLog ("DISM completed in {0:F1} min - Exit Code: {1}" -f ($el / 60000), $p.ExitCode) }
            foreach ($f in @(@($so,'DISM'),@($se,'DISM ERROR'))) {
                if (Test-Path $f[0]) {
                    foreach ($l in (Get-Content $f[0] -ErrorAction SilentlyContinue)) { if ($l.Trim()) { Write-CleanupLog "$($f[1]): $l" } }
                    Remove-Item $f[0] -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # [3/9] Stop services
        $Services = @('wuauserv','bits','cryptsvc'); $Nable = 'N-able Patch Repository Service'
        Write-CleanupLog "[3/9] Stopping services: $($Services -join ', '), $Nable"
        Stop-Service -Name $Services -Force -ErrorAction SilentlyContinue
        Stop-Service -Name $Nable -Force -ErrorAction SilentlyContinue

        # [4/9] IIS
        if (Test-Path 'C:\inetpub\logs\LogFiles\') {
            Write-CleanupLog "[4/9] Compressing IIS logs older than $DaysToDelete days..."
            $dirs = Get-ChildItem 'C:\inetpub\logs\LogFiles\' -Include *.log -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $Cutoff -and $_.Attributes -notmatch 'Compressed' } |
                Select-Object -ExpandProperty DirectoryName -Unique
            foreach ($dir in $dirs) {
                Write-CleanupLog "ACTION: Compressing $dir"
                Start-Process 'compact.exe' -ArgumentList "/c /s:`"$dir`"" -Wait -NoNewWindow
                $Compressed += (Get-ChildItem $dir -Filter *.log -ErrorAction SilentlyContinue).Count
            }
            $fr = 'C:\inetpub\logs\FailedReqLogFiles'
            if (Test-Path $fr) { Start-Process 'compact.exe' -ArgumentList "/c /s:`"$fr`"" -Wait -NoNewWindow }
            Write-CleanupLog "IIS compression complete. Directories: $(@($dirs).Count)"
        } else { Write-CleanupLog '[4/9] IIS log path not found - skipping.' }

        # [5/9] N-able cache
        $np = 'C:\Program Files (x86)\N-able Technologies\NablePatchCache'
        if (Test-Path $np) {
            $n = (Get-ChildItem $np -Recurse -File -ErrorAction SilentlyContinue).Count
            Write-CleanupLog "[5/9] Deleting $n files from N-able cache."
            Remove-Item "$np\*" -Recurse -Force -ErrorAction SilentlyContinue
            $Deleted += $n
        } else { Write-CleanupLog '[5/9] N-able Patch Cache not found - skipping.' }

        # [6/9] Temp & bloat
        $targets = @(
            'C:\Windows\Temp\*','C:\Users\*\AppData\Local\Temp\*','C:\Windows\SoftwareDistribution\Download\*',
            'C:\Windows\SoftwareDistribution\DataStore\Logs\*','C:\Windows\System32\config\systemprofile\AppData\Local\Temp\*',
            'C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\INetCache\*',
            'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*',
            'C:\ProgramData\Microsoft\Windows\WER\ReportQueue\*','C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*',
            'C:\Windows\Logs\CBS\*','C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache\*',
            'C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\*')
        Write-CleanupLog '[6/9] Purging temporary files and system bloat...'
        foreach ($t in $targets) {

            $files = Get-ChildItem $t -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $Cutoff -and $_.Name -notlike '*.log' -and $_.Attributes -notmatch 'ReparsePoint' }
            if ($files) {
                $files | Select-Object -First 5 | ForEach-Object { Write-CleanupLog "ACTION: Deleted $($_.FullName)" }
                if ($files.Count -gt 5) { Write-CleanupLog "... and $($files.Count - 5) more in $t" }
                $files | Remove-Item -Force -ErrorAction SilentlyContinue
                $Deleted += $files.Count
            }
            Write-CleanupLog "Path '$t' - $($files.Count) file(s) deleted."
        }

        # [7/9] Archives
        Write-CleanupLog '[7/9] Removing old archived logs from C:\Windows\Logs\...'
        $ac = 0
        Get-ChildItem 'C:\Windows\Logs\*' -Include *.cab,*.gz,*.zip -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $Cutoff -and $_.Name -notlike '*.log' -and $_.Attributes -notmatch 'ReparsePoint' } |
            ForEach-Object { Write-CleanupLog "ACTION: Deleted Archive $($_.FullName)"; Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue; $Deleted++; $ac++ }
        Write-CleanupLog "Archives removed: $ac"

        # [8/9] Recycle bin + minidumps
        Write-CleanupLog '[8/9] Emptying Recycle Bin...'
        try { Clear-RecycleBin -Force -ErrorAction Stop; Write-CleanupLog 'Recycle Bin emptied.' }
        catch { Write-CleanupLog "WARNING: Recycle Bin empty or inaccessible - $($_.Exception.Message)" }
        if (Test-Path 'C:\Windows\Minidump') {
            $dc = 0
            Get-ChildItem 'C:\Windows\Minidump' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $Cutoff } |
                ForEach-Object { Write-CleanupLog "ACTION: Deleted Minidump $($_.FullName)"; Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue; $Deleted++; $dc++ }
            Write-CleanupLog "Minidumps removed: $dc"
        }

        # [9/9] Restart services
        Write-CleanupLog '[9/9] Restarting services...'
        Start-Service -Name $Services -ErrorAction SilentlyContinue
        Start-Service -Name $Nable -ErrorAction SilentlyContinue

        # Optional large-file report (report only, never deletes)
        if ($ReportFilesOverMB -gt 0) {
            Write-CleanupLog "Reporting files >= $ReportFilesOverMB MB on C:\ (report only)..."
            $big = Find-LargeFiles -Path 'C:\' -ThresholdMB $ReportFilesOverMB -Top 25 -PassThru -Quiet
            foreach ($b in $big) { Write-CleanupLog ("LARGE FILE: {0,10:N0} MB  {1}  (modified {2:yyyy-MM-dd})" -f ($b.Length / 1MB), $b.FullName, $b.LastWriteTime) }
        }

        $c1 = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $AfterGB  = [double]("{0:F2}" -f ($c1.FreeSpace / 1GB))
        $AfterPct = [double]("{0:F1}" -f (($AfterGB / $TotalGB) * 100))
        $Gained   = [double]("{0:F2}" -f ($AfterGB - $BeforeGB))
        Write-CleanupLog @"

=======================================================
               CLEANUP SUMMARY (C: DRIVE)
=======================================================
  Total Disk Capacity:  $TotalGB GB
  STARTING FREE SPACE:  $BeforeGB GB ($BeforePct%)
  ENDING FREE SPACE:    $AfterGB GB ($AfterPct%)
  TOTAL SPACE GAINED:   $Gained GB
  FILES DELETED:        $Deleted
  FILES COMPRESSED:     $Compressed
  Log: $($script:CleanupLogPath)
  Completed: $(Get-Date -Format 'MM-dd-yyyy hh:mm:ss tt')
=======================================================
"@
    } catch {
        Write-CleanupLog "FATAL ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
    } finally {
        Clear-CleanupLogBuffer
        if ($RunningAsTask -and (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
    }
}
