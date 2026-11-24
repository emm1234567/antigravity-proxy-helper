# SessionStart hook entrypoint for Antigravity Proxy Helper
# Reads hook JSON on stdin, checks/repairs overwritten shortcuts, outputs valid hook JSON on stdout.

$ErrorActionPreference = "SilentlyContinue"

try {
    # Drain stdin without blocking if redirected
    if ([Console]::IsInputRedirected) {
        [void][Console]::In.ReadToEnd()
    }

    . (Join-Path $PSScriptRoot "common.ps1")
    $cfg = Get-ProxyHelperConfig

    if (-not $cfg.autoRepairOnSessionStart) {
        Write-Output '{}'
        exit 0
    }

    $repairScript = Join-Path $PSScriptRoot "repair-shortcuts.ps1"
    $resJson = (& $repairScript -Json) -join "`n"
    $res = $resJson | ConvertFrom-Json

    if ($res -and $res.repairedCount -gt 0) {
        $repairedNames = @($res.shortcuts | Where-Object { $_.status -eq "repaired" } | ForEach-Object { $_.key }) -join ", "
        $payload = @{
            injectSteps = @(
                @{
                    systemMessage = @{
                        systemMessage = ""
                        metadata = @{
                            user_markdown = "**Antigravity Proxy Helper**: Detected overwritten shortcut(s) ($repairedNames) and automatically re-bound them to the auto-proxy launcher. Takes effect on next restart."
                        }
                    }
                }
            )
        }
        Write-Output ($payload | ConvertTo-Json -Depth 6 -Compress)
    } else {
        Write-Output '{}'
    }
} catch {
    # Never break user session on hook failure
    Write-Output '{}'
}
