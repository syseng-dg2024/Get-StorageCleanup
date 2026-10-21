function Write-AnalyzeTimestamp {
    param([string]$Label)
    Write-AnalyzeLog
    Write-AnalyzeLog "*** $Label $(Get-Date -Format 'MM-dd-yyyy hh:mm:ss tt') ***"
    Write-AnalyzeLog
}
