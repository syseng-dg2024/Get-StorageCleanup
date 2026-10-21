function Get-StorageCleanup {
    <#
    .SYNOPSIS
    Interactive storage menu: analyze storage or clean storage.
    #>
    [CmdletBinding()]
    param()

    while ($true) {
        Clear-Host
        Write-Host '=============================================='
        Write-Host "  Get-StorageCleanup  v$(Get-StorageCleanupVersion)"
        Write-Host '=============================================='
        Write-Host '  1. Analyze Storage'
        Write-Host '  2. Clean Storage'
        Write-Host '  Q. Quit'
        Write-Host ' '
        $sel = (Read-Host 'Select an option').Trim()
        switch -Regex ($sel) {
            '^1$'     { Show-AnalyzeMenu }
            '^2$'     { Show-CleanMenu }
            '^[Qq]$'  { return }
            default   { Write-Host ' Invalid selection.'; Start-Sleep -Seconds 1 }
        }
    }
}
