param(
    [switch]$CheckOnly,
    [switch]$Restore,
    [switch]$Force,
    [switch]$Json,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Get-ProxyHelperConfig
$exePath = Find-AntigravityExe -Config $cfg
$vbsPath = (Resolve-Path (Join-Path $PSScriptRoot "launch-silent.vbs")).Path
$wscriptPath = Join-Path $env:SystemRoot "System32\wscript.exe"
$expectedArgs = "//nologo `"$vbsPath`""

$backupDir = Join-Path (Get-ProxyHelperStateDir) "backups"
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

$targets = @(
    [PSCustomObject]@{
        Key        = "Desktop"
        Path       = Join-Path $env:USERPROFILE "Desktop\Antigravity.lnk"
        BackupPath = Join-Path $backupDir "Desktop_Antigravity.lnk"
    },
    [PSCustomObject]@{
        Key        = "StartMenu"
        Path       = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Antigravity.lnk"
        BackupPath = Join-Path $backupDir "StartMenu_Antigravity.lnk"
    },
    [PSCustomObject]@{
        Key        = "Taskbar"
        Path       = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Antigravity.lnk"
        BackupPath = Join-Path $backupDir "Taskbar_Antigravity.lnk"
    }
)

$wsh = New-Object -ComObject WScript.Shell
$items = New-Object System.Collections.Generic.List[object]
$repairedCount = 0
$restoredCount = 0
$needsRepairCount = 0

foreach ($t in $targets) {
    if (-not (Test-Path $t.Path)) {
        if ($Restore -and (Test-Path $t.BackupPath)) {
            Copy-Item -Path $t.BackupPath -Destination $t.Path -Force
            $restoredCount++
            $items.Add([PSCustomObject]@{ key = $t.Key; path = $t.Path; status = "restored" })
        }
        continue
    }

    if ($Restore) {
        if (Test-Path $t.BackupPath) {
            Copy-Item -Path $t.BackupPath -Destination $t.Path -Force
            $restoredCount++
            $items.Add([PSCustomObject]@{ key = $t.Key; path = $t.Path; status = "restored_from_backup" })
        } elseif ($exePath) {
            $sc = $wsh.CreateShortcut($t.Path)
            $sc.TargetPath = $exePath
            $sc.Arguments = ""
            $sc.WorkingDirectory = Split-Path -Parent $exePath
            $sc.IconLocation = "$exePath,0"
            $sc.Save()
            $restoredCount++
            $items.Add([PSCustomObject]@{ key = $t.Key; path = $t.Path; status = "restored_to_exe" })
        }
        continue
    }

    $sc = $wsh.CreateShortcut($t.Path)
    $isBound = ($sc.TargetPath -ieq $wscriptPath) -and ($sc.Arguments -ieq $expectedArgs)

    if ($isBound -and -not $Force) {
        $items.Add([PSCustomObject]@{
            key    = $t.Key
            path   = $t.Path
            status = "ok"
            target = $sc.TargetPath
        })
        continue
    }

    if ($CheckOnly) {
        $needsRepairCount++
        $items.Add([PSCustomObject]@{
            key    = $t.Key
            path   = $t.Path
            status = "needs_repair"
            target = $sc.TargetPath
            args   = $sc.Arguments
        })
        continue
    }

    # Backup original shortcut ONLY if backup doesn't exist yet and current shortcut points to Antigravity.exe
    if (-not (Test-Path $t.BackupPath)) {
        if ($sc.TargetPath -match 'Antigravity\.exe$') {
            Copy-Item -Path $t.Path -Destination $t.BackupPath -Force
        } elseif ($exePath) {
            # Synthesize a clean original shortcut backup pointing directly to Antigravity.exe
            $bak = $wsh.CreateShortcut($t.BackupPath)
            $bak.TargetPath = $exePath
            $bak.Arguments = ""
            $bak.WorkingDirectory = Split-Path -Parent $exePath
            $bak.IconLocation = "$exePath,0"
            $bak.Save()
        }
    }

    $sc.TargetPath = $wscriptPath
    $sc.Arguments = $expectedArgs
    if ($exePath) {
        $sc.WorkingDirectory = Split-Path -Parent $exePath
        $sc.IconLocation = "$exePath,0"
    }
    $sc.Save()

    $repairedCount++
    Write-ProxyHelperLog "Repaired shortcut [$($t.Key)]: $($t.Path) -> $vbsPath"
    $items.Add([PSCustomObject]@{
        key    = $t.Key
        path   = $t.Path
        status = "repaired"
        backup = $t.BackupPath
    })
}

$summary = [PSCustomObject]@{
    ok               = $true
    launcherScript   = $vbsPath
    antigravityExe   = $exePath
    repairedCount    = $repairedCount
    restoredCount    = $restoredCount
    needsRepairCount = $needsRepairCount
    shortcuts        = $items
}

if ($Json) {
    $summary | ConvertTo-Json -Depth 5
} elseif (-not $Quiet) {
    foreach ($it in $items) {
        Write-Output ("[{0}] {1} -> {2}" -f $it.key, $it.status, $it.path)
    }
}
