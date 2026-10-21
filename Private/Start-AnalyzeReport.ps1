function Start-AnalyzeReport {
    $folder = $script:Config.LogFolder
    if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    $script:AnalyzeOutput = Join-Path $folder "StorageAnalysis_$(Get-Date -Format 'yyyy-MM-dd_HHmm').txt"
    "Report started: $(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss')  (Get-StorageCleanup v$(Get-StorageCleanupVersion))" | Out-File -Width 150 $script:AnalyzeOutput
}
