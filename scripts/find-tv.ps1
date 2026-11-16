# Find devices on your local network with the ADB port open (Windows PowerShell).
#   powershell -ExecutionPolicy Bypass -File scripts\find-tv.ps1 -Net 192.168.1
param([string]$Net = "192.168.1", [int]$Port = 5555)

Write-Host "Scanning $Net.1-254 for port $Port ..."
$probes = 1..254 | ForEach-Object {
    $ip = "$Net.$_"
    $c = New-Object System.Net.Sockets.TcpClient
    $null = $c.BeginConnect($ip, $Port, $null, $null)
    [pscustomobject]@{ ip = $ip; client = $c }
}
Start-Sleep -Seconds 3
$probes | Where-Object { $_.client.Connected } | ForEach-Object { Write-Host "OPEN  $($_.ip):$Port" }
$probes | ForEach-Object { $_.client.Close() }
Write-Host "Done. Connect with:  adb connect <ip>:$Port"
