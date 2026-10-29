function Build-FolderMap {
    # Measures each top-level folder. Junctions are skipped at depth 1 and every
    # dir /s call is timeout-capped, so junction loops cannot hang the scan.
    param([string]$RootPath)
    $timeout = 300
    if ($script:Config.ScanTimeoutSec) { $timeout = $script:Config.ScanTimeoutSec }
    $tops = Get-ChildItem -Path $RootPath -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | Select-Object -ExpandProperty FullName
    $map = @{}; $total = @($tops).Count; $done = 0
    Write-AnalyzeLog "  Found $total top-level folders. Measuring each..."
    foreach ($folder in $tops) {
        $done++
        $pct = [int](($done / $total) * 100); $filled = [int]($pct / 5)
        $disp = $folder; if ($disp.Length -gt 40) { $disp = '...' + $disp.Substring($disp.Length - 37) }
        Write-Host ("`r" + ("  [" + ('#' * $filled) + ('-' * (20 - $filled)) + "] $pct%  ($done/$total)  $disp").PadRight(100)) -NoNewline
        $skip = $script:SkipFolders -contains (Split-Path $folder -Leaf).ToLower()
        if ((Get-Item -LiteralPath $folder -Force -ErrorAction SilentlyContinue).Attributes -match 'ReparsePoint') { $skip = $true }
        if ($skip) { continue }

        $bytes = [long]0
        foreach ($f in (Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue)) { $bytes += $f.Length }
        $children = Get-ChildItem -LiteralPath $folder -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Attributes -notmatch 'ReparsePoint' }
        foreach ($child in $children) {
            $bytes += Measure-FolderSize -Path $child.FullName -TimeoutSec $timeout
        }
        $map[$folder] = $bytes
    }
    Write-Host ("`r" + (' ' * 100))
    Write-AnalyzeLog "  $($map.Count) folders measured."
    return $map
}