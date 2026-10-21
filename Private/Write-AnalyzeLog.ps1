function Write-AnalyzeLog {
    param([string]$Message = ' ')
    Write-Host $Message
    if ($script:AnalyzeOutput) { $Message | Out-File -Width 150 $script:AnalyzeOutput -Append }
}
