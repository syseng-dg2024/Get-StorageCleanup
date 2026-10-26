function Find-LargeFiles {
    <#
    .SYNOPSIS
    Finds individual files over a size threshold (e.g. runaway .bak, .vhdx, .dmp, .ldf). Report only; deletes nothing.
    .PARAMETER Extension
    Optional filter, e.g. -Extension .bak,.dmp
    .NOTES
    Walks the tree manually and skips reparse-point directories, so junction loops
    (e.g. ProgramData\Application Data) cannot hang the scan.
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
    $extLower = @()
    foreach ($e in $Extension) { $extLower += $e.ToLower() }
    if (-not $Quiet) { Write-AnalyzeLog "  Scanning files >= $ThresholdMB MB under $Path ..." }

    $root  = (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue).FullName
    $found = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    if ($root) { $stack.Push($root) }

    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        foreach ($f in (Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue)) {
            if ($f.Length -ge $minBytes -and ($extLower.Count -eq 0 -or $extLower -contains $f.Extension.ToLower())) {
                [void]$found.Add($f)
            }
        }
        foreach ($d in (Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($d.Attributes -notmatch 'ReparsePoint') { $stack.Push($d.FullName) }
        }
    }

    $found = @($found | Sort-Object Length -Descending | Select-Object -First $Top)
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