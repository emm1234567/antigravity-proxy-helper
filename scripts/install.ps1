param(
    [switch]$EnableLogonGuard,
    [switch]$InstallAsPlugin,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pluginDir = Join-Path $env:USERPROFILE ".gemini\config\plugins\antigravity-proxy-helper"
$activeRoot = $repoRoot

if ($InstallAsPlugin -and ($repoRoot -ine $pluginDir)) {
    Write-Output "Syncing plugin files to $pluginDir ..."
    New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null

    $itemsToCopy = @("plugin.json", "hooks.json", "README.md", "LICENSE", "config.example.json", "assets", "skills", "scripts")
    foreach ($item in $itemsToCopy) {
        $src = Join-Path $repoRoot $item
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination $pluginDir -Recurse -Force
        }
    }
    $activeRoot = $pluginDir
}

$activeScripts = Join-Path $activeRoot "scripts"
. (Join-Path $activeScripts "common.ps1")

Write-Output "=== 1. Detecting local proxy ==="
& (Join-Path $activeScripts "detect-proxy.ps1") -NoCache

Write-Output ""
Write-Output "=== 2. Backing up and binding Antigravity shortcuts ==="
$repairParams = @{}
if ($Force) { $repairParams["Force"] = $true }
& (Join-Path $activeScripts "repair-shortcuts.ps1") @repairParams

if ($EnableLogonGuard) {
    Write-Output ""
    Write-Output "=== 3. Registering optional user-level logon self-heal task ==="
    $taskName = "AntigravityProxyHelperLogonGuard"
    $repairPath = Join-Path $activeScripts "repair-shortcuts.ps1"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$repairPath`" -Quiet"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Re-binds Antigravity shortcuts if overwritten by app auto-update." -Force | Out-Null
    Write-Output "Registered user Scheduled Task: $taskName"
}

Write-Output ""
Write-Output "Installation complete! Restart Antigravity from Desktop or Start Menu to apply."
