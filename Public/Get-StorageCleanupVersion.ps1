function Get-StorageCleanupVersion {
    [CmdletBinding()] param()
    $m = Get-Module Get-StorageCleanup
    if ($m) { $m.Version.ToString() } else { 'unknown' }
}
