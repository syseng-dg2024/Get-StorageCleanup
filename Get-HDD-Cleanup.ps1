param(
    [switch]$RunTask
)

# ---------------------------------------------------------------
# Script-level variables (must be at top for self-delete to work)
# ---------------------------------------------------------------
$ScriptPath  = $MyInvocation.MyCommand.Path
$TaskName    = "Start-ServerCleanup"
$LogFolder   = "C:\Temp"
$LogFile     = "ServerCleanup_$(Get-Date -Format 'yyyy-MM-dd_HHmm').log"
$FullLogPath = Join-Path $LogFolder $LogFile


# ---------------------------------------------------------------
# MODE 1: Initial run - register and launch the scheduled task
# ---------------------------------------------------------------
if (-not $RunTask) {

    $null = net session 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: This script must be run from an Elevated (Admin) PowerShell prompt." -ForegroundColor Red
        exit 1
    }

    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Write-Host "Existing task '$TaskName' found. Removing..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $Action = New-ScheduledTaskAction -Execute "powershell.exe" `
                  -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -RunTask"

    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10)

    $Settings = New-ScheduledTaskSettingsSet `
                    -AllowStartIfOnBatteries `
                    -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit (New-TimeSpan -Hours 4)

    $Principal = New-ScheduledTaskPrincipal `
                     -UserId    "SYSTEM" `
                     -LogonType ServiceAccount `
                     -RunLevel  Highest

    Register-ScheduledTask -TaskName  $TaskName `
                           -Action    $Action `
                           -Trigger   $Trigger `
                           -Settings  $Settings `
                           -Principal $Principal `
                           -Force | Out-Null

    Write-Host "Scheduled task '$TaskName' registered. Cleanup will begin in ~10 seconds." -ForegroundColor Cyan
    Write-Host "Monitor progress with: Get-Content '$FullLogPath' -Wait" -ForegroundColor Green
    exit 0
}


# ---------------------------------------------------------------
# MODE 2: Running inside the scheduled task as SYSTEM
# ---------------------------------------------------------------

if (-not (Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder | Out-Null
}


# ---------------------------------------------------------------
# Pending Reboot Detection
# ---------------------------------------------------------------
Function Get-PendingReboot {
    $Reasons = @()

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $Reasons += "CBS/Component Servicing reboot pending"
    }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $Reasons += "Windows Update reboot required"
    }

    $PFRO = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
                              -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($PFRO) { $Reasons += "Pending file rename operations exist" }

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData") {
        $Reasons += "SCCM reboot pending"
    }

    return $Reasons
}


