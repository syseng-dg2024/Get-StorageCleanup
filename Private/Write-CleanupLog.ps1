function Write-CleanupLog {
    param([string]$Message)
    $script:CleanupBuffer += "$(Get-Date -Format 'HH:mm:ss') - $Message"
    if ($script:CleanupBuffer.Count -ge 50) { Clear-CleanupLogBuffer }
}
