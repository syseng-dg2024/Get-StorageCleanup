function Start-AnalyzeReport {
    $folder = $script:Config.LogFolder
    if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    $script:AnalyzeOutput = Join-Path $folder "StorageAnalysis_$(Get-Date -Format 'MM-dd-yyyy_hhmmtt').txt"
    "Report started: $(Get-Date -Format 'MM-dd-yyyy hh:mm:ss tt')  (Get-StorageCleanup v$(Get-StorageCleanupVersion))" | Out-File -Width 150 $script:AnalyzeOutput
}
