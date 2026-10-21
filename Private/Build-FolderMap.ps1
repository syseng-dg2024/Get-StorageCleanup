function Build-FolderMap {
    # One 'cmd /c dir /s' per top-level folder (cmd capture works under WDAC CLM; robocopy capture does not).
    param([string]$RootPath)
    $tops = Get-ChildItem -Path $RootPath -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | Select-Object -ExpandProperty FullName
    $map = @{}; $total = @($tops).Count; $done = 0
    Write-AnalyzeLog "  Found $total top-level folders. Measuring each..."
    foreach ($folder in $tops) {
        $done++
        $pct = [int](($done / $total) * 100); $filled = [int]($pct / 5)
        $disp = $folder; if ($disp.Length -gt 40) { $disp = '...' + $disp.Substring($disp.Length - 37) }
        Write-Host ("`r" + ("  [" + ('#' * $filled) + ('-' * (20 - $filled)) + "] $pct%  ($done/$total)  $disp").PadRight(100)) -NoNewline
        $skip = $script:SkipFolders -contains (Split-Path $folder -Leaf).ToLower()
        if ((Get-Item -Path $folder -Force -ErrorAction SilentlyContinue).Attributes -match 'ReparsePoint') { $skip = $true }
        if ($skip) { continue }
        $out = & cmd.exe /c dir /s /a "`"$folder`"" 2>$null
        $bytes = [long]0
        foreach ($line in $out) { if ($line -match 'File\(s\)\s+([\d,]+)\s+bytes') { $bytes = [long]($Matches[1] -replace ',','') } }
        $map[$folder] = $bytes
    }
    Write-Host ("`r" + (' ' * 100))
    Write-AnalyzeLog "  $($map.Count) folders measured."
    return $map
}
