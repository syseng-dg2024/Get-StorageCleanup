function Write-FolderResults {
    param([object[]]$SortedResults)
    $rank = 1
    foreach ($i in $SortedResults) {
        Write-AnalyzeLog ("  [{0,2}]  {1,10:N0} MB  ({2:N2} GB)  {3}" -f $rank, ($i['Bytes'] / 1MB), ($i['Bytes'] / 1GB), $i['Path'])
        $rank++
    }
}
