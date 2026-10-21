######################################################################
#
# This script finds large folders on a drive using a single-pass
# directory scan. One cmd.exe dir /s call reads the entire drive,
# building a complete folder-size map in memory. No per-folder process
# spawning - results are extracted entirely from the in-memory map.
#
# Results are written to both the console and a formatted text file.
# A custom folder scan is also available at the end.
#
# Original Author: Rob Willis 6/15/2016
#
# Updated by Claude AI (Anthropic) - claude.ai
# Edited and reviewed by Dave G (NOC Engineer)
#
# !! DISCLAIMER !!
# This script was modified with the assistance of Claude AI (Anthropic).
# AI-generated code may contain errors or unexpected behavior.
# This script has been reviewed by Dave G (NOC Engineer), however you
# are strongly advised to review, test, and validate this script
# thoroughly in a safe/non-production environment before deploying
# or running against any live systems. The authors accept no
# responsibility for unintended outcomes resulting from the use
# of this script.
#
######################################################################

# Modify these variables as needed

# Output file location and name
$findFilesFoldersOutput = "$PSScriptroot\FindLargestFilesAndFolders.txt"
# How many top results to show in the final ranked list
$foldersLimit = 10
# Minimum folder size in MB to include in results
# Default: 1024MB (1GB)
$drillThresholdMB = 1024
# Maximum folder depth to include in results
# Default: 6 levels deep (e.g. C:\a\b\c\d\e\f)
$maxDepth = 6

###################################
# Do not edit below!
###################################
$outputWidth = 150
# Convert threshold to bytes - explicit [long] to prevent int32 overflow
$script:drillThresholdBytes = [long]$drillThresholdMB * [long]1048576
# The full folder size map built from the single dir /s parse
# Key = folder path (lowercase), Value = total bytes [long]
$script:folderMap = @{}

###################################
# Known folders to skip entirely
# These are Windows junction points, symlinks, or pseudo-folders that
# either loop back to other locations or are not real directories:
#   - "Documents and Settings" -> junction to C:\Users (legacy compat)
#   - "Application Data"       -> junction to C:\Users\*\AppData\Roaming
#   - "Local Settings"         -> junction to C:\Users\*\AppData\Local
#   - "My Documents"           -> junction to C:\Users\*\Documents
#   - "System Volume Information" -> system restore / VSS data, inaccessible
#   - "$Recycle.Bin"           -> recycle bin, usually inaccessible
###################################
$skipFolders = @(
    "documents and settings",
    "application data",
    "local settings",
    "my documents",
    "system volume information",
    "`$recycle.bin"
)

###################################
# Helper: Write a line to both console and log file
###################################
Function Write-Log {
    param([string]$Message = " ")
    Write-Host $Message
    $Message | Out-File -Width $outputWidth $findFilesFoldersOutput -Append
}

###################################
# Helper: Log a timestamp line
###################################
Function Write-Timestamp {
    param([string]$Label)
    $ts = Get-Date -Format "dd-MMM-yyyy HH:mm:ss"
    Write-Log
    Write-Log "*** $Label $ts ***"
    Write-Log
}

###################################
# Helper: Print a sorted result list to console + log
###################################
Function Write-FolderResults {
    param(
        [object[]]$SortedResults,
        [switch]$Ranked
    )
    $rank = 1
    foreach ($item in $SortedResults) {
        $sizeMB = "{0:N0}" -f ($item['Bytes'] / 1MB)
        $sizeGB = "{0:N2}" -f ($item['Bytes'] / 1GB)
        if ($Ranked) {
            $line = "  [{0,2}]  {1,10} MB  ({2} GB)  {3}" -f $rank, $sizeMB, $sizeGB, $item['Path']
        } else {
            $line = "  {0,10} MB  ({1} GB)  {2}" -f $sizeMB, $sizeGB, $item['Path']
        }
        Write-Log $line
        $rank++
    }
}

