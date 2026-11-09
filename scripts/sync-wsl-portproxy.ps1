# Keeps Forge reachable after a reboot. Run elevated from a scheduled task, at logon and every
# 5 minutes. It never starts WSL itself; the WSL steps wait until WSL is running.
#   1. Restarts an Ethernet port stuck in a failed state. Since 2026-10-17 an I225-V port drops
#      out about 3 seconds after every boot, and a device restart brings it back.
#   2. Remounts WSL's NAS shares if they failed because the network wasn't up, then restarts the
#      Tdarr node, which otherwise keeps the empty folder it started with.
#   3. Keeps the Windows port proxy rules pointed at WSL, whose address can change. Docker in WSL
#      publishes only on localhost, so the LAN reaches a container through these rules.
#      3001 is Open WebUI; 11434 is Ollama, for Home Assistant's camera descriptions.
param([int[]]$Port = @(3001, 11434), [string[]]$Mounts = @('mnt-m.mount', 'mnt-gillisnas.mount'), [string]$TdarrNode = 'tdarr_node.Forge')

$log = Join-Path $env:LOCALAPPDATA 'sync-wsl-portproxy.log'
function Write-Log($text) { Add-Content -Path $log -Value "$(Get-Date -Format s) $text" }

# 1. Ethernet. A port someone disabled on purpose is left alone.
$failed = Get-PnpDevice -Class Net -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -like '*Ethernet Controller*' -and $_.Problem -notin 'CM_PROB_NONE', 'CM_PROB_DISABLED' }
foreach ($device in $failed) {
    pnputil /restart-device "$($device.InstanceId)" | Out-Null
    Start-Sleep -Seconds 15
    $now = (Get-PnpDevice -InstanceId $device.InstanceId).Problem
    Write-Log "restarted $($device.FriendlyName) ($($device.Problem)), now $now"
}

$env:WSL_UTF8 = '1'
$running = wsl.exe --list --running --quiet 2>$null
if ($LASTEXITCODE -ne 0 -or -not $running) { exit 0 }

# 2. NAS shares. They go through systemd's mount units: a plain mount from an elevated wsl.exe
# lands in a private mount namespace that Docker never sees.
$missing = @($Mounts | Where-Object { wsl.exe -u root -e systemctl is-active --quiet $_ 2>$null; $LASTEXITCODE -ne 0 })
if ($missing) {
    wsl.exe -u root -e systemctl start @missing 2>$null | Out-Null
    $still = @($Mounts | Where-Object { wsl.exe -u root -e systemctl is-active --quiet $_ 2>$null; $LASTEXITCODE -ne 0 })
    Write-Log "remounted $($missing -join ', '); still missing: $(if ($still) { $still -join ', ' } else { 'none' })"
    if (-not $still) {
        wsl.exe -e docker restart $TdarrNode 2>$null | Out-Null
        Write-Log "restarted $TdarrNode so it sees the media"
    }
}

# 3. Port proxy. It only updates rules that already exist.
$address = (wsl.exe -e ip -4 -o addr show eth0 2>$null) -join ' '
if ($address -notmatch 'inet (\d+\.\d+\.\d+\.\d+)/') { Write-Log 'no WSL address found'; exit 1 }
$wslAddress = $Matches[1]

$rules = netsh interface portproxy show v4tov4 |
    ForEach-Object { if ($_ -match '^\s*(\S+)\s+(\d+)\s+(\S+)\s+(\d+)\s*$') { [pscustomobject]@{ Listen = $Matches[1]; Port = [int]$Matches[2]; Target = $Matches[3]; TargetPort = [int]$Matches[4] } } }

$restart = $false
foreach ($p in $Port) {
    $rule = $rules | Where-Object { $_.Port -eq $p } | Select-Object -First 1
    if (-not $rule) { continue }

    # Restarting IP Helper can't help if the machine no longer has the rule's LAN address.
    if (-not (Get-NetIPAddress -IPAddress $rule.Listen -ErrorAction SilentlyContinue)) {
        Write-Log "this machine no longer has $($rule.Listen), port $p rule left alone"
        continue
    }

    $stale = $rule.Target -ne $wslAddress
    if ($stale) {
        netsh interface portproxy set v4tov4 listenaddress=$($rule.Listen) listenport=$p connectaddress=$wslAddress connectport=$($rule.TargetPort) | Out-Null
        Write-Log "port $p target changed from $($rule.Target) to $wslAddress"
    }

    $listening = Get-NetTCPConnection -LocalAddress $rule.Listen -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($stale -or -not $listening) {
        $restart = $true
        Write-Log "port $p was stale or not listening (stale target: $stale, was listening: $([bool]$listening))"
    }
}

if ($restart) {
    Restart-Service iphlpsvc -Force
    Write-Log 'restarted IP Helper'
}
