param(
    [switch]$NoCache,
    [switch]$Json,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function Test-HttpProxyEndpoint {
    param(
        [string]$HostAddr = "127.0.0.1",
        [int]$Port,
        [int]$TimeoutMs = 250
    )

    if ($Port -lt 1 -or $Port -gt 65535) {
        return $false
    }

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $connectTask = $client.BeginConnect($HostAddr, $Port, $null, $null)
        if (-not $connectTask.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($connectTask)

        $stream = $client.GetStream()
        $stream.ReadTimeout = $TimeoutMs
        $stream.WriteTimeout = $TimeoutMs

        # Pure-local HTTP CONNECT probe targeting a closed loopback port (zero external traffic, zero DNS).
        $probe = "CONNECT 127.0.0.1:1 HTTP/1.1`r`nHost: 127.0.0.1:1`r`nConnection: close`r`n`r`n"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($probe)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()

        $buffer = New-Object byte[] 512
        $read = 0
        try {
            $read = $stream.Read($buffer, 0, $buffer.Length)
        } catch {
            $read = 0
        }

        if ($read -le 0) {
            return $false
        }

        $resp = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
        if ($resp -notmatch '^HTTP/1\.[01]\s+\d{3}') {
            return $false
        }

        # Exclude Clash/Mihomo/V2Ray REST controller ports if they reply with controller greeting
        if ($resp -match '"hello"\s*:\s*"(clash|mihomo)' -or $resp -match 'X-Clash-|Clash-Controller') {
            return $false
        }

        # Exclude standard web servers replying 405 Method Not Allowed unless it's a known proxy port
        # Wait: some HTTP proxies reject CONNECT to 127.0.0.1:1 with 502/503/403/400/504, which is expected and proves HTTP proxy handling.
        if ($resp -match '^HTTP/1\.[01]\s+405\b' -and $resp -match '(?i)Server:\s*(nginx|apache|iis|uvicorn|werkzeug|express|caddy)') {
            return $false
        }

        return $true
    } catch {
        return $false
    } finally {
        if ($null -ne $client) {
            try { $client.Close() } catch {}
        }
    }
}

function Get-ListeningTcpMap {
    $map = @{}
    try {
        $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
        foreach ($c in $conns) {
            $addr = $c.LocalAddress
            if ($addr -notin @("127.0.0.1", "0.0.0.0", "::", "::1")) {
                continue
            }
            $port = [int]$c.LocalPort
            if (-not $map.ContainsKey($port)) {
                $map[$port] = New-Object System.Collections.Generic.List[int]
            }
            $owningPid = [int]$c.OwningProcess
            if (-not $map[$port].Contains($owningPid)) {
                $map[$port].Add($owningPid)
            }
        }
    } catch {
        Write-ProxyHelperLog "WARN: Get-NetTCPConnection failed: $($_.Exception.Message)"
    }
    return $map
}

function Parse-WindowsProxyServer {
    param([string]$ProxyServer)
    $results = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($ProxyServer)) {
        return $results
    }

    # Format A: "http=127.0.0.1:7890;https=127.0.0.1:7890;socks=127.0.0.1:7891"
    # Format B: "127.0.0.1:7890" or "http://127.0.0.1:7890"
    $entries = $ProxyServer -split ';'
    foreach ($entry in $entries) {
        $trimmed = $entry.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        $proto = "any"
        $target = $trimmed
        if ($trimmed -match '^([a-zA-Z0-9]+)=(.+)$') {
            $proto = $Matches[1].ToLowerInvariant()
            $target = $Matches[2].Trim()
        }
        if ($proto -notin @("any", "http", "https")) {
            continue
        }

        $target = $target -replace '^https?://', ''
        if ($target -match '^([^:]+):(\d+)$') {
            $h = $Matches[1].Trim()
            $p = [int]$Matches[2]
            if ($h -in @("127.0.0.1", "localhost", "::1")) {
                $h = "127.0.0.1"
            }
            $results.Add([PSCustomObject]@{ Host = $h; Port = $p })
        }
    }
    return $results
}

