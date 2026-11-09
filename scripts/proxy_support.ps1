# Proxy handling shared by prepare_assets.ps1 and download_repo_bootstrap.ps1 (dot-sourced).
# Order: no_proxy match -> direct | cntlm (if configured and listening) | http(s)_proxy
# environment variables | Windows system proxy with the signed-in user's credentials | direct.
# If the proxy answers 407, the caller may retry with explicit user credentials.

function Get-CntlmProxy {
    # "Configured" = cntlm.ini, service or process exists AND the local listen port answers.
    $ini = @(
        "$env:ProgramFiles\Cntlm\cntlm.ini",
        "${env:ProgramFiles(x86)}\Cntlm\cntlm.ini",
        "$env:ProgramData\Cntlm\cntlm.ini",
        "$env:USERPROFILE\cntlm.ini"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    $present = $ini -or (Get-Service -Name cntlm -ErrorAction SilentlyContinue) -or
        (Get-Process -Name cntlm -ErrorAction SilentlyContinue)
    if (-not $present) { return $null }

    $port = 3128
    if ($ini) {
        $match = Select-String -LiteralPath $ini -Pattern '^\s*Listen\s+(?:\S+:)?(\d+)\s*$' | Select-Object -First 1
        if ($match) { $port = [int]$match.Matches[0].Groups[1].Value }
    }
    $tcp = New-Object Net.Sockets.TcpClient
    try {
        $async = $tcp.BeginConnect('127.0.0.1', $port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(1000) -or -not $tcp.Connected) { return $null }
    } catch {
        return $null
    } finally {
        $tcp.Close()
    }
    [Uri]"http://127.0.0.1:$port"
}

function Test-NoProxy([Uri]$Target) {
    $list = [Environment]::GetEnvironmentVariable('no_proxy')
    if (-not $list) { return $false }
    foreach ($entry in ($list -split '[,;\s]+' | Where-Object { $_ })) {
        if ($entry -eq '*') { return $true }
        $name = ($entry -replace ':\d+$', '').TrimStart('*', '.').ToLowerInvariant()
        if ($name -and ($Target.Host -eq $name -or $Target.Host.EndsWith(".$name"))) { return $true }
    }
    $false
}

function Resolve-Proxy([Uri]$Target) {
    if (Test-NoProxy $Target) {
        return [pscustomobject]@{ Kind = 'direct'; Description = 'direct connection (no_proxy)'; Proxy = $null }
    }

    $cntlm = Get-CntlmProxy
    if ($cntlm) {
        return [pscustomobject]@{ Kind = 'cntlm'; Description = "cntlm $($cntlm.Authority)"; Proxy = (New-Object Net.WebProxy($cntlm)) }
    }

    $names = if ($Target.Scheme -eq 'https') { 'https_proxy', 'http_proxy' } else { 'http_proxy' }
    $value = $names | ForEach-Object { [Environment]::GetEnvironmentVariable($_) } |
        Where-Object { $_ } | Select-Object -First 1
    if ($value) {
        $uri = [Uri]$(if ($value -match '://') { $value } else { "http://$value" })
        $proxy = New-Object Net.WebProxy(('{0}://{1}:{2}' -f $uri.Scheme, $uri.Host, $uri.Port))
        if ($uri.UserInfo) {
            $part = $uri.UserInfo -split ':', 2
            $password = if ($part.Count -gt 1) { [Uri]::UnescapeDataString($part[1]) } else { '' }
            $proxy.Credentials = New-Object Net.NetworkCredential([Uri]::UnescapeDataString($part[0]), $password)
        }
        return [pscustomobject]@{ Kind = 'environment'; Description = "environment proxy $($uri.Host):$($uri.Port)"; Proxy = $proxy }
    }

    $system = [Net.WebRequest]::GetSystemWebProxy()
    $system.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials
    # Windows PowerShell returns the target itself when no proxy applies, PowerShell 7 returns $null.
    $proxyUri = if ($system.IsBypassed($Target)) { $null } else { $system.GetProxy($Target) }
    if ($proxyUri -and $proxyUri.Authority -ne $Target.Authority) {
        return [pscustomobject]@{ Kind = 'system'; Description = "system proxy $($proxyUri.Authority)"; Proxy = $system }
    }
    [pscustomobject]@{ Kind = 'direct'; Description = 'direct connection'; Proxy = $null }
}

# One download attempt. Explicit credentials apply to environment and system proxies
# (cntlm authenticates by itself). Failures name the route that was used.
function Invoke-ProxyDownload {
    param([string]$Url, [string]$OutFile, [pscredential]$Credential)
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $route = Resolve-Proxy ([Uri]$Url)
    if ($Credential -and $route.Kind -in 'environment', 'system') {
        $route.Proxy.Credentials = $Credential.GetNetworkCredential()
    }
    Write-Host "[proxy] Downloading via $($route.Description): $Url"
    $client = New-Object Net.WebClient
    try {
        $client.Proxy = $route.Proxy
        $client.DownloadFile($Url, $OutFile)
    } catch {
        throw (New-Object Exception("via $($route.Description): $($_.Exception.Message)", $_.Exception))
    } finally {
        $client.Dispose()
    }
}

function Test-ProxyAuthRequired($ErrorRecord) {
    for ($e = $ErrorRecord.Exception; $e; $e = $e.InnerException) {
        if ($e -is [Net.WebException] -and $e.Response -and [int]$e.Response.StatusCode -eq 407) { return $true }
    }
    $false
}

# Interactive use (build): on 407 ask for user name and password, up to three attempts.
function Save-Download {
    param([string]$Url, [string]$OutFile, [bool]$Interactive)
    $credential = $null
    for ($attempt = 1; ; $attempt++) {
        try {
            if ($credential) {
                Invoke-ProxyDownload -Url $Url -OutFile $OutFile -Credential $credential
            } else {
                Invoke-ProxyDownload -Url $Url -OutFile $OutFile
            }
            return
        } catch {
            if (-not $Interactive -or $attempt -ge 3 -or -not (Test-ProxyAuthRequired $_)) { throw }
            $credential = Get-Credential -Message 'The proxy requires authentication.'
            if (-not $credential) { throw }
        }
    }
}
