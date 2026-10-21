function Write-AnalyzeTimestamp {
    param([string]$Label)
    Write-AnalyzeLog
    Write-AnalyzeLog "*** $Label $(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss') ***"
    Write-AnalyzeLog
}