function New-ProxyResult {
    param(
        [bool]$Found,
        [string]$HostAddr = "127.0.0.1",
        [Nullable[int]]$Port = $null,
        [string]$Source = "none",
        [string]$ProcessName = "",
        $Config
    )
    $proxyUrl = if ($Found -and $Port) { "http://${HostAddr}:${Port}" } else { "" }
    return [PSCustomObject]@{
        found       = $Found
        host        = $HostAddr
        port        = $Port
        proxyUrl    = $proxyUrl
        noProxy     = $Config.noProxy
        bypassList  = $Config.bypassList
        source      = $Source
        processName = $ProcessName
        detectedAt  = (Get-Date).ToString("o")
    }
}

function Save-ProxyCache {
    param($Result)
    try {
        $cachePath = Get-ProxyHelperCachePath
        $Result | ConvertTo-Json -Depth 4 | Set-Content -Path $cachePath -Encoding UTF8
    } catch {
        Write-ProxyHelperLog "WARN: Failed to write cache.json: $($_.Exception.Message)"
    }
}

function Invoke-ProxyDetection {
    $cfg = Get-ProxyHelperConfig
    $timeout = [int]$cfg.probeTimeoutMs
    if ($timeout -lt 50) { $timeout = 250 }

    # Layer 1A: Explicit direct mode
    if ($cfg.mode -eq "direct") {
        return (New-ProxyResult -Found $false -Source "manual_direct" -Config $cfg)
    }

    # Layer 1B: Explicit manual override
    if ($cfg.mode -eq "manual" -and $null -ne $cfg.port -and [int]$cfg.port -gt 0) {
        $manualHost = if ($cfg.host) { $cfg.host } else { "127.0.0.1" }
        $manualPort = [int]$cfg.port
        $res = New-ProxyResult -Found $true -HostAddr $manualHost -Port $manualPort -Source "manual_config" -Config $cfg
        Save-ProxyCache $res
        return $res
    }

    $tested = New-Object System.Collections.Generic.HashSet[string]

    # Layer 0: Fast cache check (runs BEFORE loading NetTCPIP CIM module for instant startup)
    if (-not $NoCache) {
        $cachePath = Get-ProxyHelperCachePath
        if (Test-Path $cachePath) {
            try {
                $cached = Get-Content -Path $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($cached.found -and $cached.port) {
                    $cHost = if ($cached.host) { $cached.host } else { "127.0.0.1" }
                    $cPort = [int]$cached.port
                    if (Test-HttpProxyEndpoint -HostAddr $cHost -Port $cPort -TimeoutMs $timeout) {
                        $res = New-ProxyResult -Found $true -HostAddr $cHost -Port $cPort -Source "cache" -ProcessName ([string]$cached.processName) -Config $cfg
                        return $res
                    }
                    [void]$tested.Add("${cHost}:${cPort}")
                }
            } catch {
                # Ignore malformed cache
            }
        }
    }

    $listenMap = Get-ListeningTcpMap

    # Layer 2: Running known proxy processes -> listening ports
    $defaultPatterns = @(
        "clash", "mihomo", "v2ray", "xray", "sing-box", "singbox",
        "nekobox", "nekoray", "hiddify", "karing", "flclash",
        "verge", "nyanpasu", "shadowsocks", "ss-local", "sslocal",
        "trojan", "hysteria", "naive", "ikuuu", "v2tun", "privoxy",
        "gost", "brook"
    )
    if ($cfg.extraProcessPatterns -and $cfg.extraProcessPatterns.Count -gt 0) {
        $defaultPatterns += @($cfg.extraProcessPatterns)
    }
    $regexPattern = ($defaultPatterns | ForEach-Object { [regex]::Escape($_) }) -join "|"

    $preferredPorts = @(7890, 7897, 10809, 10808, 2080, 2081, 20171, 20172, 1081, 4780, 12334, 17890, 27890, 8118, 7891)
    if ($cfg.extraCandidatePorts -and $cfg.extraCandidatePorts.Count -gt 0) {
        $preferredPorts = @($cfg.extraCandidatePorts | ForEach-Object { [int]$_ }) + $preferredPorts
    }
    $skipPorts = @(53, 1053, 5353, 9090, 9097, 9099)

    try {
        $proxyProcs = @{}
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
            $name = [string]$_.Name
            $exe = [string]$_.ExecutablePath
            if (($name -match $regexPattern) -or ($exe -match $regexPattern)) {
                $proxyProcs[[int]$_.ProcessId] = $name
            }
        }

        if ($proxyProcs.Count -gt 0) {
            $procCandidates = New-Object System.Collections.Generic.List[object]
            foreach ($port in $listenMap.Keys) {
                if ($port -in $skipPorts) { continue }
                foreach ($owningPid in $listenMap[$port]) {
                    if ($proxyProcs.ContainsKey($owningPid)) {
                        $priority = [array]::IndexOf($preferredPorts, $port)
                        if ($priority -lt 0) { $priority = 9999 + $port }
                        $procCandidates.Add([PSCustomObject]@{
                            Port        = $port
                            ProcessName = $proxyProcs[$owningPid]
                            Priority    = $priority
                        })
                        break
                    }
                }
            }

            foreach ($cand in ($procCandidates | Sort-Object Priority, Port)) {
                $key = "127.0.0.1:$($cand.Port)"
                if ($tested.Contains($key)) { continue }
                [void]$tested.Add($key)

                if (Test-HttpProxyEndpoint -HostAddr "127.0.0.1" -Port $cand.Port -TimeoutMs $timeout) {
                    $res = New-ProxyResult -Found $true -HostAddr "127.0.0.1" -Port $cand.Port -Source "process" -ProcessName $cand.ProcessName -Config $cfg
                    Save-ProxyCache $res
                    return $res
                }
            }
        }
    } catch {
        Write-ProxyHelperLog "WARN: Process scan failed: $($_.Exception.Message)"
    }

    # Layer 3: Read-only Windows Internet Settings ProxyServer
    try {
        $inet = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($inet -and $inet.ProxyServer) {
            $regEntries = Parse-WindowsProxyServer -ProxyServer ([string]$inet.ProxyServer)
            foreach ($entry in $regEntries) {
                $key = "$($entry.Host):$($entry.Port)"
                if ($tested.Contains($key)) { continue }
                [void]$tested.Add($key)

                $isListening = ($entry.Host -ne "127.0.0.1") -or $listenMap.ContainsKey($entry.Port)
                if ($isListening -and (Test-HttpProxyEndpoint -HostAddr $entry.Host -Port $entry.Port -TimeoutMs $timeout)) {
                    $res = New-ProxyResult -Found $true -HostAddr $entry.Host -Port $entry.Port -Source "system_proxy_registry" -Config $cfg
                    Save-ProxyCache $res
                    return $res
                }
            }
        }
    } catch {
        Write-ProxyHelperLog "WARN: Registry proxy read failed: $($_.Exception.Message)"
    }

    # Layer 4: Common proxy port fallback scan
    foreach ($port in ($preferredPorts | Select-Object -Unique)) {
        if (-not $listenMap.ContainsKey($port)) { continue }
        $key = "127.0.0.1:$port"
        if ($tested.Contains($key)) { continue }
        [void]$tested.Add($key)

        if (Test-HttpProxyEndpoint -HostAddr "127.0.0.1" -Port $port -TimeoutMs $timeout) {
            $res = New-ProxyResult -Found $true -HostAddr "127.0.0.1" -Port $port -Source "common_port_scan" -Config $cfg
            Save-ProxyCache $res
            return $res
        }
    }

    return (New-ProxyResult -Found $false -Source "none" -Config $cfg)
}

$result = Invoke-ProxyDetection

if ($Json) {
    $result | ConvertTo-Json -Depth 4
} elseif (-not $Quiet) {
    if ($result.found) {
        $procInfo = if ($result.processName) { " [$($result.processName)]" } else { "" }
        Write-Output "Detected proxy: $($result.proxyUrl) (source: $($result.source)$procInfo)"
    } else {
        Write-Output "No active local HTTP/mixed proxy detected (source: $($result.source))."
    }
}
