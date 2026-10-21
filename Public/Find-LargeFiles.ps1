function Find-LargeFiles {
    <#
    .SYNOPSIS
    Finds individual files over a size threshold (e.g. runaway .bak, .vhdx, .dmp, .ldf). Report only; deletes nothing.
    .PARAMETER Extension
    Optional filter, e.g. -Extension .bak,.dmp
    #>
    [CmdletBinding()]
    param(
        [string]$Path = 'C:\',
        [int]$ThresholdMB = 500,
        [int]$Top = 25,
        [string[]]$Extension,
        [switch]$PassThru,
        [switch]$Quiet
    )
    $minBytes = [long]$ThresholdMB * [long]1048576
    $skipRegex = '\\(documents and settings|application data|local settings|my documents|system volume information|\$recycle\.bin)\\'
    $extLower = @()
    foreach ($e in $Extension) { $extLower += $e.ToLower() }
    if (-not $Quiet) { Write-AnalyzeLog "  Scanning files >= $ThresholdMB MB under $Path ..." }
    $found = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Length -ge $minBytes -and
            -not ($_.Attributes -match 'ReparsePoint') -and
            ($extLower.Count -eq 0 -or $extLower -contains $_.Extension.ToLower()) -and
            ($_.FullName.ToLower() -notmatch $skipRegex)
        } | Sort-Object Length -Descending | Select-Object -First $Top
    if ($PassThru) { return $found }
    if (-not $found) { Write-AnalyzeLog "  No files found at or above $ThresholdMB MB."; return }
    $h = "Top $Top largest files under $Path (largest first):"
    Write-AnalyzeLog $h; Write-AnalyzeLog ('-' * $h.Length)
    Write-FileResults -Files $found
    Write-AnalyzeLog; Write-AnalyzeLog '  By extension (files above threshold):'
    $found | Group-Object { $_.Extension.ToLower() } | Sort-Object { ($_.Group | Measure-Object Length -Sum).Sum } -Descending | ForEach-Object {
        Write-AnalyzeLog ("    {0,-10} {1,4} file(s)  {2,10:N0} MB" -f $(if ($_.Name) { $_.Name } else { '(none)' }), $_.Count, (($_.Group | Measure-Object Length -Sum).Sum / 1MB))
    }
}
