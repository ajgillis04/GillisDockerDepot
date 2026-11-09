# ------------------------------------------------------------------------------
# Install-NextcloudAutoUpdate.ps1 - Stop the Nextcloud desktop app's update popups
# and update it quietly once a month instead (Windows).
# ------------------------------------------------------------------------------
# How to use: double-click Install-NextcloudAutoUpdate.cmd (next to this file), or
# right-click this file > Run with PowerShell. Click Yes on the Windows admin prompt.
# Run it as the person who uses Nextcloud on that PC; they need to be an
# administrator on it (normal for a home PC), because installing updates needs admin.
#
# What it sets up:
#   1. Turns off Nextcloud's own update check (machine-wide registry value
#      HKLM\Software\Nextcloud GmbH\Nextcloud  skipUpdateCheck = 1). No more popups.
#   2. Writes C:\Scripts\Nextcloud\Update-NextcloudDesktop.ps1, which uses winget to
#      install any newer Nextcloud silently and restarts Nextcloud if it was running.
#   3. Creates the scheduled task "Nextcloud Desktop monthly update": 1st of the month
#      at 12:00, or at the next chance if the PC was off. Runs on battery too.
#   4. Runs it once and shows the result. Each run is logged to C:\Scripts\Nextcloud\update.log.
#
# Safe to run again (it just refreshes everything). To undo on a PC:
#   Set skipUpdateCheck back to 0, and run:
#   Unregister-ScheduledTask -TaskName "Nextcloud Desktop monthly update"
#
# Needs: Nextcloud desktop installed normally (C:\Program Files\Nextcloud) and winget
# (built into Windows 10/11 as "App Installer").
# First set up on Andy's laptop 2026-11-09.
# ------------------------------------------------------------------------------
param([string]$ForUser)

$taskName = 'Nextcloud Desktop monthly update'
$dir      = 'C:\Scripts\Nextcloud'
$exe      = 'C:\Program Files\Nextcloud\nextcloud.exe'

# --- Ask for admin once, remembering who the task is for ----------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $me = "$env:USERDOMAIN\$env:USERNAME"
    Write-Host "Asking Windows for admin rights (click Yes)..."
    try {
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ForUser', "`"$me`"")
    } catch {
        Write-Host "Admin rights weren't given, so nothing was changed." -ForegroundColor Yellow
        Read-Host "Press Enter to close"; exit 1
    }
    if (Test-Path "$dir\install.log") { Get-Content "$dir\install.log" | Select-String 'OK|WARNING|FAILED|log:|task|popups|test run' | ForEach-Object { Write-Host $_.Line } }
    Read-Host "Press Enter to close"; exit $p.ExitCode
}
if (-not $ForUser) { $ForUser = "$env:USERDOMAIN\$env:USERNAME" }

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Start-Transcript -Path "$dir\install.log" -Force | Out-Null
$ok = $true
try {
    if (-not (Test-Path $exe)) { throw "Nextcloud isn't installed at $exe. Install it first: https://nextcloud.com/install/#install-clients" }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget isn't available. Install 'App Installer' from the Microsoft Store, then run this again." }

    # 1. No more update popups from the Nextcloud app
    $key = 'HKLM:\Software\Nextcloud GmbH\Nextcloud'
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    Set-ItemProperty -Path $key -Name skipUpdateCheck -Value 1 -Type DWord
    "popups off: skipUpdateCheck = $((Get-ItemProperty $key).skipUpdateCheck)"

    # 2. The updater script the task runs
    $updater = @'
# Update-NextcloudDesktop.ps1 - Quietly update the Nextcloud desktop app.
# Run monthly by the scheduled task "Nextcloud Desktop monthly update", created by
# Install-NextcloudAutoUpdate.ps1 (GillisDockerDepot/scripts/windows). Uses winget to
# install a newer Nextcloud.NextcloudDesktop silently, restarts Nextcloud if the update
# closed it, and logs each run to update.log next to this file.
$ErrorActionPreference = 'Continue'
$log = Join-Path $PSScriptRoot 'update.log'
$exe = 'C:\Program Files\Nextcloud\nextcloud.exe'
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Add-Content -Path $log -Encoding utf8 }

$before = (Get-Item $exe -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
$wasRunning = [bool](Get-Process nextcloud -ErrorAction SilentlyContinue)
Log "start: installed $before, running=$wasRunning"

$out = & winget upgrade --id Nextcloud.NextcloudDesktop --exact --silent `
    --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-String
$code = $LASTEXITCODE
$after = (Get-Item $exe -ErrorAction SilentlyContinue).VersionInfo.ProductVersion

if ($before -ne $after) {
    Log "updated $before -> $after (winget exit $code)"
} elseif ($code -eq -1978335189 -or $out -match 'No available upgrade|No newer package|No applicable upgrade|UpdateNoPackagesFound') {
    # -1978335189 = 0x8A15002B, winget's "no applicable update"; with no console it prints UpdateNoPackagesFound
    Log "already up to date ($after)"
} else {
    Log "no change ($after), winget exit $code : $(($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | ')"
}

# The installer closes Nextcloud; start it again if it was running before.
Start-Sleep -Seconds 5
if ($wasRunning -and -not (Get-Process nextcloud -ErrorAction SilentlyContinue)) {
    # Through Explorer, so it runs as the normal (non-admin) user, not elevated like this task.
    Start-Process -FilePath explorer.exe -ArgumentList "`"$exe`""
    Log "restarted Nextcloud"
}
'@
    Set-Content -Path "$dir\Update-NextcloudDesktop.ps1" -Value $updater -Encoding UTF8

    # 3. Monthly task, as the Nextcloud user, elevated, only when they're logged on
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dir\Update-NextcloudDesktop.ps1`""
    schtasks.exe /Create /F /TN $taskName /SC MONTHLY /D 1 /ST 12:00 /TR $cmd /RU $ForUser /IT /RL HIGHEST | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "creating the scheduled task for $ForUser failed" }
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Set-ScheduledTask -TaskName $taskName -Settings $settings | Out-Null
    "task created for $ForUser, next run $((Get-ScheduledTaskInfo -TaskName $taskName).NextRunTime)"

    # Get-LocalGroupMember can throw on PCs with leftover deleted accounts; only ever warn.
    $userIsAdmin = $true
    try {
        $userIsAdmin = [bool](Get-LocalGroupMember -Group Administrators -ErrorAction Stop |
            Where-Object { $_.Name -eq $ForUser })
    } catch { }
    if (-not $userIsAdmin) {
        "WARNING: $ForUser isn't an administrator on this PC, so the monthly install may fail. Check update.log after the 1st."
    }

    # 4. Test run now (installs an update straight away if one is waiting)
    Start-ScheduledTask -TaskName $taskName
    $i = 0; do { Start-Sleep -Seconds 5; $i++ } while ((Get-ScheduledTask -TaskName $taskName).State -eq 'Running' -and $i -lt 60)
    "test run: $((Get-Content "$dir\update.log" -ErrorAction SilentlyContinue | Select-Object -Last 1))"
    "log: $dir\update.log"
    "OK - Nextcloud will update itself quietly once a month."
} catch {
    $ok = $false
    "FAILED: $_"
} finally {
    Stop-Transcript | Out-Null
}
if (-not $ok) { exit 1 }
