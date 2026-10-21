function Show-AnalyzeMenu {
    while ($true) {
        Clear-Host
        Write-Host '=============================================='
        Write-Host '  Analyze Storage'
        Write-Host '=============================================='
        Write-Host '  1. Scan a drive (largest folders and files, with drill-down)'
        Write-Host '  2. Find large files in a path (.bak, .dmp, .vhdx, ...)'
        Write-Host '  B. Back'
        Write-Host ' '
        $sel = (Read-Host 'Select an option').Trim()
        switch -Regex ($sel) {
            '^1$'     { Invoke-DriveAnalysis }
            '^2$'     { Invoke-LargeFileScan; Wait-ForKey }
            '^[Bb]$'  { return }
            default   { Write-Host ' Invalid selection.'; Start-Sleep -Seconds 1 }
        }
    }
}
