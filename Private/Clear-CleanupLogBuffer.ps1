function Clear-CleanupLogBuffer {
    if ($script:CleanupBuffer.Count -gt 0) {
        $script:CleanupBuffer | Out-File -FilePath $script:CleanupLogPath -Append -Encoding UTF8
        $script:CleanupBuffer = @()
    }
}
