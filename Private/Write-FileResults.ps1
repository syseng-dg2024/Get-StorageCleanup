function Write-FileResults {
    param([object[]]$Files)
    $rank = 1
    foreach ($f in $Files) {
        Write-AnalyzeLog ("  [{0,2}]  {1,10:N0} MB  ({2:N2} GB)  {3:yyyy-MM-dd}  {4}" -f $rank, ($f.Length / 1MB), ($f.Length / 1GB), $f.LastWriteTime, $f.FullName)
        $rank++
    }
}
