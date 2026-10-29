function Find-LargeFiles {
    <#
    .SYNOPSIS
    Finds individual files over a size threshold (e.g. runaway .bak, .vhdx, .dmp, .ldf). Report only; deletes nothing.
    .PARAMETER Extension
    Optional filter, e.g. -Extension .bak,.dmp
    .NOTES
    Uses robocopy /L /MIN so the filesystem walk is native and only large files are returned.
    /XJ skips junctions, so loops (e.g. ProgramData\Application Data) cannot hang the scan.
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

    $timeout = 600
    if ($script:Config.ScanTimeoutSec) { $timeout = $script:Config.ScanTimeoutSec }

    # A trailing backslash before the closing quote breaks robocopy argument parsing, so add a dot
    $src = $Path
    if ($src -match '\\$') { $src = $src + '.' }

    $outFile = Join-Path $env:TEMP "gsc_big_$PID.out"
    $rcArgs  = "`"$src`" NULL /L /E /XJ /R:0 /W:0 /BYTES /FP /NC /NDL /NJH /NJS /NP /MIN:$minBytes /XD `"System Volume Information`" `"`$RECYCLE.BIN`""
    $p = Start-Process robocopy.exe -ArgumentList $rcArgs -PassThru -NoNewWindow -RedirectStandardOutput $outFile
    if (-not $p.WaitForExit($timeout * 1000)) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Write-AnalyzeLog "  TIMEOUT: large-file scan of '$Path' exceeded $timeout sec - results may be incomplete."
    }

    $hits = New-Object System.Collections.ArrayList
    foreach ($line in (Get-Content $outFile -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*(\d+)\s+(\S.*)$') {
            $full = $Matches[2].Trim()
            if ($extLower.Count -gt 0) {
                $dot = $full.LastIndexOf('.')
                $ext = ''
                if ($dot -ge 0) { $ext = $full.Substring($dot).ToLower() }
                if ($extLower -notcontains $ext) { continue }
            }
            [void]$hits.Add([pscustomobject]@{ Size = [long]$Matches[1]; Path = $full })
        }
    }
    Remove-Item $outFile -Force -ErrorAction SilentlyContinue

    # Only the top N need real file objects (Write-FileResults expects FileInfo)
    $found = @()
    foreach ($h in ($hits | Sort-Object Size -Descending | Select-Object -First $Top)) {
        $fi = Get-Item -LiteralPath $h.Path -Force -ErrorAction SilentlyContinue
        if ($fi) { $found += $fi }
    }

    if ($PassThru) { return $found }
    if (-not $found) { Write-AnalyzeLog "  No files found at or above $ThresholdMB MB."; return }
    $hdr = "Top $Top largest files under $Path (largest first):"
    Write-AnalyzeLog $hdr; Write-AnalyzeLog ('-' * $hdr.Length)
    Write-FileResults -Files $found
    Write-AnalyzeLog; Write-AnalyzeLog '  By extension (files above threshold):'
    $found | Group-Object { $_.Extension.ToLower() } | Sort-Object { ($_.Group | Measure-Object Length -Sum).Sum } -Descending | ForEach-Object {
        Write-AnalyzeLog ("    {0,-10} {1,4} file(s)  {2,10:N0} MB" -f $(if ($_.Name) { $_.Name } else { '(none)' }), $_.Count, (($_.Group | Measure-Object Length -Sum).Sum / 1MB))
    }
}