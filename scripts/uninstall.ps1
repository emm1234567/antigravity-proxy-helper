param(
    [switch]$PurgeState,
    [switch]$RemovePluginCopy
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Write-Output "=== 1. Restoring original Antigravity shortcuts ==="
& (Join-Path $PSScriptRoot "repair-shortcuts.ps1") -Restore

Write-Output ""
Write-Output "=== 2. Removing optional logon guard task (if present) ==="
$taskName = "AntigravityProxyHelperLogonGuard"
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Output "Removed Scheduled Task: $taskName"
} else {
    Write-Output "No logon guard Scheduled Task found."
}

if ($PurgeState) {
    $stateDir = Get-ProxyHelperStateDir
    if (Test-Path $stateDir) {
        Remove-Item -Path $stateDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "Removed state directory: $stateDir"
    }
}

if ($RemovePluginCopy) {
    $pluginDir = Join-Path $env:USERPROFILE ".gemini\config\plugins\antigravity-proxy-helper"
    if (Test-Path $pluginDir) {
        Remove-Item -Path $pluginDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "Removed installed plugin directory: $pluginDir"
    }
}

Write-Output ""
Write-Output "Uninstall complete. Antigravity shortcuts have been restored."
