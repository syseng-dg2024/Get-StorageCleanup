#Requires -Version 5.1
<#
Get-StorageCleanup module loader.
Version is defined in Get-StorageCleanup.psd1 (semantic versioning, see CHANGELOG.md).
Public\  = exported commands.  Private\ = internal helpers (not exported).
DISCLAIMER: Partly AI-assisted. Review and test in non-production before use on live systems.
#>

# Folders skipped during analysis (junctions / pseudo-folders)
$script:SkipFolders = @('documents and settings','application data','local settings','my documents','system volume information','$recycle.bin')

$Private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter *.ps1 -ErrorAction SilentlyContinue)
$Public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter *.ps1 -ErrorAction SilentlyContinue)

foreach ($file in @($Private + $Public)) {
    try { . $file.FullName }
    catch { Write-Error "Failed to load $($file.FullName): $($_.Exception.Message)" }
}

Export-ModuleMember -Function $Public.BaseName
