Add-Type -AssemblyName System.Windows.Forms
$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
$dlg.SelectedPath = "v:\___VAC\__K\__CODE\_PY\_SAIPENVIEW\"
$res = $dlg.ShowDialog()
Write-Output "Res: $res Path: $($dlg.SelectedPath)"
