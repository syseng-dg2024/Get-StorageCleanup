function Get-StorageCleanup {
    <#
    .SYNOPSIS
    Entry point for the Get-StorageCleanup module. Shows a menu, or runs an action directly.
    .PARAMETER Action
    Menu (default), Analyze, LargeFiles, Cleanup, Version.
    .PARAMETER Parameters
    Hashtable passed to the underlying command, e.g.
      Get-StorageCleanup -Action Cleanup -Parameters @{ DaysToDelete = 7; AsScheduledTask = $true }
      Get-StorageCleanup -Action LargeFiles -Parameters @{ Path = 'D:\'; ThresholdMB = 1000; Extension = '.bak' }
      Get-StorageCleanup -Action Analyze -Parameters @{ FileThresholdMB = 500 }
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Menu','Analyze','LargeFiles','Cleanup','Version')]
        [string]$Action = 'Menu',
        [hashtable]$Parameters = @{}
    )

    if ($Action -eq 'Menu') {
        Write-Host ' '
        Write-Host "Get-StorageCleanup v$(Get-StorageCleanupVersion)"
        Write-Host '  [1] Analyze a drive (largest folders + files, drill-down)'
        Write-Host '  [2] Find large files in a path (.bak, .dmp, .vhdx, ...)'
        Write-Host '  [3] Run server cleanup (background scheduled task, 7 days)'
        Write-Host '  [Q] Quit'
        $sel = (Read-Host 'Enter selection').Trim()
        switch -Regex ($sel) {
            '^1$' { $Action = 'Analyze' }
            '^2$' {
                $Action = 'LargeFiles'
                $p = Read-Host 'Path to scan (default C:\)'
                if ($p) { $Parameters['Path'] = $p }
                $t = Read-Host 'Minimum size in MB (default 500)'
                if ($t -match '^\d+$') { $Parameters['ThresholdMB'] = [int]$t }
                $x = Read-Host 'Extensions, comma separated (blank = all, e.g. .bak,.dmp)'
                if ($x) { $Parameters['Extension'] = @($x -split ',' | ForEach-Object { $_.Trim() }) }
            }
            '^3$' {
                $Action = 'Cleanup'
                $c = Read-Host 'This deletes files. Type YES to continue'
                if ($c -cne 'YES') { Write-Host 'Cancelled.'; return }
                $Parameters['AsScheduledTask'] = $true
            }
            default { return }
        }
    }

    switch ($Action) {
        'Analyze'    { Get-LargestFolders @Parameters }
        'LargeFiles' { Find-LargeFiles @Parameters }
        'Cleanup'    { Start-ServerCleanup @Parameters }
        'Version'    { Get-StorageCleanupVersion }
    }
}
