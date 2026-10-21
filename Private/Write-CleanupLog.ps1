function Write-CleanupLog {
    param([string]$Message)
    $script:CleanupBuffer += "$(Get-Date -Format 'hh:mm:ss tt') - $Message"
    if ($script:CleanupBuffer.Count -ge 50) { Clear-CleanupLogBuffer }
}
