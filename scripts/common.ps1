# Shared helpers for Antigravity Proxy Helper (Windows)

function Get-ProxyHelperStateDir {
    $dir = Join-Path $env:USERPROFILE ".gemini\antigravity-proxy-helper"
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-ProxyHelperDefaultConfig {
    return [ordered]@{
        mode                     = "auto"   # "auto" | "manual" | "direct"
        host                     = "127.0.0.1"
        port                     = $null
        noProxy                  = "localhost,127.0.0.1,::1"
        bypassList               = "localhost;127.0.0.1;[::1]"
        probeTimeoutMs           = 250
        autoRepairOnSessionStart = $true
        antigravityExePath       = ""
        extraProcessPatterns     = @()
        extraCandidatePorts      = @()
    }
}

function Get-ProxyHelperConfig {
    $cfg = Get-ProxyHelperDefaultConfig
    $cfgPath = Join-Path (Get-ProxyHelperStateDir) "config.json"
    if (Test-Path $cfgPath) {
        try {
            $raw = Get-Content -Path $cfgPath -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json
                foreach ($key in @($cfg.Keys)) {
                    $prop = $parsed.PSObject.Properties[$key]
                    if ($null -ne $prop) {
                        $cfg[$key] = $prop.Value
                    }
                }
            }
        } catch {
            Write-ProxyHelperLog "WARN: Failed to parse config.json, using defaults: $($_.Exception.Message)"
        }
    }
    return [PSCustomObject]$cfg
}

function Write-ProxyHelperLog {
    param([string]$Message)
    try {
        $logDir = Join-Path (Get-ProxyHelperStateDir) "logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logPath = Join-Path $logDir "launcher.log"
        if ((Test-Path $logPath) -and ((Get-Item $logPath).Length -gt 65536)) {
            $tail = Get-Content -Path $logPath -Tail 100 -ErrorAction SilentlyContinue
            Set-Content -Path $logPath -Value $tail -Encoding UTF8
        }
        $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $logPath -Value "[$ts] $Message" -Encoding UTF8
    } catch {
        # Never fail caller due to logging issues
    }
}

function Find-AntigravityExe {
    param($Config = $null)
    if ($null -eq $Config) {
        $Config = Get-ProxyHelperConfig
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Config.antigravityExePath)) {
        $candidates.Add($Config.antigravityExePath)
    }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\Antigravity\Antigravity.exe"))
        $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\antigravity\Antigravity.exe"))
    }
    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles "Antigravity\Antigravity.exe"))
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} "Antigravity\Antigravity.exe"))
    }

    foreach ($p in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path $p)) {
            return (Resolve-Path $p).Path
        }
    }

    # Fallback: inspect existing shortcuts
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $lnkList = @(
            (Join-Path $env:USERPROFILE "Desktop\Antigravity.lnk"),
            (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Antigravity.lnk")
        )
        foreach ($lnk in $lnkList) {
            if (Test-Path $lnk) {
                $target = $wsh.CreateShortcut($lnk).TargetPath
                if ($target -and ($target -match 'Antigravity\.exe$') -and (Test-Path $target)) {
                    return (Resolve-Path $target).Path
                }
            }
        }
    } catch {
        # Ignore COM errors
    }

    return $null
}

function Get-ProxyHelperCachePath {
    return (Join-Path (Get-ProxyHelperStateDir) "cache.json")
}