# ---------------------------------------------------------------
# Main Cleanup Function
# ---------------------------------------------------------------
Function Start-ServerCleanup {
    [CmdletBinding(SupportsShouldProcess=$True)]
    param(
        [int]$DaysToDelete = 1
    )

    # --- Buffered log writer (CLM-safe: pure cmdlets only) ---
    $LogBuffer = @()

    Function Write-Log {
        param($Message)
        $line = "$(Get-Date -Format 'HH:mm:ss') - $Message"
        $script:LogBuffer += $line
        if ($script:LogBuffer.Count -ge 50) {
            $script:LogBuffer | Out-File -FilePath $FullLogPath -Append -Encoding UTF8
            $script:LogBuffer = @()
        }
    }

    Function Flush-Log {
        if ($script:LogBuffer.Count -gt 0) {
            $script:LogBuffer | Out-File -FilePath $FullLogPath -Append -Encoding UTF8
            $script:LogBuffer = @()
        }
    }

    $DeletedCount    = 0
    $CompressedCount = 0
    $Cutoff          = (Get-Date).AddDays(-$DaysToDelete)

    try {

        # 1. Capture Initial State
        # --- CLM-safe rounding: -f format operator instead of [math]::Round() ---
        $DriveC_Start  = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $TotalSizeGB   = [double]("{0:F2}" -f ($DriveC_Start.Size      / 1GB))
        $BeforeFreeGB  = [double]("{0:F2}" -f ($DriveC_Start.FreeSpace / 1GB))
        $BeforePercent = [double]("{0:F1}" -f (($BeforeFreeGB / $TotalSizeGB) * 100))

        Write-Log "======================================================"
        Write-Log "CLEANUP STARTED: $(Get-Date)"
        Write-Log "Days to Delete threshold: $DaysToDelete days (cutoff: $Cutoff)"
        Write-Log "Start Free Space: $BeforeFreeGB GB ($BeforePercent% free)"
        Write-Log "======================================================"


        # 2. Pending Reboot Check
        Write-Log "[1/9] Checking for pending reboots..."
        $RebootReasons = Get-PendingReboot
        if ($RebootReasons.Count -gt 0) {
            foreach ($r in $RebootReasons) {
                Write-Log "WARNING: Pending Reboot Detected - $r"
            }
            Write-Log "WARNING: DISM may hang or behave unexpectedly with a pending reboot. Proceeding anyway."
        } else {
            Write-Log "Pending Reboot Check: None detected. Safe to run DISM."
        }


        # 3. DISM Cleanup - heartbeat + timeout
        Write-Log "[2/9] Starting DISM Component Cleanup..."

        $DismStdOut = Join-Path $LogFolder "dism_stdout.tmp"
        $DismStdErr = Join-Path $LogFolder "dism_stderr.tmp"

        $DismProc = Start-Process "dism.exe" `
            -ArgumentList "/online /Cleanup-Image /StartComponentCleanup /NoRestart" `
            -PassThru -NoNewWindow `
            -RedirectStandardOutput $DismStdOut `
            -RedirectStandardError  $DismStdErr

        $TimeoutMs   = 600000
        $HeartbeatMs = 30000
        $Elapsed     = 0

        while (-not $DismProc.HasExited -and $Elapsed -lt $TimeoutMs) {
            Start-Sleep -Milliseconds $HeartbeatMs
            $Elapsed += $HeartbeatMs
            $ElapsedMin = [double]("{0:F1}" -f ($Elapsed / 60000))
            Write-Log "DISM: Still running... ($ElapsedMin min elapsed)"
            Flush-Log
        }

        if (-not $DismProc.HasExited) {
            Stop-Process -Id $DismProc.Id -Force
            $TimeoutMin = [double]("{0:F0}" -f ($TimeoutMs / 60000))
            Write-Log "ERROR: DISM killed - exceeded $TimeoutMin minute timeout."
        } else {
            $ElapsedMin = [double]("{0:F1}" -f ($Elapsed / 60000))
            Write-Log "DISM completed in $ElapsedMin min - Exit Code: $($DismProc.ExitCode)"
        }

        if (Test-Path $DismStdOut) {
            $DismOutput = Get-Content $DismStdOut -ErrorAction SilentlyContinue
            if ($DismOutput) {
                Write-Log "--- DISM OUTPUT ---"
                foreach ($line in $DismOutput) { if ($line.Trim()) { Write-Log "DISM: $line" } }
            }
            Remove-Item $DismStdOut -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path $DismStdErr) {
            $DismErrors = Get-Content $DismStdErr -ErrorAction SilentlyContinue
            if ($DismErrors) {
                Write-Log "--- DISM ERRORS ---"
                foreach ($line in $DismErrors) { if ($line.Trim()) { Write-Log "DISM ERROR: $line" } }
            }
            Remove-Item $DismStdErr -Force -ErrorAction SilentlyContinue
        }


        # 4. Stop Services
        $Services         = @("wuauserv", "bits", "cryptsvc")
        $NableServiceName = "N-able Patch Repository Service"
        Write-Log "[3/9] Stopping services: $($Services -join ', '), $NableServiceName"
        Stop-Service -Name $Services         -Force -ErrorAction SilentlyContinue
        Stop-Service -Name $NableServiceName -Force -ErrorAction SilentlyContinue
        Write-Log "Services stopped."


        # 5. IIS Log Compression
        if (Test-Path "C:\inetpub\logs\LogFiles\") {
            Write-Log "[4/9] Compressing IIS logs older than $DaysToDelete days..."

            $DirsToCompress = Get-ChildItem "C:\inetpub\logs\LogFiles\" -Include *.log -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $Cutoff -and $_.Attributes -notmatch "Compressed" } |
                Select-Object -ExpandProperty DirectoryName -Unique

            foreach ($Dir in $DirsToCompress) {
                Write-Log "ACTION: Compressing directory $Dir"
                Start-Process "compact.exe" -ArgumentList "/c /s:`"$Dir`"" -Wait -NoNewWindow
                $CompressedCount += (Get-ChildItem $Dir -Filter *.log -ErrorAction SilentlyContinue).Count
            }

            $FailedReqPath = "C:\inetpub\logs\FailedReqLogFiles"
            if (Test-Path $FailedReqPath) {
                Write-Log "ACTION: Compressing IIS Failed Request logs at $FailedReqPath"
                Start-Process "compact.exe" -ArgumentList "/c /s:`"$FailedReqPath`"" -Wait -NoNewWindow
            }

            Write-Log "IIS compression complete. Directories processed: $($DirsToCompress.Count)"
        } else {
            Write-Log "[4/9] IIS log path not found - skipping."
        }


        # 6. N-able Patch Cache
        $NablePath = "C:\Program Files (x86)\N-able Technologies\NablePatchCache"
        if (Test-Path $NablePath) {
            Write-Log "[5/9] Cleaning N-able Patch Cache at $NablePath..."
            $NableCount = (Get-ChildItem $NablePath -Recurse -File -ErrorAction SilentlyContinue).Count
            Write-Log "ACTION: Bulk deleting $NableCount files from N-able cache."
            Remove-Item "$NablePath\*" -Recurse -Force -ErrorAction SilentlyContinue
            $DeletedCount += $NableCount
            Write-Log "N-able cache cleanup complete."
        } else {
            Write-Log "[5/9] N-able Patch Cache path not found - skipping."
        }


        # 7. Temp & System Bloat
        $TargetPaths = @(
            "C:\Windows\Temp\*",
            "C:\Users\*\AppData\Local\Temp\*",
            "C:\Windows\SoftwareDistribution\Download\*",
            "C:\Windows\SoftwareDistribution\DataStore\Logs\*",
            "C:\Windows\System32\config\systemprofile\AppData\Local\Temp\*",
            "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\INetCache\*",
            "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*",
            "C:\ProgramData\Microsoft\Windows\WER\ReportQueue\*",
            "C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*",
            "C:\Windows\Logs\CBS\*",
            "C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache\*",
            "C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\*"
        )

        Write-Log "[6/9] Purging temporary files and system bloat..."
        foreach ($Path in $TargetPaths) {
            $PathCount = 0
            Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $Cutoff -and $_.Name -notlike "*.log" } |
                ForEach-Object {
                    Write-Log "ACTION: Deleted $($_.FullName)"
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    $DeletedCount++
                    $PathCount++
                }
            Write-Log "Path '$Path' - $PathCount file(s) deleted."
        }


        # 8. Archive / Cab Cleanup
        Write-Log "[7/9] Removing old archived logs from C:\Windows\Logs\..."
        $ArchiveCount = 0
        Get-ChildItem "C:\Windows\Logs\*" -Include *.cab, *.gz, *.zip -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $Cutoff } |
            ForEach-Object {
                Write-Log "ACTION: Deleted Archive $($_.FullName)"
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                $DeletedCount++
                $ArchiveCount++
            }
        Write-Log "Archives removed: $ArchiveCount"


        # 9. Recycle Bin
        Write-Log "[8/9] Emptying Recycle Bin..."
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Log "Recycle Bin emptied."
        } catch {
            Write-Log "WARNING: Recycle Bin empty or inaccessible - $($_.Exception.Message)"
        }


        # 10. Old Minidumps
        $MiniDumpPath = "C:\Windows\Minidump"
        if (Test-Path $MiniDumpPath) {
            Write-Log "Checking for old minidumps in $MiniDumpPath..."
            $DumpCount = 0
            Get-ChildItem $MiniDumpPath -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $Cutoff } |
                ForEach-Object {
                    Write-Log "ACTION: Deleted Minidump $($_.FullName)"
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    $DeletedCount++
                    $DumpCount++
                }
            Write-Log "Minidumps removed: $DumpCount"
        }


        # 11. Restart Services
        Write-Log "[9/9] Restarting services..."
        Start-Service -Name $Services         -ErrorAction SilentlyContinue
        Start-Service -Name $NableServiceName -ErrorAction SilentlyContinue
        Write-Log "Services restarted."


        # 12. Final Summary — inside try so all variables are guaranteed populated
        $DriveC_End   = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $AfterFreeGB  = [double]("{0:F2}" -f ($DriveC_End.FreeSpace / 1GB))
        $AfterPercent = [double]("{0:F1}" -f (($AfterFreeGB / $TotalSizeGB) * 100))
        $GainedGB     = [double]("{0:F2}" -f ($AfterFreeGB - $BeforeFreeGB))

        $Summary = @"
=======================================================
               CLEANUP SUMMARY (C: DRIVE)
=======================================================
  Total Disk Capacity:  $TotalSizeGB GB
-------------------------------------------------------
  STARTING FREE SPACE:  $BeforeFreeGB GB ($BeforePercent%)
  ENDING FREE SPACE:    $AfterFreeGB GB ($AfterPercent%)
-------------------------------------------------------
  TOTAL SPACE GAINED:   $GainedGB GB
-------------------------------------------------------
  FILES DELETED:        $DeletedCount
  FILES COMPRESSED:     $CompressedCount
=======================================================
  Log: $FullLogPath
  Completed: $(Get-Date)
=======================================================
"@
        Write-Log $Summary

    } catch {
        Write-Log "FATAL ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
    } finally {
        Flush-Log
    }
}

# Run it
Start-ServerCleanup -DaysToDelete 7


# ---------------------------------------------------------------
# CLEANUP: Remove scheduled task, then self-delete the .ps1
# ---------------------------------------------------------------
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Start-Process powershell.exe -ArgumentList @(
    "-NonInteractive",
    "-NoProfile",
    "-Command",
    "Start-Sleep -Seconds 5; Remove-Item -LiteralPath '$ScriptPath' -Force"
) -WindowStyle Hidden