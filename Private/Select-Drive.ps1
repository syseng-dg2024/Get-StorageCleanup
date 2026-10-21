function Select-Drive {
    Write-Host ' '; Write-Host 'Available drives:'; Write-Host ' '
    $list = @(); $idx = 1
    foreach ($d in (Get-CimInstance Win32_LogicalDisk)) {
        $type = switch ($d.DriveType) { 2 {'Removable'} 3 {'Local Disk'} 4 {'Network'} 5 {'CD/DVD'} default {'Unknown'} }
        if ($d.Size) {
            $lbl = if ($d.VolumeName) { $d.VolumeName } else { 'No Label' }
            Write-Host ("  [{0}]  {1}  [{2}]  {3}  -  {4:N0} GB total, {5:N0} GB free" -f $idx, $d.DeviceID, $type, $lbl, ($d.Size / 1GB), ($d.FreeSpace / 1GB))
        } else { Write-Host ("  [{0}]  {1}  [{2}]  (no media)" -f $idx, $d.DeviceID, $type) }
        $list += $d.DeviceID; $idx++
    }
    while ($true) {
        $s = (Read-Host 'Enter number to select drive (B to go back)').Trim()
        if ($s -match '^[Bb]$') { return $null }
        if ($s -match '^\d+$' -and [int]$s -ge 1 -and [int]$s -le $list.Count) { return $list[[int]$s - 1] }
        Write-Host " Invalid selection - enter 1 to $($list.Count)."
    }
}
