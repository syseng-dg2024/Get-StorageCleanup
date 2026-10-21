function Get-TopFolders {
    param([string]$RootPath, [hashtable]$FolderMap, [long]$ThresholdBytes, [int]$Top)
    $root = $RootPath.ToLower().TrimEnd('\')
    $res = @()
    foreach ($p in $FolderMap.Keys) {
        if (-not $p.ToLower().StartsWith($root) -or $p.ToLower() -eq $root) { continue }
        if ($FolderMap[$p] -ge $ThresholdBytes) { $res += @{ Path = $p; Bytes = $FolderMap[$p] } }
    }
    return $res | Sort-Object { $_['Bytes'] } -Descending | Select-Object -First $Top
}
