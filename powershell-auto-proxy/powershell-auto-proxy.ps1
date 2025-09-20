# PowerShell 代理助手
function Test-ProxyPort {
    param($ProxyHost, $Port)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $conn = $tcp.BeginConnect($ProxyHost, $Port, $null, $null)
        $ok = $conn.AsyncWaitHandle.WaitOne(800, $false)
        if ($ok) { $tcp.EndConnect($conn); return $true }
    } catch {}
    finally { if ($tcp) { $tcp.Close() } }
    return $false
}

function Set-SmartProxy {
    param([string]$ProxyHost='127.0.0.1', [int]$HttpPort=7890, [switch]$UseSocks, [int]$SocksPort=7891)

    if (!(Test-ProxyPort $ProxyHost $HttpPort)) {
        Clear-Proxy
        Write-Host "❌ 代理不可用 ${ProxyHost}:${HttpPort}" -ForegroundColor Red
        return
    }

    $http = "http://${ProxyHost}:${HttpPort}"
    $env:HTTP_PROXY=$http; $env:HTTPS_PROXY=$http; $env:http_proxy=$http; $env:https_proxy=$http
    $env:NO_PROXY='localhost,127.0.0.1,::1,.local,.lan'; $env:no_proxy=$env:NO_PROXY

    $msg = "✅ 代理: ${ProxyHost}:${HttpPort}"
    if ($UseSocks -and (Test-ProxyPort $ProxyHost $SocksPort)) {
        $socks = "socks5://${ProxyHost}:${SocksPort}"
        $env:ALL_PROXY=$socks; $env:all_proxy=$socks
        $msg += " + SOCKS:${SocksPort}"
    }
    Write-Host $msg -ForegroundColor Green
}

function Clear-Proxy {
    $vars = 'HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','http_proxy','https_proxy','all_proxy','no_proxy'
    foreach ($var in $vars) { Remove-Item Env:$var -ErrorAction SilentlyContinue }
    Write-Host "ℹ️ 已关闭代理" -ForegroundColor Yellow
}

function Get-ProxyStatus {
    if ($env:HTTP_PROXY) {
        Write-Host "🟢 HTTP: $env:HTTP_PROXY" -ForegroundColor Green
    } else {
        Write-Host "🔴 未设置代理" -ForegroundColor Red
    }
    if ($env:ALL_PROXY) { Write-Host "🟢 SOCKS: $env:ALL_PROXY" -ForegroundColor Green }
}

# 启动提示
if (Test-ProxyPort '127.0.0.1' 7890) {
    Write-Host "[代理可用] Set-SmartProxy | Clear-Proxy | Get-ProxyStatus" -ForegroundColor DarkGray
}