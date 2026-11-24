param(
    [switch]$DryRun,
    [switch]$NoCache,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassThruArgs
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Get-ProxyHelperConfig
$exePath = Find-AntigravityExe -Config $cfg

if (-not $exePath) {
    Write-ProxyHelperLog "ERROR: Could not locate Antigravity.exe."
    if ($DryRun) {
        [PSCustomObject]@{ ok = $false; error = "Antigravity.exe not found" } | ConvertTo-Json -Depth 4
    }
    exit 1
}

$detectScript = Join-Path $PSScriptRoot "detect-proxy.ps1"
$detectParams = @{ Json = $true }
if ($NoCache) { $detectParams["NoCache"] = $true }
$proxyJson = (& $detectScript @detectParams) -join "`n"
$proxy = $proxyJson | ConvertFrom-Json

$argList = New-Object System.Collections.Generic.List[string]
if ($proxy.found -and -not [string]::IsNullOrWhiteSpace($proxy.proxyUrl)) {
    $argList.Add("--proxy-server=`"$($proxy.proxyUrl)`"")
    $argList.Add("--proxy-bypass-list=`"$($proxy.bypassList)`"")
}

if ($PassThruArgs) {
    foreach ($a in $PassThruArgs) {
        if ($null -eq $a -or $a -eq "") { continue }
        if ($a -match '\s' -and -not ($a.StartsWith('"') -and $a.EndsWith('"'))) {
            $argList.Add("`"$a`"")
        } else {
            $argList.Add($a)
        }
    }
}

$joinedArgs = ($argList -join " ")

if ($DryRun) {
    [PSCustomObject]@{
        ok         = $true
        exePath    = $exePath
        arguments  = $joinedArgs
        proxyFound = $proxy.found
        proxyUrl   = $proxy.proxyUrl
        source     = $proxy.source
        process    = $proxy.processName
        noProxy    = $proxy.noProxy
    } | ConvertTo-Json -Depth 4
    exit 0
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exePath
$psi.WorkingDirectory = Split-Path -Parent $exePath
$psi.Arguments = $joinedArgs
$psi.UseShellExecute = $false

if ($proxy.found -and -not [string]::IsNullOrWhiteSpace($proxy.proxyUrl)) {
    $psi.EnvironmentVariables["HTTP_PROXY"] = $proxy.proxyUrl
    $psi.EnvironmentVariables["HTTPS_PROXY"] = $proxy.proxyUrl
    $psi.EnvironmentVariables["NO_PROXY"] = $proxy.noProxy
    $psi.EnvironmentVariables["http_proxy"] = $proxy.proxyUrl
    $psi.EnvironmentVariables["https_proxy"] = $proxy.proxyUrl
    $psi.EnvironmentVariables["no_proxy"] = $proxy.noProxy
    Write-ProxyHelperLog "Launching Antigravity with proxy $($proxy.proxyUrl) (source=$($proxy.source), proc=$($proxy.processName))"
} else {
    Write-ProxyHelperLog "Launching Antigravity directly without proxy (source=$($proxy.source))"
}

[void][System.Diagnostics.Process]::Start($psi)
