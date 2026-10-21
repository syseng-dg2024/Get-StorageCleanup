function Invoke-LargeFileScan {
    Write-Host ' '
    $path = (Read-Host 'Path to scan (Enter for C:\, B to go back)').Trim()
    if ($path -match '^[Bb]$') { return }
    if (-not $path) { $path = 'C:\' }
    if (-not (Test-Path $path)) { Write-Host " Path not found: $path"; return }

    $def = $script:Config.FileThresholdMB
    $mb = (Read-Host "Minimum file size in MB (Enter for $def, B to go back)").Trim()
    if ($mb -match '^[Bb]$') { return }
    if ($mb -match '^\d+$') { $threshold = [int]$mb } else { $threshold = $def }

    $x = (Read-Host 'Extensions, comma separated, e.g. .bak,.dmp (Enter for all)').Trim()
    $ext = @()
    if ($x) { $ext = @($x -split ',' | ForEach-Object { $_.Trim() }) }

    Start-AnalyzeReport
    Write-AnalyzeTimestamp 'Large file scan started:'
    Find-LargeFiles -Path $path -ThresholdMB $threshold -Top $script:Config.FileTop -Extension $ext
    Write-AnalyzeTimestamp 'Large file scan ended:'
    Write-Host "Report saved to: $($script:AnalyzeOutput)"
}