###################################
# Helper: Check if a path contains a skipped folder segment
###################################
Function Should-Skip {
    param([string]$FolderPath)
    $lower = $FolderPath.ToLower()
    foreach ($skip in $skipFolders) {
        if ($lower -match [regex]::Escape("\$skip")) { return $true }
        if ($lower -match [regex]::Escape("\$skip\")) { return $true }
    }
    return $false
}

###################################
# Drive Selection
# Lists all available drives numbered and prompts the user to pick by number
###################################
Function Select-Drive {
    Write-Host " "
    Write-Host "Available drives:"
    Write-Host " "

    $drives  = Get-WmiObject Win32_LogicalDisk | Select-Object DeviceID, DriveType, VolumeName, Size, FreeSpace
    $driveList = @()
    $index   = 1

    foreach ($drive in $drives) {
        $type = switch ($drive.DriveType) {
            2 { "Removable" }
            3 { "Local Disk" }
            4 { "Network"   }
            5 { "CD/DVD"    }
            default { "Unknown" }
        }
        if ($drive.Size) {
            $totalGB = "{0:N0}" -f ($drive.Size / 1GB)
            $freeGB  = "{0:N0}" -f ($drive.FreeSpace / 1GB)
            $label   = if ($drive.VolumeName) { $drive.VolumeName } else { "No Label" }
            Write-Host ("  [{0}]  {1}  [{2}]  {3}  -  {4} GB total, {5} GB free" -f $index, $drive.DeviceID, $type, $label, $totalGB, $freeGB)
        } else {
            Write-Host ("  [{0}]  {1}  [{2}]  (no media)" -f $index, $drive.DeviceID, $type)
        }
        $driveList += $drive.DeviceID
        $index++
    }

    Write-Host " "
    $selection = Read-Host "Enter number to select drive"

    if ($selection.Trim() -notmatch '^\d+$') {
        Write-Host " Invalid selection - please enter a number between 1 and $($driveList.Count)."
        return Select-Drive
    }

    $selNum = [int]$selection.Trim()

    if ($selNum -lt 1 -or $selNum -gt $driveList.Count) {
        Write-Host " Invalid selection - please enter a number between 1 and $($driveList.Count)."
        return Select-Drive
    }

    return $driveList[$selNum - 1]
}

###################################
# Folder Selection
# Shows a compact prompt - the list was already printed above by Write-FolderResults
###################################
Function Select-Folder {
    param(
        [object[]]$TopFolders,
        [switch]$CanGoBack
    )

    Write-Host " "
    $options = "1-$($TopFolders.Count) to drill in, 0 for custom path"
    if ($CanGoBack) { $options = $options + ", B to go back" }
    $options = $options + ", Q to quit"
    Write-Host "  Select a folder: $options"
    Write-Host " "

    $selection = (Read-Host "Enter selection").Trim()

    if ($selection -eq 'Q' -or $selection -eq 'q') {
        Write-Log "Exiting."
        exit
    }

    if (($selection -eq 'B' -or $selection -eq 'b') -and $CanGoBack) {
        return "BACK"
    }

    if ($selection -notmatch '^\d+$') {
        Write-Host " Invalid selection. Please try again."
        return Select-Folder -TopFolders $TopFolders -CanGoBack:$CanGoBack
    }

    $selNum = [int]$selection

    if ($selNum -lt 0 -or $selNum -gt $TopFolders.Count) {
        Write-Host " Invalid selection. Please try again."
        return Select-Folder -TopFolders $TopFolders -CanGoBack:$CanGoBack
    }

    if ($selNum -eq 0) {
        $customPath = Read-Host "Enter custom folder path"
        return "CUSTOM:$customPath"
    }

    return $TopFolders[$selNum - 1]['Path']
}

###################################
# Single-Pass Folder Size Builder using robocopy
#
# Calls robocopy once per top-level subfolder (not recursively per folder)
# capturing output into a variable which we know works under CLM.
# Robocopy /BYTES /NJH /NJS /NFL output contains per-directory byte totals
# which we parse to build the folder size map.
###################################
Function Build-FolderMap {
    param([string]$RootPath)

    Write-Host "  Getting top-level folders under $RootPath..."

    # Get immediate children only to split work into manageable robocopy calls
    $topFolders = Get-ChildItem -Path $RootPath -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.PSIsContainer } |
                  Select-Object -ExpandProperty FullName

    $folderMap   = @{}
    $totalJobs   = $topFolders.Count
    $jobsDone    = 0

    Write-Log "  Found $totalJobs top-level folders. Measuring each..."
    Write-Log

    foreach ($folder in $topFolders) {
        $jobsDone++

        # Progress bar based on top-level folders completed
        $pct    = [int](($jobsDone / $totalJobs) * 100)
        $filled = [int]($pct / 5)
        $empty  = 20 - $filled
        $bar    = "[" + ("#" * $filled) + ("-" * $empty) + "]"

        $displayPath = $folder
        if ($displayPath.Length -gt 40) {
            $displayPath = "..." + $displayPath.Substring($displayPath.Length - 37)
        }
        $progressLine = "  $bar $pct%  ($jobsDone/$totalJobs)  $displayPath"
        # Pad to 100 chars to fully overwrite any longer previous line
        $progressLine = $progressLine.PadRight(100)
        Write-Host ("`r" + $progressLine) -NoNewline

        # Skip known junctions/pseudo-folders
        $folderName = Split-Path $folder -Leaf
        $skip = $false
        foreach ($s in $skipFolders) {
            if ($folderName.ToLower() -eq $s) { $skip = $true; break }
        }
        $attribs = (Get-Item -Path $folder -Force -ErrorAction SilentlyContinue).Attributes
        if ($attribs -match "ReparsePoint") { $skip = $true }
        if ($skip) { continue }

        # One robocopy call per top-level folder - captures entire subtree bytes
        # /L = list only (no copy)  /S = recurse  /NJH /NJS /NFL /NDL = suppress output
        # /BYTES = report in bytes  /XJ = skip junctions within subtree
        # cmd.exe /c dir /s is used here - robocopy stdout capture is blocked by
        # WDAC CLM on this system. cmd.exe capture works reliably.
        # dir /s prints a summary line per subdirectory:
        #   "   X File(s)   Y bytes"
        # The LAST such line is the grand total for the entire tree.
        $cmdArgs = "/c dir /s /a `"$folder`""
        $dirOut  = & cmd.exe $cmdArgs 2>$null

        $totalBytes = [long]0
        foreach ($line in $dirOut) {
            # Match lines like "      19 File(s)  1,310,994,226 bytes"
            # Keep overwriting so last match = grand total
            if ($line -match "File\(s\)\s+([\d,]+)\s+bytes") {
                $totalBytes = [long]($Matches[1] -replace ',', '')
            }
        }

        $folderMap[$folder] = $totalBytes
    }

    Write-Host ("`r" + (" " * 100))
    Write-Host "  Scan complete. $($folderMap.Count) folders measured."
    Write-Log   "  $($folderMap.Count) folders measured."

    return $folderMap
}

###################################
# Extract top N folders from the map above the threshold
###################################
Function Get-TopFolders {
    param(
        [string]$RootPath,
        [hashtable]$FolderMap
    )

    $results   = @()
    $rootLower = $RootPath.ToLower().TrimEnd('\')

    foreach ($path in $FolderMap.Keys) {
        if (-not $path.ToLower().StartsWith($rootLower)) { continue }
        if ($path.ToLower() -eq $rootLower) { continue }

        $bytes = $FolderMap[$path]
        if ($bytes -ge $script:drillThresholdBytes) {
            $results += @{
                Path  = $path
                Bytes = $bytes
            }
        }
    }

    return $results | Sort-Object { $_['Bytes'] } -Descending | Select-Object -First $foldersLimit
}

###################################
# Scan Drive for capacity and free space
###################################
Function driveScan {
    $disk   = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$diskDrive'" | Select-Object Size, FreeSpace
    $total  = "{0:N0}" -f ($disk.Size / 1GB)     + " GB"
    $free   = "{0:N0}" -f ($disk.FreeSpace / 1GB) + " GB"
    $freeMB = "{0:N0}" -f ($disk.FreeSpace / 1MB) + " MB"

    Write-Log
    Write-Log "Total capacity of $diskDrive - $total"
    Write-Log "Total space free on $diskDrive - $free / $freeMB"
    Write-Log
}

###################################
# Main Scan - builds the folder map once, then extracts results
###################################
Function largestFolderScan {
    Write-Timestamp "Scan started:"
    Write-Log "Scanning $rootLocation for the $foldersLimit largest folders..."
    Write-Log "  Threshold : >= $drillThresholdMB MB"
    Write-Log "  Max depth : $maxDepth levels"
    Write-Log

    # Build the complete folder size map from one dir /s call
    $script:folderMap = Build-FolderMap -RootPath $rootLocation

    Write-Log "  Folder map built. $($script:folderMap.Count) paths indexed."
    Write-Log

    $script:topFolders = Get-TopFolders -RootPath $rootLocation -FolderMap $script:folderMap

    if ($script:topFolders.Count -eq 0) {
        Write-Log " No folders found above the $drillThresholdMB MB threshold."
        Write-Log " Try lowering `$drillThresholdMB in the configuration section."
    } else {
        $header = "Top $foldersLimit largest folders on $rootLocation (largest first):"
        Write-Log $header
        Write-Log ("-" * $header.Length)
        Write-FolderResults -SortedResults $script:topFolders -Ranked
    }

    Write-Log
    Write-Timestamp "Scan ended:"
}

###################################
# Custom Folder Scan
# Maintains a history stack so the user can navigate back to previous levels
###################################
Function customScan {
    if (-not $script:topFolders -or $script:topFolders.Count -eq 0) {
        Write-Log " No results available to select from. Exiting."
        return
    }

    # History stack - each entry is the result set from a previous level
    $history = @()
    $currentResults = $script:topFolders

    while ($true) {
        $canGoBack = $history.Count -gt 0
        $selection = Select-Folder -TopFolders $currentResults -CanGoBack:$canGoBack

        # Handle back navigation - pop previous result set from history
        if ($selection -eq "BACK") {
            $currentResults = $history[-1]
            $newHistory = @()
            for ($i = 0; $i -lt ($history.Count - 1); $i++) {
                $newHistory += ,$history[$i]
            }
            $history = $newHistory
            # Re-display the previous level's results above the prompt
            Write-Host " "
            $header = "Previous level results:"
            Write-Host $header
            Write-Host ("-" * $header.Length)
            Write-FolderResults -SortedResults $currentResults -Ranked
            continue
        }

        # Handle custom path prefix
        $scanPath = $selection
        if ($selection -match '^CUSTOM:(.+)$') {
            $scanPath = $Matches[1]
        }

        Write-Timestamp "Drill-down scan started:"
        Write-Log "Scanning $scanPath..."
        Write-Log

        $subMap = Build-FolderMap -RootPath $scanPath

        Write-Log "  Folder map built. $($subMap.Count) paths indexed."
        Write-Log

        $subResults = Get-TopFolders -RootPath $scanPath -FolderMap $subMap

        if ($subResults.Count -eq 0) {
            Write-Log " No subfolders found above the $drillThresholdMB MB threshold under $scanPath."
            Write-Log " Try lowering `$drillThresholdMB or selecting a different folder."
            # Don't push to history - stay at current level
        } else {
            # Push current level onto history stack before going deeper
            $history += ,$currentResults
            $currentResults = $subResults

            $header = "Top $foldersLimit largest folders in $scanPath (largest first):"
            Write-Log $header
            Write-Log ("-" * $header.Length)
            Write-FolderResults -SortedResults $currentResults -Ranked
        }

        Write-Log
        Write-Timestamp "Drill-down scan ended:"
        Write-Log "Scan saved to: $findFilesFoldersOutput..."
        Write-Log
    }
}

# Pause helper
Function Pause {
    Write-Host -NoNewLine "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Clear the screen
Clear-Host

# Write script launch timestamp to log
$scriptStart = Get-Date -Format "dd-MMM-yyyy HH:mm:ss"
"Script launched: $scriptStart" | Out-File -Width $outputWidth $findFilesFoldersOutput

# Prompt user to select a drive
$diskDrive    = Select-Drive
$rootLocation = "$diskDrive\"

Write-Host " "
Write-Host "Selected: $diskDrive"
Write-Host " "

# Execute the functions
# Comment out any of the below to prevent them from running
driveScan
largestFolderScan
customScan