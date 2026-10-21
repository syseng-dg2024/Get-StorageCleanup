#Requires -Version 5.1
<#
Get-StorageCleanup module loader.
Version is defined in Get-StorageCleanup.psd1 (semantic versioning, see CHANGELOG.md).
Public\  = exported commands (Get-StorageCleanup menu, Invoke-DriveCleanup used by the scheduled task).
Private\ = internal helpers (not exported).
DISCLAIMER: Partly AI-assisted. Review and test in non-production before use on live systems.
#>

# ---------------------------------------------------------------
# Settings - edit here
# ---------------------------------------------------------------
$script:Config = @{
    LogFolder                = (Join-Path $PSScriptRoot 'Logs')   # cleanup logs and analysis reports
    DaysToDelete             = 7           # cleanup: delete files older than this
    DismTimeoutMinutes       = 10          # cleanup: kill DISM after this long
    CleanupLargeFileReportMB = 0           # cleanup: >0 adds a report-only list of files this big (0 = off)
    Top                      = 10          # analysis: top N folders per level
    FolderThresholdMB        = 1024        # analysis: minimum folder size to list
    FileThresholdMB          = 500         # analysis: minimum file size to list (.bak etc.)
    FileTop                  = 25          # analysis: top N files per level
}

# Create log folder if it doesn't exist
if (-not (Test-Path $script:Config.LogFolder)) { New-Item -ItemType Directory -Path $script:Config.LogFolder -Force | Out-Null }

# Folders skipped during analysis (junctions / pseudo-folders)
$script:SkipFolders = @('documents and settings','application data','local settings','my documents','system volume information','$recycle.bin')

$Private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter *.ps1 -ErrorAction SilentlyContinue)
$Public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter *.ps1 -ErrorAction SilentlyContinue)

foreach ($file in @($Private + $Public)) {
    try { . $file.FullName }
    catch { Write-Error "Failed to load $($file.FullName): $($_.Exception.Message)" }
}

Export-ModuleMember -Function $Public.BaseName
