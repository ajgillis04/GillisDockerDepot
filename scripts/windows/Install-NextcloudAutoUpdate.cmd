@echo off
rem Double-click this to set up quiet monthly Nextcloud desktop updates on this PC.
rem It runs Install-NextcloudAutoUpdate.ps1 (keep both files in the same folder).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-NextcloudAutoUpdate.ps1"
