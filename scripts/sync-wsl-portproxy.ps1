# Keeps a Windows port proxy rule pointed at WSL, whose address can change when WSL restarts.
# Docker in WSL publishes only on localhost, so the LAN reaches a container through this rule.
# Run elevated from a scheduled task. It only updates a rule that already exists, and it does
# nothing while WSL is stopped, so it never starts WSL itself.
param([int]$Port = 3001)

$log = Join-Path $env:LOCALAPPDATA 'sync-wsl-portproxy.log'
function Write-Log($text) { Add-Content -Path $log -Value "$(Get-Date -Format s) $text" }

$env:WSL_UTF8 = '1'
$running = wsl.exe --list --running --quiet 2>$null
if ($LASTEXITCODE -ne 0 -or -not $running) { exit 0 }

$address = (wsl.exe -e ip -4 -o addr show eth0 2>$null) -join ' '
if ($address -notmatch 'inet (\d+\.\d+\.\d+\.\d+)/') { Write-Log 'no WSL address found'; exit 1 }
$wslAddress = $Matches[1]

$rule = netsh interface portproxy show v4tov4 |
    ForEach-Object { if ($_ -match '^\s*(\S+)\s+(\d+)\s+(\S+)\s+(\d+)\s*$') { [pscustomobject]@{ Listen = $Matches[1]; Port = [int]$Matches[2]; Target = $Matches[3]; TargetPort = [int]$Matches[4] } } } |
    Where-Object { $_.Port -eq $Port } | Select-Object -First 1
if (-not $rule) { exit 0 }

# Restarting IP Helper can't help if the machine no longer has the rule's LAN address.
if (-not (Get-NetIPAddress -IPAddress $rule.Listen -ErrorAction SilentlyContinue)) {
    Write-Log "this machine no longer has $($rule.Listen), rule left alone"
    exit 1
}

$stale = $rule.Target -ne $wslAddress
if ($stale) {
    netsh interface portproxy set v4tov4 listenaddress=$($rule.Listen) listenport=$Port connectaddress=$wslAddress connectport=$($rule.TargetPort) | Out-Null
    Write-Log "port $Port target changed from $($rule.Target) to $wslAddress"
}

$listening = Get-NetTCPConnection -LocalAddress $rule.Listen -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($stale -or -not $listening) {
    Restart-Service iphlpsvc -Force
    Write-Log "restarted IP Helper (stale target: $stale, was listening: $([bool]$listening))"
}
